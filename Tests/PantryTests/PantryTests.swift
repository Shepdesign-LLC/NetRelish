import Foundation
import GRDB
import Testing
@testable import Pantry

/// Every test gets its own in-memory Pantry, migrated and seeded.
private func freshStore() throws -> PantryStore { try PantryStore(inMemory: ()) }

@Suite("Pantry") struct PantryTests {

    @Test("V1 migrates, seeds the components, and start creates the root")
    func migrationAndSeed() throws {
        let store = try freshStore()
        let (tables, jars, readLater, recipe, root) = try store.read { db in
            (try PantrySchema.tables.filter { try db.tableExists($0) } + ["items_labels", "items_fts"].filter { try db.tableExists($0) },
             try Jar.fetchCount(db),
             try Jar.fetchOne(db, key: "read-later"),
             try Recipe.fetchOne(db, key: "seal-summarize"),
             try store.root(db))
        }
        #expect(tables.count == PantrySchema.tables.count + 2)
        #expect(jars == 2)
        #expect(readLater?.name == "Read Later")
        #expect(recipe?.trigger == .onSeal)
        #expect(root.id == "pantry" && root.activeJarId == "read-later")
    }

    @Test("Capture puts a page Item in Brine")
    func capture() throws {
        let store = try freshStore()
        let item = try store.write { db in
            try store.root(db).capture(db, url: "https://developer.apple.com/documentation/swiftui")
        }
        #expect(item.kind == .page && item.state == .brined && item.source == .browse)
        #expect(item.domain == "developer.apple.com")
        #expect(item.jarId == nil)
        let brine = try store.read { db in try store.root(db).brine(db) }
        #expect(brine.map(\.id) == [item.id], "Brine is the query jar == nil && state == brined")
    }

    @Test("Seal stamps sealedAt, is one-way, and FTS finds a body phrase")
    func sealAndSearch() throws {
        let store = try freshStore()
        let item = Item(body: "The invoice terms say net thirty days from receipt.", title: "Kickoff notes", url: "https://example.com/notes")
        let sealed = try store.write { db -> Item in
            var it = item
            try it.insert(db)
            try it.seal(db)
            return it
        }
        #expect(sealed.state == .sealed)
        #expect(sealed.sealedAt != nil)
        let again = try store.write { db -> Item in var it = sealed; try it.seal(db); return it }   // one-way: no-op
        #expect(again.sealedAt == sealed.sealedAt)

        let (hits, misses) = try store.read { db in (try store.search(db, "invoice terms"), try store.search(db, "nonexistent phrase")) }
        #expect(hits.map(\.id) == [item.id])
        #expect(misses.isEmpty)
    }

    @Test("FTS follows updates and deletes — all three triggers")
    func ftsTriggers() throws {
        let store = try freshStore()
        var item = Item(body: "alpha bravo", title: "t")
        try store.write { db in try item.insert(db) }
        #expect(try store.read { db in try store.search(db, "bravo").count } == 1)
        item.body = "charlie delta"
        try store.write { db in try item.update(db) }
        let (bravo, delta) = try store.read { db in (try store.search(db, "bravo").count, try store.search(db, "delta").count) }
        #expect(bravo == 0, "update trigger")
        #expect(delta == 1)
        try store.write { db in _ = try item.delete(db) }
        #expect(try store.read { db in try store.search(db, "delta").count } == 0, "delete trigger")
    }

    @Test("Deleting a jar sends its items back to Brine, never deletes them")
    func jarDeleteKeepsItems() throws {
        let store = try freshStore()
        var item = Item(state: .jarred, title: "kept", jarId: "reference")
        try store.write { db in
            try item.insert(db)
            _ = try Jar.deleteOne(db, key: "reference")
        }
        let kept = try store.read { db in try Item.fetchOne(db, key: item.id) }
        #expect(kept != nil)
        #expect(kept?.jarId == nil)
    }

    @Test("A Recipe runs its steps in order inside a Batch")
    func recipeRun() throws {
        let store = try freshStore()
        var recipe = Recipe(name: "Sort", trigger: .manual)
        var move = Step(action: .moveToJar, order: 1, params: Data(#"{"jar":"reference"}"#.utf8), recipeId: recipe.id)
        var seal = Step(action: .seal, order: 2, recipeId: recipe.id)
        var item = Item(title: "to sort")
        let batch = try store.write { db -> Batch in
            try recipe.insert(db); try move.insert(db); try seal.insert(db); try item.insert(db)
            return try store.root(db).runRecipe(db, recipe: recipe, items: [item])
        }
        #expect(batch.status == "done")
        #expect(batch.finishedAt != nil)
        let (after, ranRecipe) = try store.read { db in (try Item.fetchOne(db, key: item.id), try Recipe.fetchOne(db, key: recipe.id)) }
        #expect(after?.jarId == "reference")
        #expect(after?.state == .sealed, "moveToJar then seal: the last step wins")
        #expect(after?.batchId == batch.id)
        #expect(ranRecipe?.lastRunAt != nil)
    }

    @Test("Events reach an AsyncStream listener")
    func events() async throws {
        let store = try freshStore()
        let stream = Item.onSealed.stream
        var item = Item(title: "event")
        try store.write { db in try item.insert(db) }
        let listener = Task { () -> Item? in
            for await sealedItem in stream { return sealedItem }
            return nil
        }
        try await Task.sleep(for: .milliseconds(50))   // let the listener attach
        let toSeal = item
        try store.write { db in var it = toSeal; try it.seal(db) }
        let received = await listener.value
        #expect(received?.id == item.id)
    }

    @Test("Labels are a many-to-many through items_labels")
    func labels() throws {
        let store = try freshStore()
        var item = Item(title: "labelled")
        var a = Label(name: "client"), b = Label(name: "spec")
        try store.write { db in
            try item.insert(db); try a.insert(db); try b.insert(db)
            try item.setLabels([a.id, b.id], db)
        }
        let (names, aItems) = try store.read { db in (try item.labels(db).map(\.name), try a.items(db).map(\.id)) }
        #expect(Set(names) == ["client", "spec"])
        #expect(aItems == [item.id])
    }
}

/// The smart jars are queries over the one Item table and the open tabs (non-negotiable 2):
/// nothing is moved into one, so each test only writes ordinary rows and reads the query.
@Suite("Smart jars") struct SmartJarQueryTests {

    @Test("Today is everything created since midnight, in any jar, newest first")
    func today() throws {
        let store = try freshStore()
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 15))!
        let midnight = calendar.startOfDay(for: now)
        try store.write { db in
            var jar = Jar(name: "Meridian", shelfLifeDays: 3)
            try jar.insert(db)
            var yesterday = Item(createdAt: midnight.addingTimeInterval(-60), title: "Yesterday")
            var morning = Item(createdAt: midnight.addingTimeInterval(3600), title: "Morning")
            var afternoon = Item(createdAt: now, title: "Afternoon", jarId: jar.id)
            try yesterday.insert(db); try morning.insert(db); try afternoon.insert(db)
        }
        let titles = try store.read { db in try store.today(db, now: now, calendar: calendar).map(\.title) }
        #expect(titles == ["Afternoon", "Morning"])
    }

