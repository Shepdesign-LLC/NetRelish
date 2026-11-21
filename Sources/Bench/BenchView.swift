// BenchView.swift — the web panes (manifest v2.1 §8 Bench, ADR 0035). The Bench shows the
// active tab's WKWebView, one web view per tab, each on its jar's data store; or the jar's
// board; or a smart jar's rows; or a sealed item's saved copy. The tabs live in the title
// strip (TabStrip.swift) and the address in the row over the Bench (ShellRows.swift); Seal
// draws in the window's one overlay (Seal/SealOverlay.swift). The Panel slides in over the
// Bench's trailing edge (ContentView).

import AppKit
import Network
import Pantry
import SwiftUI
import WebKit

@MainActor
@Observable
final class BenchWebViews {
    private var byTab: [String: JarWebView] = [:]

    /// Set by the Bench: makes a new, active tab for a page's new window, given the jar and
    /// the opener's tab id.
    @ObservationIgnored var makeTab: ((_ jarId: String, _ openerTabId: String) -> Tab?)?
    /// Set by the Bench: closes a tab by id, for a page that closed its own window.
    @ObservationIgnored var closeTab: ((String) -> Void)?

    func view(for tab: Tab) -> JarWebView {
        let jarId = tab.jarId ?? "brine"
        // A tab that has changed jars never keeps the page it had: that page lives on the
        // store of the jar it left (non-negotiable 6). Checked here, and not only when the
        // move happens, because every window keeps its own web views.
        if let v = byTab[tab.id], v.jarId == jarId { return v }
        let v = JarWebView(jarId: jarId)
        if let state = tab.interactionState, !state.isEmpty {
            v.interactionState = state          // restored from a sunk item, or from last launch
        } else if let url = tab.url {
            v.load(url)
        }
        adopt(v, as: tab.id)
        return v
    }

    /// A page in `parent` asked for a new window: make a tab in the same jar and give WebKit
    /// a web view for it, built on the configuration WebKit passed. Nil if no tab was made,
    /// and nil if that configuration isn't on the opener's jar's store: a new tab there would
    /// keep its cookies in the wrong jar (non-negotiable 6).
    func openNewWindow(from parent: JarWebView, configuration: WKWebViewConfiguration) -> WKWebView? {
        guard configuration.websiteDataStore.identifier == JarProfile.storeIdentifier(for: parent.jarId),
              let openerId = byTab.first(where: { $0.value === parent })?.key,
              let tab = makeTab?(parent.jarId, openerId) else { return nil }
        let child = JarWebView(jarId: parent.jarId, configuration: configuration, openedByPage: true)
        adopt(child, as: tab.id)
        return child.webView
    }

    /// Registers a web view as a tab's and routes the page's new windows to new tabs.
    private func adopt(_ v: JarWebView, as tabId: String) {
        v.onNewWindow = { [weak self, weak v] configuration in
            guard let self, let v else { return nil }
            return self.openNewWindow(from: v, configuration: configuration)
        }
        // Only a window a page opened is the page's to close.
        if v.openedByPage { v.onClose = { [weak self] in self?.closeTab?(tabId) } }
        byTab[tabId] = v
    }

    /// Lets go of web views whose tab is closed, or now lives in another jar. Every window
    /// runs this for its own web views when the open tabs change, because only one window
    /// hears `onTabsGone`; otherwise a closed page would stay alive here, and a moved one
    /// would stay open, signed in, on the jar its tab left. `tabs` is every open tab.
    func forgetStale(_ tabs: [Tab]) {
        let jarOf = Dictionary(tabs.map { ($0.id, $0.jarId ?? "brine") }, uniquingKeysWith: { first, _ in first })
        for (tabId, view) in byTab where jarOf[tabId] != view.jarId { byTab[tabId] = nil }
    }

    func existing(for tabId: String) -> JarWebView? { byTab[tabId] }
    func forget(_ tabId: String) { byTab[tabId] = nil }
}

struct BenchView: View {
    @Bindable var workbench: Workbench
    /// This window's web views, owned by the window so the title and address rows reach the
    /// page in front too.
    let webViews: BenchWebViews

    /// One container, so the wiring runs whatever the Bench is showing first.
    var body: some View {
        ZStack { content }
            .sealAnchor(.page)          // where the Seal overlay blinks the frozen page
            .onAppear { wire() }
            .onChange(of: workbench.allTabs) { _, tabs in webViews.forgetStale(tabs) }
    }

    @ViewBuilder private var content: some View {
        if let comparison = workbench.comparison {
            ComparisonView(comparison: comparison, workbench: workbench)
                .id("\(comparison.older.id)|\(comparison.newer.id)")
        } else if let item = workbench.savedCopy {
            SavedCopyView(item: item, workbench: workbench)
                .id(item.id)
        } else if let smart = workbench.activeSmartJar {
            SmartJarView(smart: smart, workbench: workbench)
        } else if let jar = workbench.activeJar {
            // The page, or the jar's board: asked for, or all there is when no tab is open.
            if !workbench.showingBoard, let tab = workbench.activeTab {
                let web = webViews.view(for: tab)
                TabPane(tab: tab, web: web, workbench: workbench)
                    .id(tab.id)
                    .background(NRColor.surface)
            } else {
                JarBoard(jar: jar, workbench: workbench)
                    .id(jar.id)
            }
        } else {
            EmptyBench(message: "No jar yet. Make one on the Shelf.")
        }
    }

