// ShelfView.swift — the jar rail (manifest §8 Shelf). shelfW wide on the leading edge,
// surface2, one jar per row with its label under it, the active row tinted relish100
// (relish placement #3). Smart jars sit at the bottom under a hairline — Brine first,
// ⌘⇧1 — then New Jar last.

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
            SmartJarRow(name: "Brine", count: workbench.brine.count, isActive: workbench.showingBrine) {
                workbench.activateBrine()
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

/// A smart jar: `#nr-jar-smart`, neutral, with a count.
struct SmartJarRow: View {
    let name: String
    let count: Int
    let isActive: Bool
    let activate: () -> Void

    var body: some View {
        Button(action: activate) {
            VStack(spacing: 2) {
                NRSymbol.jarSmart.image.resizable().frame(width: 20, height: 20)
                    .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2)
                    .overlay(alignment: .topTrailing) {
                        if count > 0 { NRBadge("\(count)").offset(x: 10, y: -6) }
                    }
                Text(name).font(NRType.font(NRType.fsXs)).lineLimit(1)
                    .foregroundStyle(isActive ? NRColor.fg : NRColor.fg2)
            }
            .frame(width: 48, height: 44)
            .background(isActive ? NRColor.relish100 : .clear, in: RoundedRectangle(cornerRadius: NRRadius.r1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(name) — ⌘⇧1")
        .accessibilityLabel(name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
