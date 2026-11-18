// TabStrip.swift — the tabs in the title strip, and the jar's chip that leads the address row
// (manifest v2.1 §8 Tabs, the Workbench facelift comp). Tabs are attached: the tab in front is
// white, joined to the Bench with no line under it, with a lip in its jar's color along its
// top edge; the tabs behind are filled light grey with no border. Hand-written.

import AppKit
import Pantry
import SwiftUI

// MARK: - Layout

/// How wide each tab is, a pure port of the comp's `tabLayout`. Every unpinned tab shares the
/// room, held between `tabMinW` and `tabMaxW`; the tab in front grows to fit its title, up to
/// `frontTabMaxW`, before the others shrink; a pinned tab is always `pinnedTabW`.
enum TabStripLayout {
    /// - Parameters:
    ///   - pinned: one entry per tab, in strip order: true for a pinned tab.
    ///   - frontIndex: the tab in front, if the strip has one.
    ///   - frontIdealWidth: the width the front tab's title asks for (title + 72).
    ///   - available: the width of the strip's clipping region.
    static func widths(pinned: [Bool], frontIndex: Int?, frontIdealWidth: CGFloat?, available: CGFloat) -> [CGFloat] {
        let pins = pinned.filter { $0 }.count
        let k = pinned.count - pins
        let free = available - 44 - CGFloat(pins) * NRShell.pinnedTabW - CGFloat(pinned.count) * NRShell.tabGap
        func clamp(_ v: CGFloat) -> CGFloat { min(NRShell.tabMaxW, max(NRShell.tabMinW, v)) }

        var w = k > 0 ? clamp(free / CGFloat(k)) : NRShell.tabMaxW
        var fw = w
        var front: Int?
        if let i = frontIndex, pinned.indices.contains(i), !pinned[i] {
            front = i
            if let ideal = frontIdealWidth, ideal > w {
                fw = min(NRShell.frontTabMaxW, ideal)
                if k > 1 { w = clamp((free - fw) / CGFloat(k - 1)) }
            }
        }
        return pinned.enumerated().map { i, isPinned in
            isPinned ? NRShell.pinnedTabW : (i == front ? fw : w)
        }
    }

    /// The width a tab's title asks for: the title at 12/500, plus room for the icon, the
    /// close button and the padding.
    @MainActor static func idealWidth(of title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let width = NSAttributedString(string: title, attributes: [.font: font]).size().width
        return width.rounded(.up) + 72
    }
}

/// Which edges of the strip have tabs scrolled out past them.
private struct ClipEdges: Equatable {
    var leading = false
    var trailing = false
}

// MARK: - The strip

/// The tab strip, in the title strip, over the Bench column. It shows the jar's open tabs
/// (and, while Seal runs, the sealed tab until its chip leaves), then "+". A tab can be
/// dragged onto another tab to take its place, or onto a jar on the Shelf to move there; the
/// tab it is over shows the drop mark. With a smart jar, or no jar, it shows no tabs.
struct TabStrip: View {
    @Bindable var workbench: Workbench
    /// The width from the strip's leading edge to the window's trailing edge.
    let available: CGFloat
    /// A double-click on the strip's empty stretch, as on a title bar.
    let onDoubleClick: () -> Void

    /// The tab a dragged tab is over.
    @State private var dropTarget: String?
    @State private var clipped = ClipEdges()
    /// The jar and tabs the strip last drew, so only a tab opened in place grows in.
    @State private var seenJarId: String?
    @State private var seenTabIds: Set<String> = []
    @Namespace private var lipSpace
    @Environment(\.nrReduceMotion) private var reduceMotion

    /// The room kept clear after the clipping region, for "+" and a stretch to drag. The
    /// layout keeps 44pt of the strip for it (the comp's `tabLayout`), and a full strip of
    /// tabs, insets included, ends exactly this far from the strip's end.
    private static let trailingReserve: CGFloat = 36
    private static let leadingInset: CGFloat = 8
    private static let trailingInset: CGFloat = 4

    private var motion: Animation? { reduceMotion ? nil : NRMotion.animation() }

    var body: some View {
        HStack(spacing: 0) {
            if let jar = workbench.activeJar, workbench.activeSmartJar == nil {
                strip(for: jar)
                newTabButton
                    .padding(.leading, 2)
            }
            WindowDragArea(onDoubleClick: onDoubleClick)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: NRShell.titleH)
    }

