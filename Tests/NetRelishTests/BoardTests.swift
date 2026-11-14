import Foundation
import GRDB
import Pantry
import Testing
@testable import NetRelish

/// The jar board (ADR 0034): when the Bench shows it, what it counts, and that the page
/// commands stand down while it's up. The views only ask; the Workbench decides.
@Suite("The jar board") @MainActor struct BoardTests {

    private func bench() throws -> Workbench {
        let defaults = try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
        return Workbench(store: try PantryStore(), defaults: defaults)
    }

    private func jar(_ name: String, in bench: Workbench) throws -> Jar {
        try #require(bench.jars.first { $0.name == name })
    }

    @Test("Showing the board keeps the tab open and takes the page out of front")
    func showsTheBoard() throws {
        let bench = try bench()
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://ash.example"))
        #expect(bench.benchTab?.id == tab.id && !bench.showingBoard)

        bench.showBoard()
        #expect(bench.showingBoard)
        #expect(bench.benchTab == nil && bench.pageInFront == nil)   // ⌘S and ⌘D have no page to act on
        #expect(bench.activeTab?.id == tab.id)                       // still open behind the board
        #expect(bench.panelSubject == .jar(try jar("Ash", in: bench)))
    }

    @Test("Picking a tab, or opening a new one, goes back to the page")
    func leavesTheBoard() throws {
        let bench = try bench()
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://ash.example"))

        bench.showBoard()
        bench.activateTab(tab)                 // the tab that was already active
        #expect(!bench.showingBoard && bench.benchTab?.id == tab.id)

        bench.showBoard()
        let second = try #require(bench.newTab(url: "https://ash.example/two"))
        #expect(!bench.showingBoard && bench.benchTab?.id == second.id)
    }

    @Test("Clicking a jar on the Shelf opens its board; switching jars any other way opens its page")
    func boardOfAnotherJar() throws {
        let bench = try bench()
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        bench.newTab(url: "https://ash.example")
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        bench.newTab(url: "https://birch.example")
        let ash = try jar("Ash", in: bench), birch = try jar("Birch", in: bench)

        bench.showBoard(of: ash)
        #expect(bench.activeJarId == ash.id && bench.showingBoard)

        bench.activate(birch)                  // ⌘2, a Shortcut, the palette
        #expect(bench.activeJarId == birch.id && !bench.showingBoard)
        #expect(bench.benchTab != nil)
    }

    @Test("Going to the jar you're already in, by ⌘1–9 or a Shortcut, leaves its board for its page")
    func sameJarLeavesTheBoard() throws {
        let bench = try bench()
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://ash.example"))
        let ash = try jar("Ash", in: bench)

        bench.showBoard()
        bench.activate(ash)
        #expect(!bench.showingBoard && bench.benchTab?.id == tab.id)

        bench.showBoard(of: ash)               // the Shelf, on the same jar, still opens the board
        #expect(bench.showingBoard)
        let index = try #require(bench.jars.firstIndex { $0.id == ash.id })
        bench.activate(index: index)
        #expect(!bench.showingBoard && bench.pageInFront?.id == tab.id)
    }

    @Test("A jar counts its open tabs and what it keeps, and fills toward twelve")
    func countsAndFills() throws {
        let bench = try bench()
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let ash = try jar("Ash", in: bench)
        #expect(bench.count(in: ash) == 0 && bench.fill(of: ash) == 0)

        bench.newTab(url: "https://ash.example")
        try bench.store.write { db in
            var kept = Item(state: .jarred, title: "Kept", url: "https://ash.example/kept", jarId: ash.id)
            try kept.insert(db)
        }
        bench.load()
        #expect(bench.tabCount(in: ash) == 1 && bench.keptCount(in: ash) == 1)
        #expect(bench.count(in: ash) == 2)
        #expect(bench.fill(of: ash) == 2.0 / Double(Workbench.jarHolds))
        #expect(bench.jarItems.map(\.title) == ["Kept"])

        try bench.store.write { db in
            for n in 0..<20 {
                var more = Item(state: .jarred, title: "More \(n)", jarId: ash.id)
                try more.insert(db)
            }
        }
        bench.load()
        #expect(bench.fill(of: ash) == 1)      // full is as full as it's drawn; nothing stops there
    }

    @Test("The board's lines read plainly, in the singular and the plural")
    func lines() {
        #expect(JarBoard.summary(tabs: 1, kept: 0) == "1 tab · 0 kept")
        #expect(JarBoard.summary(tabs: 3, kept: 12) == "3 tabs · 12 kept")
        #expect(JarBoard.fillLine(count: 4, holds: 12) == "4 in this jar")
        #expect(JarBoard.fillLine(count: 12, holds: 12) == "12 in this jar. It's full")
    }

    @Test("A tab's icon is its site's first letter, never the w of www")
    func tabLetters() {
        #expect(TabIcon.letter(for: Pantry.Tab(url: "https://www.juniperbakery.example/menu")) == "J")
        #expect(TabIcon.letter(for: Pantry.Tab(url: "harborsigns.example")) == "H")
        #expect(TabIcon.letter(for: Pantry.Tab(url: nil)) == nil)
    }

    @Test("The ink on a jar's color passes 4.5:1 for any color Edit Jar… allows")
    func inkContrast() {
        for l in stride(from: 0.0, through: 1.0, by: 0.05) {
            for c in [0.0, 0.05, 0.1, 0.15, 0.2, 0.25] {
                for h in stride(from: 0.0, to: 360.0, by: 30) {
                    let paint = JarPaint(OKLCH(l: l, c: c, h: h))
                    #expect(paint.inkContrast >= 4.5, "oklch(\(l) \(c) \(h)) has \(paint.inkContrast):1")
                }
            }
        }
        #expect(JarPaint(OKLCH(l: 0.6, c: 0, h: 0)).inkIsDark)      // mid gray takes black, not white
        #expect(JarPaint.relish.inkIsDark)
        #expect(!JarPaint(OKLCH(l: 0.3, c: 0.1, h: 260)).inkIsDark)
    }

    @Test("A jar with no color of its own is painted relish; a tint is read back as stored")
    func paints() throws {
        #expect(JarPaint(css: nil) == .relish)
        let sky = JarTint.presets[2]
        #expect(JarPaint(css: sky.css).oklch == OKLCH(sky.css))
    }
}
