// ShelfView.swift — the jar rail (manifest §8 Shelf). `NRSpace.shelfW` wide on the leading
// edge, `surface2`, one jar per row with its label under it, the active row tinted
// `relish100` (relish placement #3). Smart jars arrive in P2; New Jar is last.

import Pantry
import SwiftUI

struct ShelfView: View {
    @Bindable var workbench: Workbench
    @State private var showingNewJar = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: NRSpace.sp1) {
                    ForEach(Array(workbench.jars.enumerated()), id: \.element.id) { index, jar in
                        JarRow(jar: jar, index: index, isActive: jar.id == workbench.activeJarId) {
                            workbench.activate(jar)
                        }
                    }
                }
                .padding(.vertical, NRSpace.sp2)
            }
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            Button {
                showingNewJar = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(NRColor.fg2)
            .help("New Jar")
            .accessibilityLabel("New Jar")
            .padding(.vertical, NRSpace.sp1)
        }
        .frame(width: NRSpace.shelfW)
        .background(NRColor.surface2)
        .overlay(alignment: .trailing) { Rectangle().fill(NRColor.hairline).frame(width: NRSpace.hairline) }
        .sheet(isPresented: $showingNewJar) {
            NewJarSheet { name, tint, days in workbench.newJar(name: name, tint: tint, shelfLifeDays: days) }
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
                NRSymbol.jar.image.resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isActive ? tint : tint.opacity(0.75))
                Text(jar.name)
                    .font(NRType.font(NRType.fsXs))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
