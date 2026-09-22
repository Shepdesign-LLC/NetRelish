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
