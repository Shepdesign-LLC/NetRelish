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
        // GRDB's lowercased is Swift's, so "Éclair" and "éclair" match; SQLite's lower() only folds ASCII.
        var label = try Label.filter(Label.Columns.name.lowercased == trimmed.lowercased()).fetchOne(db)
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

    // MARK: Capture and Seal, shared by the app and Shortcuts

    /// A page Item in Brine, the way ⌘D makes one, but saying where it came from (the Panel
    /// shows it): `.shortcut` for Shortcuts and Siri. The title is the URL until a seal fills it.
    /// Announced once the write commits.
    @discardableResult
    public func capture(_ db: Database, url: String, title: String? = nil, source: CaptureSource, now: Date = Date()) throws -> Item {
        let given = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var item = Item(
            createdAt: now,
            domain: URL(string: url)?.host,
            kind: .page,
            source: source,
            state: .brined,
            title: given.isEmpty ? url : given,
            updatedAt: now,
            url: url
        )
        try item.insert(db)
        let saved = item
        db.afterNextTransaction { _ in NetRelish.onCapture.emit(saved) }
        return item
    }

    /// Seal (non-negotiable 3), in one place for ⌘S and Shortcuts: a new page Item in the jar,
    /// its `.webarchive` frozen beside it, `sealedAt` stamped, `onSeal` fired, and the jar's
    /// default Recipe run. Nothing changes the snapshot afterwards.
    @discardableResult
    public func sealPage(_ db: Database, url: String?, title: String, body: String?, excerpt: String?,
                         archive: Data, jarId: String, source: CaptureSource, now: Date = Date()) throws -> Item {
        var item = Item(
            body: body?.isEmpty == false ? body : nil,
            createdAt: now,
            domain: url.flatMap { URL(string: $0)?.host },
            excerpt: excerpt?.isEmpty == false ? excerpt : nil,
            kind: .page,
            source: source,
            state: .brined,
            title: title,
            updatedAt: now,
            url: url,
            jarId: jarId
        )
        try item.insert(db)
        // The id names the file, so the archive is written after the insert.
        item.snapshotPath = try snapshots.write(archive, for: item.id)
        try item.update(db)
        let sealed = try root(db).seal(db, item: item)

        // The jar's default Recipe, if it has one.
        if let jar = try Jar.fetchOne(db, key: jarId), let recipeId = jar.defaultRecipeId,
           let recipe = try Recipe.fetchOne(db, key: recipeId),
           let current = try Item.fetchOne(db, key: item.id) {
            _ = try root(db).runRecipe(db, recipe: recipe, items: [current])
        }
        return try Item.fetchOne(db, key: item.id) ?? sealed
    }

    /// The jar a Shortcut seals into when it doesn't name one: the jar the page was last
    /// captured or sealed into, else the active jar, else the first on the Shelf.
    public func jarForSealing(_ db: Database, url: String) throws -> Jar? {
        if let id = try Item.filter(Item.Columns.url == url && Item.Columns.jarId != nil)
            .order(Item.Columns.updatedAt.desc).fetchOne(db)?.jarId,
           let jar = try Jar.fetchOne(db, key: id) {
            return jar
        }
        let root = try root(db)
        if let active = try root.activeJar(db) { return active }
        return try root.jars(db).first
    }

    // MARK: The Share extension

    /// Pages shared from another app's Share menu, into Brine: page Items with "The Share menu"
    /// as their source, each announced like a ⌘D capture once the write commits. Only web pages come in. A page
    /// already waiting in Brine isn't added a second time, so sharing twice is harmless.
    @discardableResult
    public func receive(_ db: Database, _ pages: [SharedPage], now: Date = Date()) throws -> [Item] {
        var received: [Item] = []
        for page in pages {
            guard let url = URL(string: page.url), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            let inBrine = try Item.filter(Item.Columns.url == page.url && Item.Columns.jarId == nil
                                          && Item.Columns.state == ItemState.brined).fetchCount(db) > 0
            if inBrine { continue }
            let title = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let at = min(page.sharedAt, now)   // never in the future, whatever the other clock said
            var item = Item(
                createdAt: at,
                domain: url.host,
                kind: .page,
                source: .shareExtension,
                state: .brined,
                title: title.isEmpty ? page.url : title,
                updatedAt: at,
                url: page.url
            )
            try item.insert(db)
            received.append(item)
        }
        // Announced only once they're saved: a write that rolls back, and leaves the pages in
        // the inbox for the next try, has announced nothing.
        if !received.isEmpty {
            let saved = received
            db.afterNextTransaction { _ in saved.forEach(NetRelish.onCapture.emit) }
        }
        return received
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
