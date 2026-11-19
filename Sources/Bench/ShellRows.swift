// ShellRows.swift — the window's rows of chrome (manifest v2.1 §8 and §10, the Workbench
// facelift comp): the 44pt title strip across the whole window (the window's buttons, the
// cog mark, the tabs over the Bench column), the 44pt address row over the Bench only (the
// jar's chip, back and forward, the field, Seal, the Panel toggle), and the 32pt bottom bar
// across the whole window (the Brine pill, the Pantry's count, the way into ⌘K).
// Hand-written. The tabs themselves are in TabStrip.swift; the window's buttons are moved by
// WindowChrome.swift.

import AppKit
import Pantry
import SwiftUI

/// The shell's measures, from the facelift comp (ADR 0035). The Shelf and Panel widths, the
/// lip and the hairline are tokens (`NRSpace`); these are the rest.
enum NRShell {
    static let titleH: CGFloat = 44
    static let addressH: CGFloat = 44
    static let fieldH: CGFloat = 28
    static let barH: CGFloat = 32
    static let tabH: CGFloat = 33           // a tab behind
    static let frontTabH: CGFloat = 38      // the tab in front; its bottom covers the strip's hairline
    static let tabRadius: CGFloat = 8
    static let tabMinW: CGFloat = 116
    static let tabMaxW: CGFloat = 224
    static let frontTabMaxW: CGFloat = 260
    static let pinnedTabW: CGFloat = 44
    static let tabGap: CGFloat = 4
    static let markSize: CGFloat = 28
    static let markLeading: CGFloat = 80
    static let windowButtonsLeading: CGFloat = 18
    static let windowButtonsCenterY: CGFloat = 22
    static let windowMinW: CGFloat = 960
    static let windowMinH: CGFloat = 600
}

