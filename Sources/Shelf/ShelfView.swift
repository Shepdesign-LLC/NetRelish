// ShelfView.swift — the jar rail (manifest §8 Shelf). shelfW wide on the leading edge,
// surface2, one jar per row with its label under it, the active row tinted relish100
// (relish placement #3). Smart jars sit at the bottom under a hairline — Brine, Today,
// Sealed, Sinking soon, ⌃⌘1–4 — then New Jar last.
//
// A jar can be dragged, but only along the Shelf: it slides up and down the rail and
// nowhere else. A tab or a Brine row dragged onto a jar lands in it, and the row shows the
// drop mark (relish placement #9) while it would.

import Pantry
import SwiftUI

struct ShelfView: View {
    @Bindable var workbench: Workbench
    @State private var showingNewJar = false
    @State private var editingJar: Jar?
    /// The jar being slid along the rail: where it started and how far it has come.
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
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: NRSpace.sp1) {
                    ForEach(Array(workbench.jars.enumerated()), id: \.element.id) { index, jar in
                        JarRow(jar: jar, index: index, isActive: jar.id == workbench.activeJarId,
                               isDropTarget: dropTarget == jar.id) {
                            workbench.activate(jar)
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
                .padding(.vertical, NRSpace.sp2)
            }
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            VStack(spacing: NRSpace.sp1) {
                ForEach(SmartJar.allCases) { smart in
                    SmartJarRow(smart: smart, count: workbench.count(of: smart),
                                isActive: workbench.activeSmartJar == smart) {
                        workbench.activate(smart)
                    }
                }
            }
            .padding(.vertical, NRSpace.sp1)
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            Button { showingNewJar = true } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .medium)).frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(NRColor.fg2).help("New Jar").accessibilityLabel("New Jar")
            .padding(.vertical, NRSpace.sp1)
        }
        .frame(width: NRSpace.shelfW)
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

/// The colors a jar's menu offers. Any other color is still one click away in Edit Jar…;
/// like every tint, these only ever paint the jar's own glyph (ADR 0005).
struct JarTint: Identifiable {
    let name: String
    let oklch: OKLCH
    var id: String { css }
    var css: String { oklch.css }
    var color: Color { oklch.color }

    /// One lightness and chroma, six hues, so no jar shouts over another.
    static let presets: [JarTint] = [
        JarTint(name: "Clay", oklch: OKLCH(l: 0.72, c: 0.14, h: 40)),
        JarTint(name: "Honey", oklch: OKLCH(l: 0.72, c: 0.14, h: 85)),
        JarTint(name: "Dill", oklch: OKLCH(l: 0.72, c: 0.14, h: 145)),
        JarTint(name: "Brine", oklch: OKLCH(l: 0.72, c: 0.14, h: 200)),
        JarTint(name: "Plum", oklch: OKLCH(l: 0.72, c: 0.14, h: 300)),
        JarTint(name: "Beet", oklch: OKLCH(l: 0.72, c: 0.14, h: 350)),
    ]
}

/// One jar on the rail: the glyph in the jar's own tint (its data, not chrome), the name under it.
struct JarRow: View {
    /// A row's height on the rail. The Shelf uses it to work out how far a jar slides.
    static let height: CGFloat = 44

    let jar: Jar
    let index: Int
    let isActive: Bool
    /// A dragged tab or Brine row is over this jar and would land in it.
    var isDropTarget = false
    let activate: () -> Void

    private var tint: Color { jar.tint.flatMap(OKLCH.init)?.color ?? NRColor.fg2 }

    var body: some View {
        Button(action: activate) {
            VStack(spacing: 2) {
                NRSymbol.jar.image.resizable().frame(width: 20, height: 20)
                    .foregroundStyle(isActive ? tint : tint.opacity(0.75))
                Text(jar.name).font(NRType.font(NRType.fsXs)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2)
            }
            .frame(width: 48, height: Self.height)
            .background(isActive ? NRColor.relish100 : .clear, in: RoundedRectangle(cornerRadius: NRRadius.r1))
            .overlay(alignment: .leading) { if isDropTarget { NRDropMark() } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(index < 9 ? "\(jar.name) — ⌘\(index + 1)" : jar.name)
        .accessibilityLabel(jar.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// A smart jar: `#nr-jar-smart`, neutral. Brine and Sinking soon carry a count badge
/// (relish placement #6), because those are the two that ask for something; Today and
/// Sealed only ever grow, so a number there is noise.
struct SmartJarRow: View {
    let smart: SmartJar
    let count: Int
    let isActive: Bool
    let activate: () -> Void

    private var showsCount: Bool { smart == .brine || smart == .sinking }
    /// The rail is 56pt wide; "Sinking soon" says "Sinking" there and in full everywhere else.
    private var shelfLabel: String { smart == .sinking ? "Sinking" : smart.name }

    var body: some View {
        Button(action: activate) {
            VStack(spacing: 2) {
                NRSymbol.jarSmart.image.resizable().frame(width: 20, height: 20)
                    .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2)
                    .overlay(alignment: .topTrailing) {
                        if showsCount, count > 0 { NRBadge("\(count)").offset(x: 10, y: -6) }
                    }
                Text(shelfLabel).font(NRType.font(NRType.fsXs)).lineLimit(1).minimumScaleFactor(0.85)
                    .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2)
            }
            .frame(width: 48, height: 44)
            .background(isActive ? NRColor.relish100 : .clear, in: RoundedRectangle(cornerRadius: NRRadius.r1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(smart.name) — \(smart.shortcutLabel)")
        .accessibilityLabel(showsCount ? "\(smart.name), \(count)" : smart.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
