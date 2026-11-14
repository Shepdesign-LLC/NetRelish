// ShellRows.swift — the window's three rows of chrome around the Shelf, the Bench and the
// Panel (manifest v2.0 §8 and §10, Workstation v5 spec §5): the title row (the window's
// buttons, back and forward, the mark, the tab strip), the address row under it with its
// relish top line, and the bottom bar with the Brine pill. Hand-written.

import Pantry
import SwiftUI

/// The shell's measures, from the Workstation v5 spec §3.2. The Shelf and Panel widths and
/// the tab height are tokens (`NRSpace`); these are the rest.
enum NRShell {
    static let titleH: CGFloat = 48
    static let searchH: CGFloat = 46
    static let barH: CGFloat = 44
    static let tabW: CGFloat = 176
    static let pinnedTabW: CGFloat = 46
    static let tabGap: CGFloat = 6
    /// Room for the window's close, minimize and zoom buttons, which sit over the title row.
    static let windowButtonsW: CGFloat = 78
    /// The relish line along the top of the address row.
    static let relishLineH: CGFloat = 2
}

/// Row 1: the window's buttons, back and forward, the mark, then the tab strip. The title
/// bar is hidden, so this row is the top of the window; its empty stretches move the window.
struct TitleRow: View {
    @Bindable var workbench: Workbench
    /// The page in front, if the Bench is showing one.
    let web: JarWebView?

    var body: some View {
        HStack(spacing: NRSpace.sp2) {
            Color.clear.frame(width: NRShell.windowButtonsW)
                .contentShape(Rectangle()).gesture(WindowDragGesture())
            Button { web?.goBack() } label: { Image(systemName: "chevron.left").frame(width: 24, height: 28).contentShape(Rectangle()) }
                .disabled(web?.canGoBack != true).help("Back").accessibilityLabel("Back")
            Button { web?.goForward() } label: { Image(systemName: "chevron.right").frame(width: 24, height: 28).contentShape(Rectangle()) }
                .disabled(web?.canGoForward != true).help("Forward").accessibilityLabel("Forward")
            Button { workbench.showBoard() } label: {
                NRLogo.cog.image.resizable().frame(width: 28, height: 28)
            }
            .disabled(workbench.activeJar == nil)
            .help("What's in this jar").accessibilityLabel("Jar board")
            TabStrip(workbench: workbench)
                .layoutPriority(1)
            Color.clear.frame(minWidth: NRSpace.sp6, maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle()).gesture(WindowDragGesture())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NRColor.fg2)
        .font(.system(size: 13, weight: .medium))
        .padding(.trailing, NRSpace.sp3)
        .frame(height: NRShell.titleH)
        .background(NRColor.surface2)
    }
}

/// Row 2: the address field, full width, under a line of relish. With a page in front it
/// shows that page's address and loads what you type there; otherwise what you type opens
/// in a new tab in the jar you're in.
struct SearchRow: View {
    @Bindable var workbench: Workbench
    /// The page in front, if the Bench is showing one.
    let web: JarWebView?
    @State private var address = ""
    @FocusState private var focused: Bool

    private var tab: Tab? { workbench.benchTab }
    private var reading: Bool { workbench.isReading }

