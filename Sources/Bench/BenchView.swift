// BenchView.swift — the web panes (manifest v2.0 §8 Bench + Tabs). The Bench shows the
// active tab's WKWebView, one web view per tab, each on its jar's data store; or the jar's
// board; or a smart jar's rows; or a sealed item's saved copy. The tab strip lives in the
// window's title row and the address in the row under it (ShellRows.swift).

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
                    .overlay(alignment: .topLeading) {
                        SealDrip(trigger: workbench.sealTrigger)
                            .padding(.leading, NRSpace.sp2)
                            .padding(.top, NRSpace.sp2)   // just under the address row
                    }
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
            }
        }
        .onAppear {
            let jarId = web.jarId      // the view's own jar, so a page left behind by a move is told apart
            web.onNavigation = { [workbench] url, title in
                workbench.tabDidNavigate(tab.id, fromJar: jarId, url: url, title: title)
            }
        }
    }
}

/// The tab strip, in the window's title row (manifest v2.0 §8 Tabs, Workstation v5 spec
/// §6.2). It leads with the jar's chip, which opens the jar's board. Every tab is a fixed
/// width and always has a border, so a tab never blends into the chrome; the tab in front
/// takes the jar's color on its border and along its bottom edge. A tab can be dragged onto
/// another tab to take its place, or onto a jar on the Shelf to move there; the tab it is
/// over shows the drop mark.
struct TabStrip: View {
    @Bindable var workbench: Workbench
    /// The tab a dragged tab is over.
    @State private var dropTarget: String?

    /// The strip is only as wide as its tabs, so the rest of the title row moves the window.
    private var tabsWidth: CGFloat {
        let widths = workbench.tabs.map { $0.isPinned ? NRShell.pinnedTabW : NRShell.tabW }
        return widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * NRShell.tabGap
    }

    var body: some View {
        HStack(spacing: NRShell.tabGap) {
            if let jar = workbench.activeJar {
                JarChip(jar: jar, fill: workbench.fill(of: jar), isFront: workbench.panelSubject == .jar(jar)) {
                    workbench.showBoard()
                }
                .contextMenu {
                    Button("New Tab in \(jar.name)") { workbench.newTab(in: jar.id) }
                    Button("Edit Jar…") { workbench.requestEditActiveJar() }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NRShell.tabGap) {
                        ForEach(workbench.tabs) { tab in
                            TabChip(tab: tab, jar: jar, isActive: tab.id == workbench.benchTab?.id, now: workbench.now,
                                    glyph: workbench.glyph(of: tab), isDropTarget: dropTarget == tab.id,
                                    activate: { workbench.activateTab(tab) }, close: { workbench.closeTab(tab) })
                                .contextMenu { menu(for: tab) }
                                .draggable(DragPayload.tab(tab.id).string)
                                .dropDestination(for: String.self) { payloads, _ in
                                    workbench.drop(payloads, onTab: tab)
                                } isTargeted: { over in
                                    if over { dropTarget = tab.id } else if dropTarget == tab.id { dropTarget = nil }
                                }
                        }
                    }
                }
                .frame(maxWidth: tabsWidth)
                .layoutPriority(1)
                Button { workbench.newTab() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                        .frame(width: NRSpace.tabH, height: NRSpace.tabH).contentShape(Rectangle())
                        .overlay(RoundedRectangle(cornerRadius: NRRadius.r2)
                            .strokeBorder(NRColor.hairline, style: StrokeStyle(lineWidth: NRSpace.hairline, dash: [3, 3])))
                }
                .buttonStyle(.plain).foregroundStyle(NRColor.fg2).help("New Tab (⌘T)").accessibilityLabel("New Tab")
            } else if let smart = workbench.activeSmartJar {
                Text(smart.name).font(NRType.font(NRType.fsMd, weight: .semibold)).foregroundStyle(NRColor.fg2)
                    .padding(.horizontal, NRSpace.sp3)
            }
        }
    }

    @ViewBuilder private func menu(for tab: Tab) -> some View {
        Button(tab.isPinned ? "Unpin" : "Pin") { workbench.togglePin(tab) }
        Picker("Icon", selection: Binding(get: { workbench.glyph(of: tab) ?? TabGlyph.standard },
                                          set: { workbench.setGlyph($0 == TabGlyph.standard ? nil : $0, for: tab) })) {
            ForEach(TabGlyph.choices) { choice in
                Label(choice.name, systemImage: choice.symbol).tag(choice.symbol)
            }
        }
        .pickerStyle(.palette)
        Divider()
        Button("Copy Link") { workbench.copyLink(of: tab) }.disabled(tab.url?.isEmpty != false)
        let others = workbench.jars.filter { $0.id != tab.jarId }
        if !others.isEmpty {
            Menu("Move to Jar") {
                ForEach(others) { other in
                    Button(other.name) { workbench.moveTab(tab, toJar: other.id) }
                }
            }
        }
        Divider()
        Button("Close") { workbench.closeTab(tab) }
        Button("Close Other Tabs") { workbench.closeOtherTabs(tab) }.disabled(workbench.tabs.count < 2)
    }
}