    @ViewBuilder private func strip(for jar: Jar) -> some View {
        let tabs = workbench.stripTabs
        let frontId = workbench.benchTab?.id
        let clip = max(0, available - Self.trailingReserve)
        let frontIndex = tabs.firstIndex { $0.id == frontId }
        let ideal = frontIndex.map { TabStripLayout.idealWidth(of: Self.label(of: tabs[$0])) }
        let widths = TabStripLayout.widths(pinned: tabs.map(\.isPinned), frontIndex: frontIndex,
                                           frontIdealWidth: ideal, available: available)
        let gaps = CGFloat(max(0, tabs.count - 1)) * NRShell.tabGap
        let content = Self.leadingInset + widths.reduce(0, +) + gaps + Self.trailingInset
        let canGrow = seenJarId == jar.id && !reduceMotion

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: NRShell.tabGap) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        chip(for: tab, in: jar, width: index < widths.count ? widths[index] : NRShell.tabMinW,
                             isFront: tab.id == frontId,
                             growIn: canGrow && !seenTabIds.contains(tab.id))
                            .id(tab.id)
                            .transition(AnyTransition.opacity.animation(NRMotion.animation(duration: 0.16)))
                    }
                }
                .padding(.leading, Self.leadingInset)
                .padding(.trailing, Self.trailingInset)
                .frame(height: NRShell.titleH, alignment: .top)
                .animation(motion, value: tabs.map(\.id))
                .animation(motion, value: frontId)
            }
            .onScrollGeometryChange(for: ClipEdges.self) { geo in
                ClipEdges(leading: geo.contentOffset.x > 0.5,
                          trailing: geo.contentOffset.x + geo.containerSize.width < geo.contentSize.width - 0.5)
            } action: { _, new in
                clipped = new
            }
            .frame(width: min(content, clip), height: NRShell.titleH)
            .overlay(alignment: .topLeading) {
                if clipped.leading { edgeLine }
            }
            .overlay(alignment: .topTrailing) {
                if clipped.trailing { edgeLine }
            }
            .sealAnchor(.tabStrip)
            .onAppear {
                if let frontId { proxy.scrollTo(frontId) }
            }
            .onChange(of: frontId) { _, id in
                guard let id else { return }
                if let motion {
                    withAnimation(motion) { proxy.scrollTo(id) }
                } else {
                    proxy.scrollTo(id)
                }
            }
            .onChange(of: workbench.sealPhase.run?.id) { _, runId in
                // Seal reads the tab's settled frame, so this scroll is never animated.
                guard runId != nil, let id = workbench.sealPhase.run?.tab.id ?? workbench.benchTab?.id else { return }
                proxy.scrollTo(id)
            }
            .onChange(of: tabs.map(\.id), initial: true) { _, ids in
                seenJarId = jar.id
                seenTabIds = Set(ids)
            }
        }
    }

    /// A 1pt line on an edge the tabs scroll out past. No gradient mask.
    private var edgeLine: some View {
        Rectangle().fill(NRColor.hairline)
            .frame(width: NRSpace.hairline, height: 26)
            .padding(.top, 13)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func chip(for tab: Tab, in jar: Jar, width: CGFloat, isFront: Bool, growIn: Bool) -> some View {
        let held = workbench.isHeldBySeal(tab)
        let base = TabChip(tab: tab, jar: jar, width: width, isFront: isFront, now: workbench.now,
                           glyph: workbench.glyph(of: tab), isDropTarget: dropTarget == tab.id,
                           growIn: growIn, lipSpace: lipSpace,
                           activate: { workbench.activateTab(tab) }, close: { workbench.closeTab(tab) })
            .sealAnchor(.tab(tab.id))
        if held {
            // The sealed tab, drawn until its chip leaves for the jar: the same look, and
            // nothing to click, drag or drop on.
            base.allowsHitTesting(false)
        } else {
            base
                .contextMenu { menu(for: tab) }
                .draggable(DragPayload.tab(tab.id).string)
                .dropDestination(for: String.self) { payloads, _ in
                    workbench.drop(payloads, onTab: tab)
                } isTargeted: { over in
                    if over { dropTarget = tab.id } else if dropTarget == tab.id { dropTarget = nil }
                }
        }
    }

    private var newTabButton: some View {
        NewTabButton { workbench.newTab() }
            .padding(.top, 13)
            .frame(height: NRShell.titleH, alignment: .top)
            .sealAnchor(.newTab)
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

    /// What a tab is called: its title, else its address, else "New Tab".
    static func label(of tab: Tab) -> String {
        (tab.title?.isEmpty == false ? tab.title : tab.url) ?? "New Tab"
    }
}

/// "+": a new tab in the jar you're in.
private struct NewTabButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(NRColor.fg3)
                .frame(width: 28, height: 28)
                .background(hovering ? NRColor.tab : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        .help("New Tab (⌘T)")
        .accessibilityLabel("New Tab")
    }
}

