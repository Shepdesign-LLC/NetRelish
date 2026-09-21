// OKLCH.swift — runtime OKLCH ↔ Color, for values that are user data rather than tokens
// (a jar's tint). Tokens are converted at generation time by scripts/gen-tokens.swift
// with the same maths; this is the in-app counterpart.

import AppKit
import SwiftUI

public struct OKLCH: Equatable, Sendable {
    /// Lightness 0…1, chroma ≥ 0, hue in degrees.
    public var l: Double, c: Double, h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l; self.c = c; self.h = h
    }

    /// Parses `oklch(70% 0.15 140)` or `oklch(0.7 0.15 140)`. Nil if malformed.
    public init?(_ css: String) {
        let s = css.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("oklch("), s.hasSuffix(")") else { return nil }
        let parts = s.dropFirst(6).dropLast().split(separator: " ").map(String.init)
        guard parts.count == 3, let c = Double(parts[1]), let h = Double(parts[2]) else { return nil }
        let l: Double
        if parts[0].hasSuffix("%"), let p = Double(parts[0].dropLast()) { l = p / 100 } else if let v = Double(parts[0]) { l = v } else { return nil }
        self.init(l: l, c: c, h: h)
    }

    /// The CSS form, as the Jar model stores it.
    public var css: String {
        String(format: "oklch(%.1f%% %.3f %.1f)", l * 100, c, h)
    }

    /// Display P3 components, gamma-encoded and clamped.
    public var p3: (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180
        let a = c * cos(hr), b = c * sin(hr)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bl = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        let X = 0.4123907993 * r + 0.3575843394 * g + 0.1804807884 * bl
        let Y = 0.2126390059 * r + 0.7151686788 * g + 0.0721923154 * bl
        let Z = 0.0193308187 * r + 0.1191947798 * g + 0.9505321522 * bl
        func gam(_ v: Double) -> Double { let v = min(1, max(0, v)); return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        return (gam(2.4934969119 * X - 0.9313836179 * Y - 0.4027107845 * Z),
                gam(-0.8294889696 * X + 1.7626640603 * Y + 0.0236246858 * Z),
                gam(0.0358458302 * X - 0.0761723893 * Y + 0.9568845240 * Z))
    }

    public var color: Color {
        let p = p3
        return Color(nsColor: NSColor(displayP3Red: p.r, green: p.g, blue: p.b, alpha: 1))
    }

    /// From any Color, via sRGB.
    public init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(ns.redComponent), g = lin(ns.greenComponent), b = lin(ns.blueComponent)
        let l_ = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s_ = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        var hue = atan2(B, A) * 180 / .pi
        if hue < 0 { hue += 360 }
        let chroma = (A * A + B * B).squareRoot()
        self.init(l: L, c: chroma < 0.0005 ? 0 : chroma, h: chroma < 0.0005 ? 0 : hue)
    }
}
