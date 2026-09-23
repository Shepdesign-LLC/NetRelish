import Foundation
import Pantry
import Testing
@testable import NetRelish

/// The rows ⌘K offers, against an in-memory Pantry.
@Suite("Palette rows") @MainActor struct PaletteSourceTests {

    private func workbench() throws -> Workbench {
        let store = try PantryStore()   // in-memory
        let bench = Workbench(store: store)
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        return bench
    }

    @Test("With no tab open, tab commands are not offered")
    func commandsNeedATab() throws {
        let bench = try workbench()
        let titles = PaletteSource.rows(for: "", workbench: bench).map(\.title)
        #expect(!titles.contains("Capture this page"))
        #expect(!titles.contains("Close Tab"))
        #expect(titles.contains("New Tab"))      // a jar exists, so this one is offered
    }

    @Test("Brine is always a row, and every jar is a row")
    func jarsAndBrine() throws {
        let bench = try workbench()
        let titles = PaletteSource.rows(for: "", workbench: bench).map(\.title)
        #expect(titles.contains("Brine"))
        #expect(titles.contains("Meridian"))
    }

    @Test("Opening a tab adds Capture, and capture puts the page in Brine with its real title")
    func captureGoesToBrine() throws {
        let bench = try workbench()
        _ = bench.newTab(url: "https://example.com")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com"), title: "Example Domain")
        #expect(PaletteSource.rows(for: "capture", workbench: bench).first?.title == "Capture this page")

        bench.captureActivePage()
        let brined = bench.searchPantry("Example")
        #expect(brined.count == 1)
        #expect(brined.first?.title == "Example Domain")
        #expect(brined.first?.jarId == nil)          // non-negotiable 2: Brine is a query
        #expect(brined.first?.state == .brined)
        #expect(brined.first?.sealedAt == nil)       // capture is not seal — that's P2
    }

    @Test("A one-letter query searches nothing; two letters reach the Pantry")
    func searchNeedsTwoLetters() throws {
        let bench = try workbench()
        _ = bench.newTab(url: "https://example.com")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com"), title: "Example Domain")
        bench.captureActivePage()
        #expect(PaletteSource.pantryRows(for: "E", workbench: bench).isEmpty)
        #expect(PaletteSource.pantryRows(for: "Exam", workbench: bench).count == 1)
    }

    @Test("A Pantry row says which jar it came from; Brine items say Brine")
    func provenance() throws {
        let bench = try workbench()
        _ = bench.newTab(url: "https://example.com")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com"), title: "Example Domain")
        bench.captureActivePage()
        #expect(PaletteSource.pantryRows(for: "Exam", workbench: bench).first?.subtitle == "Brine")
    }
}
