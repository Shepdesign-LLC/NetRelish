import AppKit
import SwiftUI
import Testing
@testable import NetRelish

/// Resolves a Color under a given appearance and returns 0–255 sRGB components.
@MainActor
private func srgb(_ color: Color, dark: Bool = false) -> (Int, Int, Int) {
    guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return (-1, -1, -1) }
    var out = (-1, -1, -1)
    appearance.performAsCurrentDrawingAppearance {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
        out = (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
               Int((c.blueComponent * 255).rounded()))
    }
    return out
}

private func close(_ a: (Int, Int, Int), _ b: (Int, Int, Int), tol: Int = 1) -> Bool {
    abs(a.0 - b.0) <= tol && abs(a.1 - b.1) <= tol && abs(a.2 - b.2) <= tol
}

/// Relative luminance of 0–255 sRGB components.
private func luminance(_ c: (Int, Int, Int)) -> Double {
    func lin(_ v: Int) -> Double { let s = Double(v) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
}

@Suite("Jar paint") struct JarPaintTests {
    private var sky: JarTint { JarTint.presets[2] }

    @Test("A jar with no color, and the Relish preset, are relish; Sky is not")
    func relishIsRecognized() throws {
        #expect(JarPaint(css: nil).isRelish)
        let relish = try #require(JarTint.presets.first(where: { $0.name == "Relish" }))
        #expect(JarPaint(css: relish.css).isRelish)
        #expect(!JarPaint(css: sky.css).isRelish)
    }

    @Test("A Relish tile is exactly the relish tokens: wash relish-100, edge relish-300 in light")
    @MainActor func relishStepsArePinnedToTokens() {
        let paint = JarPaint.relish
        #expect(close(srgb(paint.wash100), srgb(NRColor.relish100)))
        #expect(close(srgb(paint.edge300), srgb(NRColor.relish300)))
        #expect(close(srgb(paint.edge300, dark: true), srgb(NRColor.relish700)))
        #expect(close(srgb(paint.text700), srgb(NRColor.relish700)))
    }

    @Test("Any other color's wash is lighter than its face in light, and darker in dark")
    @MainActor func washIsAWash() {
        let paint = JarPaint(css: sky.css)
        let face = luminance(srgb(paint.face))
        #expect(luminance(srgb(paint.wash100)) > face)
        #expect(luminance(srgb(paint.wash100, dark: true)) < face)
        #expect(luminance(srgb(paint.edge300)) > face)
    }
}