    @Test("Sealed is every sealed item, most recently sealed first; captured items stay out")
    func sealed() throws {
        let store = try freshStore()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try store.write { db in
            var first = Item(sealedAt: t0, state: .sealed, title: "First")
            var second = Item(sealedAt: t0.addingTimeInterval(60), state: .sealed, title: "Second")
            var captured = Item(title: "Captured")
            try first.insert(db); try second.insert(db); try captured.insert(db)
        }
        let titles = try store.read { db in try store.sealed(db).map(\.title) }
        #expect(titles == ["Second", "First"])
    }

    @Test("Sinking soon is the fading tabs, soonest first; pinned, fresh and forever tabs stay out")
    func sinkingSoon() throws {
        let store = try freshStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let ids = try store.write { db -> [String: String] in
            var oneDay = Jar(name: "One day", shelfLifeDays: 1)
            var forever = Jar(name: "Forever", shelfLifeDays: nil)
            try oneDay.insert(db); try forever.insert(db)
            func tab(_ title: String, age: TimeInterval, pinned: Bool = false, jar: Jar) throws -> String {
                var t = Tab(isPinned: pinned, sortOrder: 0, title: title, touchedAt: now.addingTimeInterval(-age), jarId: jar.id)
                try t.insert(db)
                return t.id
            }
            return [
                "late": try tab("Late", age: day * 0.98, jar: oneDay),
                "fading": try tab("Fading", age: day * 0.92, jar: oneDay),
                "fresh": try tab("Fresh", age: day * 0.5, jar: oneDay),
                "pinned": try tab("Pinned", age: day * 0.95, pinned: true, jar: oneDay),
                "forever": try tab("Forever", age: day * 50, jar: forever),
            ]
        }
        let sinking = try store.read { db in try store.sinkingSoon(db, now: now).map(\.id) }
        #expect(sinking == [ids["late"]!, ids["fading"]!])
    }
}

/// What the Panel reads and writes: a page's item, and labels by name.
@Suite("Panel queries") struct PanelQueryTests {

    @Test("A label is one label whatever its case; removing it from one item keeps it for the rest")
    func labelsByName() throws {
        let store = try freshStore()
        let before = try store.read { db in try Label.fetchCount(db) }
        let (a, b) = try store.write { db -> (Item, Item) in
            var a = Item(title: "Invoice terms")
            var b = Item(title: "Kickoff notes")
            try a.insert(db)
            try b.insert(db)
            return (a, b)
        }
        try store.write { db -> Void in
            _ = try store.addLabel(db, named: "Client", to: a)
            _ = try store.addLabel(db, named: "client", to: a)        // same label, not a second one
            _ = try store.addLabel(db, named: "  CLIENT ", to: b)
            #expect(try store.addLabel(db, named: "   ", to: b) == nil) // blank is nothing
        }
        let (onA, onB, total) = try store.read { db in (try a.labels(db), try b.labels(db), try Label.fetchCount(db)) }
        #expect(onA.map(\.name) == ["Client"])
        #expect(onB.map(\.id) == onA.map(\.id))
        #expect(total == before + 1)

        try store.write { db in try store.removeLabel(db, onA[0], from: a) }
        let (afterA, afterB, stillThere) = try store.read { db in (try a.labels(db), try b.labels(db), try Label.fetchCount(db)) }
        #expect(afterA.isEmpty)
        #expect(afterB.count == 1)
        #expect(stillThere == before + 1)
    }

    @Test("A page's item is its sealed copy when there is one, else its newest capture")
    func itemForPage() throws {
        let store = try freshStore()
        let url = "https://example.com/terms"
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try store.write { db -> Void in
            var old = Item(createdAt: t0, title: "Old capture", url: url)
            var sealed = Item(createdAt: t0.addingTimeInterval(60), sealedAt: t0.addingTimeInterval(60), state: .sealed, title: "Sealed", url: url)
            var newest = Item(createdAt: t0.addingTimeInterval(120), title: "Newest capture", url: url)
            try old.insert(db); try sealed.insert(db); try newest.insert(db)
        }
        #expect(try store.read { db in try store.item(db, url: url)?.title } == "Sealed")
        #expect(try store.read { db in try store.item(db, url: "https://example.com/nowhere") } == nil)
    }
}
