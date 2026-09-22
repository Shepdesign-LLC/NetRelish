// JarSheet.swift — new or edit: name, color, shelf life. The color is stored as OKLCH on
// the jar and only ever paints that jar's glyph (ADR 0005). Shelf life is stored in days;
// the unit picker exists so a demo (or an impatient person) can say "60 seconds".

import Pantry
import SwiftUI

struct JarSheet: View {
    enum Unit: String, CaseIterable, Identifiable {
        case seconds, minutes, hours, days
        var id: String { rawValue }
        var perDay: Double { switch self { case .seconds: 86_400; case .minutes: 1_440; case .hours: 24; case .days: 1 } }
    }

    /// Nil for a new jar.
    var existing: Jar?
    var save: (_ name: String, _ tint: String?, _ shelfLifeDays: Double?) -> Void
    var vault: VaultStore = .live
    @Environment(\.dismiss) private var dismiss
    @State private var ownCard = false
    @State private var card = Identity()
    @State private var name = ""
    @State private var color: Color = OKLCH(l: 0.72, c: 0.14, h: 40).color
    @State private var amount = 3
    @State private var unit: Unit = .days
    @State private var hasShelfLife = true

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp4) {
            Text(existing == nil ? "New Jar" : "Edit Jar").font(NRType.font(NRType.fsLg, weight: .semibold)).foregroundStyle(NRColor.fg)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: NRSpace.sp3, verticalSpacing: NRSpace.sp3) {
                GridRow {
                    Text("Name").font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                    TextField("Meridian", text: $name).textFieldStyle(.roundedBorder).frame(width: 240).onSubmit(submit)
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
                    VStack(alignment: .leading, spacing: NRSpace.sp2) {
                        HStack(spacing: NRSpace.sp2) {
                            Toggle("", isOn: $hasShelfLife).labelsHidden().toggleStyle(.switch)
                            TextField("", value: $amount, format: .number).textFieldStyle(.roundedBorder).frame(width: 56)
                                .multilineTextAlignment(.trailing).disabled(!hasShelfLife).accessibilityLabel("Shelf life amount")
                            Stepper("", value: $amount, in: 1...999).labelsHidden().disabled(!hasShelfLife)
                            Picker("", selection: $unit) { ForEach(Unit.allCases) { Text($0.rawValue).tag($0) } }
                                .labelsHidden().frame(width: 110).disabled(!hasShelfLife)
                        }
                        Text(hasShelfLife ? "Idle tabs sink into Brine after this. Pinned tabs never sink." : "Tabs in this jar never sink.")
                            .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg3)
                    }
                }
                if existing != nil {
                    GridRow {
                        Text("Card").font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                        VStack(alignment: .leading, spacing: NRSpace.sp2) {
                            Toggle("Use a different card in this jar", isOn: $ownCard).toggleStyle(.switch)
                                .font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg)
                            Text(ownCard ? "⌘⇧F fills forms in this jar from this card instead of Me." : "⌘⇧F fills forms in this jar from Me (Settings → Me).")
                                .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg3)
                            if ownCard { IdentityFields(identity: $card) }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.nrSecondary).keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Create" : "Save") { submit() }.buttonStyle(.nrPrimary).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(NRSpace.sp6)
        .frame(width: 520)
        .background(NRColor.surface)
        .onAppear(perform: seed)
    }

    private func seed() {
        guard let existing else { return }
        name = existing.name
        if let own = try? vault.hasOverride(for: existing.id), own {
            ownCard = true
            card = (try? vault.identity(for: existing.id)) ?? Identity()
        }
        if let tint = existing.tint, let c = OKLCH(tint) { color = c.color }
        if let days = existing.shelfLifeDays, days > 0 {
            hasShelfLife = true
            // Show the largest unit that divides evenly.
            for u in [Unit.days, .hours, .minutes, .seconds] {
                let v = days * u.perDay
                if abs(v - v.rounded()) < 1e-6 { amount = max(1, Int(v.rounded())); unit = u; break }
            }
        } else {
            hasShelfLife = false
        }
    }

    private func submit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        save(name, OKLCH(color).css, hasShelfLife ? Double(amount) / unit.perDay : nil)
        if let existing {
            if ownCard, !card.isEmpty { try? vault.save(card, for: existing.id) } else { try? vault.remove(for: existing.id) }
        }
        dismiss()
    }
}
