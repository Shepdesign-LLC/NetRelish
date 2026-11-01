// BenchView.swift — the web panes (manifest §8 Bench + Tabs). A tab strip at tabH, the
// address bar, and the active tab's WKWebView. One web view per tab, each on its jar's
// data store. When the Shelf's Brine jar is active, the Bench shows Brine instead; when a
// sealed item is opened, it shows that item's saved copy.

import Pantry
import SwiftUI
import WebKit

@MainActor
@Observable
final class BenchWebViews {
    private var byTab: [String: JarWebView] = [:]

    /// Set by the Bench: makes a new, active tab in a jar for a page's new window.
    @ObservationIgnored var makeTab: ((String) -> Tab?)?
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
    /// a web view for it, built on the configuration WebKit passed. Nil if no tab was made.
    func openNewWindow(from parent: JarWebView, configuration: WKWebViewConfiguration) -> WKWebView? {
        guard let tab = makeTab?(parent.jarId) else { return nil }
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
        v.onClose = { [weak self] in self?.closeTab?(tabId) }
        byTab[tabId] = v
    }

    func existing(for tabId: String) -> JarWebView? { byTab[tabId] }
    func forget(_ tabId: String) { byTab[tabId] = nil }
}

struct BenchView: View {
    @Bindable var workbench: Workbench
    @State private var webViews = BenchWebViews()

    var body: some View {
        if let item = workbench.sealedCopy {
            SealedCopyView(item: item, workbench: workbench)
                .id(item.id)
        } else if workbench.showingBrine {
            BrineView(workbench: workbench)
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
            .onAppear { wire() }
            .onChange(of: workbench.tabs.map(\.id)) { old, new in
                for gone in Set(old).subtracting(new) { webViews.forget(gone) }
            }
        } else {
            EmptyBench(message: "No jar yet. Make one on the Shelf.")
        }
    }

    /// The sweep asks the Bench for a tab's live interaction state before sinking it.
    private func wire() {
        webViews.makeTab = { [workbench] jarId in workbench.newTab(in: jarId) }
        webViews.closeTab = { [workbench] tabId in workbench.closeTab(id: tabId) }
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
            WebViewHost(jarWebView: web)
        }
        .onAppear {
            address = web.url?.absoluteString ?? tab.url ?? ""
            web.onNavigation = { [workbench] url, title in workbench.tabDidNavigate(tab.id, url: url, title: title) }
            if web.url == nil, tab.url == nil, !web.openedByPage { addressFocused = true }
        }
        .onChange(of: web.url) { _, new in if !addressFocused { address = new?.absoluteString ?? "" } }
    }

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
    var body: some View {
        VStack(spacing: NRSpace.sp4) {
            NRLogo.cog.image.resizable().frame(width: 48, height: 48)
            Text(message).font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NRColor.bg)
    }
}

/// A sealed item's saved copy: the page as it was when sealed, read only. JavaScript is off
/// and the data store is throwaway, so nothing on the page runs, nothing is signed in, and
/// the snapshot on disk is never written to (non-negotiable 3).
struct SealedCopyView: View {
    let item: Item
    @Bindable var workbench: Workbench
    @State private var webView = SealedCopyView.makeWebView()
    @State private var missing = false

    static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: config)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            if missing {
                EmptyBench(message: "The saved copy of this page is missing.")
            } else {
                PlainWebViewHost(webView: webView)
            }
        }
        .background(NRColor.surface)
        .onExitCommand { workbench.sealedCopy = nil }
        .task {
            guard let data = workbench.snapshotData(for: item) else { missing = true; return }
            webView.load(data, mimeType: "application/x-webarchive", characterEncodingName: "utf-8",
                         baseURL: item.url.flatMap(URL.init(string:)) ?? URL(string: "about:blank")!)
        }
    }

    private var header: some View {
        HStack(spacing: NRSpace.sp3) {
            NRSymbol.seal.image.resizable().frame(width: 16, height: 16).foregroundStyle(NRColor.fg2)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                Text(subtitle).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
            }
            Spacer()
            if item.url != nil {
                Button("Open Live Page") { workbench.openLivePage(item) }.buttonStyle(.nrSecondary)
            }
            Button("Done") { workbench.sealedCopy = nil }.buttonStyle(.nrSecondary)
        }
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: 52)
        .background(NRColor.surface)
    }

    private var subtitle: String {
        let sealed = item.sealedAt.map { "Sealed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Sealed"
        return [sealed, item.domain, "saved copy"].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Hosts a bare WKWebView in SwiftUI.
struct PlainWebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
