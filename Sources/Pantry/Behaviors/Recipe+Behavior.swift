// Recipe+Behavior.swift — hand-written mirror of the diagram's Recipe.run (ADR 0004).

import Foundation
import GRDB

extension Recipe: RecipeMethods {
    /// Runs every step over every item, in order, inside one Batch.
    /// A failing step halts the run only if `haltOnFail` is set on that step.
    @discardableResult
    public mutating func run(_ db: Database, items: [Item]) throws -> Batch {
        var batch = Batch(status: "running", recipeId: id)
        try batch.insert(db)
        // Tag every item with the batch first; the steps then work on the tagged copies.
        let tagged: [Item] = try items.map { item in
            var item = item
            item.batchId = batch.id
            try item.update(db)
            return item
        }
        let orderedSteps = try steps(db).sorted { $0.order < $1.order }
        for var item in tagged {
            for var step in orderedSteps {
                do {
                    item = try step.execute(db, item: item)
                } catch {
                    if step.haltOnFail == true {
                        batch.status = "failed"
                        batch.finishedAt = Date()
                        try batch.update(db)
                        Recipe.onRunFinished.emit(batch)
                        return batch
                    }
                }
            }
        }
        batch.status = "done"
        batch.finishedAt = Date()
        try batch.update(db)
        lastRunAt = Date()
        try update(db)
        Recipe.onRunFinished.emit(batch)
        return batch
    }
}
