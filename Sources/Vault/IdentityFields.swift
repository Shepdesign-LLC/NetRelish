// IdentityFields.swift — the nine fields as a labeled grid. Used by Settings → Me and by the
// Jar sheet's override. Manifest §8: fsSm labels in fg2, system text fields, no decoration.

import SwiftUI

struct IdentityFields: View {
    @Binding var identity: Identity

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: NRSpace.sp3, verticalSpacing: NRSpace.sp2) {
            row(.givenName, .familyName)
            row(.email)
            row(.phone)
            row(.street)
            row(.city, .state)
            row(.postalCode, .country)
        }
    }

    private func row(_ a: IdentityField, _ b: IdentityField? = nil) -> some View {
        GridRow {
            label(a)
            HStack(spacing: NRSpace.sp3) {
                field(a)
                if let b { label(b); field(b) }
            }
        }
    }

    private func label(_ f: IdentityField) -> some View {
        Text(f.label).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
    }

    private func field(_ f: IdentityField) -> some View {
        TextField("", text: Binding(get: { identity[f] }, set: { identity[f] = $0 }))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120)
            .accessibilityLabel(f.label)
    }
}
