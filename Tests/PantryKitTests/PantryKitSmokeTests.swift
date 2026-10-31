import Foundation
import GRDB
import Testing
@testable import PantryKit

// The package build of the Pantry core (Package.swift → PantryKit, ADR 0009).
// These three tests mirror Tests/PantryTests/PantryTests.swift — the module is the
// same source files, so the behavior contract is the same; what THIS target proves
// is that the SwiftPM build of it works end to end: resolve GRDB, migrate, seed,
// capture into Brine, seal one-way, search via FTS5. Keep them in lockstep with
// the originals.

/// Every test gets its own in-memory Pantry, migrated and seeded.
private func freshStore() throws -> PantryStore { try PantryStore(inMemory: ()) }

@Suite("PantryKit package") struct PantryKitSmokeTests {

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
}