// MARK: - A tab

/// One tab, attached. In front: `frontTabH` tall from 6pt down, white (`surface`) with a 1pt
/// hairline on its left, top and right edges and none at the bottom, so it joins the row
/// under it; its jar's lip runs along its top. Behind: `tabH` tall from 10pt down, filled
/// `tab`, unbordered, `tabHover` under the pointer.
struct TabChip: View {
    let tab: Tab
    let jar: Jar
    let width: CGFloat
    let isFront: Bool
    let now: Date
    /// The icon picked for this tab, as an SF Symbol name; nil for the standard one.
    var glyph: String? = nil
    /// A dragged tab is over this one and would take its place.
    var isDropTarget = false
    /// A tab just opened grows in from nothing.
    var growIn = false
    let lipSpace: Namespace.ID
    let activate: () -> Void
    let close: () -> Void

    @State private var hovering = false
    @State private var closeHovering = false
    @State private var grown: Bool

    init(tab: Tab, jar: Jar, width: CGFloat, isFront: Bool, now: Date, glyph: String? = nil,
         isDropTarget: Bool = false, growIn: Bool = false, lipSpace: Namespace.ID,
         activate: @escaping () -> Void, close: @escaping () -> Void) {
        self.tab = tab
        self.jar = jar
        self.width = width
        self.isFront = isFront
        self.now = now
        self.glyph = glyph
        self.isDropTarget = isDropTarget
        self.growIn = growIn
        self.lipSpace = lipSpace
        self.activate = activate
        self.close = close
        _grown = State(initialValue: !growIn)
    }

    private var fading: Bool { ShelfLife.isFading(tab, in: jar, now: now) }
    private var label: String { TabStrip.label(of: tab) }
    private var shape: NRTabShape { NRTabShape(radius: NRShell.tabRadius) }
    private var height: CGFloat { isFront ? NRShell.frontTabH : NRShell.tabH }
    private var fill: Color { isFront ? NRColor.surface : (hovering ? NRColor.tabHover : NRColor.tab) }
    private var titleColor: Color { fading ? NRColor.fg3 : (isFront ? NRColor.fg : NRColor.fg2) }

    var body: some View {
        content
            .frame(width: width, height: height)
            .background(fill, in: shape)
            .overlay { if isFront { TabOutline(radius: NRShell.tabRadius).stroke(NRColor.hairline, lineWidth: NRSpace.hairline) } }
            .overlay(alignment: .bottomTrailing) { if tab.isPinned { pinMark } }
            .overlay(alignment: .leading) { if isDropTarget { NRDropMark().padding(.vertical, NRSpace.sp1) } }
            .frame(width: grown ? width : 0, alignment: .leading)
            .clipped()
            // The lip sits outside the clip so it can slide to the next tab in front.
            .overlay(alignment: .top) {
                if isFront {
                    NRTabLip(color: jar.paint.face)
                        .frame(height: 14, alignment: .top)
                        .clipShape(NRTabShape(radius: NRShell.tabRadius))
                        .matchedGeometryEffect(id: "lip", in: lipSpace)
                        .allowsHitTesting(false)
                }
            }
            .padding(.top, isFront ? 6 : 10)
            .frame(height: NRShell.titleH, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: activate)
            .onHover { hovering = $0 }
            .onAppear {
                guard !grown else { return }
                withAnimation(NRMotion.animation()) { grown = true }
            }
            .help(tab.isPinned ? "\(label). Pinned: it never sinks" : label)
            .accessibilityAddTraits(isFront ? [.isButton, .isSelected] : .isButton)
            .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
            .animation(NRMotion.animation(duration: NRMotion.fast), value: fading)
    }

    @ViewBuilder private var content: some View {
        if tab.isPinned {
            TabIcon(tab: tab, glyph: glyph, isFront: isFront)
        } else {
            HStack(spacing: NRSpace.sp2) {
                TabIcon(tab: tab, glyph: glyph, isFront: isFront)
                Text(label)
                    .font(NRType.font(NRType.fsSm, weight: .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hovering {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(NRColor.fg3)
                            .frame(width: 18, height: 18)
                            .background(closeHovering ? NRColor.tabHover : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { closeHovering = $0 }
                    .help("Close Tab (⌘W)")
                    .accessibilityLabel("Close Tab")
                }
            }
            .padding(.leading, NRSpace.sp3)
            .padding(.trailing, NRSpace.sp2)
        }
    }

    /// The pinned mark: a pin in a small disc, on the tab's bottom-trailing corner.
    private var pinMark: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 7))
            .foregroundStyle(NRColor.fg2)
            .frame(width: 12, height: 12)
            .background(isFront ? NRColor.surface : NRColor.tab, in: Circle())
            .padding(.trailing, 4)
            .padding(.bottom, 5)
            .accessibilityHidden(true)
    }
}

