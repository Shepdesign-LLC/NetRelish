// FloatShadow.swift — the one float shadow (manifest v2.1 §6, ADR 0035), for things that
// float over the window: the ⌘K palette, menus and sheets. Chrome rows stay flat. Light: the
// float fill, a 1pt hairline and two soft shadows (0 4 20 at 8%, 0 1 3 at 4%). Dark: the
// hairline alone does the work; a shadow on near-black reads as a smudge. Hand-written.

import SwiftUI

struct NRFloatModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let lit = colorScheme != .dark
        content
            .clipShape(shape)
            // The shadows sit on the fill alone, so nothing inside the box casts one of its own.
            .background {
                shape.fill(NRColor.float)
                    .shadow(color: .black.opacity(lit ? 0.08 : 0), radius: 10, x: 0, y: 4)
                    .shadow(color: .black.opacity(lit ? 0.04 : 0), radius: 1.5, x: 0, y: 1)
            }
            .overlay {
                shape.strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Floats this view: the float fill, a hairline, and in light mode the soft float shadow
    /// (manifest v2.1 §6). For floating things only, never for a chrome row.
    func nrFloat(cornerRadius: CGFloat = 12) -> some View {
        modifier(NRFloatModifier(cornerRadius: cornerRadius))
    }
}
