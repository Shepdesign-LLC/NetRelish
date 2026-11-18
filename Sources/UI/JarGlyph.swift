// JarGlyph.swift — the jar, drawn (manifest v2.1 §7, ADR 0035). The line art of the beta
// art: a dark outline, a separate neck, a lid (ink while the jar is active, grey while it
// idles), and a flat fill in the jar's own color with a meniscus line and one highlight. No
// gradients. A jar's fill level is data, so the jar is drawn live and never an image, and it
// is built from Shapes so the level animates and the token colors resolve per appearance.
// Hand-written. The jar's color is the user's data (ADR 0005); the paint only shades it.

import AppKit
import SwiftUI

/// A jar's color, and the shades drawn from it: the face, the darker base the fill runs
/// down to, the ink that reads on the face, and the three steps the chrome uses for it
/// (`wash100`, `edge300`, `text700`).
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

// MARK: - The jar's own steps (manifest v2.1 jar-color list)

public extension JarPaint {
    /// The paint is relish: the color a jar has until it's given one, or the Relish preset.
    /// A Relish jar is pinned to the relish tokens, so its tile is exactly relish-100/300.
    var isRelish: Bool {
        let r = JarPaint.relish.oklch
        return abs(oklch.l - r.l) < 0.002 && abs(oklch.c - r.c) < 0.002 && abs(oklch.h - r.h) < 0.5
    }

    /// The active Shelf tile's wash. Light: L .964; dark: L .295. Relish is `relish100`.
    var wash100: Color {
        if isRelish { return NRColor.relish100 }
        let o = oklch
        return JarPaint.adaptive(light: OKLCH(l: 0.964, c: min(o.c, 0.03), h: o.h),
                                dark: OKLCH(l: 0.295, c: min(o.c, 0.06), h: o.h))
    }

    /// The 1pt edge of the active tile and of the tile's count badge. Light: L .86; dark:
    /// L .535. Relish is `relish300` in light and `relish700` in dark.
    var edge300: Color {
        if isRelish {
            return Color(nsColor: NSColor(name: nil) { appearance in
                NSColor(JarPaint.isDark(appearance) ? NRColor.relish700 : NRColor.relish300)
            })
        }
        let o = oklch
        return JarPaint.adaptive(light: OKLCH(l: 0.86, c: min(o.c, 0.075), h: o.h),
                                dark: OKLCH(l: 0.535, c: min(o.c, 0.13), h: o.h))
    }

    /// The jar's color as text on a light ground. Light: L .52; dark: the face itself.
    /// Relish is `relish700`.
    var text700: Color {
        if isRelish { return NRColor.relish700 }
        let o = oklch
        return JarPaint.adaptive(light: OKLCH(l: 0.52, c: min(o.c, 0.17), h: o.h), dark: o)
    }

    /// A Display P3 color that resolves against the drawing appearance, as Tokens.swift's
    /// `nr_dynamic` does: light for Aqua, dark for Dark Aqua.
    private static func adaptive(light: OKLCH, dark: OKLCH) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let p = (JarPaint.isDark(appearance) ? dark : light).p3
            return NSColor(displayP3Red: p.r, green: p.g, blue: p.b, alpha: 1)
        })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - The jar's parts, in its 33 × 47 box (x −0.5…32.5, y 0…47)

/// Maps the jar's own units into a rect: x from −0.5, y from 0.
private func jarTransform(_ rect: CGRect) -> CGAffineTransform {
    let sx = rect.width / 33, sy = rect.height / 47
    return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: rect.minX + 0.5 * sx, ty: rect.minY)
}

/// A rounded rect given in the jar's units.
private func jarRect(_ r: CGRect, radius: CGFloat, in rect: CGRect) -> Path {
    Path(roundedRect: r, cornerRadius: radius, style: .circular).applying(jarTransform(rect))
}

/// The jar's body: shoulders of radius 5, a base of radius 7.
public struct JarBodyShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 1, y: 30))
        p.addArc(tangent1End: CGPoint(x: 1, y: 12.5), tangent2End: CGPoint(x: 31, y: 12.5), radius: 5)
        p.addArc(tangent1End: CGPoint(x: 31, y: 12.5), tangent2End: CGPoint(x: 31, y: 45.5), radius: 5)
        p.addArc(tangent1End: CGPoint(x: 31, y: 45.5), tangent2End: CGPoint(x: 1, y: 45.5), radius: 7)
        p.addArc(tangent1End: CGPoint(x: 1, y: 45.5), tangent2End: CGPoint(x: 1, y: 12.5), radius: 7)
        p.closeSubpath()
        return p.applying(jarTransform(rect))
    }
}

