// SealedPill.swift — the "Sealed" pill (manifest v2.1 §4 #4): relish-100 fill, a 1pt relish
// edge, a relish-500 disc holding an ink check, then "Sealed". Regular (28pt) lands at the end
// of the address row during Seal; small (22pt) sits on sealed cards. Hand-written.

import SwiftUI

struct NRSealedPill: View {
    enum Size { case regular, small }   // 28pt (address row, during Seal) / 22pt (sealed cards)
    var size: Size = .regular
    /// How much of the check is drawn, 0…1. The Seal overlay draws it on; at rest it's whole.
    var checkProgress: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var height: CGFloat { size == .regular ? 28 : 22 }
    private var disc: CGFloat { size == .regular ? 16 : 14 }
    private var check: CGFloat { size == .regular ? 11 : 9.5 }
    private var fontSize: CGFloat { size == .regular ? NRType.fsMd : NRType.fsXs }
    private var spacing: CGFloat { size == .regular ? 7 : 5 }
    private var leading: CGFloat { size == .regular ? 7 : 4 }
    private var trailing: CGFloat { size == .regular ? 12 : 9 }

    var body: some View {
        HStack(spacing: spacing) {
            Circle()
                .fill(NRColor.relish500)
                .frame(width: disc, height: disc)
                .overlay {
                    SealCheckShape()
                        .trim(from: 0, to: checkProgress)
                        .stroke(colorScheme == .dark ? NRColor.relishInk : Color.black,
                                style: StrokeStyle(lineWidth: check * 3.2 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: check, height: check)
                }
            Text("Sealed")
                .font(NRType.font(fontSize, weight: .semibold))
                .foregroundStyle(NRColor.fg)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, leading)
        .padding(.trailing, trailing)
        .frame(height: height)
        .background(Capsule().fill(NRColor.relish100))
        // relish-300 on relish-100 is a faint edge; under Increase Contrast it takes the
        // contrast step, relish-700, as dark mode already does. Still the pill (placement 4).
        .overlay(Capsule().strokeBorder(Self.strongEdge(dark: colorScheme == .dark, contrast: contrast)
                                            ? NRColor.relish700 : NRColor.relish300,
                                        lineWidth: NRSpace.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sealed")
    }

    /// Whether the pill's edge is relish-700 rather than relish-300.
    static func strongEdge(dark: Bool, contrast: ColorSchemeContrast) -> Bool {
        dark || contrast == .increased
    }
}

/// The comp's check, `M6.5 12.5 l3.5 3.5 7.5-8` on a 24-unit square, scaled to the frame.
struct SealCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24, sy = rect.height / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 6.5 * sx, y: rect.minY + 12.5 * sy))
        path.addLine(to: CGPoint(x: rect.minX + 10 * sx, y: rect.minY + 16 * sy))
        path.addLine(to: CGPoint(x: rect.minX + 17.5 * sx, y: rect.minY + 8 * sy))
        return path
    }
}
