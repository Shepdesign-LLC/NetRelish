// Shapes.swift — the superellipse (manifest §6) and the jar silhouette built from it.
// Hand-written; not generated.

import SwiftUI

/// A superellipse: |x/a|ⁿ + |y/b|ⁿ = 1. With `n = NRRadius.superellipseN` (5) this is
/// the squircle behind the mark, the app icon, and jar shoulders. `n = 2` is an ellipse.
/// Not a `border-radius` approximation — the curve is sampled from the equation.
public struct Superellipse: Shape, InsettableShape {
    public var n: Double
    public var inset: CGFloat = 0

    public init(n: Double = NRRadius.superellipseN) {
        self.n = n
    }

    public func inset(by amount: CGFloat) -> Superellipse {
        var copy = self
        copy.inset += amount
        return copy
    }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > 0, r.height > 0 else { return Path() }
        let a = Double(r.width / 2), b = Double(r.height / 2)
        let cx = Double(r.midX), cy = Double(r.midY)
        var path = Path()
        // One quadrant of samples, mirrored into four. 32 per quadrant is visually
        // indistinguishable from the analytic curve at icon-to-window sizes.
        let quadrant = Superellipse.quadrant(n: n)
        func pt(_ sx: Double, _ sy: Double) -> CGPoint { CGPoint(x: cx + sx * a, y: cy + sy * b) }
        path.move(to: pt(1, 0))
        for (x, y) in quadrant.dropFirst() { path.addLine(to: pt(x, y)) }           // right → top
        for (x, y) in quadrant.reversed().dropFirst() { path.addLine(to: pt(-x, y)) }  // top → left
        for (x, y) in quadrant.dropFirst() { path.addLine(to: pt(-x, -y)) }          // left → bottom
        for (x, y) in quadrant.reversed().dropFirst() { path.addLine(to: pt(x, -y)) }  // bottom → right
        path.closeSubpath()
        return path
    }

    /// Unit-quadrant samples from (1, 0) to (0, 1), inclusive.
    static func quadrant(n: Double, samples: Int = 32) -> [(Double, Double)] {
        let e = 2 / n
        return (0...samples).map { i in
            let t = Double(i) / Double(samples) * (.pi / 2)
            return (pow(cos(t), e), pow(sin(t), e))
        }
    }
}

/// The jar body: a superellipse shoulder on each top corner, straight sides, and
/// `NRRadius.rJar`-proportioned round corners at the base. The lid is a separate
/// view element so it can sit on the neck as `#nr-jar` draws it.
///
/// Proportions follow the symbol: on a 24pt glyph the body is 11 wide, the
/// shoulders are 2.5 wide × 3 tall, the base corners are 2.5.
public struct JarShape: Shape {
    public var n: Double
    /// Shoulder size as fractions of the body width (x) and height (y).
    public var shoulderFraction: CGSize
    /// Base corner radius as a fraction of the body width.
    public var baseRadiusFraction: CGFloat

    public init(n: Double = NRRadius.superellipseN,
                shoulderFraction: CGSize = CGSize(width: 2.5 / 11, height: 3 / 13),
                baseRadiusFraction: CGFloat = 2.5 / 11) {
        self.n = n
        self.shoulderFraction = shoulderFraction
        self.baseRadiusFraction = baseRadiusFraction
    }

    /// The shoulder box in points for a given rect (exposed for tests and the Design Kit).
    public func shoulder(for rect: CGRect) -> CGSize {
        CGSize(width: rect.width * shoulderFraction.width, height: rect.height * shoulderFraction.height)
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let sh = shoulder(for: rect)
        let br = min(rect.width * baseRadiusFraction, rect.width / 2, rect.height / 2)
        let q = Superellipse.quadrant(n: n)
        var p = Path()

        // Top-left shoulder: from the left side up and over to the top edge.
        // Superellipse centre is (minX + sw, minY + sh); we trace the (−x, −y) quadrant
        // in view space (y down), i.e. from (minX, minY+sh) to (minX+sw, minY).
        let tlc = CGPoint(x: rect.minX + sh.width, y: rect.minY + sh.height)
        p.move(to: CGPoint(x: rect.minX, y: tlc.y))
        for (x, y) in q.dropFirst() {
            p.addLine(to: CGPoint(x: tlc.x - x * sh.width, y: tlc.y - y * sh.height))
        }

        // Top edge to the right shoulder.
        let trc = CGPoint(x: rect.maxX - sh.width, y: rect.minY + sh.height)
        p.addLine(to: CGPoint(x: trc.x, y: rect.minY))
        for (x, y) in q.reversed().dropFirst() {
            p.addLine(to: CGPoint(x: trc.x + x * sh.width, y: trc.y - y * sh.height))
        }

        // Right side down to the base corner.
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The shoulder hairline of `#nr-jar`: just the two superellipse curves and the neck,
/// for drawing a stroke over `JarShape`'s fill the way the symbol does.
public struct JarShoulderLine: Shape {
    public var n: Double
    public var shoulderFraction: CGSize

    public init(n: Double = NRRadius.superellipseN, shoulderFraction: CGSize = CGSize(width: 2.5 / 11, height: 3 / 13)) {
        self.n = n
        self.shoulderFraction = shoulderFraction
    }

    public func path(in rect: CGRect) -> Path {
        let sh = CGSize(width: rect.width * shoulderFraction.width, height: rect.height * shoulderFraction.height)
        let q = Superellipse.quadrant(n: n)
        var p = Path()
        let tlc = CGPoint(x: rect.minX + sh.width, y: rect.minY + sh.height)
        p.move(to: CGPoint(x: rect.minX, y: tlc.y))
        for (x, y) in q.dropFirst() { p.addLine(to: CGPoint(x: tlc.x - x * sh.width, y: tlc.y - y * sh.height)) }
        let trc = CGPoint(x: rect.maxX - sh.width, y: rect.minY + sh.height)
        p.addLine(to: CGPoint(x: trc.x, y: rect.minY))
        for (x, y) in q.reversed().dropFirst() { p.addLine(to: CGPoint(x: trc.x + x * sh.width, y: trc.y - y * sh.height)) }
        return p
    }
}
