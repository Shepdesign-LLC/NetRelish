import AppKit
import Foundation
import GRDB
import Pantry
import Testing
@testable import NetRelish

/// Right-click and drag: jars move along the Shelf, tabs move within the strip and between
/// jars, a Brine row is restored into the jar it is dropped on, and a tab keeps the icon it
/// was given. The views only call these; what moves, and what stays behind, is decided here.
@Suite("Rearranging") @MainActor struct RearrangeTests {

    /// A Workbench on a throwaway Pantry, with its own UserDefaults so tab icons never leak
    /// between tests.
    private func bench(store: PantryStore? = nil, defaults: UserDefaults? = nil) throws -> Workbench {
        Workbench(store: try store ?? PantryStore(), defaults: try defaults ?? scratchDefaults())
    }

    private func scratchDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
    }

    private func jar(_ name: String, in bench: Workbench) throws -> Jar {
        try #require(bench.jars.first { $0.name == name })
    }

    /// The jars these tests made, in Shelf order, by name. A fresh Pantry may hold others.
    private func mine(_ bench: Workbench) -> [String] {
        bench.jars.map(\.name).filter { ["Ash", "Birch", "Cedar"].contains($0) }
    }

    private func threeJars() throws -> Workbench {
        let bench = try bench()
        for name in ["Ash", "Birch", "Cedar"] { bench.newJar(name: name, tint: nil, shelfLifeDays: 3) }
        return bench
    }

    private func stored(_ tab: Pantry.Tab, in bench: Workbench) throws -> Pantry.Tab {
        try #require(try bench.store.read { db in try Pantry.Tab.fetchOne(db, key: tab.id) })
    }

    // MARK: What a drag carries

    @Test("A drag's payload reads back, and anything else dragged in is left alone")
    func payloads() {
        #expect(DragPayload(DragPayload.tab("T1").string) == .tab("T1"))
        #expect(DragPayload(DragPayload.brine("I1").string) == .brine("I1"))
        #expect(DragPayload("https://example.com/") == nil)
        #expect(DragPayload("netrelish-drag:jar:J1") == nil)
        #expect(DragPayload("netrelish-drag:tab:") == nil)
        #expect(DragPayload("") == nil)
    }

    // MARK: Jars along the Shelf

    @Test("A jar moved along the Shelf keeps its new place after a relaunch")
    func movesAJar() throws {
        let store = try PantryStore()
        let bench = try bench(store: store)
        for name in ["Ash", "Birch", "Cedar"] { bench.newJar(name: name, tint: nil, shelfLifeDays: 3) }
        let ash = try #require(bench.jars.firstIndex { $0.name == "Ash" })

        bench.moveJar(try jar("Cedar", in: bench).id, to: ash)
        #expect(mine(bench) == ["Cedar", "Ash", "Birch"])

        let relaunched = try self.bench(store: store)
        #expect(mine(relaunched) == ["Cedar", "Ash", "Birch"])
    }

    @Test("A jar can't be moved past either end of the Shelf")
    func staysOnTheShelf() throws {
        let bench = try threeJars()
        let before = bench.jars.map(\.id)

        bench.moveJar(before[0], to: -4)
        #expect(bench.jars.map(\.id) == before)

        bench.moveJar(before[0], to: 99)
        #expect(bench.jars.last?.id == before[0])
        #expect(bench.jars.count == before.count)
    }

    @Test("Move Up and Move Down go one place, and do nothing at the ends")
    func movesByOne() throws {
        let bench = try threeJars()

        bench.moveJar(try jar("Cedar", in: bench), by: -1)
        #expect(mine(bench) == ["Ash", "Cedar", "Birch"])

        bench.moveJar(try jar("Cedar", in: bench), by: 1)
        #expect(mine(bench) == ["Ash", "Birch", "Cedar"])

        let last = try #require(bench.jars.last)
        let order = bench.jars.map(\.id)
        bench.moveJar(last, by: 1)
        #expect(bench.jars.map(\.id) == order)
    }

    @Test("Moving a jar doesn't change which jar is showing")
    func keepsTheActiveJar() throws {
        let bench = try threeJars()
        let showing = bench.activeJarId
        bench.moveJar(try jar("Ash", in: bench), by: 1)
        #expect(bench.activeJarId == showing)
    }

    @Test("A color picked from a jar's menu is saved on the jar")
    func tintsAJar() throws {
        let bench = try threeJars()
        let css = JarTint.presets[2].css

        let birch = try jar("Birch", in: bench)
        bench.setTint(css, of: birch)

        let shown = try jar("Birch", in: bench)
        #expect(shown.tint == css)
        let saved = try bench.store.read { db in try Jar.fetchOne(db, key: birch.id) }
        #expect(saved?.tint == css)
        #expect(OKLCH(css) != nil)   // the menu's colors parse the way a jar's tint is read
    }

    // MARK: Tabs in the strip

    @Test("A tab dropped on another takes its place in the strip")
    func reordersTabs() throws {
        let bench = try bench()
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let a = try #require(bench.newTab(url: "https://a.example/"))
        let b = try #require(bench.newTab(url: "https://b.example/"))
        let c = try #require(bench.newTab(url: "https://c.example/"))

        #expect(bench.drop([DragPayload.tab(c.id).string], onTab: a))
        #expect(bench.tabs.map(\.id) == [c.id, a.id, b.id])

        #expect(bench.drop([DragPayload.tab(c.id).string], onTab: b))
        #expect(bench.tabs.map(\.id) == [a.id, b.id, c.id])

        #expect(!bench.drop([DragPayload.tab(a.id).string], onTab: a))   // onto itself: nothing to do
        #expect(!bench.drop(["https://example.com/"], onTab: a))          // not ours
        #expect(bench.tabs.map(\.id) == [a.id, b.id, c.id])
    }

    @Test("Close Other Tabs keeps this tab and the pinned ones")
    func closesTheOthers() throws {
        let bench = try bench()
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let a = try #require(bench.newTab(url: "https://a.example/"))
        _ = try #require(bench.newTab(url: "https://b.example/"))
        let c = try #require(bench.newTab(url: "https://c.example/"))
        bench.togglePin(a)

        bench.closeOtherTabs(c)

        #expect(bench.tabs.map(\.id) == [a.id, c.id])
        #expect(bench.activeTabId == c.id)
    }

    // MARK: Tabs between jars

    @Test("A tab moved to another jar leaves this strip, lands last in that one, and starts clean there")
    func movesATabToAnotherJar() throws {
        let bench = try bench()
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        let waiting = try #require(bench.newTab(url: "https://waiting.example/"))
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)        // Ash is showing
        let a = try #require(bench.newTab(url: "https://a.example/", interactionState: Data("SIGNED-IN".utf8)))
        let b = try #require(bench.newTab(url: "https://b.example/"))
        bench.activateTab(a)
        var gone: [String] = []
        bench.onTabsGone = { gone += $0 }
        let birch = try jar("Birch", in: bench)

        #expect(bench.drop([DragPayload.tab(a.id).string], onJar: birch))

        #expect(bench.tabs.map(\.id) == [b.id])
        #expect(bench.activeTabId == b.id)
        #expect(gone == [a.id])                       // the Bench lets go of the page on Ash's store
        let moved = try stored(a, in: bench)
        #expect(moved.jarId == birch.id)
        #expect(moved.url == "https://a.example/")
        #expect(moved.interactionState == nil)        // nothing made with Ash's sign-ins crosses over

        bench.activate(birch)
        #expect(bench.tabs.map(\.id) == [waiting.id, a.id])
    }

    @Test("A tab that changed jars gets a new web view on the new jar's store, in every window")
    func aMovedTabNeverKeepsItsOldPage() throws {
        let bench = try bench()
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://a.example/"))
        let birch = try jar("Birch", in: bench)
        // Two windows share one Workbench and each keeps its own web views. Only the window
        // wired last hears that a tab is gone, so the other must work it out for itself.
        let otherWindow = BenchWebViews()
        let before = otherWindow.view(for: tab)
        #expect(before.jarId == tab.jarId)

        bench.moveTab(tab, toJar: birch.id)

        let moved = try stored(tab, in: bench)
        let after = otherWindow.view(for: moved)
        #expect(after !== before)
        #expect(after.jarId == birch.id)
        #expect(otherWindow.view(for: moved) === after)      // and it keeps the new one
    }

    @Test("A page still open on the jar a tab left can't write its address onto the tab")
    func aPageLeftBehindCannotRenameTheTab() throws {
        let bench = try bench()
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://a.example/"))
        let kept = try #require(bench.newTab(url: "https://kept.example/"))
        let ash = try jar("Ash", in: bench)
        let birch = try jar("Birch", in: bench)
        let otherWindow = BenchWebViews()
        _ = otherWindow.view(for: tab)
        let keptView = otherWindow.view(for: kept)

        bench.moveTab(tab, toJar: birch.id)
        bench.activate(birch)

        // The old page, still on Ash's store in the other window, navigates.
        bench.tabDidNavigate(tab.id, fromJar: ash.id, url: URL(string: "https://a.example/account"), title: "Account")
        let untouched = try stored(tab, in: bench)
        #expect(untouched.url == "https://a.example/")

        // The tab's own page in Birch is believed.
        bench.tabDidNavigate(tab.id, fromJar: birch.id, url: URL(string: "https://a.example/next"), title: "Next")
        let navigated = try stored(tab, in: bench)
        #expect(navigated.url == "https://a.example/next")

        // And the other window lets the old page go, without touching a tab that stayed put.
        otherWindow.forgetMoved(bench.allTabs)
        #expect(otherWindow.existing(for: tab.id) == nil)
        #expect(otherWindow.existing(for: kept.id) === keptView)
    }

    @Test("Reader view started on a tab that then moved jars doesn't show the old jar's article")
    func readerDoesNotFollowAMovedTab() async throws {
        let bench = try bench()
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://a.example/account"))
        let birch = try jar("Birch", in: bench)
        bench.readerProvider = { reading in
            bench.moveTab(reading, toJar: birch.id)      // moved while the article is being read,
            bench.activate(birch)                        // and it is the tab showing in its new jar
            return Extraction.Article(title: "Account", byline: "", site: "a.example",
                                      html: "<p>Signed in as someone.</p>", wordCount: 120)
        }

        await bench.toggleReader()

        #expect(bench.activeTab?.id == tab.id)           // the same tab is in front, now in Birch
        #expect(bench.activeTab?.jarId == birch.id)
        #expect(bench.reader == nil)                     // and Ash's article is not laid over it
    }

    @Test("A Seal that finishes after its tab moved to another jar leaves the tab where it was put")
    func aSealDoesNotCloseAMovedTab() async throws {
        let bench = try bench()
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://a.example/"))
        let ash = try jar("Ash", in: bench)
        let birch = try jar("Birch", in: bench)
        bench.sealProvider = { sealing in
            bench.moveTab(sealing, toJar: birch.id)      // moved while the page is being frozen
            return (Data("WEBARCHIVE".utf8), Extraction.Result(title: "A page", excerpt: "", body: "A page."))
        }

        let sealed = await bench.sealActiveTab()

        #expect(sealed)
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.jarId == ash.id)                    // the page was sealed where Seal was asked
        let moved = try stored(tab, in: bench)           // and the tab is still open,
        #expect(moved.jarId == birch.id)                 // in the jar it was moved to
    }

    @Test("A new tab opens after the last one, even when tabs have left the strip")
    func newTabsGoLast() throws {
        let bench = try bench()
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let a = try #require(bench.newTab(url: "https://a.example/"))
        let b = try #require(bench.newTab(url: "https://b.example/"))
        let c = try #require(bench.newTab(url: "https://c.example/"))
        let d = try #require(bench.newTab(url: "https://d.example/"))
        let birch = try jar("Birch", in: bench)

        bench.moveTab(a, toJar: birch.id)
        bench.moveTab(b, toJar: birch.id)
        let e = try #require(bench.newTab(url: "https://e.example/"))

        #expect(bench.tabs.map(\.id) == [c.id, d.id, e.id])
    }

    @Test("Dropping a tab on its own jar, or something that isn't ours on any jar, does nothing")
    func ignoresDropsThatAreNotMoves() throws {
        let bench = try bench()
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let a = try #require(bench.newTab(url: "https://a.example/"))

        let ash = try jar("Ash", in: bench)
        let birch = try jar("Birch", in: bench)

        #expect(!bench.drop([DragPayload.tab(a.id).string], onJar: ash))
        #expect(!bench.drop(["https://example.com/", "netrelish-drag:tab:no-such-tab"], onJar: birch))
        #expect(bench.tabs.map(\.id) == [a.id])
    }

    // MARK: Brine onto a jar

    @Test("A Brine row dropped on a jar reopens there; its history only comes back to the jar it sank from")
    func restoresIntoAJar() throws {
        let bench = try bench()
        bench.newJar(name: "Birch", tint: nil, shelfLifeDays: 3)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        var sinking = try #require(bench.newTab(url: "https://sunk.example/", interactionState: Data("HISTORY".utf8)))
        _ = try bench.store.write { db in try sinking.sink(db) }
        bench.load()
        let item = try #require(bench.brine.first { $0.url == "https://sunk.example/" })
        let birch = try jar("Birch", in: bench)

        #expect(bench.drop([DragPayload.brine(item.id).string], onJar: birch))
        #expect(bench.activeJarId == birch.id)
        #expect(bench.activeTab?.url == "https://sunk.example/")
        #expect(bench.activeTab?.interactionState == nil)

        bench.restore(item)                                   // the row's own button: back where it sank from
        let ash = try jar("Ash", in: bench)
        #expect(bench.activeJarId == ash.id)
        #expect(bench.activeTab?.interactionState == Data("HISTORY".utf8))
    }

    // MARK: Tab icons

    @Test("A tab keeps the icon it was given across a relaunch, and loses it when it closes")
    func tabIcons() throws {
        let store = try PantryStore()
        let defaults = try scratchDefaults()
        let bench = try bench(store: store, defaults: defaults)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://a.example/"))
        #expect(bench.glyph(of: tab) == nil)

        bench.setGlyph("key", for: tab)
        #expect(bench.glyph(of: tab) == "key")
        let relaunched = try self.bench(store: store, defaults: defaults)
        #expect(relaunched.glyph(of: tab) == "key")

        bench.setGlyph(nil, for: tab)
        #expect(bench.glyph(of: tab) == nil)

        bench.setGlyph("envelope", for: tab)
        bench.closeTab(tab)
        #expect(bench.glyph(of: tab) == nil)
        let afterClosing = try self.bench(store: store, defaults: defaults)
        #expect(afterClosing.tabGlyphs.isEmpty)
    }

    @Test("Every icon a tab's menu offers is a real system symbol")
    func iconsExist() {
        for choice in TabGlyph.choices {
            #expect(NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil) != nil, "\(choice.symbol)")
        }
        #expect(TabGlyph.choices.first?.symbol == TabGlyph.standard)
        #expect(Set(TabGlyph.choices.map(\.symbol)).count == TabGlyph.choices.count)
    }
}
