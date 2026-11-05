// V2.swift — Seal & Summarize becomes a real Recipe (ADR 0012, ADR 0020). V1 seeded the
// Recipe row with no steps and no jar using it, so a Seal ran nothing. This gives it its one
// step, summarize, and makes it the default Recipe of every jar that has none.
//
// Data only; the schema is unchanged. Hand-written, as every migration after V1 is (ADR 0004).

import Foundation
import GRDB

extension PantryMigrations {
    static let sealAndSummarizeStepId = "seal-summarize.summarize"

    static func registerV2(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2-seal-and-summarize") { db in
            let recipe = PantryStore.sealAndSummarizeRecipeId
            // Present since V1's seed; written again in case a Pantry lost it.
            try db.execute(sql: "INSERT OR IGNORE INTO recipes (id, isShortcutExposed, name, trigger) VALUES (?, ?, ?, ?)",
                           arguments: [recipe, true, "Seal & Summarize", RecipeTrigger.onSeal.rawValue])
            try db.execute(sql: #"INSERT OR IGNORE INTO steps (id, action, haltOnFail, "order", recipeId) VALUES (?, ?, ?, ?, ?)"#,
                           arguments: [sealAndSummarizeStepId, StepAction.summarize.rawValue, false, 0.0, recipe])
            try db.execute(sql: "UPDATE jars SET defaultRecipeId = ? WHERE defaultRecipeId IS NULL", arguments: [recipe])
        }
    }
}
