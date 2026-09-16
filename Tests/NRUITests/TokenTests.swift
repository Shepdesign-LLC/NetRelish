import AppKit
import SwiftUI
import Testing
@testable import NRUI

/// Resolves a token Color under a given appearance and returns 0–255 sRGB components.
@MainActor
private func srgb(_ color: Color, dark: Bool) -> (Int, Int, Int) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    var out = (0, 0, 0)
    appearance.performAsCurrentDrawingAppearance {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        out = (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
    return out
}

private func hex(_ h: String) -> (Int, Int, Int) {
    let v = Int(h.dropFirst(), radix: 16)!
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
}

private func close(_ a: (Int, Int, Int), _ b: (Int, Int, Int), tol: Int) -> Bool {
    abs(a.0 - b.0) <= tol && abs(a.1 - b.1) <= tol && abs(a.2 - b.2) <= tol
}

@Suite("Tokens") struct TokenTests {

    /// Every colour in tokens.css carries an sRGB hex fallback. The generated Color,
    /// resolved in light and dark, must land on that hex (± rounding). This is the
    /// OKLCH → P3 maths, checked end to end through the real generated file.
    @Test("Every colour token round-trips to its hex fallback, light and dark")
    @MainActor func coloursMatchHexFallbacks() throws {
        let css = try CSSFixture(contentsOf: repoRoot.appendingPathComponent("design/tokens.css"))
        var checked = 0
        for entry in NRTokenCatalog.colors {
            guard let lightHex = css.lightHex[entry.css] else { continue }   // aliases like --nr-focus have no hex
            let light = srgb(entry.color, dark: false)
            #expect(close(light, hex(lightHex), tol: 3), "\(entry.css) light: got \(light), css says \(lightHex)")
            // A token with no dark value keeps its light hex in dark mode.
            let darkHex = css.darkHex[entry.css] ?? (css.dark[entry.css] == nil ? lightHex : nil)
            if let darkHex {
                let dark = srgb(entry.color, dark: true)
                #expect(close(dark, hex(darkHex), tol: 3), "\(entry.css) dark: got \(dark), css says \(darkHex)")
            }
            checked += 1
        }
        #expect(checked >= 15, "expected to check most colour tokens, checked \(checked)")
    }

    @Test("--nr-focus is relish-500, not a copy of it")
    @MainActor func focusIsRelish() {
        #expect(srgb(NRColor.focus, dark: false) == srgb(NRColor.relish500, dark: false))
        #expect(srgb(NRColor.focus, dark: true) == srgb(NRColor.relish500, dark: true))
    }

    @Test("Relish-500 is #93E413, stored in Display P3")
    @MainActor func relishIsTheRelish() {
        // The brand hex named in CLAUDE.md and the manifest; ADR 0001 made the OKLCH agree.
        let ns = NSColor(NRColor.relish500)
        #expect(ns.colorSpace.colorSpaceModel == .rgb)
        #expect(ns.usingColorSpace(.displayP3) != nil)
        #expect(close(srgb(NRColor.relish500, dark: false), hex("#93E413"), tol: 1))
        #expect(close(srgb(NRColor.relish500, dark: true), hex("#93E413"), tol: 1))
    }

    @Test("Every custom property in tokens.css has exactly one static")
    func everyPropertyHasOneStatic() throws {
        let css = try CSSFixture(contentsOf: repoRoot.appendingPathComponent("design/tokens.css"))
        let generated = NRTokenCatalog.allCSSNames
        let expected = Set(css.light.keys)
        #expect(Set(generated) == expected, "missing: \(expected.subtracting(generated)); extra: \(Set(generated).subtracting(expected))")
        #expect(generated.count == Set(generated).count, "a property maps to more than one static")
    }

    @Test("Scalar tokens carry their CSS values")
    func scalars() {
        #expect(NRSpace.sp1 == 4 && NRSpace.sp12 == 48)
        #expect(NRSpace.shelfW == 56 && NRSpace.inspectorW == 320 && NRSpace.tabH == 34 && NRSpace.lipH == 3 && NRSpace.hairline == 1)
        #expect(NRRadius.r1 == 6 && NRRadius.r2 == 10 && NRRadius.r3 == 16 && NRRadius.rJar == 14)
        #expect(NRRadius.superellipseN == 5)
        #expect(NRType.fsXs == 11 && NRType.fs3xl == 40 && NRType.lhBody == 1.5)
        #expect(NRMotion.fast == 0.12 && NRMotion.base == 0.2 && NRMotion.seal == 0.48)
    }
}
