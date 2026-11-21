// FloatShadow.swift — the one float shadow (manifest v2.1 §6, ADR 0035), for things that
// float over the window: the ⌘K palette, menus and sheets. Chrome rows stay flat. Light: the
// float fill, a 1pt hairline and two soft shadows (0 4 20 at 8%, 0 1 3 at 4%). Dark: the
// hairline alone does the work; a shadow on near-black reads as a smudge. Under Increase
// Contrast or Reduce Transparency the edge is drawn in --nr-fg-3 instead: the hairline alone
// is too faint an edge to find a float by. Hand-written.

import SwiftUI

struct NRFloatModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Whether the float's edge is drawn strong. The hairline is a faint edge (about 1.3:1
    /// against the float in light, 1.4:1 in dark, where there's no shadow at all), so anyone
    /// who asked the Mac for more contrast, or for less see-through, gets a 1pt --nr-fg-3
    /// edge in its place. The shadows stay as they are.
    static func edgeIsStrong(contrast: ColorSchemeContrast, reduceTransparency: Bool) -> Bool {
        contrast == .increased || reduceTransparency
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let lit = colorScheme != .dark
        let edge = Self.edgeIsStrong(contrast: contrast, reduceTransparency: reduceTransparency)
            ? NRColor.fg3 : NRColor.hairline
        content
            .clipShape(shape)
            // The shadows sit on the fill alone, so nothing inside the box casts one of its own.
            .background {
                shape.fill(NRColor.float)
                    .shadow(color: .black.opacity(lit ? 0.08 : 0), radius: 10, x: 0, y: 4)
                    .shadow(color: .black.opacity(lit ? 0.04 : 0), radius: 1.5, x: 0, y: 1)
            }
            .overlay {
                shape.strokeBorder(edge, lineWidth: NRSpace.hairline)
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
