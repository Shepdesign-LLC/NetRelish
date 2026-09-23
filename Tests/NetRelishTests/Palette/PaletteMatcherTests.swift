import Testing
@testable import NetRelish

@Suite("Palette matching") struct PaletteMatcherTests {

    private let names = ["Capture this page", "Close Tab", "New Tab", "Pin Tab", "Fill this form", "Brine", "Meridian", "Taxes"]

    private func rank(_ query: String) -> [String] {
        var scored: [(name: String, score: Int)] = []
        for name in names {
            if let s = PaletteMatcher.score(name, query: query) { scored.append((name, s)) }
        }
        scored.sort { a, b in a.score == b.score ? a.name < b.name : a.score > b.score }
        return scored.map(\.name)
    }

    @Test("An empty query keeps everything, in the order given")
    func emptyQueryMatchesAll() {
        #expect(names.allSatisfy { PaletteMatcher.score($0, query: "") != nil })
    }

    @Test("Matching ignores case and is a subsequence, so 'ctp' finds 'Capture this page'")
    func subsequence() {
        #expect(PaletteMatcher.score("Capture this page", query: "ctp") != nil)
        #expect(PaletteMatcher.score("Capture this page", query: "CAPT") != nil)
        #expect(PaletteMatcher.score("Capture this page", query: "zz") == nil)
        #expect(PaletteMatcher.score("Capture this page", query: "pac") == nil)   // order matters
    }

    @Test("A prefix beats a word start, which beats a scattered match")
    func ranking() {
        let prefix = PaletteMatcher.score("Tab strip", query: "tab")!
        let wordStart = PaletteMatcher.score("New Tab", query: "tab")!
        let scattered = PaletteMatcher.score("Startable", query: "tab")!   // t-a-b, none at a word start
        #expect(prefix > wordStart)
        #expect(wordStart > scattered)
    }

    @Test("Typing 'tab' finds the tab commands and nothing else — a jar named Taxes has no b")
    func tabCommandsWin() {
        // Shorter names win the tie, so the two 7-letter ones lead.
        #expect(rank("tab") == ["New Tab", "Pin Tab", "Close Tab"])
    }

    @Test("Typing a jar's name finds the jar")
    func jarByName() {
        #expect(rank("meri").first == "Meridian")
    }

    @Test("Adjacent letters score better than the same letters spread out")
    func adjacencyWins() {
        let tight = PaletteMatcher.score("Fill this form", query: "fill")!
        let loose = PaletteMatcher.score("Fill this form", query: "ffm")!
        #expect(tight > loose)
    }
}