/// Row 1, the title strip, across the whole window: the window's buttons (AppKit draws them),
/// the cog mark at 80pt, then the tabs from the Shelf's width on, so they sit over the Bench
/// column. The title bar is hidden, so this row is the top of the window; its empty stretches
/// move the window. A double-click on it is AppKit's title bar's, as on any window.
struct TitleRow: View {
    @Bindable var workbench: Workbench
    @FocusState private var markFocused: Bool

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                WindowDragArea()
                    .frame(width: NRShell.markLeading)
                mark
                WindowDragArea()
                    .frame(width: max(0, NRSpace.shelfW - NRShell.markLeading - NRShell.markSize))
                TabStrip(workbench: workbench, available: max(0, geo.size.width - NRSpace.shelfW))
            }
            .frame(width: geo.size.width, height: NRShell.titleH, alignment: .leading)
        }
        .frame(height: NRShell.titleH)
        // Under the tabs: the tab in front covers this line, so it joins the address row.
        .background(alignment: .bottom) {
            Rectangle().fill(NRColor.hairlineSoft).frame(height: NRSpace.hairline)
        }
        .background(NRColor.surface)
        .background(WindowButtonsPlacement())
    }

    /// The cog mark (logo-cog, never redrawn): it opens the jar's board.
    private var mark: some View {
        Button { workbench.showBoard() } label: {
            NRLogo.cog.image.resizable()
                .frame(width: NRShell.markSize, height: NRShell.markSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($markFocused)
        .overlay {
            if markFocused {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(NRColor.focus, lineWidth: 2)
                    .padding(-2)
                    .allowsHitTesting(false)
            }
        }
        .disabled(workbench.activeJar == nil)
        .help("Show the jar’s board")
        .accessibilityLabel("Jar board")
        .frame(width: NRShell.markSize, height: NRShell.titleH)
    }
}

/// Row 2, the address row, over the Bench column only: the jar's chip, back and forward, the
/// address field, Seal, and the Panel toggle. With a page in front the field shows that page's
/// address and loads what you type there; otherwise what you type opens in a new tab in the
/// jar you're in.
struct SearchRow: View {
    @Bindable var workbench: Workbench
    /// The page in front, if the Bench is showing one.
    let web: JarWebView?
    @State private var address = ""
    @FocusState private var focused: Bool

    private var tab: Tab? { workbench.benchTab }
    /// Origin chrome always follows the live page, never Seal's retained animation chip.
    var pageURL: URL? { web?.url ?? tab?.url.flatMap { URL(string: $0) } }
    var pageAddress: String { web?.url?.absoluteString ?? tab?.url ?? "" }
    /// Derive idle text during rendering so a tab switch cannot display the old origin
    /// for a frame while waiting for an onChange callback. Only edits live in state.
    private var displayedAddress: String { focused ? address : pageAddress }

    var body: some View {
        HStack(spacing: NRSpace.sp1) {
            if let jar = workbench.activeJar {
                JarChip(workbench: workbench, jar: jar)
            } else if let smart = workbench.activeSmartJar {
                SmartJarChip(smart: smart)
            }
            RowIconButton(systemName: "chevron.left", help: "Back") { web?.goBack() }
                .disabled(web?.canGoBack != true)
            RowIconButton(systemName: "chevron.right", help: "Forward") { web?.goForward() }
                .disabled(web?.canGoForward != true)
            AddressField(workbench: workbench, web: web, pageURL: pageURL,
                         address: Binding(get: { displayedAddress }, set: { address = $0 }),
                         focused: $focused, go: go)
                .padding(.leading, NRSpace.sp1)
            sealSlot
                .padding(.leading, NRSpace.sp1)
            RowIconButton(systemName: "sidebar.trailing",
                          help: workbench.showPanel ? "Hide Panel (⌘⌥I)" : "Show Panel (⌘⌥I)",
                          label: workbench.showPanel ? "Hide panel" : "Show panel",
                          isOn: workbench.showPanel) { workbench.showPanel.toggle() }
        }
        .padding(.leading, NRSpace.sp3)
        .padding(.trailing, 10)
        .frame(height: NRShell.addressH)
        .frame(maxWidth: .infinity)
        .background(NRColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(NRColor.hairlineSoft).frame(height: NRSpace.hairline) }
        .onChange(of: tab?.id, initial: true) { _, _ in show(pageAddress) }
        .onChange(of: focused) { _, editing in
            if editing { address = pageAddress }
        }
        .animation(.easeOut(duration: NRMotion.base), value: workbench.fillStatus)
    }

    /// Seal (relish placement #4): the glyph in relish while a page is in front. The Seal
    /// overlay draws the pulse and the Sealed pill over this slot, so it has no motion of its own.
    private var sealSlot: some View {
        let enabled = workbench.pageInFront != nil
        return Button { Task { await workbench.sealActiveTab() } } label: {
            NRSymbol.seal.image.resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(enabled ? NRColor.relish500 : NRColor.fg3)
                .opacity(enabled ? 1 : 0.35)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help("Seal (⌘S)")
        .accessibilityLabel("Seal")
        .frame(width: 28, height: 28)
        .sealAnchor(.sealSlot)
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

/// The address field: 28pt, the `tab` fill, no stroke at rest and the focus ring when typing
/// in it. With a page in front and the field idle, it shows the page's host in `fg` and the
/// rest of its address in `fg3`, behind the lock (relish placement #11).
private struct AddressField: View {
    @Bindable var workbench: Workbench
    let web: JarWebView?
    let pageURL: URL?
    @Binding var address: String
    var focused: FocusState<Bool>.Binding
    let go: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var tab: Tab? { workbench.benchTab }
    private var reading: Bool { workbench.isReading }
    private var sealFrozen: Bool {
        if case .frozen = workbench.sealPhase { return true }
        return false
    }

    /// The page's address, split for the idle field: its host, and everything after it.
    private var parts: (host: String, rest: String)? {
        guard tab != nil, !focused.wrappedValue, let url = URL(string: address), let host = url.host,
              let range = address.range(of: host) else { return nil }
        let rest = String(address[range.upperBound...])
        return (host, rest == "/" ? "" : rest)
    }

    private var placeholder: String {
        if let jar = workbench.activeJar { return "Type a web address — it opens in \(jar.name)" }
        return "Type a web address"
    }

    var body: some View {
        HStack(spacing: NRSpace.sp2) {
            leadingGlyph
            // The real field always takes the click and stays in the accessibility tree; idle
            // with a page in front, its text is clear and the styled address is drawn over it.
            TextField(placeholder, text: $address)
                .textFieldStyle(.plain)
                .font(NRType.font(NRType.fsMd))
                .foregroundStyle(parts == nil ? NRColor.fg : Color.clear)
                .tint(NRColor.focus)
                .focused(focused)
                .onSubmit(go)
                .accessibilityLabel("Address")
                .overlay(alignment: .leading) {
                    if let parts {
                        Self.styled(host: parts.host, rest: parts.rest)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            if let status = workbench.fillStatus {
                Text(status).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2).lineLimit(1)
                    .transition(.opacity).accessibilityIdentifier("fill-status")
            }
            if tab != nil {
                HStack(spacing: 0) {
                    FieldButton(systemName: "tray.and.arrow.down", help: "Capture This Page (⌘D)",
                                label: "Capture this page") { workbench.captureActivePage() }
                    FieldButton(systemName: "doc.plaintext",
                                help: reading ? "Back to the Page (⌘⇧R)" : "Reader View (⌘⇧R)",
                                label: reading ? "Back to the page" : "Reader view",
                                isOn: reading) { Task { await workbench.toggleReader() } }
                    if let web {
                        FieldButton(systemName: web.isLoading ? "xmark" : "arrow.clockwise",
                                    help: web.isLoading ? "Stop" : "Reload",
                                    label: web.isLoading ? "Stop" : "Reload") {
                            web.isLoading ? web.webView.stopLoading() : web.reload()
                        }
                    }
                }
                .opacity(sealFrozen ? 0 : 1)
                .allowsHitTesting(!sealFrozen)
                .accessibilityHidden(sealFrozen)
                .animation(NRMotion.animation(duration: NRMotion.fast), value: sealFrozen)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, NRSpace.sp1)
        .frame(height: NRShell.fieldH)
        .frame(maxWidth: .infinity)
        .background(NRColor.tab, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if focused.wrappedValue {
                RoundedRectangle(cornerRadius: 8).strokeBorder(NRColor.focus, lineWidth: 2)
            }
        }
    }

    /// The idle field's address: the host at 13/500 in `fg`, the rest at 13/400 in `fg3`.
    private static func styled(host: String, rest: String) -> Text {
        let head: Text = Text(verbatim: host).font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg)
        let tail: Text = Text(verbatim: rest).font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg3)
        return Text("\(head)\(tail)")
    }

    /// The lock while a page is in front (relish-700, relish-500 in dark), else the magnifier.
    /// The lock means a secure connection, so a page that isn't on https wears a neutral globe.
    @ViewBuilder private var leadingGlyph: some View {
        if tab != nil, pageURL?.scheme?.lowercased() == "https" {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? NRColor.relish500 : NRColor.relish700)
                .accessibilityHidden(true)
        } else if tab != nil {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NRColor.fg3)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NRColor.fg3)
                .accessibilityHidden(true)
        }
    }
}

/// A 28pt square button in the address row: `fg3`, the `tab` fill under the pointer; `fg` on
/// the `tab` fill while it is on.
private struct RowIconButton: View {
    let systemName: String
    let help: String
    var label: String? = nil
    var isOn = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? NRColor.fg : (hovering && isEnabled ? NRColor.fg2 : NRColor.fg3))
                .frame(width: 28, height: 28)
                .background(isOn || (hovering && isEnabled) ? NRColor.tab : .clear, in: RoundedRectangle(cornerRadius: 7))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        .help(help)
        .accessibilityLabel(label ?? help)
    }
}

