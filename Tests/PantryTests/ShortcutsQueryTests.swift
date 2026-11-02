import Foundation
import GRDB
import Testing
@testable import Pantry

/// The Pantry side of Shortcuts: capture from a Shortcut, the one Seal that ⌘S and Shortcuts
/// share, which jar a Shortcut seals into, and what Shortcuts sees of jars and items.
@Suite("Shortcuts in the Pantry") struct ShortcutsQueryTests {

    private func store() throws -> PantryStore { try PantryStore(inMemory: ()) }

    /// After the seeded jars on the Shelf, so "the first jar" stays the seeded first.
    private func jar(_ name: String, in store: PantryStore) throws -> Jar {
        try store.write { db in
            let last = try Jar.fetchAll(db).compactMap(\.sortOrder).max() ?? 0
            var jar = Jar(name: name, sortOrder: last + 1)
            try jar.insert(db)
            return jar
        }
    }

    @Test("A page captured from Shortcuts lands in Brine, saying Shortcuts brought it")
    func captureFromShortcuts() throws {
        let store = try store()
        let item = try store.write { db in try store.capture(db, url: "https://example.com/brief", source: .shortcut) }
        #expect(item.source == .shortcut)
        #expect(item.state == .brined)
        #expect(item.jarId == nil)
        #expect(item.title == "https://example.com/brief")   // the URL until a seal fills it
        #expect(item.domain == "example.com")
    }

    @Test("Sealing freezes the snapshot beside a sealed item in the jar, and its text is searchable")
    func sealPage() throws {
        let store = try store()
        let clients = try jar("Clients", in: store)
        let item = try store.write { db in
            try store.sealPage(db, url: "https://example.com/terms", title: "Terms", body: "Net thirty with a pumpernickel clause.",
                               excerpt: "Net thirty.", archive: Data("ARCHIVE".utf8), jarId: clients.id, source: .shortcut)
        }
        #expect(item.state == .sealed)
        #expect(item.sealedAt != nil)
        #expect(item.jarId == clients.id)
        #expect(item.source == .shortcut)
        let path = try #require(item.snapshotPath)
        #expect(try store.snapshots.read(path) == Data("ARCHIVE".utf8))
        #expect(try store.read { db in try store.search(db, "pumpernickel") }.map(\.id) == [item.id])
    }

    @Test("Sealing runs the jar's default Recipe on the new item")
    func sealRunsTheRecipe() throws {
        let store = try store()
        var clients = try jar("Clients", in: store)
        try store.write { db in
            var recipe = Recipe(name: "File it", trigger: .onSeal)
            try recipe.insert(db)
            clients.defaultRecipeId = recipe.id
            try clients.update(db)
        }
        let item = try store.write { db in
            try store.sealPage(db, url: "https://example.com/a", title: "A", body: nil, excerpt: nil,
                               archive: Data(), jarId: clients.id, source: .browse)
        }
        let batches = try store.read { db in try Batch.fetchAll(db) }
        #expect(batches.count == 1)
        #expect(item.batchId == batches.first?.id)
    }

    @Test("With no jar named, a page seals into the jar it was last kept in, else the active jar, else the first")
    func jarForSealing() throws {
        let store = try store()
        let first = try store.read { db in try store.root(db).jars(db).first }
        let clients = try jar("Clients", in: store)
        let research = try jar("Research", in: store)
        let url = "https://example.com/kept"

        // Nothing kept, no active jar set: the first on the Shelf.
        try store.write { db in var root = try store.root(db); root.activeJarId = nil; try root.update(db) }
        #expect(try store.read { db in try store.jarForSealing(db, url: url) }?.id == first?.id)

        // An active jar wins over the first.
        try store.write { db in var root = try store.root(db); root.activeJarId = research.id; try root.update(db) }
        #expect(try store.read { db in try store.jarForSealing(db, url: url) }?.id == research.id)

        // The jar the page was kept in wins over both.
        try store.write { db in var kept = Item(title: "Kept", url: url, jarId: clients.id); try kept.insert(db) }
        #expect(try store.read { db in try store.jarForSealing(db, url: url) }?.id == clients.id)
    }

    @Test("Shortcuts lists every jar, and finds one by part of its name in any case")
    func jarEntities() throws {
        let store = try store()
        _ = try jar("Clients", in: store)
        let all = try JarEntityQuery.jars(in: store)
        #expect(all.contains { $0.name == "Clients" })
        #expect(try JarEntityQuery.jars(in: store, matching: "CLIE").map(\.name) == ["Clients"])
        #expect(try JarEntityQuery.jars(in: store, matching: "  ").count == all.count)   // blank is everything
    }

    @Test("Search returns Pantry items that say where they are, best match first, at most the limit")
    func searchEntities() throws {
        let store = try store()
        let clients = try jar("Clients", in: store)
        try store.write { db in
            _ = try store.sealPage(db, url: "https://example.com/terms", title: "Pumpernickel terms", body: "pumpernickel",
                                   excerpt: nil, archive: Data(), jarId: clients.id, source: .browse)
            _ = try store.capture(db, url: "https://example.com/rye", title: "Pumpernickel and rye", source: .shortcut)
        }
        let found = try PantryItemQuery.search(in: store, for: "pumpernickel")
        #expect(found.count == 2)
        #expect(Set(found.map(\.place)) == ["Sealed in Clients", "In Brine"])
        #expect(found.first { $0.place == "In Brine" }?.url == URL(string: "https://example.com/rye"))
        #expect(try PantryItemQuery.search(in: store, for: "pumpernickel", limit: 1).count == 1)
        #expect(try store.read { db in try store.search(db, "pumpernickel", limit: 1) }.count == 1)   // limited in SQL
        #expect(try PantryItemQuery.search(in: store, for: "nothing-like-this").isEmpty)

        let ids = found.map(\.id)
        #expect(Set(try PantryItemQuery.items(in: store, ids: ids).map(\.id)) == Set(ids))
    }
}
