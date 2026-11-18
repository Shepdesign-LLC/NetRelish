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

import Pantry
import SwiftUI

struct ShelfView: View {
    @Bindable var workbench: Workbench
    @Environment(\.openWindow) private var openWindow
    @State private var showingNewJar = false
    @State private var editingJar: Jar?
    /// The jar being slid along the Shelf: where it started and how far it has come.
    @State private var lifted: Lifted?
    /// The jar a dragged tab or Brine row is over.
    @State private var dropTarget: String?

    private struct Lifted: Equatable {
        let id: String
        let from: Int
        var travel: CGFloat
    }

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
            ScrollView(.vertical) {
                VStack(spacing: Self.tileGap) {
                    jars
                    NewJarButton { showingNewJar = true }
                }
                // Inside the scroll view, so a tile's bump is never clipped at the top.
                .padding(.top, Self.top)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: jarsHeight)
            .layoutPriority(1)

            Rectangle().fill(NRColor.hairlineSoft).frame(height: NRSpace.hairline)
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
        .overlay(alignment: .trailing) { Rectangle().fill(NRColor.hairlineSoft).frame(width: NRSpace.hairline) }
        .sheet(isPresented: $showingNewJar) {
            JarSheet(existing: nil) { name, tint, days in workbench.newJar(name: name, tint: tint, shelfLifeDays: days) }
        }
        .sheet(item: $editingJar) { jar in
            JarSheet(existing: jar) { name, tint, days in workbench.updateJar(jar, name: name, tint: tint, shelfLifeDays: days) }
        }
        .onChange(of: workbench.jarToEdit) { _, jar in
            if let jar { editingJar = jar; workbench.jarToEdit = nil }
        }
    }

    // MARK: Sections

    private var jars: some View {
        ForEach(Array(workbench.jars.enumerated()), id: \.element.id) { index, jar in
            JarTile(jar: jar, index: index, count: workbench.count(in: jar),
                    isActive: jar.id == workbench.activeJarId, isDropTarget: dropTarget == jar.id,
                    workbench: workbench) {
                workbench.showBoard(of: jar)
            }
            .offset(y: slide(of: jar, at: index))
            .zIndex(lifted?.id == jar.id ? 1 : 0)
            .animation(lifted?.id == jar.id ? nil : NRMotion.animation(duration: NRMotion.fast), value: landing)
            .contextMenu { menu(for: jar, at: index) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { editingJar = jar })
            .highPriorityGesture(slideGesture(for: jar, at: index))
            .dropDestination(for: String.self) { payloads, _ in
                workbench.drop(payloads, onJar: jar)
            } isTargeted: { over in
                if over { dropTarget = jar.id } else if dropTarget == jar.id { dropTarget = nil }
            }
        }
    }

    private var pantry: some View {
        VStack(spacing: 0) {
            // Brine is the pill in the bottom bar; ⌃⌘1 still opens it.
            ForEach(SmartJar.allCases.filter { $0 != .brine }) { smart in
                SmartJarRow(smart: smart, count: workbench.count(of: smart),
                            isActive: workbench.activeSmartJar == smart) {
                    workbench.activate(smart)
                }
            }
        }
    }

    /// One row for the Zest window, neutral (`--nr-fg-2`, manifest v2.1 §4 #11): the tools
    /// are chosen inside it.
    private var zest: some View {
        ShelfRow(title: "Zest", help: "Open the Zest window") {
            Image(systemName: "square.grid.2x2").font(.system(size: 13, weight: .regular))
                .foregroundStyle(NRColor.fg2)
        } action: {
            openWindow(id: "zest")
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
    @ViewBuilder let glyph: Glyph
    let action: () -> Void
    @State private var hovering = false

    init(title: String, help: String, isActive: Bool = false, badge: String? = nil,
         @ViewBuilder glyph: () -> Glyph, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.isActive = isActive
        self.badge = badge
        self.glyph = glyph()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                glyph.frame(width: 16, height: 16).foregroundStyle(NRColor.fg3)
                Text(title).font(NRType.font(NRType.fsSm, weight: .medium))
                    .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if let badge { NRBadge(badge).layoutPriority(1) }
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
            .frame(height: Self.height)
            .background(isActive ? NRColor.relish100 : (hovering ? NRColor.tab : .clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        .help(help)
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
    /// Open tabs plus what the jar keeps.
    let count: Int
    let isActive: Bool
    /// A dragged tab or Brine row is over this jar and would land in it.
    var isDropTarget = false
    let workbench: Workbench
    let activate: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var paint: JarPaint { jar.paint }

    private var tileFill: Color {
        if isActive { return colorScheme == .dark ? NRColor.float : paint.wash100 }
        return hovering ? NRColor.tab : .clear
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
                        .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 96)
                }
                .padding(.top, 6)
                .frame(width: Self.width, height: Self.height, alignment: .top)
                .background(tileFill, in: RoundedRectangle(cornerRadius: Self.radius))
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: Self.radius).strokeBorder(paint.edge300, lineWidth: NRSpace.hairline)
                    }
                }
                .overlay(alignment: .topTrailing) { countBadge.opacity(state.badgeVisible ? 1 : 0) }
                .overlay(alignment: .leading) { if isDropTarget { NRDropMark().padding(.vertical, 10) } }
                .contentShape(RoundedRectangle(cornerRadius: Self.radius))
                .scaleEffect(state.bump)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
            .animation(NRMotion.animation(duration: NRMotion.fast), value: isActive)
            .help(index < 9 ? "\(jar.name) — ⌘\(index + 1)" : jar.name)
            .accessibilityLabel("\(jar.name), \(count) inside")
            .accessibilityAddTraits(isActive ? .isSelected : [])
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
    let activate: () -> Void

    private var showsCount: Bool { smart == .brine || smart == .sinking }

    var body: some View {
        ShelfRow(title: smart.name, help: "\(smart.name) — \(smart.shortcutLabel)", isActive: isActive,
                 badge: showsCount && count > 0 ? "\(count)" : nil) {
            NRSymbol.jarSmart.image.resizable().frame(width: 16, height: 16)
        } action: {
            activate()
        }
        .accessibilityLabel(showsCount ? "\(smart.name), \(count)" : smart.name)
    }
}
