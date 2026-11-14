// JarGlyph.swift — the jar, drawn (manifest v2.0 §7, Workstation v5 spec §4). A jar's fill
// level is data, so the jar is drawn live and never an image: glass, the fill with its
// meniscus, bubbles when full, the specular pass, the outline, the lid. Hand-written.
// The jar's color is the user's data (ADR 0005); the paint only shades it.

import SwiftUI

/// A jar's color, and the shades drawn from it: the face, the darker base the fill runs
/// down to, and the ink that reads on the face.
public struct JarPaint: Equatable, Sendable {
    public var oklch: OKLCH

    public init(_ oklch: OKLCH) { self.oklch = oklch }

    /// A stored tint, or relish for a jar that was never given a color.
    public init(css: String?) { self.oklch = css.flatMap(OKLCH.init) ?? JarPaint.relish.oklch }

    /// `--relish-500`: the color a jar has until it's given one.
    public static let relish = JarPaint(OKLCH(l: 0.834, c: 0.224, h: 130.9))

    public var face: Color { oklch.color }
    public var base: Color { OKLCH(l: oklch.l * 0.78, c: oklch.c, h: oklch.h).color }
    /// The face's relative luminance (WCAG), from its Display P3 components.
    public var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let (r, g, b) = oklch.p3
        return 0.2289746 * linear(r) + 0.6917385 * linear(g) + 0.0792869 * linear(b)
    }

    /// Whether black reads better on the face than white. They tie at a luminance of about
    /// 0.179, where each still has 4.58:1, so the better of the two never falls under 4.5:1,
    /// whatever color the jar was given in Edit Jar….
    public var inkIsDark: Bool { (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) }

    /// The contrast of `ink` on the face.
    public var inkContrast: Double {
        inkIsDark ? (luminance + 0.05) / 0.05 : 1.05 / (luminance + 0.05)
    }

    /// Text on the face: black or white, whichever has more contrast.
    public var ink: Color { inkIsDark ? .black : .white }
    /// The face at a part of its strength: row tints, chips, borders.
    public func wash(_ amount: Double) -> Color { face.opacity(amount) }
}

/// The jar's body in its 22 × 26 box, scaled to the rect it's given.
public struct JarBodyShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 4.6, y: 7.6))
        p.addCurve(to: CGPoint(x: 7, y: 5.2), control1: CGPoint(x: 4.6, y: 6.3), control2: CGPoint(x: 5.7, y: 5.2))
        p.addLine(to: CGPoint(x: 15, y: 5.2))
        p.addCurve(to: CGPoint(x: 17.4, y: 7.6), control1: CGPoint(x: 16.3, y: 5.2), control2: CGPoint(x: 17.4, y: 6.3))
        p.addLine(to: CGPoint(x: 17.4, y: 19.2))
        p.addQuadCurve(to: CGPoint(x: 14, y: 22.6), control: CGPoint(x: 17.4, y: 22.6))
        p.addLine(to: CGPoint(x: 8, y: 22.6))
        p.addQuadCurve(to: CGPoint(x: 4.6, y: 19.2), control: CGPoint(x: 4.6, y: 22.6))
        p.closeSubpath()
        let scale = CGAffineTransform(scaleX: rect.width / 22, y: rect.height / 26)
        return p.applying(scale).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// A jar at any width, filled to `fill` (0…1) in its own color.
public struct NRFilledJar: View {
    public var paint: JarPaint
    public var fill: Double
    public var size: CGFloat

    public init(paint: JarPaint, fill: Double, size: CGFloat = 24) {
        self.paint = paint
        self.fill = max(0, min(1, fill))
        self.size = size
    }

    public var body: some View {
        let paint = self.paint
        let level = self.fill
        Canvas { context, canvas in
            let u = canvas.width / 22
            let body = JarBodyShape().path(in: CGRect(origin: .zero, size: canvas))
            // 1. The empty glass.
            context.fill(body, with: .color(paint.base.opacity(0.10)))
            // 2. The fill, clipped to the body, with its meniscus.
            if level > 0 {
                var inside = context
                inside.clip(to: body)
                let top = (22.6 - 17.4 * level) * u
                inside.fill(Path(CGRect(x: 0, y: top, width: canvas.width, height: canvas.height - top)),
                            with: .linearGradient(Gradient(colors: [paint.face, paint.base]),
                                                  startPoint: CGPoint(x: 0, y: top),
                                                  endPoint: CGPoint(x: 0, y: 22.6 * u)))
                inside.fill(Path(ellipseIn: CGRect(x: 4.5 * u, y: top - 0.9 * u, width: 13 * u, height: 1.8 * u)),
                            with: .color(paint.face.opacity(0.85)))
                // 3. Bubbles, only when full.
                if level >= 1 {
                    inside.fill(Path(ellipseIn: CGRect(x: 8 * u, y: 12 * u, width: 1.6 * u, height: 1.6 * u)),
                                with: .color(.white.opacity(0.30)))
                    inside.fill(Path(ellipseIn: CGRect(x: 12.4 * u, y: 16 * u, width: 1.2 * u, height: 1.2 * u)),
                                with: .color(.white.opacity(0.22)))
                }
            }
            // 4. The specular pass: what gives the jar depth.
            context.fill(body, with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.42), location: 0),
                    .init(color: .white.opacity(0), location: 0.35),
                    .init(color: .white.opacity(0), location: 0.85),
                    .init(color: .white.opacity(0.16), location: 1),
                ]),
                startPoint: CGPoint(x: 4.6 * u, y: 0), endPoint: CGPoint(x: 17.4 * u, y: 0)))
            // 5. The outline.
            context.stroke(body, with: .color(paint.base.opacity(0.6)), lineWidth: max(1, 1.15 * u))
            // 6. The lid and its highlight.
            context.fill(Path(roundedRect: CGRect(x: 5.4 * u, y: 1.5 * u, width: 11.2 * u, height: 3.6 * u),
                              cornerRadius: 1.3 * u),
                         with: .color(paint.base.opacity(0.8)))
            context.fill(Path(roundedRect: CGRect(x: 6.4 * u, y: 2.1 * u, width: 4 * u, height: 0.9 * u),
                              cornerRadius: 0.45 * u),
                         with: .color(.white.opacity(0.28)))
        }
        .frame(width: size, height: size * 26 / 22)
        .accessibilityHidden(true)
    }
}