/// The front tab's border: its left, top and right edges, with the top corners rounded, and
/// no bottom edge, so it joins the address row.
private struct TabOutline: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = NRSpace.hairline / 2
        let minX = rect.minX + inset, maxX = rect.maxX - inset, minY = rect.minY + inset, maxY = rect.maxY
        let r = max(0, min(radius, (maxX - minX) / 2, maxY - minY))
        var path = Path()
        path.move(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + r, y: minY), radius: r)
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + r), radius: r)
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        return path
    }
}

// MARK: - Tab icons

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

/// A tab's icon: the first letter of its site on a small tile, or the icon picked for it. On
/// a tab behind, the tile is grey with a `fg2` letter; on the tab in front it is ink with a
/// white letter (the art's dark square). A picked icon has no tile.
struct TabIcon: View {
    let tab: Tab
    var glyph: String? = nil
    var size: CGFloat = 16
    var isFront: Bool = false

    /// The site's first letter: "j" for juniperbakery.example, never the "w" of "www".
    static func letter(for tab: Tab) -> String? {
        guard let url = tab.url, let host = URL(string: url)?.host ?? URL(string: "https://" + url)?.host else { return nil }
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return name.first.map { String($0).uppercased() }
    }

    var body: some View {
        Group {
            if let glyph {
                symbol(glyph)
            } else if let letter = Self.letter(for: tab) {
                Text(letter)
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(isFront ? NRColor.surface : NRColor.fg2)
                    .frame(width: size, height: size)
                    .background(isFront ? NRColor.fg : NRColor.hairline, in: RoundedRectangle(cornerRadius: size * 0.28))
            } else {
                symbol(TabGlyph.standard)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.75, weight: .medium))
            .foregroundStyle(isFront ? NRColor.fg : NRColor.fg2)
    }
}

// MARK: - The jar's chip

/// The jar's chip at the head of the address row: the jar drawn at 18pt and its name, on the
/// neutral `tab` fill (the drawn jar carries the color). It opens the jar's board.
struct JarChip: View {
    @Bindable var workbench: Workbench
    let jar: Jar

    private var isFront: Bool { workbench.panelSubject == .jar(jar) }

    var body: some View {
        Button { workbench.showBoard() } label: {
            HStack(spacing: NRSpace.sp2) {
                NRFilledJar(paint: jar.paint, fill: workbench.fill(of: jar), size: 18, isActive: true)
                // The frame's ideal width is the name's, held to 180: a long name truncates
                // here and never crowds the field. The tooltip has it in full.
                Text(jar.name)
                    .font(NRType.font(NRType.fsSm, weight: .semibold))
                    .foregroundStyle(NRColor.fg)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .leading)
            }
            .padding(.leading, NRSpace.sp2)
            .padding(.trailing, 10)
            .frame(height: 28)
            .fixedSize(horizontal: true, vertical: false)
            .background(NRColor.tab, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NRColor.hairlineSoft, lineWidth: NRSpace.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(jar.name): what's in this jar")
        .accessibilityLabel("\(jar.name) board")
        .accessibilityAddTraits(isFront ? .isSelected : [])
        .contextMenu {
            Button("New Tab in \(jar.name)") { workbench.newTab(in: jar.id) }
            Button("Edit Jar…") { workbench.requestEditActiveJar() }
        }
    }
}

/// A smart jar's chip at the head of the address row: its glyph and name. It has no action.
struct SmartJarChip: View {
    let smart: SmartJar

    var body: some View {
        HStack(spacing: NRSpace.sp2) {
            (smart == .brine ? NRSymbol.sink : NRSymbol.jarSmart).image
                .resizable().frame(width: 16, height: 16)
                .foregroundStyle(NRColor.fg2)
                .accessibilityHidden(true)
            Text(smart.name)
                .font(NRType.font(NRType.fsSm, weight: .semibold))
                .foregroundStyle(NRColor.fg)
                .lineLimit(1)
        }
        .padding(.leading, NRSpace.sp2)
        .padding(.trailing, 10)
        .frame(height: 28)
        .fixedSize(horizontal: true, vertical: false)
        .background(NRColor.tab, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NRColor.hairlineSoft, lineWidth: NRSpace.hairline))
        .accessibilityElement(children: .combine)
    }
}
