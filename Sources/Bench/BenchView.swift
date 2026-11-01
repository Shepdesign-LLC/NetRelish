// BenchView.swift — the web panes (manifest §8 Bench + Tabs). A tab strip at tabH, the
// address bar, and the active tab's WKWebView. One web view per tab, each on its jar's
// data store. When a smart jar is active, the Bench shows that jar's rows instead; when a
// sealed item is opened, it shows that item's saved copy.

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
        if let v = byTab[tab.id] { return v }
        let v = JarWebView(jarId: tab.jarId ?? "brine")
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

    func existing(for tabId: String) -> JarWebView? { byTab[tabId] }
    func forget(_ tabId: String) { byTab[tabId] = nil }
}

struct BenchView: View {
    @Bindable var workbench: Workbench
    @State private var webViews = BenchWebViews()

    /// One container, so the wiring runs whatever the Bench is showing first.
    var body: some View {
        ZStack { content }
            .onAppear { wire() }
    }

    @ViewBuilder private var content: some View {
        if let item = workbench.savedCopy {
            SavedCopyView(item: item, workbench: workbench)
                .id(item.id)
        } else if let smart = workbench.activeSmartJar {
            SmartJarView(smart: smart, workbench: workbench)
        } else if let jar = workbench.activeJar {
            VStack(spacing: 0) {
                TabStrip(workbench: workbench, jar: jar)
                if let tab = workbench.activeTab {
                    let web = webViews.view(for: tab)
                    TabPane(tab: tab, web: web, workbench: workbench)
                        .id(tab.id)
                        .overlay(alignment: .topLeading) {
                            SealDrip(trigger: workbench.sealTrigger)
                                .padding(.leading, NRSpace.sp2)
                                .padding(.top, 44)   // just under the address bar
                        }
                } else {
                    EmptyBench(message: "No tabs in \(jar.name). Press ⌘T.")
                }
            }
            .background(NRColor.surface)
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
    }
}

/// One tab's address bar and web view.
struct TabPane: View {
    let tab: Tab
    let web: JarWebView
    @Bindable var workbench: Workbench
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
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
            }
        }
        .onAppear {
            address = web.url?.absoluteString ?? tab.url ?? ""
            web.onNavigation = { [workbench] url, title in workbench.tabDidNavigate(tab.id, url: url, title: title) }
            if web.url == nil, tab.url == nil, !web.openedByPage { addressFocused = true }
        }
        .onChange(of: web.url) { _, new in if !addressFocused { address = new?.absoluteString ?? "" } }
    }

    private var reading: Bool { workbench.reader?.tabId == tab.id }

    private var addressBar: some View {
        HStack(spacing: NRSpace.sp2) {
            Button { web.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!web.canGoBack).help("Back")
            Button { web.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!web.canGoForward).help("Forward")
            TextField("Address", text: $address)
                .textFieldStyle(.plain)
                .font(NRType.font(NRType.fsSm, design: NRType.fontMono))
                .foregroundStyle(NRColor.fg)
                .focused($addressFocused)
                .onSubmit { web.load(address); addressFocused = false }
                .padding(.horizontal, NRSpace.sp3)
                .frame(height: 26)
                .background(NRColor.surface2, in: RoundedRectangle(cornerRadius: NRRadius.r1))
                .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(addressFocused ? NRColor.focus : .clear, lineWidth: 2))
            if let status = workbench.fillStatus {
                Text(status).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
                    .transition(.opacity).accessibilityIdentifier("fill-status")
            }
            Button { Task { await workbench.toggleReader() } } label: { Image(systemName: "doc.plaintext") }
                .foregroundStyle(reading ? NRColor.fg : NRColor.fg2)
                .help(reading ? "Back to the Page (⌘⇧R)" : "Reader View (⌘⇧R)")
                .accessibilityLabel(reading ? "Back to the page" : "Reader view")
            Button { web.isLoading ? web.webView.stopLoading() : web.reload() } label: {
                Image(systemName: web.isLoading ? "xmark" : "arrow.clockwise")
            }.help(web.isLoading ? "Stop" : "Reload")
        }
        .buttonStyle(.plain)
        .foregroundStyle(NRColor.fg2)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, NRSpace.sp3)
        .frame(height: 38)
        .background(NRColor.surface)
        .animation(.easeOut(duration: NRMotion.base), value: workbench.fillStatus)
    }
}

