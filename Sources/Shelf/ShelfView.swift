// ShelfView.swift — the Shelf (manifest v2.1 §8, ADR 0035). A 120pt rail on the leading
// edge, always open, full height. Jars first, as big tiles: each jar drawn at 58pt in its
// own color, filled to its level, its name under it. The active tile takes a wash of the
// jar's color and a 1pt edge in it (in dark, a neutral float tile with that edge). New Jar
// sits under the jars. Then a hairline, the Pantry's smart jars (Today, Sealed, Sinking
// soon; Brine lives in the bottom bar) as small neutral rows, and Zest at the bottom.
//
// A jar can be dragged, but only along the Shelf: it slides up and down among the jars and
// nowhere else. A tab or a Brine row dragged onto a jar lands in it, and the tile shows the
// drop mark while it would. When something lands, the tile plays the jar fill (JarFill.swift).
//
// For VoiceOver and the keyboard (P5): the Shelf is one named group. Each tile says its name,
// and its value says what it holds and how its tabs sink. Every drag and right-click has a
// named action on the tile too. With Keyboard navigation on, the arrow keys step through the
// Shelf top to bottom, and the tile with the keyboard wears the focus ring (--nr-focus).

import Pantry
import SwiftUI

struct ShelfView: View {
    @Bindable var workbench: Workbench
    @Environment(\.openWindow) private var openWindow
    @Environment(\.nrReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    /// Where the keyboard is on the Shelf: the arrow keys move it, and its ring is drawn there.
    @FocusState private var focus: ShelfFocus?
    /// Ties each jar tile to its entry in the "Jars" rotor, as ComparisonView does for changes.
    @Namespace private var jarSpace
    @State private var showingNewJar = false
    @State private var editingJar: Jar?
    /// What the jar sheet's save says, held until the sheet has gone: posted while the sheet
    /// is still the key window, it can be lost as focus jumps back to the main window.
    @State private var pendingLine: String?
    /// The jar being slid along the Shelf: where it started and how far it has come.
    @State private var lifted: Lifted?
    /// The jar a dragged tab or Brine row is over.
    @State private var dropTarget: String?

    private struct Lifted: Equatable {
        let id: String
        let from: Int
        var travel: CGFloat
    }

    /// Every place on the Shelf the keyboard can stop.
    enum ShelfFocus: Hashable {
        case jar(String)
        case newJar
        case smart(SmartJar)
        case zest
    }

    /// The smart jars the Shelf shows. Brine is the pill in the bottom bar; ⌃⌘1 still opens it.
    static var shelfSmartJars: [SmartJar] { SmartJar.allCases.filter { $0 != .brine } }

    /// The keyboard's stops, top to bottom as they are drawn: the jars, New Jar, the smart
    /// jars, then Zest.
    static func focusOrder(jarIds: [String]) -> [ShelfFocus] {
        jarIds.map { ShelfFocus.jar($0) } + [.newJar] + shelfSmartJars.map { ShelfFocus.smart($0) } + [.zest]
    }

    /// The stop `step` places from `current`. Nil past either end: the arrows stop there
    /// rather than wrap, so the person can tell they've reached the top or the bottom.
    static func neighbor(of current: ShelfFocus, in order: [ShelfFocus], by step: Int) -> ShelfFocus? {
        guard let index = order.firstIndex(of: current) else { return nil }
        let next = index + step
        return order.indices.contains(next) ? order[next] : nil
    }

    /// What VoiceOver hears when a tile opens its jar's board. The Bench changes while the
    /// focus stays on the Shelf, so nothing else would say so.
    static func boardLine(jarName: String) -> String { "\(jarName) board" }
    /// After Create in the jar sheet.
    static func createdLine(name: String) -> String {
        "\(name.trimmingCharacters(in: .whitespaces)) is on the Shelf."
    }
    /// After Save in the jar sheet.
    static func savedLine(name: String) -> String { "Saved \(name.trimmingCharacters(in: .whitespaces))." }

    /// Under Increase Contrast the Shelf's two hairlines take fg3, so the rail's edges hold.
    private var hairline: Color { contrast == .increased ? NRColor.fg3 : NRColor.hairlineSoft }

    /// One tile and the gap under it: how far a jar slides to change places with its neighbor.
    private static let pitch = JarTile.height + tileGap
    private static let tileGap: CGFloat = 8
    /// The rail's insets, and the room above the first tile.
    private static let inset: CGFloat = 10
    private static let top: CGFloat = 12

    /// The jars and New Jar, at their full height: the scrolling part of the rail never grows
    /// past it, so the smart jars sit right under the jars until the jars need to scroll.
    private var jarsHeight: CGFloat {
        Self.top + CGFloat(workbench.jars.count) * Self.pitch + NewJarButton.height + 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: Self.tileGap) {
                        jars
                        NewJarButton(isFocused: focus == .newJar) { showingNewJar = true }
                            .focused($focus, equals: .newJar)
                            .id(ShelfFocus.newJar)
                    }
                    // Inside the scroll view, so a tile's bump is never clipped at the top.
                    .padding(.top, Self.top)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: jarsHeight)
                .sealAnchor(.shelfJars)
                // The keyboard can step onto a tile the rail has scrolled out of sight.
                .onChange(of: focus) { _, place in
                    switch place {
                    case .jar(let id)?: proxy.scrollTo(id)
                    case .newJar?: proxy.scrollTo(ShelfFocus.newJar)
                    default: break
                    }
                }
            }
            .layoutPriority(1)

            Rectangle().fill(hairline).frame(height: NRSpace.hairline)
                .padding(.vertical, 8)
                .padding(.horizontal, Self.inset + 2)
            pantry.padding(.horizontal, Self.inset)
            Spacer(minLength: 0)
            zest.padding(.horizontal, Self.inset)
        }
        .padding(.bottom, Self.inset)
        .frame(width: NRSpace.shelfW)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NRColor.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(hairline).frame(width: NRSpace.hairline) }
        // One focus section, so focus coming in from the Bench lands on the Shelf as a whole.
        // Up and down step between its stops; Return and Space press the one with the keyboard.
        .focusSection()
        .onKeyPress(.downArrow) { moveFocus(1) }
        .onKeyPress(.upArrow) { moveFocus(-1) }
        // One named group, so VoiceOver can say where it is and skip past it whole.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shelf")
        .accessibilityRotor(Text("Jars")) {
            ForEach(workbench.jars) { jar in
                AccessibilityRotorEntry(Text(jar.name), id: jar.id, in: jarSpace)
            }
        }
        .sheet(isPresented: $showingNewJar, onDismiss: { postPendingLine() }) {
            JarSheet(existing: nil) { name, tint, days in
                workbench.newJar(name: name, tint: tint, shelfLifeDays: days)
                pendingLine = Self.createdLine(name: name)
            }
        }
        .sheet(item: $editingJar, onDismiss: { postPendingLine() }) { jar in
            JarSheet(existing: jar) { name, tint, days in
                workbench.updateJar(jar, name: name, tint: tint, shelfLifeDays: days)
                pendingLine = Self.savedLine(name: name)
            }
        }
        .onChange(of: workbench.jarToEdit) { _, jar in
            if let jar { editingJar = jar; workbench.jarToEdit = nil }
        }
    }

    // MARK: Sections

    private var jars: some View {
        // How many of each jar's open tabs are sinking soon, worked out once for the Shelf.
        let sinking = Dictionary(grouping: workbench.sinkingSoon.compactMap(\.jarId), by: { $0 }).mapValues(\.count)
        return ForEach(Array(workbench.jars.enumerated()), id: \.element.id) { index, jar in
            JarTile(jar: jar, index: index, tabs: workbench.tabCount(in: jar), kept: workbench.keptCount(in: jar),
                    sinking: sinking[jar.id] ?? 0,
                    isActive: jar.id == workbench.activeJarId, isDropTarget: dropTarget == jar.id,
                    isFocused: focus == .jar(jar.id), workbench: workbench) {
                workbench.showBoard(of: jar)
                NRAnnounce.post(Self.boardLine(jarName: jar.name))
            }
            .focused($focus, equals: .jar(jar.id))
            .accessibilityRotorEntry(id: jar.id, in: jarSpace)
            .offset(y: slide(of: jar, at: index))
            .zIndex(lifted?.id == jar.id ? 1 : 0)
            // Under Reduce Motion the jars a slid jar passes jump to their places.
            .animation(lifted?.id == jar.id || reduceMotion ? nil : NRMotion.animation(duration: NRMotion.fast),
                       value: landing)
            .contextMenu { menu(for: jar, at: index) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { editingJar = jar })
            .highPriorityGesture(slideGesture(for: jar, at: index))
            .dropDestination(for: String.self) { payloads, _ in
                let landed = workbench.drop(payloads, onJar: jar)
                if landed, let line = JarTile.dropAnnouncement(payloads: payloads, jarName: jar.name) {
                    NRAnnounce.post(line, priority: .high)
                }
                return landed
            } isTargeted: { over in
                if over { dropTarget = jar.id } else if dropTarget == jar.id { dropTarget = nil }
            }
            // The drag, the double-click and the right-click, as VoiceOver actions. All of
            // them always, so the tile stays the same view as it moves along the Shelf; at an
            // end, Move Up or Move Down says so.
            .accessibilityAction(named: Text("Move Tab Here")) { moveTabHere(jar) }
            .accessibilityAction(named: Text("New Tab")) { _ = workbench.newTab(in: jar.id) }
            .accessibilityAction(named: Text("Edit Jar")) { editingJar = jar }
            .accessibilityAction(named: Text("Move Up")) { moveJar(jar, by: -1) }
            .accessibilityAction(named: Text("Move Down")) { moveJar(jar, by: 1) }
        }
    }

    private var pantry: some View {
        VStack(spacing: 0) {
            ForEach(Self.shelfSmartJars) { smart in
                SmartJarRow(smart: smart, count: workbench.count(of: smart),
                            isActive: workbench.activeSmartJar == smart, isFocused: focus == .smart(smart)) {
                    workbench.activate(smart)
                }
                .focused($focus, equals: .smart(smart))
            }
        }
    }

    /// One row for the Zest window, neutral (`--nr-fg-2`, manifest v2.1 §4 #11): the tools
    /// are chosen inside it, or straight from the row's right-click menu.
    private var zest: some View {
        ShelfRow(title: "Zest", help: "Open the Zest window", isFocused: focus == .zest) {
            Image(systemName: "square.grid.2x2").font(.system(size: 14, weight: .regular))
                .foregroundStyle(NRColor.fg2)
        } action: {
            openWindow(id: "zest")
        }
        .focused($focus, equals: .zest)
        .contextMenu {
            ForEach(ZestTool.allCases) { tool in
                Button(tool.title) {
                    workbench.zestToolRequest = tool
                    openWindow(id: "zest")
                }
            }
        }
    }

    // MARK: Right-click

    @ViewBuilder private func menu(for jar: Jar, at index: Int) -> some View {
        Button("New Tab in \(jar.name)") { workbench.newTab(in: jar.id) }
        Button("Edit Jar…") { editingJar = jar }
        Picker("Color", selection: Binding(get: { jar.tint ?? "" }, set: { workbench.setTint($0, of: jar) })) {
            ForEach(JarTint.presets) { preset in
                Label(preset.name, systemImage: "circle.fill").tint(preset.color).tag(preset.css)
            }
        }
        .pickerStyle(.palette)
        Divider()
        Button("Move Up") { workbench.moveJar(jar, by: -1) }.disabled(index == 0)
        Button("Move Down") { workbench.moveJar(jar, by: 1) }.disabled(index == workbench.jars.count - 1)
    }

    // MARK: VoiceOver and the keyboard

    /// Up or down one stop on the Shelf. Ignored past an end, or when the keyboard isn't on
    /// one of the Shelf's stops, so the key goes on to whatever else wants it.
    private func moveFocus(_ step: Int) -> KeyPress.Result {
        guard let current = focus,
              let next = Self.neighbor(of: current, in: Self.focusOrder(jarIds: workbench.jars.map(\.id)), by: step)
        else { return .ignored }
        focus = next
        return .handled
    }

    /// The jar sheet has gone: say what its save did, now that the main window has the
    /// keyboard again. A turn later, so the window is key when it's posted. Cancel says nothing.
    private func postPendingLine() {
        guard let line = pendingLine else { return }
        pendingLine = nil
        Task { @MainActor in
            await Task.yield()
            NRAnnounce.post(line)
        }
    }

    /// Move Tab Here: the page in front goes into this jar, the same way a dropped tab does,
    /// so the jar's rules and its fill are the drop's.
    private func moveTabHere(_ jar: Jar) {
        guard let tab = workbench.pageInFront else { NRAnnounce.post(JarTile.noPageLine); return }
        guard tab.jarId != jar.id else { NRAnnounce.post(JarTile.alreadyHereLine(jarName: jar.name)); return }
        if workbench.drop([DragPayload.tab(tab.id).string], onJar: jar) {
            NRAnnounce.post(JarTile.movedLine(jarName: jar.name), priority: .high)
        }
    }

    /// Move Up and Move Down as VoiceOver actions: the menu's move, then where the jar is now.
    private func moveJar(_ jar: Jar, by step: Int) {
        guard let from = workbench.jars.firstIndex(where: { $0.id == jar.id }) else { return }
        guard workbench.jars.indices.contains(from + step) else {
            NRAnnounce.post(JarTile.endLine(jarName: jar.name, up: step < 0))
            return
        }
        workbench.moveJar(jar, by: step)
        let now = workbench.jars.firstIndex(where: { $0.id == jar.id }) ?? from + step
        NRAnnounce.post(JarTile.moveLine(jarName: jar.name, index: now, count: workbench.jars.count))
    }

    // MARK: Sliding a jar along the Shelf

    /// Where the lifted jar would land if it were let go now.
    private var landing: Int? {
        guard let lifted else { return nil }
        let steps = Int((lifted.travel / Self.pitch).rounded())
        return min(max(lifted.from + steps, 0), workbench.jars.count - 1)
    }

    /// How far a row sits from its place: the lifted jar follows the pointer, held to the
    /// rail's two ends, and the jars it passes step one place aside.
    private func slide(of jar: Jar, at index: Int) -> CGFloat {
        guard let lifted, let landing else { return 0 }
        if jar.id == lifted.id {
            let up = -CGFloat(lifted.from) * Self.pitch
            let down = CGFloat(workbench.jars.count - 1 - lifted.from) * Self.pitch
            return min(max(lifted.travel, up), down)
        }
        if lifted.from < landing, index > lifted.from, index <= landing { return -Self.pitch }
        if lifted.from > landing, index >= landing, index < lifted.from { return Self.pitch }
        return 0
    }

    /// Up and down only. Measured in the window, because the row itself moves with the drag.
    private func slideGesture(for jar: Jar, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                lifted = Lifted(id: jar.id, from: index, travel: value.translation.height)
            }
            .onEnded { _ in
                if let lifted, let landing, landing != lifted.from { workbench.moveJar(lifted.id, to: landing) }
                lifted = nil
            }
    }
}