/// The jar's chip at the head of the tab strip: the jar drawn at 19pt and its name, on a
/// wash of the jar's color. It opens the jar's board, and is outlined while the board shows.
struct JarChip: View {
    let jar: Jar
    let fill: Double
    /// The board, not a page, is what the Bench shows.
    let isFront: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: NRSpace.sp2) {
                NRFilledJar(paint: jar.paint, fill: fill, size: 16)
                // The frame's ideal width is the name's, held to 180: a long name truncates
                // here and never crowds the tabs. The tooltip has it in full.
                Text(jar.name).font(NRType.font(NRType.fsMd, weight: .semibold)).foregroundStyle(NRColor.fg)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .leading)
            }
            .padding(.horizontal, NRSpace.sp3)
            .frame(height: NRSpace.tabH)
            .fixedSize(horizontal: true, vertical: false)
            .background(jar.paint.wash(0.20), in: RoundedRectangle(cornerRadius: NRRadius.r2))
            .overlay(RoundedRectangle(cornerRadius: NRRadius.r2)
                .strokeBorder(jar.paint.wash(isFront ? 1 : 0.45), lineWidth: NRSpace.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(jar.name): what's in this jar")
        .accessibilityLabel("\(jar.name) board")
        .accessibilityAddTraits(isFront ? .isSelected : [])
    }
}

/// The icons a tab's menu offers, as SF Symbols (manifest §7: system line icons for
/// everything that isn't a jar). The first is what every tab wears until one is picked.
struct TabGlyph: Identifiable {
    let symbol: String
    let name: String
    var id: String { symbol }

    static let standard = "globe"
    static let choices: [TabGlyph] = [
        TabGlyph(symbol: standard, name: "Website"),
        TabGlyph(symbol: "envelope", name: "Mail"),
        TabGlyph(symbol: "doc.text", name: "Document"),
        TabGlyph(symbol: "photo", name: "Picture"),
        TabGlyph(symbol: "key", name: "Sign-in"),
        TabGlyph(symbol: "powerplug", name: "Plug-in"),
        TabGlyph(symbol: "shippingbox", name: "Store"),
        TabGlyph(symbol: "hammer", name: "Build"),
    ]
}

/// A tab's icon chip: the icon picked for it, or the first letter of its site.
struct TabIcon: View {
    let tab: Tab
    var glyph: String? = nil
    var size: CGFloat = 19

    /// The site's first letter: "j" for juniperbakery.example, never the "w" of "www".
    static func letter(for tab: Tab) -> String? {
        guard let url = tab.url, let host = URL(string: url)?.host ?? URL(string: "https://" + url)?.host else { return nil }
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return name.first.map { String($0).uppercased() }
    }