/// Manifest §8 Tabs: tabH, r2 top corners, surface active / transparent inactive, the lip
/// on the active tab only, a pin glyph on pinned tabs, fg3 over the last 10% of shelf life.
struct TabStrip: View {
    @Bindable var workbench: Workbench
    let jar: Jar

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(workbench.tabs) { tab in
                        TabChip(tab: tab, jar: jar, isActive: tab.id == workbench.activeTabId, now: workbench.now,
                                activate: { workbench.activateTab(tab) }, close: { workbench.closeTab(tab) }, pin: { workbench.togglePin(tab) })
                    }
                }
            }
            Button { workbench.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(NRColor.fg2).help("New Tab (⌘T)")
        }
        .padding(.horizontal, NRSpace.sp2)
        .padding(.top, NRSpace.sp2)
        .frame(height: NRSpace.tabH + NRSpace.sp2)
        .background(NRColor.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline) }
    }
}

struct TabChip: View {
    let tab: Tab
    let jar: Jar
    let isActive: Bool
    let now: Date
    let activate: () -> Void
    let close: () -> Void
    let pin: () -> Void
    @State private var hovering = false

    private var fading: Bool { ShelfLife.isFading(tab, in: jar, now: now) }
    private var label: String { (tab.title?.isEmpty == false ? tab.title : tab.url) ?? "New Tab" }

    var body: some View {
        HStack(spacing: NRSpace.sp2) {
            if tab.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(NRColor.fg2).help("Pinned — never sinks")
            } else {
                Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(NRColor.fg3)
            }
            if !tab.isPinned {
                Text(label)
                    .font(NRType.font(NRType.fsSm, weight: isActive ? .medium : .regular))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            if hovering, !tab.isPinned {
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(NRColor.fg2).help("Close Tab (⌘W)")
            }
        }
        .foregroundStyle(fading ? NRColor.fg3 : NRColor.fg)
        .padding(.horizontal, NRSpace.sp3)
        .frame(height: NRSpace.tabH)
        .background(isActive ? NRColor.surface : .clear,
                    in: UnevenRoundedRectangle(topLeadingRadius: NRRadius.r2, topTrailingRadius: NRRadius.r2))
        .overlay(alignment: .top) { if isActive { NRTabLip().padding(.horizontal, NRSpace.sp2) } }
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(tab.isPinned ? "Unpin" : "Pin", action: pin)
            Button("Close", action: close)
        }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: fading)
    }
}

struct EmptyBench: View {
    let message: String
    /// An optional way out, shown as the view's one primary button.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: NRSpace.sp4) {
            NRLogo.cog.image.resizable().frame(width: NRSpace.sp12, height: NRSpace.sp12)
            Text(message).font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg2)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.nrPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NRColor.bg)
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

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
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
            if let data = workbench.snapshotData(for: item) { archive = data } else { missing = true }
        }
    }

    private var header: some View {
        HStack(spacing: NRSpace.sp3) {
            NRSymbol.seal.image.resizable().frame(width: NRSpace.sp4, height: NRSpace.sp4)
                .foregroundStyle(NRColor.relish500)   // manifest §4, placement 4
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                Text(subtitle).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
            }
            Spacer()
            if item.url != nil, !missing {
                Button("Open Live Page") { workbench.openLivePage(item) }.buttonStyle(.nrSecondary)
            }
            Button("Done") { workbench.savedCopy = nil }
                .buttonStyle(.nrSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: NRSpace.sp12)
        .background(NRColor.surface)
    }

    private var subtitle: String {
        let sealed = item.sealedAt.map { "Saved copy, sealed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Saved copy"
        return [sealed, item.domain].compactMap { $0 }.joined(separator: " · ")
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
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.loadHTMLString(ReaderPage.html(for: article), baseURL: baseURL)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.openLink = follow }
}

