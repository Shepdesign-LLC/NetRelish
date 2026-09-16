import AppKit
import Testing
@testable import NRUI

@Suite("Symbols") struct SymbolTests {

    @Test("All seven manifest §7 symbols exist, in order")
    func ids() {
        #expect(NRSymbol.allCases.map(\.rawValue) == ["nr-jar", "nr-jar-smart", "nr-jar-pickle", "nr-seal", "nr-lip", "nr-drip", "nr-sink"])
    }

    @Test("Symbols load as template images at their viewBox size")
    @MainActor func symbolsAreTemplates() {
        for s in NRSymbol.allCases {
            let img = s.nsImage
            #expect(img.isTemplate, "\(s.rawValue) must be a template (currentColor)")
            #expect(img.size.width == 24, "\(s.rawValue) width")
            #expect(img.size.height == (s == .lip ? 3 : 24), "\(s.rawValue) height")
        }
    }

    @Test("Logos load full-color, never as templates")
    @MainActor func logosAreNotTemplates() {
        for l in NRLogo.allCases {
            let img = l.nsImage
            #expect(!img.isTemplate, "\(l) must keep its colors")
            #expect(img.size == NSSize(width: 100, height: 100))
        }
    }

    @Test("Embedded logo bytes are the files in /design, untouched")
    func logosMatchFiles() throws {
        let mark = try String(contentsOf: repoRoot.appendingPathComponent("design/logo.svg"), encoding: .utf8)
        let cog = try String(contentsOf: repoRoot.appendingPathComponent("design/logo-cog.svg"), encoding: .utf8)
        #expect(NRLogo.mark.svg == mark)
        #expect(NRLogo.cog.svg == cog)
    }
}