    /// The sweep asks the Bench for a tab's live interaction state before sinking it.
    private func wire() {
        webViews.makeTab = { [workbench] jarId, openerId in workbench.newTab(in: jarId, openedBy: openerId) }
        webViews.closeTab = { [workbench] tabId in workbench.closeTab(id: tabId) }
        // Only tabs that are really gone let go of their web views. A jar you switch away
        // from, or one hidden behind a smart jar or a saved copy, keeps its pages live.
        workbench.onTabsGone = { [webViews] ids in ids.forEach(webViews.forget) }
        workbench.interactionStateProvider = { [webViews] tab in
            webViews.existing(for: tab.id)?.interactionState
        }
        workbench.formFiller = { [webViews] tab, identity in
            try await FormFill.fill(identity, in: webViews.view(for: tab).webView)
        }
        workbench.sealProvider = { [webViews] tab in
            let web = webViews.view(for: tab).webView
            // Extract first: createWebArchiveData can take a moment on a heavy page, and the
            // page must still be live when Defuddle reads it.
            let extracted = try await Extraction.run(in: web)
            let archive = try await web.dataForWebArchive()
            return (archive, extracted)
        }
        workbench.readerProvider = { [webViews] tab in
            try await Extraction.article(in: webViews.view(for: tab).webView)
        }
        // Shortcuts seal a tab live only when its page is already loaded in a web view;
        // otherwise they load it off screen rather than freeze a page that hasn't arrived.
        workbench.livePageAvailable = { [webViews] tab in
            guard let web = webViews.existing(for: tab.id)?.webView else { return false }
            return !web.isLoading && web.url != nil
        }
    }
}

/// One tab's page: its web view, or the reader over it. The address lives in the window's
/// address row (`SearchRow`).
struct TabPane: View {
    let tab: Tab
    let web: JarWebView
    @Bindable var workbench: Workbench
    /// The Workbench is every window's: only the key window speaks for it.
    @Environment(\.controlActiveState) private var activeState

    private var reading: Bool { workbench.reader?.tabId == tab.id }

    var body: some View {
        Group {
            if let reader = workbench.reader, reader.tabId == tab.id {
                // The live page stays loaded behind the reader, so ⌘S still seals it.
                ReaderHost(article: reader.article,
                           baseURL: reader.url.flatMap(URL.init(string:)) ?? URL(string: "about:blank")!,
                           follow: { [workbench, web] url in
                               workbench.closeReader()
                               web.load(url.absoluteString)
                           })
                    .id(reader.url)
                    .onExitCommand { workbench.closeReader() }
            } else {
                WebViewHost(jarWebView: web)
                    .onAppear { takeKeyboardIfNobodyHasIt() }
            }
        }
        .onAppear {
            let jarId = web.jarId      // the view's own jar, so a page left behind by a move is told apart
            web.onNavigation = { [workbench] url, title in
                workbench.tabDidNavigate(tab.id, fromJar: jarId, url: url, title: title)
            }
        }
        // Reader view swaps the whole page, and ⌘⇧R from the menu changes nothing VoiceOver
        // is on, so the swap is said. Only a change: a tab that opens already reading says nothing.
        .onChange(of: reading) { _, now in
            guard activeState == .key else { return }
            NRAnnounce.post(now ? BenchText.readerOpened : BenchText.readerClosed)
        }
    }

    /// The page that had the keyboard left the window with it (Seal closed the tab in front,
    /// a tab closed or changed, Reader view closed), so this one arrives without it, and
    /// typing and the arrow keys go nowhere until it's clicked. Take it only when nobody has
    /// it: never from the address field, which a new tab focuses, or from ⌘K. A blank tab
    /// leaves it to the field. A turn later, once the web view is in the window.
    private func takeKeyboardIfNobodyHasIt() {
        guard web.url != nil || tab.url != nil else { return }
        let page = web.webView
        Task { @MainActor in
            guard let window = page.window else { return }
            let responder = window.firstResponder
            guard responder == nil || responder === window else { return }
            _ = window.makeFirstResponder(page)
        }
    }
}

/// An empty state (manifest v2.1 §8): the cog mark at 56pt (relish placement #8), one line,
/// and an optional way out as the view's one primary button (#1), on the canvas.
struct EmptyBench: View {
    let message: String
    /// An optional way out, shown as the view's one primary button.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: NRSpace.sp4) {
            NRLogo.cog.image.resizable().frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text(message).font(NRType.font(NRType.fsLg)).foregroundStyle(NRColor.fg2)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.nrPrimary).nrFocusRing()
            }
        }
        .padding(NRSpace.sp6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NRColor.canvas)
    }
}

