// V1.swift — the first migration. Tables come from the generated PantrySchema;
// this file adds what the diagram cannot express: the FTS5 index over items and
// the three triggers that keep it honest, then the seed rows.
//
// Once V1 has shipped it is frozen. Later changes to the diagram regenerate
// PantrySchema (the target shape) and get a hand-written V2, V3… (ADR 0004).

import Foundation
import GRDB

public enum PantryMigrations {
    /// Every migration, in order. `PantryStore` registers these.
    public static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            try PantrySchema.create(db)

            // Full-text search over the columns the plan names: title, excerpt, body.
            // External-content FTS5: the index stores nothing itself and reads `items`.
            try db.create(virtualTable: "items_fts", using: FTS5()) { t in
                t.synchronize(withTable: "items")   // GRDB installs the insert, update AND delete triggers
                t.tokenizer = .porter(wrapping: .unicode61())
                t.column("title")
                t.column("excerpt")
                t.column("body")
            }

            try PantrySeed.apply(db)
        }
    }
}