/// A 26pt button inside the address field: `fg3`, `tabHover` under the pointer, `fg` while on.
private struct FieldButton: View {
    let systemName: String
    let help: String
    let label: String
    var isOn = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? NRColor.fg : NRColor.fg3)
                .frame(width: 26, height: 26)
                .background(hovering ? NRColor.tabHover : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}

/// Row 3, the bottom bar, across the whole window. Brine is the pill on the leading edge: it
/// lights (relish placement #13, narrowed) only for tabs that sank since Brine was last
/// opened, and opens Brine on the Bench. The trailing edge carries the Pantry's count and the
/// way into ⌘K.
struct BottomBar: View {
    @Bindable var workbench: Workbench

    var body: some View {
        HStack(spacing: NRSpace.sp3) {
            BrinePill(workbench: workbench)
            Spacer()
            Text("\(workbench.itemCount.formatted()) in the Pantry")
                .font(NRType.font(NRType.fsSm)).monospacedDigit().foregroundStyle(NRColor.fg3)
            SearchPantryButton { workbench.showPalette = true }
        }
        .padding(.leading, NRSpace.sp3)
        .padding(.trailing, 10)
        .frame(height: NRShell.barH)
        .frame(maxWidth: .infinity)
        .background(NRColor.rail)
        .overlay(alignment: .top) { Rectangle().fill(NRColor.hairlineSoft).frame(height: NRSpace.hairline) }
    }
}

