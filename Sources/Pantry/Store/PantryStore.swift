// PantryStore.swift — the one database. SQLite on disk via GRDB; the source of truth
// on this Mac. Nothing here talks to a network (CLAUDE.md non-negotiable 5).

import Foundation
import GRDB

public final class PantryStore: Sendable {
    public let dbQueue: DatabaseQueue

    /// The app's Pantry: `~/Library/Containers/…/Application Support/NetRelish/pantry.sqlite`
    /// inside the sandbox. Created and migrated on first access.
    public static let shared: PantryStore = {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("NetRelish", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return try PantryStore(path: dir.appendingPathComponent("pantry.sqlite").path)
        } catch {
            fatalError("NetRelish cannot open its Pantry: \(error)")
        }
    }()

    /// Sealed pages, beside the database.
    public let snapshots: SnapshotStore

    /// A Pantry on disk at `path`.
    public init(path: String) throws {
        snapshots = SnapshotStore(directory: URL(fileURLWithPath: path).deletingLastPathComponent()
            .appendingPathComponent("Snapshots", isDirectory: true))
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try migrate()
    }

    /// A throwaway in-memory Pantry, for tests.
    public init(inMemory: Void = ()) throws {
        snapshots = SnapshotStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NetRelishTestSnapshots/\(UUID().uuidString)", isDirectory: true))
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // Pre-release: V1 is still moving with the diagram. A dev Pantry whose schema
        // no longer matches is thrown away rather than migrated. Removed before 1.0.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        PantryMigrations.register(in: &migrator)
        try migrator.migrate(dbQueue)
    }

    // MARK: The root

    /// The `NetRelish` row — the workbench. Mirrors the diagram's `start` behavior:
    /// if the singleton is missing it is created.
    ///
    /// ```javascript
    /// function start() {
    ///   const NetRelish = this.require('NetRelish');
    ///   if (!this.require('pantry')) {
    ///     new NetRelish({ _id: 'pantry' });
    ///   }
    /// }
    /// ```
    public func root(_ db: Database) throws -> NetRelish {
        if let existing = try NetRelish.fetchOne(db, key: NetRelish.singletonId) { return existing }
        var fresh = NetRelish(id: NetRelish.singletonId, tagline: "Savor the web. Get more done.")
        try fresh.insert(db)
        return fresh
    }

    // MARK: Convenience

    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    public func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }

    /// Full-text search over title, excerpt and body. Returns items, best match first.
    public func search(_ db: Database, _ query: String) throws -> [Item] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        return try Item.fetchAll(db, sql: """
            SELECT items.* FROM items
            JOIN items_fts ON items_fts.rowid = items.rowid
            WHERE items_fts MATCH ?
            ORDER BY bm25(items_fts)
            """, arguments: [pattern])
    }

    // MARK: The Panel

    /// The Pantry's item for a page: its sealed copy if there is one, else the newest capture.
    public func item(_ db: Database, url: String) throws -> Item? {
        try Item.filter(Item.Columns.url == url)
            .order(Item.Columns.sealedAt.desc, Item.Columns.createdAt.desc)   // NULL sealedAt sorts last
            .fetchOne(db)
    }

    /// Puts a label on an item, by name. A label that already exists under that name, in any
    /// case, is reused, so "Client" and "client" are one label. Labelling a sealed item adds a
    /// row beside it; the item and its snapshot are untouched (non-negotiable 3).
    @discardableResult
    public func addLabel(_ db: Database, named name: String, to item: Item) throws -> Label? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var label = try Label.filter(sql: "lower(name) = lower(?)", arguments: [trimmed]).fetchOne(db)
            ?? Label(name: trimmed)
        if try !label.exists(db) { try label.insert(db) }
        let ids = try item.labels(db).map(\.id)
        if !ids.contains(label.id) { try item.setLabels(ids + [label.id], db) }
        return label
    }

    /// Takes a label off an item. The label itself stays, for the other items that carry it.
    public func removeLabel(_ db: Database, _ label: Label, from item: Item) throws {
        try item.setLabels(try item.labels(db).map(\.id).filter { $0 != label.id }, db)
    }

    // MARK: Smart jars — queries, never places (non-negotiable 2). Nothing moves into one.

    /// Today: everything that came into the Pantry since midnight, in any jar, newest first.
    public func today(_ db: Database, now: Date = Date(), calendar: Calendar = .current) throws -> [Item] {
        try Item.filter(Item.Columns.createdAt >= calendar.startOfDay(for: now))
            .order(Item.Columns.createdAt.desc).fetchAll(db)
    }

    /// Sealed: every sealed item, most recently sealed first.
    public func sealed(_ db: Database) throws -> [Item] {
        try Item.filter(Item.Columns.state == ItemState.sealed)
            .order(Item.Columns.sealedAt.desc, Item.Columns.createdAt.desc).fetchAll(db)
    }

    /// Sinking soon: open tabs, in any jar, in the last tenth of their shelf life.
    public func sinkingSoon(_ db: Database, now: Date = Date()) throws -> [Tab] {
        ShelfLife.sinkingSoon(try Tab.fetchAll(db), jars: try Jar.fetchAll(db), now: now)
    }
}