/// The colors a jar's menu offers: the six jar colors of Workstation v5. Any other color is
/// still one click away in Edit Jar…; a tint is the jar's own data (ADR 0005).
struct JarTint: Identifiable {
    let name: String
    let oklch: OKLCH
    var id: String { css }
    var css: String { oklch.css }
    var color: Color { oklch.color }

    static let presets: [JarTint] = [
        JarTint(name: "Relish", oklch: OKLCH(l: 0.834, c: 0.224, h: 130.9)),
        JarTint(name: "Amber", oklch: OKLCH(l: 0.749, c: 0.148, h: 78.2)),
        JarTint(name: "Sky", oklch: OKLCH(l: 0.623, c: 0.188, h: 259.8)),
        JarTint(name: "Rose", oklch: OKLCH(l: 0.657, c: 0.193, h: 20)),
        JarTint(name: "Violet", oklch: OKLCH(l: 0.709, c: 0.159, h: 293.5)),
        JarTint(name: "Teal", oklch: OKLCH(l: 0.785, c: 0.133, h: 181.9)),
    ]
}

extension Jar {
    /// The jar's color and its shades; relish until the jar is given one.
    var paint: JarPaint { JarPaint(css: tint) }
}

/// New Jar, under the jars: a plus, neutral, the tile's width.
struct NewJarButton: View {
    static let height: CGFloat = 28
    /// The keyboard is here: draw the focus ring.
    var isFocused = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 15, weight: .regular))
                .foregroundStyle(NRColor.fg3)
                .frame(width: JarTile.width, height: Self.height)
                .background(hovering ? NRColor.tab : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        // The ring is ours, in --nr-focus and the button's shape, not the system's.
        .focusEffectDisabled()
        .overlay { if isFocused { NRFocusRing(cornerRadius: 8) } }
        .onHover { hovering = $0 }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        .help("New Jar")
        .accessibilityLabel("New Jar")
    }
}