/// The Brine pill: neutral with its count; lit while something sank since Brine was last
/// opened; outlined while Brine is on the Bench.
private struct BrinePill: View {
    @Bindable var workbench: Workbench
    @Environment(\.colorScheme) private var colorScheme

    private var sunk: Int { workbench.brine.count }
    private var lit: Bool { workbench.brineFresh > 0 }
    private var isOpen: Bool { workbench.activeSmartJar == .brine }
    private var edge: Color? {
        if lit { return colorScheme == .dark ? NRColor.relish700 : NRColor.relish300 }
        if isOpen { return NRColor.fg3 }
        return nil
    }

    var body: some View {
        Button { workbench.activateBrine() } label: {
            HStack(spacing: 6) {
                NRSymbol.sink.image.resizable()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(lit ? NRColor.fg2 : NRColor.fg3)
                Text("Brine")
                    .font(NRType.font(NRType.fsSm, weight: .medium))
                    .foregroundStyle(lit ? NRColor.fg : NRColor.fg2)
                Text("\(sunk)")
                    .font(NRType.font(NRType.fsSm, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(NRColor.fg)
            }
            .padding(.leading, NRSpace.sp2)
            .padding(.trailing, 10)
            .frame(height: 24)
            .background(lit ? NRColor.relish100 : NRColor.tab, in: Capsule())
            .overlay {
                if let edge { Capsule().strokeBorder(edge, lineWidth: NRSpace.hairline) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(NRMotion.animation(), value: lit)
        .help("Brine — \(SmartJar.brine.shortcutLabel)")
        .accessibilityLabel("Brine, \(sunk) sunk")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}

/// "Search the Pantry ⌘K": the way into the Command Palette.
private struct SearchPantryButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NRColor.fg3)
                Text("Search the Pantry")
                    .font(NRType.font(NRType.fsSm, weight: .medium))
                    .foregroundStyle(NRColor.fg2)
                Text("⌘K")
                    .font(NRType.font(NRType.fsXs, weight: .medium))
                    .foregroundStyle(NRColor.fg3)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
            }
            .padding(.leading, NRSpace.sp2)
            .padding(.trailing, 6)
            .frame(height: 24)
            .background(hovering ? NRColor.tab : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        .help("Search the Pantry (⌘K)")
        .accessibilityLabel("Search the Pantry")
    }
}