/// The reader's one page. Colors, sizes, line heights and weights are the Bench's tokens
/// (tokens.css, manifest §5), light and dark; tests hold the page to them.
enum ReaderPage {
    /// token → (light, dark), copied from design/tokens.css; a test holds them to it.
    static let palette: [(token: String, light: String, dark: String)] = [
        ("--nr-bg", "#FCFCFB", "#171716"),
        ("--nr-fg", "#1D1D1B", "#F0F0EE"),
        ("--nr-fg-2", "#66665F", "#A8A8A2"),
        ("--nr-hairline", "#E3E3E0", "#3B3B38"),
    ]

    /// Our policy, ahead of anything in the article: no scripts, no frames, no fetches but
    /// images and media, no forms, no base URL games.
    static let contentSecurityPolicy =
        "default-src 'none'; img-src * data:; media-src *; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'; frame-src 'none'"

    static func html(for article: Extraction.Article) -> String {
        let light = palette.map { "\($0.token): \($0.light);" }.joined(separator: " ")
        let dark = palette.map { "\($0.token): \($0.dark);" }.joined(separator: " ")
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

/// The right column (manifest §8, "Inspector" row; called the Panel everywhere a person sees
/// it, ADR 0010 row 9): token width, surface2, the trailing edge, sections between hairlines,
/// fsSm labels in fg2. It describes whatever the Bench is showing. No relish.
struct PanelView: View {
    @Bindable var workbench: Workbench

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: NRSpace.inspectorW)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NRColor.surface2)
        .overlay(alignment: .leading) { Rectangle().fill(NRColor.hairline).frame(width: NRSpace.hairline) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel")
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
            PanelHeader(title: jar.name, subtitle: "Jar")
            PanelSection("Jar") {
                PanelRow("Shelf life", jar.shelfLifeDays.map { PanelText.days($0) } ?? "None. Tabs never sink")
                PanelRow("Open tabs", "\(workbench.tabs.count)")
            }
        case .smartJar(let smart):
            PanelHeader(title: smart.name, subtitle: "Smart jar")
            PanelSection("Smart jar") {
                PanelRow("Holds", "\(workbench.count(of: smart))")
                PanelNote(smart.blurb)
            }
        case .nothing:
            PanelNote("Nothing to describe yet. Open a page or a jar.")
                .padding(NRSpace.sp3)
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
            PanelSection("Labels") {
                ForEach(labels) { label in
                    HStack(spacing: NRSpace.sp2) {
                        Text(label.name).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg)
                        Spacer()
                        Button { workbench.removeLabel(label, from: item) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain).foregroundStyle(NRColor.fg2)
                        .help("Remove \(label.name)").accessibilityLabel("Remove \(label.name)")
                    }
                }
                TextField("Add a label", text: $newLabel)
                    .textFieldStyle(.plain)
                    .font(NRType.font(NRType.fsSm))
                    .foregroundStyle(NRColor.fg)
                    .onSubmit {
                        workbench.addLabel(newLabel, to: item)
                        newLabel = ""
                    }
            }
        }
        .task(id: "\(item.id)|\(workbench.labelRevision)") { labels = workbench.labels(of: item) }
    }
}

private struct PanelHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(2)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
            }
        }
        .padding(NRSpace.sp3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
        VStack(alignment: .leading, spacing: NRSpace.sp2) {
            Text(title.uppercased()).font(NRType.font(NRType.fsXs, weight: .medium)).foregroundStyle(NRColor.fg2)
            content
        }
        .padding(NRSpace.sp3)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(value).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg)
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
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
