// Pantry.swift — the Pantry framework. Models, migrations, store, intelligence and
// intents arrive in Prompt 3, generated from /design/NetRelish.json. This file
// exists so the target builds and links GRDB today.

import GRDB

public enum Pantry {
    /// The migrations applied so far. Prompt 3 adds V1.
    public static let migrationIdentifiers: [String] = []

    /// A throwaway in-memory database, proving GRDB links. Replaced by the real
    /// store in Prompt 3.
    public static func scratchDatabase() throws -> DatabaseQueue {
        try DatabaseQueue()
    }
}
