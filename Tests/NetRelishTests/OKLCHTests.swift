import SwiftUI
import Testing
@testable import NetRelish

@Suite("OKLCH") struct OKLCHTests {
    @Test("Parses both percent and unit lightness, and formats back")
    func parse() {
        #expect(OKLCH("oklch(70% 0.15 140)") == OKLCH(l: 0.7, c: 0.15, h: 140))
        #expect(OKLCH("oklch(0.7 0.15 140)") == OKLCH(l: 0.7, c: 0.15, h: 140))
        #expect(OKLCH("oklch(70% 0.15 140)")?.css == "oklch(70.0% 0.150 140.0)")
        #expect(OKLCH("rgb(1 2 3)") == nil)
    }

    @Test("Relish-500 round-trips through Color and back within rounding")
    @MainActor func roundTrip() {
        let relish = OKLCH("oklch(83.4% 0.224 130.9)")!
        let back = OKLCH(relish.color)
        #expect(abs(back.l - relish.l) < 0.01)
        #expect(abs(back.h - relish.h) < 2)
    }
}