/// A sealed item's saved copy: the page as it was when sealed, read only (non-negotiable 3).
/// JavaScript is off, the data store is throwaway, and that store's only proxy goes nowhere,
/// so nothing on the page runs, nothing is signed in, and whatever the archive doesn't hold
/// fails to load instead of coming from the live site. The file on disk is only ever read.
/// A clicked link opens the live page in a new tab in the copy's jar.
struct SavedCopyView: View {
    let item: Item
    @Bindable var workbench: Workbench
    @State private var archive: Data?
    @State private var missing = false
    /// Whether the copy on disk is still the one that was sealed (ADR 0030).
    @State private var integrity: SealIntegrity = .unchecked
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            if integrity == .broken, !missing {
                brokenSeal
                Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            }
            if missing {
                EmptyBench(message: "We can’t find the saved copy of this page on this Mac.",
                           actionTitle: item.url == nil ? nil : "Open Live Page",
                           action: { workbench.openLivePage(item) })
            } else if let archive {
                SavedCopyHost(archive: archive,
                              baseURL: item.url.flatMap(URL.init(string:)) ?? URL(string: "about:blank")!,
                              openLink: { [workbench, item] url in workbench.openLink(url, from: item) })
            } else {
                NRColor.bg
            }
        }
        .background(NRColor.surface)
        .onExitCommand { workbench.savedCopy = nil }
        .task {
            guard let data = workbench.snapshotData(for: item) else { missing = true; return }
            archive = data
            // Checked every time the copy is opened, against the fingerprint kept in the Pantry.
            // Hashing a large archive takes a moment, so it runs off the main actor and the
            // page is already on screen when the answer arrives.
            let recorded = workbench.provenance(of: item)
            integrity = await Task.detached(priority: .userInitiated) {
                Provenance.integrity(of: data, against: recorded)
            }.value
        }
        // The banner arrives after the copy is on screen, so someone reading it with
        // VoiceOver would never hear it. Said once, in the banner's own words.
        .onChange(of: integrity) { _, now in
            guard now == .broken, !missing, activeState == .key else { return }
            NRAnnounce.post(BenchText.brokenSeal, priority: .high)
        }
    }

    /// Shown instead of silence when the copy no longer matches its fingerprint. The copy is
    /// still shown underneath: the point is that the change can be seen, not that it is hidden.
    private var brokenSeal: some View {
        HStack(spacing: NRSpace.sp2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NRColor.danger)
            Text(BenchText.brokenSeal)
                .font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg)
            Spacer()
        }
        .padding(.horizontal, NRSpace.sp4)
        .padding(.vertical, NRSpace.sp2)
        .background(NRColor.surface2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("broken-seal")
    }

    private var header: some View {
        HStack(spacing: NRSpace.sp3) {
            NRSymbol.seal.image.resizable().frame(width: NRSpace.sp4, height: NRSpace.sp4)
                .foregroundStyle(NRColor.relish500)   // manifest §4, placement 4
                .accessibilityHidden(true)            // the subtitle says "sealed"
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
                    .accessibilityLabel(PanelText.spokenList(subtitle))
            }
            Spacer()
            if item.url != nil, !missing {
                Button("Open Live Page") { workbench.openLivePage(item) }.buttonStyle(.nrSecondary).nrFocusRing()
            }
            Button("Done") { workbench.savedCopy = nil }
                .buttonStyle(.nrSecondary)
                .nrFocusRing()
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: NRSpace.sp12)
        .background(NRColor.surface)
    }

    private var subtitle: String {
        let sealed = item.sealedAt.map { "Saved copy, sealed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Saved copy"
        return [sealed, item.domain, integrity == .intact ? "Unchanged since sealed" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Reader view: the article alone, in system type on the Bench's colors. JavaScript is off,
/// a content policy lets nothing but images and media load (live page loads, which
/// non-negotiable 5 allows), and the store keeps nothing. Links follow the saved copy's rules,
/// except that a clicked page opens in the same tab: Reader view is a way of reading the
/// tab, not a place.
struct ReaderHost: NSViewRepresentable {
    let article: Extraction.Article
    let baseURL: URL
    let follow: (URL) -> Void

    func makeCoordinator() -> SavedCopyNavigator { SavedCopyNavigator(openLink: follow) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let web = ReaderWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.loadHTMLString(ReaderPage.html(for: article), baseURL: baseURL)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.openLink = follow }
}

/// Reader view's web view takes the keyboard once, when it arrives. The page it covers had
/// it and left the window with it, so otherwise the arrow keys and Space go nowhere and
/// VoiceOver isn't taken to the article. Never from a text field someone is typing in.
final class ReaderWebView: WKWebView {
    private var tookKeyboard = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !tookKeyboard else { return }
        tookKeyboard = true
        // A turn later, once SwiftUI has taken the page out of the window.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window, !(window.firstResponder is NSTextView) else { return }
            _ = window.makeFirstResponder(self)
        }
    }
}

/// The reader's one page. Colors, sizes, line heights and weights are the Bench's tokens
/// (tokens.css, manifest §5), light and dark; tests hold the page to them.
enum ReaderPage {
    /// token → (light, dark), copied from design/tokens.css; a test holds them to it.
    static let palette: [(token: String, light: String, dark: String)] = [
        ("--nr-bg", "#FCFCFB", "#171716"),
        ("--nr-fg", "#1D1D1B", "#F0F0EE"),
        ("--nr-fg-2", "#66665F", "#A8A8A2"),
        ("--nr-hairline", "#E5E5E2", "#3B3B38"),
    ]

    /// Under Increase Contrast (`prefers-contrast: more`): the byline, captions and quotes
    /// take `--nr-fg`, and rules and borders take `--nr-fg-3`. Token values; a test holds them.
    static let increasedContrast: [(token: String, light: String, dark: String)] = [
        ("--nr-fg-2", "#1D1D1B", "#F0F0EE"),       // --nr-fg
        ("--nr-hairline", "#6C6C65", "#96968F"),   // --nr-fg-3
    ]

    /// Our policy, ahead of anything in the article: no scripts, no frames, no fetches but
    /// images and media, no forms, no base URL games.
    static let contentSecurityPolicy =
        "default-src 'none'; img-src * data:; media-src *; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'; frame-src 'none'"

    static func html(for article: Extraction.Article) -> String {
        let light = palette.map { "\($0.token): \($0.light);" }.joined(separator: " ")
        let dark = palette.map { "\($0.token): \($0.dark);" }.joined(separator: " ")
        let moreLight = increasedContrast.map { "\($0.token): \($0.light);" }.joined(separator: " ")
        let moreDark = increasedContrast.map { "\($0.token): \($0.dark);" }.joined(separator: " ")
        let meta = [article.site, article.byline].filter { !$0.isEmpty }.map(escape).joined(separator: " · ")
        let metaLine = meta.isEmpty ? "" : "<p class=\"meta\">" + meta + "</p>"
        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width">
        <title>\(escape(article.title))</title>
        <style>
        :root { color-scheme: light dark; \(light) }
        @media (prefers-color-scheme: dark) { :root { \(dark) } }
        @media (prefers-contrast: more) { :root { \(moreLight) } }
        @media (prefers-contrast: more) and (prefers-color-scheme: dark) { :root { \(moreDark) } }
        html { background: var(--nr-bg); }
        body { margin: 0; padding: 48px 24px 96px; color: var(--nr-fg);
               font: 20px/1.5 -apple-system, "SF Pro Text", system-ui, sans-serif; }
        article { max-width: 680px; margin: 0 auto; }
        h1.title { font-size: 28px; line-height: 1.15; font-weight: 600; letter-spacing: -0.01em; margin: 0 0 8px; }
        p.meta { color: var(--nr-fg-2); font-size: 13px; margin: 0 0 32px; padding-bottom: 16px;
                 border-bottom: 1px solid var(--nr-hairline); }
        a { color: var(--nr-fg); text-decoration: underline; text-underline-offset: 2px; }
        img, video, svg, figure { max-width: 100%; height: auto; }
        figcaption { color: var(--nr-fg-2); font-size: 13px; }
        pre, code { font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 15px; }
        pre { overflow-x: auto; padding: 12px 16px; border: 1px solid var(--nr-hairline); border-radius: 6px; }
        blockquote { margin: 1.5em 0; padding-left: 1em; border-left: 2px solid var(--nr-hairline); color: var(--nr-fg-2); }
        table { border-collapse: collapse; } th, td { border: 1px solid var(--nr-hairline); padding: 4px 8px; }
        hr { border: 0; border-top: 1px solid var(--nr-hairline); }
        </style>
        </head><body><article>
        <h1 class="title">\(escape(article.title))</h1>
        \(metaLine)
        \(article.html)
        </article></body></html>
        """
    }

    /// For text we put into the page ourselves. The article's markup was cleaned in the page.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

/// The saved copy's web view, built here and nowhere else, so SwiftUI owns exactly one per
/// copy and its delegate lives as long as it does.
struct SavedCopyHost: NSViewRepresentable {
    let archive: Data
    let baseURL: URL
    let openLink: (URL) -> Void

    func makeCoordinator() -> SavedCopyNavigator { SavedCopyNavigator(openLink: openLink) }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: SavedCopyNavigator.configuration())
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.load(archive, mimeType: "application/x-webarchive", characterEncodingName: "utf-8", baseURL: baseURL)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.openLink = openLink }
}

/// Keeps a saved copy frozen. The archive is the one page load it allows; a clicked link
/// leaves the copy for the live page, in a tab; everything else is cancelled.
@MainActor
final class SavedCopyNavigator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var openLink: (URL) -> Void
    private var archiveLoaded = false

    init(openLink: @escaping (URL) -> Void) { self.openLink = openLink }

    /// JavaScript off, a throwaway store, and a proxy on the discard port of this Mac, which
    /// refuses every connection. Archived resources never touch the network, so they load;
    /// nothing else can.
    static func configuration() -> WKWebViewConfiguration {
        let store = WKWebsiteDataStore.nonPersistent()
        store.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: 9))]
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return config
    }

    enum Decision: Equatable {
        case allow, cancel
        case openInTab(URL)
        case openInApp(URL)
    }

    /// What a saved copy does with a navigation. Pure, so the rules are testable without
    /// WebKit's navigation objects.
    static func decide(url: URL?, type: WKNavigationType, isMainFrame: Bool,
                       archiveLoaded: Bool, current: URL?) -> Decision {
        guard let url else { return .cancel }
        if isMainFrame, !archiveLoaded { return .allow }               // the archive itself
        if type == .linkActivated {
            if isMainFrame, url.fragment != nil, let current, sameDocument(url, current) { return .allow }
            if let app = JarWebView.forAnotherApp(url) { return .openInApp(app) }
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" { return .openInTab(url) }
            return .cancel
        }
        // The archive's own frames load from the archive; a frame it doesn't hold fails at
        // the proxy. The page itself never moves on its own (redirects, forms, refreshes).
        return isMainFrame ? .cancel : .allow
    }

    private static func sameDocument(_ a: URL, _ b: URL) -> Bool {
        var x = URLComponents(url: a, resolvingAgainstBaseURL: false)
        var y = URLComponents(url: b, resolvingAgainstBaseURL: false)
        x?.fragment = nil
        y?.fragment = nil
        return x != nil && x?.url == y?.url
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let decision = Self.decide(url: navigationAction.request.url, type: navigationAction.navigationType,
                                   isMainFrame: isMainFrame, archiveLoaded: archiveLoaded, current: webView.url)
        if decision == .allow, isMainFrame { archiveLoaded = true }
        decisionHandler(decision == .allow ? .allow : .cancel)
        perform(decision)
    }

    /// target=_blank inside the copy follows the same rules as a click; it never gets a window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        perform(Self.decide(url: navigationAction.request.url, type: .linkActivated, isMainFrame: false,
                            archiveLoaded: true, current: nil))
        return nil
    }

    /// After WebKit has its answer: leaving the copy tears down this web view.
    private func perform(_ decision: Decision) {
        switch decision {
        case .openInTab(let url): Task { @MainActor in self.openLink(url) }
        case .openInApp(let url): NSWorkspace.shared.open(url)
        case .allow, .cancel: break
        }
    }
}

// MARK: - The Panel (⌘⌥I)

/// The right column (manifest v2.1 §8, "Inspector" row; called the Panel everywhere a person
/// sees it, ADR 0010 row 9): token width, the rail color, a soft hairline on its leading edge,
/// sections between soft hairlines under small-caps labels. It slides in over the Bench's
/// trailing edge and starts closed (ContentView). It describes whatever the Bench is showing.
/// Its one relish is the shelf-life bar (placement #5).
struct PanelView: View {
    @Bindable var workbench: Workbench
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // One stop for Tab and the arrow keys under Full Keyboard Access.
        .focusSection()
        .frame(width: NRSpace.inspectorW)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NRColor.rail)
        .overlay(alignment: .leading) {
            Rectangle().fill(ShellInk.edge(contrast) ?? NRColor.hairlineSoft).frame(width: NRSpace.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel")
        .accessibilityIdentifier("panel")
    }

    @ViewBuilder private var content: some View {
        switch workbench.panelSubject {
        case .savedCopy(let item):
            PanelHeader(title: item.title, subtitle: item.domain)
            PanelItemSections(item: item, workbench: workbench)
                .id(item.id)                          // fresh state per item: no labels or draft carried over
        case .tab(let tab):
            PanelTabSections(tab: tab, workbench: workbench)
                .id(tab.id)
        case .jar(let jar):
            PanelHeader(title: jar.name, subtitle: JarBoard.summary(tabs: workbench.tabs.count, kept: workbench.jarItems.count))
            PanelSection("Jar") {
                PanelRow("Shelf life", jar.shelfLifeDays.map { PanelText.days($0) } ?? "None. Tabs never sink")
                PanelRow("Open tabs", "\(workbench.tabs.count)")
                PanelRow("Kept", "\(workbench.jarItems.count)")
            }
            PanelSection("Color") {
                JarSwatches(selected: jar.tint) { workbench.setTint($0, of: jar) }
            }
            PanelSection("Do something") {
                Button("New Tab") { workbench.newTab(in: jar.id) }.buttonStyle(.nrSecondary).nrFocusRing()
                Button("Edit Jar…") { workbench.requestEditActiveJar() }.buttonStyle(.nrSecondary).nrFocusRing()
            }
        case .smartJar(let smart):
            PanelHeader(title: smart.name, subtitle: "Smart jar")
            PanelSection("Smart jar") {
                PanelRow("Holds", "\(workbench.count(of: smart))")
                PanelNote(smart.blurb)
            }
        case .nothing:
            PanelNote("Nothing to describe yet. Open a page or a jar.")
                .padding(20)
        }
    }
}

/// A live tab: its jar and shelf life, then what the Pantry holds for its page, if anything.
private struct PanelTabSections: View {
    let tab: Tab
    @Bindable var workbench: Workbench
    @State private var item: Item?

    init(tab: Tab, workbench: Workbench) {
        self.tab = tab
        self.workbench = workbench
        _item = State(initialValue: workbench.pantryItem(for: tab.url))   // no "not in your Pantry" flash
    }

    var body: some View {
        // One real container, so the task has a view to run on (on EmptyView it never would).
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: (tab.title?.isEmpty == false ? tab.title : nil) ?? tab.url ?? "New Tab",
                        subtitle: tab.url.flatMap { URL(string: $0)?.host })
            PanelSection("Tab") {
                PanelRow("Jar", workbench.jarName(for: tab.jarId))
                PanelRow("Shelf life", shelfLife)
                if let remaining = shelfLifeRemaining {
                    // The row above already says it; the bar would only say it again.
                    NRShelfLifeBar(remaining: remaining)
                        .padding(.top, NRSpace.sp1)
                        .accessibilityHidden(true)
                }
            }
            if let item {
                PanelItemSections(item: item, workbench: workbench)
                    .id(item.id)
            } else if let url = tab.url, !url.isEmpty {
                PanelSection("Pantry") {
                    PanelNote("Not in your Pantry yet. ⌘D captures this page; ⌘S seals it.")
                }
            }
        }
        .task(id: "\(tab.url ?? "")|\(workbench.itemCount)|\(workbench.sealedItems.count)") {
            item = workbench.pantryItem(for: tab.url)
        }
    }

    /// How much of the tab's shelf life is left, 0…1; nil for a tab that never sinks.
    private var shelfLifeRemaining: Double? {
        guard !tab.isPinned,
              let jar = workbench.jars.first(where: { $0.id == tab.jarId }),
              let days = jar.shelfLifeDays, days > 0,
              let left = ShelfLife.timeLeft(of: tab, in: jar, now: workbench.now) else { return nil }
        return left / (days * 86_400)
    }

    private var shelfLife: String {
        if tab.isPinned { return "Pinned. Never sinks" }
        guard let jar = workbench.jars.first(where: { $0.id == tab.jarId }),
              let left = ShelfLife.timeLeft(of: tab, in: jar, now: workbench.now) else { return "Never sinks" }
        return "Sinks " + workbench.now.addingTimeInterval(left).formatted(.relative(presentation: .named))
    }
}

/// An item in the Pantry: what it is, where it came from, when, and its labels.
private struct PanelItemSections: View {
    let item: Item
    @Bindable var workbench: Workbench
    @State private var labels: [Pantry.Label]   // not SwiftUI.Label
    @State private var newLabel = ""
    @FocusState private var labelFieldFocused: Bool
    /// The label whose Remove button has the keyboard, if any.
    @FocusState private var focusedRemove: Pantry.Label.ID?

    init(item: Item, workbench: Workbench) {
        self.item = item
        self.workbench = workbench
        _labels = State(initialValue: workbench.labels(of: item))
    }

    var body: some View {
        // One real container, so the task has a view to run on (on EmptyView it never would).
        VStack(alignment: .leading, spacing: 0) {
            PanelSection("Pantry") {
                PanelRow("Kind", item.kind.rawValue.capitalized)
                PanelRow("State", PanelText.state(item, jar: workbench.jarName(for: item.jarId ?? item.sunkOriginJarId)))
                PanelRow("Source", PanelText.source(item.source))
                PanelRow("Captured", item.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let sealed = item.sealedAt {
                    PanelRow("Sealed", sealed.formatted(date: .abbreviated, time: .shortened))
                }
            }
            PanelSummarySection(item: item, workbench: workbench)
            if item.state == .sealed, item.url != nil {
                PanelSealsSection(item: item, workbench: workbench)
            }
            if item.state == .sealed, item.snapshotPath != nil {
                PanelProofSection(item: item, workbench: workbench)
            }
            PanelSection("Labels") {
                ForEach(labels) { label in
                    HStack(spacing: NRSpace.sp2) {
                        Text(label.name).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg)
                        Spacer()
                        Button { remove(label, refocus: focusedRemove == label.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain).foregroundStyle(NRColor.fg2)
                        .focusEffectDisabled()
                        .focused($focusedRemove, equals: label.id)
                        .overlay {
                            if focusedRemove == label.id {
                                NRFocusRing(cornerRadius: 4, inset: -3)
                            }
                        }
                        .help("Remove \(label.name)").accessibilityLabel("Remove \(label.name)")
                    }
                    // VoiceOver hears the label once, with Remove as its action, instead of
                    // the name and then a separate button. The button stays for the pointer.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label.name)
                    .accessibilityAction(named: Text("Remove")) { remove(label, refocus: true) }
                }
                TextField("Add a label", text: $newLabel)
                    .textFieldStyle(.plain)
                    .font(NRType.font(NRType.fsSm))
                    .foregroundStyle(NRColor.fg)
                    .focused($labelFieldFocused)
                    .overlay {
                        if labelFieldFocused {
                            NRFocusRing(cornerRadius: 6, inset: -4)
                        }
                    }
                    .accessibilityLabel("New label")
                    .onSubmit {
                        let name = newLabel.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        let before = workbench.labelRevision
                        workbench.addLabel(name, to: item)
                        newLabel = ""
                        // Only once it's in: a failure says so on its own (the status line).
                        if workbench.labelRevision != before { NRAnnounce.post(PanelText.labelAdded(name)) }
                    }
            }
        }
        .task(id: "\(item.id)|\(workbench.labelRevision)") { labels = workbench.labels(of: item) }
    }

    /// Removes a label and says so. The Remove button leaves with its row, so the keyboard
    /// would go nowhere; when it came from the keyboard or VoiceOver, the field takes it.
    private func remove(_ label: Pantry.Label, refocus: Bool) {
        let before = workbench.labelRevision
        workbench.removeLabel(label, from: item)
        guard workbench.labelRevision != before else { return }
        NRAnnounce.post(PanelText.labelRemoved(label.name))
        if refocus { labelFieldFocused = true }
    }
}

/// Seal & Summarize's result for a sealed page: the summary, or one line saying where it
/// stands. Nothing at all for a page no summary is coming for.
private struct PanelSummarySection: View {
    let item: Item
    @Bindable var workbench: Workbench
    @State private var state: SummaryState?

    init(item: Item, workbench: Workbench) {
        self.item = item
        self.workbench = workbench
        _state = State(initialValue: workbench.summary(of: item))
    }

    var body: some View {
        // One real container, so the task has a view to run on (on EmptyView it never would).
        VStack(alignment: .leading, spacing: 0) {
            if let state {
                PanelSection("Summary") {
                    switch PanelText.summary(state) {
                    case .summary(let text):
                        Text(text).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    case .note(let text):
                        PanelNote(text)
                    }
                }
            }
        }
        .task(id: "\(item.id)|\(workbench.summaryRevision)") { state = workbench.summary(of: item) }
    }
}

/// Reseal & diff (Pro): every seal of this page, sealing it again, and comparing the last two.
private struct PanelSealsSection: View {
    let item: Item
    @Bindable var workbench: Workbench
    @State private var seals: [Item]
    @Environment(\.controlActiveState) private var activeState

    init(item: Item, workbench: Workbench) {
        self.item = item
        self.workbench = workbench
        _seals = State(initialValue: workbench.seals(of: item))
    }

    var body: some View {
        // One real container, so the task has a view to run on.
        VStack(alignment: .leading, spacing: 0) {
            PanelSection("Seals") {
                ForEach(seals.prefix(PanelText.sealsShown)) { seal in
                    PanelRow(PanelText.sealLabel(seal, current: item), PanelText.sealDate(seal))
                }
                if seals.count > PanelText.sealsShown {
                    PanelNote(PanelText.moreSeals(seals.count - PanelText.sealsShown))
                }
                if workbench.resealingURL == item.url {
                    PanelNote(PanelText.resealing)
                } else {
                    HStack(spacing: NRSpace.sp2) {
                        Button("Seal Again") { Task { await workbench.resealAndCompare(item) } }
                            .buttonStyle(.nrSecondary)
                            .nrFocusRing()
                            .help(PanelText.sealAgainHelp)
                        if seals.count > 1 {
                            Button("Compare") { Task { await workbench.compareWithPrevious(seals[0]) } }
                                .buttonStyle(.nrSecondary)
                                .nrFocusRing()
                                .help(PanelText.compareHelp)
                        }
                        if !workbench.pro.isUnlocked { ProTag() }
                    }
                }
            }
        }
        .task(id: "\(item.id)|\(workbench.sealedItems.count)") { seals = workbench.seals(of: item) }
        // Sealing again takes a moment and replaces the buttons with a note; say the note.
        // The comparison says how it came out.
        .onChange(of: workbench.resealingURL == item.url) { _, on in
            guard on, activeState == .key else { return }
            NRAnnounce.post(PanelText.resealing)
        }
    }
}

/// Provenance (Pro): the saved copy's fingerprint, its timestamp, and Export Proof.
private struct PanelProofSection: View {
    let item: Item
    @Bindable var workbench: Workbench
    @State private var provenance: Provenance?

    init(item: Item, workbench: Workbench) {
        self.item = item
        self.workbench = workbench
        _provenance = State(initialValue: workbench.provenance(of: item))
    }

    var body: some View {
        // One real container, so the task has a view to run on.
        VStack(alignment: .leading, spacing: 0) {
            PanelSection("Proof") {
                if let provenance {
                    PanelRow("Fingerprint", PanelText.shortFingerprint(provenance.fingerprint))
                    PanelRow("Timestamp", PanelText.timestamp(provenance, on: workbench.timestampsOn))
                    HStack(spacing: NRSpace.sp2) {
                        Button("Export Proof…") { workbench.exportProof(item) }
                            .buttonStyle(.nrSecondary)
                            .nrFocusRing()
                            .help(PanelText.exportProofHelp)
                        if !workbench.pro.isUnlocked { ProTag() }
                    }
                } else {
                    PanelNote(PanelText.fingerprinting)
                }
            }
        }
        .task(id: "\(item.id)|\(workbench.provenanceRevision)") { provenance = workbench.provenance(of: item) }
    }
}

private struct PanelHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(NRType.font(NRType.fsXl, weight: .semibold)).tracking(-0.2)
                .foregroundStyle(NRColor.fg).lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(NRType.font(NRType.fsSm, weight: .medium)).foregroundStyle(NRColor.fg3).lineLimit(1)
                    .accessibilityLabel(PanelText.spokenList(subtitle))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp2) {
            Text(title.uppercased()).font(NRType.font(NRType.fsXs, weight: .semibold)).tracking(0.6)
                .foregroundStyle(NRColor.fg3)
                .padding(.bottom, 2)
                .accessibilityLabel(title)          // drawn in capitals, never spelled out
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, NRSpace.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(ShellInk.separator(contrast)).frame(height: NRSpace.hairline)
                .padding(.horizontal, 20)
        }
    }
}

private struct PanelRow: View {
    let key: String
    let value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NRSpace.sp2) {
            Text(key).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
            Spacer(minLength: NRSpace.sp2)
            Text(value).font(NRType.font(NRType.fsSm, weight: .medium)).foregroundStyle(NRColor.fg)
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
        // One element, read as a name and its value ("Kind, Page"), not two unrelated lines.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key)
        .accessibilityValue(value)
    }
}

private struct PanelNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The Panel's words, kept out of the views so tests can read them.
enum PanelText {
    // Provenance

    static let fingerprinting = "Working out this page’s fingerprint…"
    static let exportProofHelp = "Save a PDF, the saved copy and its timestamp, so anyone can check what this page said and when"

    /// The first and last eight characters, enough to compare by eye; the proof has it whole.
    static func shortFingerprint(_ hex: String) -> String {
        hex.count > 16 ? "\(hex.prefix(8))…\(hex.suffix(8))" : hex
    }

    static func timestamp(_ provenance: Provenance, on: Bool) -> String {
        if let stamp = provenance.timestamp {
            return stamp.time.formatted(date: .abbreviated, time: .shortened)
        }
        switch provenance.status {
        case .failed: return "Couldn’t get one"
        default: return on ? "Waiting" : "Not set up"
        }
    }

    /// The summary to show, or a line about it in the note style.
    enum SummaryLine: Equatable {
        case summary(String)
        case note(String)
    }

    // Reseal & diff

    static let sealsShown = 5
    static let resealing = "Sealing this page again…"
    static let sealAgainHelp = "Seal this page again and compare it with the last seal"
    static let compareHelp = "Compare the two most recent seals side by side"

    /// "This copy" for the seal the Panel describes, "Sealed" for the others.
    static func sealLabel(_ seal: Item, current: Item) -> String {
        seal.id == current.id ? "This copy" : "Sealed"
    }

    static func sealDate(_ seal: Item) -> String {
        seal.sealedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Sealed"
    }

    static func moreSeals(_ n: Int) -> String {
        n == 1 ? "1 earlier seal" : "\(n) earlier seals"
    }

    // Labels, as VoiceOver says them

    static func labelAdded(_ name: String) -> String { "Added the label \(name)" }
    static func labelRemoved(_ name: String) -> String { "Removed the label \(name)" }

    /// A subtitle as VoiceOver reads it: the middle dots between its parts become commas,
    /// so no punctuation setting reads "middle dot" aloud.
    static func spokenList(_ text: String) -> String {
        text.replacingOccurrences(of: " · ", with: ", ")
    }

    static func summary(_ state: SummaryState) -> SummaryLine {
        switch state {
        case .done(let text): .summary(text)
        case .pending, .retrying: .note("Summarizing on this Mac…")
        case .noText: .note("This page had no article text to summarize.")
        case .unavailable(.appleIntelligenceOff): .note("Turn on Apple Intelligence in System Settings and sealed pages get a summary here.")
        case .unavailable(.deviceNotEligible): .note("This Mac can’t write summaries. It doesn’t support Apple Intelligence.")
        case .failed: .note("Apple Intelligence couldn’t summarize this page.")
        }
    }

    static func state(_ item: Item, jar: String) -> String {
        switch item.state {
        case .brined: "In Brine"
        case .jarred: "In \(jar)"
        case .sealed: item.jarId == nil ? "Sealed" : "Sealed in \(jar)"
        }
    }

    static func source(_ source: CaptureSource) -> String {
        switch source {
        case .browse: "Browsing"
        case .shareExtension: "The Share menu"
        case .clipboard: "The clipboard"
        case .drop: "Dropped in"
        case .shortcut: "Shortcuts"
        case .recipe: "A Recipe"
        }
    }

    /// A shelf life in the largest unit that says it exactly: 3 days, 12 hours, 90 minutes.
    /// Short ones exist (the demo sets minutes), so nothing rounds up to an hour.
    static func days(_ days: Double) -> String {
        let units: [(perDay: Double, name: String)] = [(1, "day"), (24, "hour"), (1_440, "minute"), (86_400, "second")]
        for unit in units {
            let value = days * unit.perDay
            if value >= 1, abs(value - value.rounded()) < 1e-6 {
                let n = Int(value.rounded())
                return n == 1 ? "1 \(unit.name)" : "\(n) \(unit.name)s"
            }
        }
        let seconds = max(1, Int((days * 86_400).rounded()))
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }
}

/// What the Bench says out loud, kept out of the views so tests can read it.
enum BenchText {
    static let readerOpened = "Reader view"
    static let readerClosed = "Back to the page"
    /// The broken-seal banner's sentence, drawn and spoken alike.
    static let brokenSeal = "This saved copy has changed since it was sealed. It no longer matches its fingerprint."
}
