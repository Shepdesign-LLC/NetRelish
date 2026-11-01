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

/// ⌘⇧1–4 and the Shelf: four smart jars, each a query, none a place to put things.
@Suite("Smart jars") @MainActor struct SmartJarTests {

    private func bench() throws -> Workbench {
        let bench = Workbench(store: try PantryStore())
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 1)
        return bench
    }

    @Test("Smart jar ids round-trip, in shelf order, ⌘⇧1–4")
    func ids() {
        #expect(SmartJar.allCases.map(\.name) == ["Brine", "Today", "Sealed", "Sinking soon"])
        #expect(SmartJar.allCases.map(\.number) == [1, 2, 3, 4])
        for smart in SmartJar.allCases { #expect(SmartJar(id: smart.id) == smart) }
        #expect(SmartJar(id: "smart:nope") == nil)
        #expect(SmartJar(id: "read-later") == nil)
        #expect(SmartJar.brineId == "smart:brine")   // the id Brine always had
    }

    @Test("Showing a smart jar hides the jar's tabs from commands, and ⌘T opens a tab in the Shelf's first jar")
    func showingASmartJar() throws {
        let bench = try bench()
        _ = try #require(bench.newTab(url: "https://example.com"))
        bench.activate(.sealed)
        #expect(bench.activeSmartJar == .sealed)
        #expect(bench.activeJar == nil)
        #expect(bench.benchTab == nil)
        #expect(bench.tabs.isEmpty)

        // The same rule ⌘T always had from Brine. A fresh Pantry's first jar is the seeded Read Later.
        let tab = try #require(bench.newTab())
        #expect(tab.jarId == bench.jars.first?.id)
        #expect(bench.activeJar?.id == tab.jarId)
        #expect(bench.activeSmartJar == nil)
    }

    @Test("Today and Sealed fill themselves as you capture and seal")
    func fillThemselves() async throws {
        let bench = try bench()
        _ = bench.newTab(url: "https://example.com/terms")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com/terms"), title: "Terms")
        bench.captureActivePage()
        #expect(bench.today.map(\.title) == ["Terms"])
        #expect(bench.count(of: .sealed) == 0)

        bench.sealProvider = { _ in (Data("WEBARCHIVE".utf8), Extraction.Result(title: "Terms", excerpt: "", body: "Net thirty.")) }
        await bench.sealActiveTab()
        #expect(bench.sealedItems.map(\.title) == ["Terms"])
        #expect(bench.count(of: .today) == 2)          // the capture and the seal
    }

    @Test("A fading tab shows in Sinking soon, and opening it starts its shelf life over")
    func sinkingSoon() throws {
        let bench = try bench()
        let jarId = try #require(bench.activeJar?.id)
        let tab = try #require(bench.newTab(url: "https://example.com/old"))
        try bench.store.write { db in
            var old = try #require(try Tab.fetchOne(db, key: tab.id))
            old.touchedAt = Date().addingTimeInterval(-86_400 * 0.95)
            try old.update(db)
        }
        _ = bench.newTab(url: "https://example.com/new")   // so the old one isn't active
        bench.activate(.sinking)
        #expect(bench.sinkingSoon.map(\.id) == [tab.id])
        #expect(bench.count(of: .sinking) == 1)

        bench.open(try #require(bench.sinkingSoon.first))
        #expect(bench.activeJar?.id == jarId)
        #expect(bench.activeTabId == tab.id)
        #expect(bench.sinkingSoon.isEmpty)
    }

    @Test("⌘K lists all four smart jars with their shortcuts")
    func palette() throws {
        let bench = try bench()
        let rows = PaletteSource.jars(bench)
        for smart in SmartJar.allCases {
            let row = try #require(rows.first { $0.title == smart.name })
            #expect(row.shortcut == "⌘⇧\(smart.number)")
        }
    }

    @Test("Open on a captured item from Today opens it in a tab, even with a smart jar showing")
    func openFromToday() throws {
        let bench = try bench()
        let captured = try bench.store.write { db in try bench.store.root(db).capture(db, url: "https://example.com/brief") }
        bench.activate(.today)
        bench.open(captured)
        #expect(bench.activeSmartJar == nil)
        #expect(bench.activeTab?.url == "https://example.com/brief")
        #expect(bench.activeTab?.jarId == bench.jars.first?.id)
    }

    @Test("Showing a smart jar or switching jars keeps pages live; closing or sinking a tab lets go")
    func webViewsOnlyGoWithTheirTab() throws {
        let bench = try bench()
        let meridian = try #require(bench.activeJar)
        var gone: [String] = []
        bench.onTabsGone = { gone += $0 }
        let a = try #require(bench.newTab(url: "https://example.com/a"))
        let b = try #require(bench.newTab(url: "https://example.com/b"))

        bench.activate(.sealed)
        bench.activate(meridian)
        #expect(gone.isEmpty)

        bench.closeTab(b)
        #expect(gone == [b.id])

        bench.activate(.brine)                  // so a isn't the active tab, which never sinks
        try bench.store.write { db in           // after the switch, which touches the tab it leaves
            var old = try #require(try Tab.fetchOne(db, key: a.id))
            old.touchedAt = Date().addingTimeInterval(-86_400 * 30)
            try old.update(db)
        }
        bench.sweep()
        #expect(gone.contains(a.id))
    }
}