    var body: some View {
        Group {
            if let glyph {
                Image(systemName: glyph).font(.system(size: size * 0.6, weight: .medium))
            } else if let letter = Self.letter(for: tab) {
                Text(letter).font(.system(size: size * 0.55, weight: .semibold))
            } else {
                Image(systemName: TabGlyph.standard).font(.system(size: size * 0.6))
            }
        }
        .foregroundStyle(NRColor.fg2)
        .frame(width: size, height: size)
        .background(glyph == nil ? NRColor.hairline.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: size * 0.3))
        .accessibilityHidden(true)
    }
}

struct TabChip: View {
    let tab: Tab
    let jar: Jar
    let isActive: Bool
    let now: Date
    /// The icon picked for this tab, as an SF Symbol name; nil for the standard one.
    var glyph: String? = nil
    /// A dragged tab is over this one and would take its place.
    var isDropTarget = false
    let activate: () -> Void
    let close: () -> Void
    @State private var hovering = false

    private var fading: Bool { ShelfLife.isFading(tab, in: jar, now: now) }
    private var label: String { (tab.title?.isEmpty == false ? tab.title : tab.url) ?? "New Tab" }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: NRRadius.r2) }

    var body: some View {
        HStack(spacing: NRSpace.sp2) {
            TabIcon(tab: tab, glyph: glyph)
            if !tab.isPinned {
                Text(label)
                    .font(NRType.font(NRType.fsMd, weight: isActive ? .medium : .regular))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hovering {
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(NRColor.fg2).help("Close Tab (⌘W)")
                        .accessibilityLabel("Close Tab")
                }
            }
        }
        .foregroundStyle(fading ? NRColor.fg3 : NRColor.fg)
        .padding(.horizontal, tab.isPinned ? 0 : NRSpace.sp3)
        .frame(width: tab.isPinned ? NRShell.pinnedTabW : NRShell.tabW, height: NRSpace.tabH)
        .background(isActive ? NRColor.surface : NRColor.bg, in: shape)
        .overlay(shape.strokeBorder(isActive ? jar.paint.face : NRColor.hairline, lineWidth: NRSpace.hairline))
        // The tab in front: a bar in the jar's color along its bottom edge.
        .overlay(alignment: .bottom) {
            if isActive {
                Capsule().fill(jar.paint.face).frame(height: 2).padding(.horizontal, 9)
            }
        }
        .overlay(alignment: .topTrailing) {
            if tab.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 7)).foregroundStyle(NRColor.fg3).padding(3)
            }
        }
        .overlay(alignment: .leading) { if isDropTarget { NRDropMark().padding(.vertical, NRSpace.sp1) } }
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .onHover { hovering = $0 }
        .help(tab.isPinned ? "\(label). Pinned: it never sinks" : label)
        .accessibilityAddTraits(.isButton)
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
    /// Whether the copy on disk is still the one that was sealed (ADR 0030).
    @State private var integrity: SealIntegrity = .unchecked

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
    }

    /// Shown instead of silence when the copy no longer matches its fingerprint. The copy is
    /// still shown underneath: the point is that the change can be seen, not that it is hidden.
    private var brokenSeal: some View {
        HStack(spacing: NRSpace.sp2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NRColor.danger)
            Text("This saved copy has changed since it was sealed. It no longer matches its fingerprint.")
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
                Button("New Tab") { workbench.newTab(in: jar.id) }.buttonStyle(.nrSecondary)
                Button("Edit Jar…") { workbench.requestEditActiveJar() }.buttonStyle(.nrSecondary)
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
                            .help(PanelText.sealAgainHelp)
                        if seals.count > 1 {
                            Button("Compare") { Task { await workbench.compareWithPrevious(seals[0]) } }
                                .buttonStyle(.nrSecondary)
                                .help(PanelText.compareHelp)
                        }
                        if !workbench.pro.isUnlocked { ProTag() }
                    }
                }
            }
        }
        .task(id: "\(item.id)|\(workbench.sealedItems.count)") { seals = workbench.seals(of: item) }
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