/// One small row on the Shelf that isn't a jar: a 16pt glyph in fg3, a name, an optional
/// trailing count. Selected, it takes relish-100 (manifest v2.1 §4 #3).
struct ShelfRow<Glyph: View>: View {
    static var height: CGFloat { 28 }

    let title: String
    var help: String
    var isActive = false
    var badge: String? = nil
    /// The keyboard is here: draw the focus ring.
    var isFocused = false
    let glyph: Glyph
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    init(title: String, help: String, isActive: Bool = false, badge: String? = nil, isFocused: Bool = false,
         @ViewBuilder glyph: () -> Glyph, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.isActive = isActive
        self.badge = badge
        self.isFocused = isFocused
        self.glyph = glyph()
        self.action = action
    }

    /// Under Differentiate Without Color the selected row is told apart by more than its
    /// tint: a semibold name and a neutral edge.
    private var marksSelection: Bool { isActive && differentiateWithoutColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // The glyph is decoration; the row speaks its name.
                glyph.frame(width: 16, height: 16).foregroundStyle(NRColor.fg3)
                    .accessibilityHidden(true)
                Text(title).font(NRType.font(NRType.fsSm, weight: marksSelection ? .semibold : .medium))
                    .foregroundStyle(isActive || contrast == .increased ? NRColor.fg : NRColor.fg2)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if let badge { NRBadge(badge).layoutPriority(1) }
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
            .frame(height: Self.height)
            .background(isActive ? NRColor.relish100 : (hovering ? NRColor.tab : .clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if marksSelection { RoundedRectangle(cornerRadius: 8).strokeBorder(NRColor.fg2, lineWidth: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .overlay { if isFocused { NRFocusRing(cornerRadius: 8) } }
        .onHover { hovering = $0 }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// One jar on the Shelf, as a tile: the jar drawn at 58pt filled in its own color (its data,
/// not chrome; idle jars keep their color), its name under it. The active tile takes the
/// jar's wash and a 1pt edge in the jar's color; in dark, a neutral float tile with that
/// edge, so there is never a dark-green panel. The count badge shows only for a moment after
/// something lands in the jar.
struct JarTile: View {
    /// A tile's size on the Shelf. The Shelf uses the height to work out how far a jar slides.
    static let width: CGFloat = 100
    static let height: CGFloat = 88
    private static let radius: CGFloat = 12

    let jar: Jar
    let index: Int
    /// The jar's open tabs.
    let tabs: Int
    /// What the jar keeps.
    let kept: Int
    /// Open tabs plus what the jar keeps: the count badge.
    private var count: Int { tabs + kept }
    /// The jar's open tabs that are sinking soon. Spoken only; the Shelf draws no number for it.
    let sinking: Int
    let isActive: Bool
    /// A dragged tab or Brine row is over this jar and would land in it.
    var isDropTarget = false
    /// The keyboard is here: draw the focus ring.
    var isFocused = false
    let workbench: Workbench
    let activate: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.nrReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var hovering = false
    /// The bump a tile gives when its jar becomes the active one (manifest v2.1 §9 Jar switch).
    @State private var switchBump: CGFloat = 1

    private var paint: JarPaint { jar.paint }

    private var tileFill: Color {
        if isActive { return colorScheme == .dark ? NRColor.float : paint.wash100 }
        return hovering ? NRColor.tab : .clear
    }

    /// Under Increase Contrast or Differentiate Without Color the active tile's edge firms up:
    /// 2pt in the jar's 700 step, so the selection isn't carried by a faint edge and the wash.
    private var firmEdge: Bool { contrast == .increased || differentiateWithoutColor }

    /// What VoiceOver says the jar holds, after its name, in the words the jar's chip and its
    /// board use for the same jar (JarBoard.metaParts): "3 tabs, 2 kept, 1 sinking soon, tabs
    /// sink after 3 idle days".
    static func spokenValue(tabs: Int, kept: Int, sinking: Int, shelfLifeDays: Double?) -> String {
        var parts = JarBoard.metaParts(tabs: tabs, kept: kept, shelfLifeDays: nil)
        if sinking > 0 { parts.append("\(sinking) sinking soon") }
        if let days = shelfLifeDays, days > 0 {
            parts.append(JarBoard.sinkLine(days: days))
        } else {
            parts.append("tabs never sink")
        }
        return parts.joined(separator: ", ")
    }

    /// After a tab lands in a jar, by a drop or Move Tab Here.
    static func movedLine(jarName: String) -> String { "Moved to \(jarName)" }
    /// After a Brine row is dropped on a jar: it opens there as a tab, and stays in Brine.
    static func openedLine(jarName: String) -> String { "Opened in \(jarName)" }
    /// Move Tab Here with no page in front (the board, Brine, or Zest is showing).
    static let noPageLine = "Open a page first."
    /// Move Tab Here when the page in front is in this jar already.
    static func alreadyHereLine(jarName: String) -> String { "Already in \(jarName)." }
    /// After Move Up or Move Down: where the jar is now. `index` counts from 0.
    static func moveLine(jarName: String, index: Int, count: Int) -> String { "\(jarName), \(index + 1) of \(count)" }
    /// Move Up on the top jar, or Move Down on the bottom one.
    static func endLine(jarName: String, up: Bool) -> String {
        "\(jarName) is already at the \(up ? "top" : "bottom")."
    }

    /// What VoiceOver hears after something dropped on a jar landed. A tab moves; a Brine row
    /// opens. Nil if nothing in the drop was ours.
    static func dropAnnouncement(payloads: [String], jarName: String) -> String? {
        let dropped = payloads.compactMap(DragPayload.init)
        guard !dropped.isEmpty else { return nil }
        let hasTab = dropped.contains { payload in
            if case .tab(_) = payload { return true }
            return false
        }
        return hasTab ? movedLine(jarName: jarName) : openedLine(jarName: jarName)
    }

    var body: some View {
        JarFillDriver(jar: jar, workbench: workbench) { state in
            Button(action: activate) {
                VStack(spacing: 3) {
                    NRFilledJar(paint: paint, fill: state.fill, size: 58, isActive: isActive,
                                dropProgress: state.dropProgress)
                        .sealAnchor(.jar(jar.id))
                    Text(jar.name)
                        .font(NRType.font(NRType.fsSm, weight: isActive ? .semibold : .medium))
                        .tracking(-0.15)
                        .foregroundStyle(isActive || contrast == .increased ? NRColor.fg : NRColor.fg2)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 96)
                }
                .padding(.top, 6)
                .frame(width: Self.width, height: Self.height, alignment: .top)
                .background(tileFill, in: RoundedRectangle(cornerRadius: Self.radius))
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: Self.radius)
                            .strokeBorder(firmEdge ? paint.text700 : paint.edge300, lineWidth: firmEdge ? 2 : NRSpace.hairline)
                    }
                }
                .overlay(alignment: .topTrailing) { countBadge.opacity(state.badgeVisible ? 1 : 0) }
                .overlay(alignment: .leading) { if isDropTarget { NRDropMark().padding(.vertical, 10) } }
                .contentShape(RoundedRectangle(cornerRadius: Self.radius))
                .scaleEffect(state.bump * switchBump)
            }
            .buttonStyle(.plain)
            // The ring is ours, in --nr-focus and the tile's shape, not the system's.
            .focusEffectDisabled()
            .overlay { if isFocused { NRFocusRing(cornerRadius: Self.radius) } }
            .onHover { hovering = $0 }
            .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
            .animation(NRMotion.animation(duration: NRMotion.fast), value: isActive)
            .onChange(of: isActive) { _, active in
                guard active, !reduceMotion else { return }
                bumpOnSwitch()
            }
            .help(index < 9 ? "\(jar.name) — ⌘\(index + 1)" : jar.name)
            .accessibilityLabel(jar.name)
            .accessibilityValue(Self.spokenValue(tabs: tabs, kept: kept, sinking: sinking, shelfLifeDays: jar.shelfLifeDays))
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
    }

    /// 1 → 1.05 → 1 over 320ms on easeJar, which overshoots on the way back.
    private func bumpOnSwitch() {
        withAnimation(NRMotion.animation(NRMotion.easeJar, duration: 0.16)) { switchBump = 1.05 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(NRMotion.animation(NRMotion.easeJar, duration: 0.16)) { switchBump = 1 }
        }
    }

    /// How many things the jar holds, in the jar's colors: float, a 1pt edge, ink numerals.
    private var countBadge: some View {
        Text("\(count)")
            .font(NRType.font(NRType.fsXs, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(NRColor.fg)
            .padding(.horizontal, 5)
            .frame(minWidth: 20)
            .frame(height: 18)
            .background(NRColor.float, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(paint.edge300, lineWidth: NRSpace.hairline))
            .padding(6)
            .accessibilityHidden(true)
    }
}

/// A smart jar: `#nr-jar-smart`, neutral. Sinking soon carries a count badge, because it
/// asks for something; Today and Sealed only ever grow, so a number there is noise.
struct SmartJarRow: View {
    let smart: SmartJar
    let count: Int
    let isActive: Bool
    /// The keyboard is here: draw the focus ring.
    var isFocused = false
    let activate: () -> Void

    private var showsCount: Bool { smart == .brine || smart == .sinking }

    /// What VoiceOver says the smart jar holds, after its name. Spoken for every smart jar,
    /// though only Sinking soon draws its number: the badge rule is about noise on screen,
    /// and VoiceOver says it only when asked. Sinking soon holds open tabs; the others, items.
    static func spokenValue(smart: SmartJar, count: Int) -> String {
        switch smart {
        case .sinking: count == 0 ? "None" : count == 1 ? "1 tab" : "\(count) tabs"
        case .brine, .today, .sealed: count == 0 ? "Empty" : count == 1 ? "1 item" : "\(count) items"
        }
    }

    var body: some View {
        // ShelfRow speaks the name; the count is the value.
        ShelfRow(title: smart.name, help: "\(smart.name) — \(smart.shortcutLabel)", isActive: isActive,
                 badge: showsCount && count > 0 ? "\(count)" : nil, isFocused: isFocused) {
            NRSymbol.jarSmart.image.resizable().frame(width: 16, height: 16)
        } action: {
            activate()
        }
        .accessibilityValue(Self.spokenValue(smart: smart, count: count))
    }
}
