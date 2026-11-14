// ShelfView.swift — the Shelf (manifest v2.0 §8, Workstation v5 spec §6.4). shelfW wide on
// the leading edge and always open. Jars first, under their section label: one row each,
// the jar drawn filled in its own color, its name, and how much is in it. The active row
// takes a wash of the jar's color. Then the Pantry's smart jars (Today, Sealed, Sinking
// soon; Brine lives in the bottom bar), then the Zest tools.
//
// A jar can be dragged, but only along the Shelf: it slides up and down among the jars and
// nowhere else. A tab or a Brine row dragged onto a jar lands in it, and the row shows the
// drop mark while it would.

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

    /// One row and the gap under it: how far a jar slides to change places with its neighbor.
    private static let pitch = JarRow.height + NRSpace.sp1

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: NRSpace.sp4) {
                jars
                pantry
                zest
            }
            .padding(NRSpace.sp3)
        }
        .frame(width: NRSpace.shelfW)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NRColor.surface2)
        .overlay(alignment: .trailing) { Rectangle().fill(NRColor.hairline).frame(width: NRSpace.hairline) }
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
        VStack(alignment: .leading, spacing: NRSpace.sp2) {
            ShelfSectionLabel(title: "Jars", tile: { NRSymbol.jar.image.resizable() },
                              action: "New Jar", actionSymbol: "plus") { showingNewJar = true }
            VStack(spacing: NRSpace.sp1) {
                ForEach(Array(workbench.jars.enumerated()), id: \.element.id) { index, jar in
                    JarRow(jar: jar, index: index, count: workbench.count(in: jar), fill: workbench.fill(of: jar),
                           isActive: jar.id == workbench.activeJarId, isDropTarget: dropTarget == jar.id) {
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
        }
    }

    private var pantry: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp2) {
            ShelfSectionLabel(title: "Pantry", tile: { NRSymbol.jarSmart.image.resizable() })
            VStack(spacing: NRSpace.sp1) {
                // Brine is the pill in the bottom bar; ⌃⌘1 still opens it.
                ForEach(SmartJar.allCases.filter { $0 != .brine }) { smart in
                    SmartJarRow(smart: smart, count: workbench.count(of: smart),
                                isActive: workbench.activeSmartJar == smart) {
                        workbench.activate(smart)
                    }
                }
            }
        }
    }

    private var zest: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp2) {
            ShelfSectionLabel(title: "Zest", tile: { Image(systemName: "square.stack.3d.up.fill").resizable().scaledToFit() })
            VStack(spacing: NRSpace.sp1) {
                ForEach(ZestTool.allCases) { tool in
                    ShelfRow(title: tool.shelfName, help: "Open \(tool.shelfName) in the Zest window") {
                        Image(systemName: tool.shelfSymbol).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(NRColor.relish700)
                    } action: {
                        workbench.zestToolRequest = tool
                        openWindow(id: "zest")
                    }
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

extension ZestTool {
    /// The tool's name on the Shelf, as the Zest line spells it.
    var shelfName: String {
        switch self {
        case .studio: "Zest"
        case .mail: "ZestMail"
        case .md: "Zest MD"
        case .image: "ZestImage"
        }
    }

    var shelfSymbol: String {
        switch self {
        case .studio: "paintpalette"
        case .mail: "envelope"
        case .md: "doc.text"
        case .image: "photo"
        }
    }
}

/// A section's label on the Shelf: a tile in relish holding the section's glyph, the name,
/// and, where the section can grow, one button on the trailing edge.
struct ShelfSectionLabel<Tile: View>: View {
    let title: String
    @ViewBuilder let tile: Tile
    var action: String? = nil
    var actionSymbol: String = "plus"
    var perform: (() -> Void)? = nil

    init(title: String, @ViewBuilder tile: () -> Tile, action: String? = nil, actionSymbol: String = "plus",
         perform: (() -> Void)? = nil) {
        self.title = title
        self.tile = tile()
        self.action = action
        self.actionSymbol = actionSymbol
        self.perform = perform
    }

    var body: some View {
        HStack(spacing: NRSpace.sp2) {
            tile
                .frame(width: 11, height: 11)
                .foregroundStyle(NRColor.relishInk)
                .frame(width: 18, height: 18)
                .background(NRColor.relish500, in: RoundedRectangle(cornerRadius: 5))
                .accessibilityHidden(true)
            Text(title.uppercased())
                .font(NRType.font(NRType.fsSm, weight: .semibold)).tracking(0.3)
                .foregroundStyle(NRColor.fg2)
            Spacer(minLength: 0)
            if let action, let perform {
                Button(action: perform) {
                    Image(systemName: actionSymbol).font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(NRColor.fg2).help(action).accessibilityLabel(action)
            }
        }
        .padding(.horizontal, NRSpace.sp2)
        .frame(height: 36)
        .background(NRColor.surface, in: RoundedRectangle(cornerRadius: NRRadius.r2))
        .overlay(RoundedRectangle(cornerRadius: NRRadius.r2).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
        .accessibilityAddTraits(.isHeader)
    }
}

/// One row on the Shelf that isn't a jar: a glyph, a name, an optional trailing count.
struct ShelfRow<Glyph: View>: View {
    let title: String
    var help: String
    var isActive = false
    var badge: String? = nil
    @ViewBuilder let glyph: Glyph
    let action: () -> Void

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
            HStack(spacing: NRSpace.sp3) {
                glyph.frame(width: 24, height: 24)
                Text(title).font(NRType.font(NRType.fsLg, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2).lineLimit(1)
                Spacer(minLength: 0)
                if let badge { NRBadge(badge) }
            }
            .padding(.horizontal, NRSpace.sp3)
            .frame(height: JarRow.height)
            .background(isActive ? NRColor.relish100 : .clear, in: RoundedRectangle(cornerRadius: NRRadius.r2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// One jar on the Shelf: the jar drawn filled in its own color (its data, not chrome), its
/// name, and how much is in it. The active row takes a wash of that color.
struct JarRow: View {
    /// A row's height on the Shelf. The Shelf uses it to work out how far a jar slides.
    static let height: CGFloat = 44

    let jar: Jar
    let index: Int
    /// Open tabs plus what the jar keeps.
    let count: Int
    /// How full the jar is drawn, 0…1.
    let fill: Double
    let isActive: Bool
    /// A dragged tab or Brine row is over this jar and would land in it.
    var isDropTarget = false
    let activate: () -> Void

    var body: some View {
        Button(action: activate) {
            HStack(spacing: NRSpace.sp3) {
                NRFilledJar(paint: jar.paint, fill: fill, size: 20).frame(width: 24, height: 24)
                Text(jar.name).font(NRType.font(NRType.fsLg, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text("\(count)").font(NRType.font(NRType.fsSm)).monospacedDigit().foregroundStyle(NRColor.fg3)
            }
            .padding(.horizontal, NRSpace.sp3)
            .frame(height: Self.height)
            .background(isActive ? jar.paint.wash(0.16) : .clear, in: RoundedRectangle(cornerRadius: NRRadius.r2))
            .overlay(alignment: .leading) { if isDropTarget { NRDropMark().padding(.vertical, NRSpace.sp1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(index < 9 ? "\(jar.name) — ⌘\(index + 1)" : jar.name)
        .accessibilityLabel("\(jar.name), \(count) inside")
        .accessibilityAddTraits(isActive ? .isSelected : [])
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
            NRSymbol.jarSmart.image.resizable().frame(width: 20, height: 20)
                .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2)
        } action: {
            activate()
        }
        .accessibilityLabel(showsCount ? "\(smart.name), \(count)" : smart.name)
    }
}
