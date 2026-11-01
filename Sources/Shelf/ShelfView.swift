// ShelfView.swift — the jar rail (manifest §8 Shelf). shelfW wide on the leading edge,
// surface2, one jar per row with its label under it, the active row tinted relish100
// (relish placement #3). Smart jars sit at the bottom under a hairline — Brine, Today,
// Sealed, Sinking soon, ⌘⇧1–4 — then New Jar last.

import Pantry
import SwiftUI

struct ShelfView: View {
    @Bindable var workbench: Workbench
    @State private var showingNewJar = false
    @State private var editingJar: Jar?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: NRSpace.sp1) {
                    ForEach(Array(workbench.jars.enumerated()), id: \.element.id) { index, jar in
                        JarRow(jar: jar, index: index, isActive: jar.id == workbench.activeJarId) {
                            workbench.activate(jar)
                        }
                        .contextMenu {
                            Button("Edit Jar…") { editingJar = jar }
                        }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { editingJar = jar })
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
}

/// One jar on the rail: the glyph in the jar's own tint (its data, not chrome), the name under it.
struct JarRow: View {
    let jar: Jar
    let index: Int
    let isActive: Bool
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
            .frame(width: 48, height: 44)
            .background(isActive ? NRColor.relish100 : .clear, in: RoundedRectangle(cornerRadius: NRRadius.r1))
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
        .help("\(smart.name) — ⌘⇧\(smart.number)")
        .accessibilityLabel(showsCount ? "\(smart.name), \(count)" : smart.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