    var body: some View {
        HStack(spacing: NRSpace.sp2) {
            omnibox
            Button { workbench.showPanel.toggle() } label: {
                Image(systemName: "sidebar.trailing").frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .help(workbench.showPanel ? "Hide Panel (⌘⌥I)" : "Show Panel (⌘⌥I)")
            .accessibilityLabel(workbench.showPanel ? "Hide panel" : "Show panel")
        }
        .buttonStyle(.plain)
        .foregroundStyle(NRColor.fg2)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: NRShell.searchH)
        .background(NRColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(NRColor.relish500).frame(height: NRShell.relishLineH) }
        .overlay(alignment: .bottom) { Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline) }
        .onChange(of: tab?.id, initial: true) { _, _ in show(web?.url?.absoluteString ?? tab?.url ?? "") }
        .onChange(of: web?.url) { _, new in if !focused { address = new?.absoluteString ?? tab?.url ?? "" } }
        .animation(.easeOut(duration: NRMotion.base), value: workbench.fillStatus)
    }

    private var omnibox: some View {
        HStack(spacing: NRSpace.sp2) {
            Image(systemName: "magnifyingglass").foregroundStyle(NRColor.relish700).accessibilityHidden(true)
            TextField("Type a web address", text: $address)
                .textFieldStyle(.plain)
                .font(NRType.font(NRType.fsMd))
                .foregroundStyle(NRColor.fg)
                .focused($focused)
                .onSubmit(go)
                .accessibilityLabel("Address")
            if let status = workbench.fillStatus {
                Text(status).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
                    .transition(.opacity).accessibilityIdentifier("fill-status")
            }
            if tab != nil {
                Button { workbench.captureActivePage() } label: { Image(systemName: "bookmark") }
                    .help("Capture This Page (⌘D)").accessibilityLabel("Capture this page")
                Button { Task { await workbench.toggleReader() } } label: { Image(systemName: "doc.plaintext") }
                    .foregroundStyle(reading ? NRColor.fg : NRColor.fg2)
                    .help(reading ? "Back to the Page (⌘⇧R)" : "Reader View (⌘⇧R)")
                    .accessibilityLabel(reading ? "Back to the page" : "Reader view")
                if let web {
                    Button { web.isLoading ? web.webView.stopLoading() : web.reload() } label: {
                        Image(systemName: web.isLoading ? "xmark" : "arrow.clockwise")
                    }
                    .help(web.isLoading ? "Stop" : "Reload").accessibilityLabel(web.isLoading ? "Stop" : "Reload")
                }
            }
        }
        .padding(.horizontal, NRSpace.sp3)
        .frame(height: 32)
        .background(NRColor.bg, in: RoundedRectangle(cornerRadius: NRRadius.r2))
        .overlay(RoundedRectangle(cornerRadius: NRRadius.r2)
            .strokeBorder(focused ? NRColor.focus : NRColor.hairline, lineWidth: focused ? 2 : NRSpace.hairline))
    }

    /// The address of what's in front. A new, blank tab takes the cursor, ready to type.
    private func show(_ text: String) {
        address = text
        if let tab, let web, web.url == nil, tab.url == nil, !web.openedByPage { focused = true }
    }

    private func go() {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let web { web.load(text) } else { workbench.newTab(url: text) }
        focused = false
    }
}

/// Row 4: the bottom bar. Brine is the pill on the leading edge: it lights up in relish
/// when something has sunk, and opens Brine on the Bench. The trailing edge carries the
/// Pantry's count and the way into ⌘K.
struct BottomBar: View {
    @Bindable var workbench: Workbench

    private var sunk: Int { workbench.brine.count }
    private var isOpen: Bool { workbench.activeSmartJar == .brine }

    var body: some View {
        HStack(spacing: NRSpace.sp3) {
            Button { workbench.activateBrine() } label: {
                HStack(spacing: NRSpace.sp2) {
                    NRSymbol.sink.image.resizable().frame(width: 14, height: 14)
                    Text("Brine").font(NRType.font(NRType.fsMd, weight: .medium))
                    if sunk > 0 {
                        Text("\(sunk)").font(NRType.font(NRType.fsXs, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(NRColor.relishInk)
                            .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                            .background(NRColor.relish500, in: Capsule())
                    }
                }
                .foregroundStyle(sunk > 0 ? NRColor.relish700 : NRColor.fg2)
                .padding(.horizontal, NRSpace.sp3)
                .frame(height: 30)
                .background(sunk > 0 || isOpen ? NRColor.relish100 : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(sunk > 0 ? NRColor.relish500 : NRColor.hairline,
                                                lineWidth: sunk > 0 ? 1.5 : NRSpace.hairline))
                .contentShape(Capsule())
            }
            .help("Brine — \(SmartJar.brine.shortcutLabel)")
            .accessibilityLabel("Brine, \(sunk) sunk")
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            Spacer()
            Text("\(workbench.itemCount) \(workbench.itemCount == 1 ? "item" : "items") in the Pantry")
                .font(NRType.font(NRType.fsSm)).monospacedDigit().foregroundStyle(NRColor.fg3)
            Button { workbench.showPalette = true } label: {
                Text("⌘K").font(NRType.font(NRType.fsXs, weight: .medium)).foregroundStyle(NRColor.fg2)
                    .padding(.horizontal, NRSpace.sp2).frame(height: 24)
                    .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                    .contentShape(Rectangle())
            }
            .help("Command Palette (⌘K)").accessibilityLabel("Command palette")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: NRShell.barH)
        .background(NRColor.surface2)
        .overlay(alignment: .top) { Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline) }
    }
}
