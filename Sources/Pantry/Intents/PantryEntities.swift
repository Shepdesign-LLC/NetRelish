// PantryEntities.swift — how Shortcuts names a jar and a Pantry item. Each is a small,
// read-only description built from the Pantry; Shortcuts never holds a live record.
// Nothing here talks to a network (non-negotiable 5) or involves a model (non-negotiable 4).

import AppIntents
import Foundation
import GRDB

/// A jar, as Shortcuts offers it in a picker and as Siri hears it ("Open Clients").
public struct JarEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Jar"
    public static var defaultQuery: JarEntityQuery { JarEntityQuery() }

    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public init(_ jar: Jar) { self.init(id: jar.id, name: jar.name) }

    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

public struct JarEntityQuery: EntityStringQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [JarEntity.ID]) async throws -> [JarEntity] {
        try Self.jars(in: .shared).filter { identifiers.contains($0.id) }
    }

    public func entities(matching string: String) async throws -> [JarEntity] {
        try Self.jars(in: .shared, matching: string)
    }

    public func suggestedEntities() async throws -> [JarEntity] {
        try Self.jars(in: .shared)
    }

    /// Every jar on the Shelf, in Shelf order; or those whose name contains `string`, in any case.
    public static func jars(in store: PantryStore, matching string: String? = nil) throws -> [JarEntity] {
        let jars = try store.read { db in try store.root(db).jars(db) }
        let wanted = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return jars.filter { wanted.isEmpty || $0.name.localizedCaseInsensitiveContains(wanted) }.map(JarEntity.init)
    }
}

/// A Pantry item, as Search Your Pantry returns it: enough for a Shortcut to show it, open
/// its page, or pass it on.
public struct PantryItemEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pantry Item"
    public static var defaultQuery: PantryItemQuery { PantryItemQuery() }

    public let id: String

    @Property(title: "Title")
    public var title: String

    @Property(title: "URL")
    public var url: URL?

    @Property(title: "Sealed")
    public var isSealed: Bool

    /// "Sealed", "In Brine", or "In <jar>", the way the Panel says it.
    public let place: String

    public init(_ item: Item, jarName: String?) {
        id = item.id
        place = switch item.state {
        case .sealed: jarName.map { "Sealed in \($0)" } ?? "Sealed"
        case .jarred: jarName.map { "In \($0)" } ?? "In a jar"
        case .brined: "In Brine"
        }
        title = item.title
        url = item.url.flatMap(URL.init(string:))
        isSealed = item.state == .sealed
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(place)")
    }
}

public struct PantryItemQuery: EntityQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [PantryItemEntity.ID]) async throws -> [PantryItemEntity] {
        try Self.items(in: .shared, ids: identifiers)
    }

    public static func items(in store: PantryStore, ids: [String]) throws -> [PantryItemEntity] {
        try store.read { db in
            try Item.filter(keys: ids).fetchAll(db).map { try entity($0, db) }
        }
    }

    /// Full-text search, best match first, at most `limit` results.
    public static func search(in store: PantryStore, for query: String, limit: Int = 20) throws -> [PantryItemEntity] {
        try store.read { db in
            try store.search(db, query).prefix(limit).map { try entity($0, db) }
        }
    }

    private static func entity(_ item: Item, _ db: Database) throws -> PantryItemEntity {
        PantryItemEntity(item, jarName: try item.jarId.flatMap { try Jar.fetchOne(db, key: $0)?.name })
    }
}