/// The neck between the lid and the shoulders.
public struct JarNeckShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        jarRect(CGRect(x: 8, y: 7.5, width: 16, height: 5.5), radius: 1, in: rect)
    }
}

/// The lid.
public struct JarLidShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        jarRect(CGRect(x: 5.5, y: 1.5, width: 21, height: 6.5), radius: 2, in: rect)
    }
}

/// What's in the jar: from its surface (y 45.5 empty, 15.5 full) down past the base. Draw
/// it clipped to `JarBodyShape`. With `band`, only that many units under the surface: the
/// meniscus. The level animates.
public struct JarLiquidShape: Shape {
    public var level: Double
    public var band: Double?

    public init(level: Double, band: Double? = nil) {
        self.level = level
        self.band = band
    }

    public var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    /// The surface's y in the jar's units.
    public static func surface(_ level: Double) -> Double { 45.5 - level * 30 }

    public func path(in rect: CGRect) -> Path {
        let top = Self.surface(level)
        let bottom = band.map { top + $0 } ?? 47
        guard bottom > top else { return Path() }
        return Path(CGRect(x: -0.5, y: top, width: 33, height: bottom - top)).applying(jarTransform(rect))
    }
}

// MARK: - The jar, drawn

/// A jar drawn `size` points tall (and `size` × 33 / 47 wide), filled to `fill` (0…1) in
/// its own color. `isActive` picks the lid: ink when the jar is the one on the Bench, grey
/// when it idles. `dropProgress` (0…1) is the jar-fill drip's drop on its way down; nil
/// draws no drop.
public struct NRFilledJar: View {
    public var paint: JarPaint
    public var fill: Double
    public var size: CGFloat
    public var isActive: Bool
    public var dropProgress: Double?

    public init(paint: JarPaint, fill: Double, size: CGFloat = 24, isActive: Bool = true, dropProgress: Double? = nil) {
        self.paint = paint
        // The jar-fill drip overshoots on easeJar while it animates; a resting fill is 0…1.
        self.fill = max(0, min(1, fill))
        self.size = size
        self.isActive = isActive
        self.dropProgress = dropProgress.map { max(0, min(1, $0)) }
    }

    /// The outline's width on screen: heavier on the big jars, so every size reads as one line.
    private var lineWidth: CGFloat { size >= 40 ? 1.35 : size >= 24 ? 1.2 : 1.05 }

    public var body: some View {
        let u = size / 47
        let width = size * 33 / 47
        let menisc = OKLCH(l: paint.oklch.l * 0.86, c: paint.oklch.c, h: paint.oklch.h).color
        ZStack {
            // 1. The neck, behind the shoulders.
            JarNeckShape().fill(NRColor.float)
            JarNeckShape().stroke(NRColor.jarLine, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            // 2. The glass.
            JarBodyShape().fill(NRColor.float)
            // 3. Inside the body: the highlight, the fill and its meniscus, bubbles, the drop.
            ZStack {
                Path(roundedRect: CGRect(x: 5.5 * u, y: 16.5 * u, width: 1.8 * u, height: 25 * u),
                     cornerRadius: 0.9 * u, style: .circular)
                    .fill(NRColor.hairline)
                JarLiquidShape(level: fill).fill(paint.face)
                JarLiquidShape(level: fill, band: 1.9).fill(menisc)
                if fill >= 1 {
                    Circle().fill(Color.white.opacity(0.32))
                        .frame(width: 3.4 * u, height: 3.4 * u)
                        .position(x: 22 * u, y: 24.5 * u)
                    Circle().fill(Color.white.opacity(0.24))
                        .frame(width: 2.3 * u, height: 2.3 * u)
                        .position(x: 13.5 * u, y: 32.5 * u)
                }
                if let p = dropProgress {
                    // Born under the neck, it falls to the surface on gravity, stretching.
                    let travel = max(0, JarLiquidShape.surface(fill) - 17.5)
                    Ellipse().fill(paint.face)
                        .frame(width: 4 * u, height: 5.6 * u)
                        .scaleEffect(x: 1, y: 0.7 + 0.45 * p)
                        .opacity(0.95 - 0.05 * p)
                        .position(x: 16.5 * u, y: (15 + travel * p) * u)
                }
            }
            .frame(width: width, height: size)
            .clipShape(JarBodyShape())
            // 4. The outline.
            JarBodyShape().stroke(NRColor.jarLine, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            // 5. The lid: ink on the active jar, grey on an idle one.
            JarLidShape().fill(isActive ? NRColor.jarLine : NRColor.jarLid)
            JarLidShape().stroke(NRColor.jarLine, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
        .frame(width: width, height: size)
        .accessibilityHidden(true)
    }
}
