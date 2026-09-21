// NewJarSheet.swift — name, color, shelf life. The color is stored as OKLCH on the jar
// and only ever paints that jar's glyph (ADR 0005).

import SwiftUI

struct NewJarSheet: View {
    var create: (_ name: String, _ tint: String?, _ shelfLifeDays: Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: Color = OKLCH(l: 0.72, c: 0.14, h: 40).color
    @State private var shelfLifeDays = 3

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp4) {
            Text("New Jar").font(NRType.font(NRType.fsLg, weight: .semibold)).foregroundStyle(NRColor.fg)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: NRSpace.sp3, verticalSpacing: NRSpace.sp3) {
                GridRow {
                    Text("Name").font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                    TextField("Meridian", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit(submit)
                }
                GridRow {
                    Text("Color").font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                    HStack(spacing: NRSpace.sp2) {
                        ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
                        NRSymbol.jar.image.resizable().frame(width: 20, height: 20).foregroundStyle(color)
                        Text("Only this jar wears it.").font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg3)
                    }
                }
                GridRow {
                    Text("Shelf life").font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                    HStack(spacing: NRSpace.sp2) {
                        Stepper(value: $shelfLifeDays, in: 1...90) {
                            Text("\(shelfLifeDays) \(shelfLifeDays == 1 ? "day" : "days")").monospacedDigit()
                        }
                        Text("Idle tabs sink into Brine after this.").font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg3)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.nrSecondary).keyboardShortcut(.cancelAction)
                Button("Create") { submit() }.buttonStyle(.nrPrimary).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(NRSpace.sp6)
        .frame(width: 460)
        .background(NRColor.surface)
    }

    private func submit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        create(name, OKLCH(color).css, Double(shelfLifeDays))
        dismiss()
    }
}
