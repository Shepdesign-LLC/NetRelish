import Foundation
import GRDB
import Testing
@testable import Pantry

@Suite("Shelf life and sinking") struct ShelfLifeTests {
    let jar = Jar(name: "J", shelfLifeDays: 1)

    @Test("Remaining life runs from touchedAt; pinned never sinks")
    func remaining() {
        let t0 = Date()
        var tab = Tab(isPinned: false, sortOrder: 0, touchedAt: t0, jarId: jar.id)
        #expect(ShelfLife.remaining(of: tab, in: jar, now: t0) == 1)
        #expect(abs(ShelfLife.remaining(of: tab, in: jar, now: t0.addingTimeInterval(12 * 3600))! - 0.5) < 1e-9)
        #expect(ShelfLife.shouldSink(tab, in: jar, now: t0.addingTimeInterval(86_400)))
        #expect(ShelfLife.isFading(tab, in: jar, now: t0.addingTimeInterval(86_400 * 0.95)))
        #expect(!ShelfLife.isFading(tab, in: jar, now: t0.addingTimeInterval(86_400 * 0.5)))
        tab.isPinned = true
        #expect(ShelfLife.remaining(of: tab, in: jar, now: t0.addingTimeInterval(1e9)) == nil)
        #expect(!ShelfLife.shouldSink(tab, in: jar, now: t0.addingTimeInterval(1e9)))
    }

    @Test("A jar with no shelf life never sinks its tabs")
    func noShelfLife() {
        let forever = Jar(name: "Forever", shelfLifeDays: nil)
        let tab = Tab(isPinned: false, sortOrder: 0, touchedAt: .distantPast, jarId: forever.id)
        #expect(!ShelfLife.shouldSink(tab, in: forever))
    }

    @Test("Sinking a tab makes a brined Item carrying its state, and removes the tab")
    func sink() throws {
        let store = try PantryStore(inMemory: ())
        let state = Data([1, 2, 3, 4])
        var tab = Tab(interactionState: state, isPinned: false, sortOrder: 0, title: "Kickoff notes", url: "https://example.com/notes", jarId: "read-later")
        let item = try store.write { db -> Item in
            try tab.insert(db)
            return try tab.sink(db)
        }
        #expect(item.state == .brined && item.jarId == nil && item.kind == .page)
        #expect(item.title == "Kickoff notes" && item.domain == "example.com")
        #expect(item.sunkInteractionState == state)
        #expect(item.sunkOriginJarId == "read-later")
        let (tabs, brine) = try store.read { db in (try Tab.fetchCount(db), try store.root(db).brine(db).count) }
        #expect(tabs == 0)
        #expect(brine == 1, "Brine is the query, and the sunk tab is in it")
    }
}
