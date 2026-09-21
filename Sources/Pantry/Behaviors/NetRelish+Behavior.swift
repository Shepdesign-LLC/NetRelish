// NetRelish+Behavior.swift — hand-written mirrors of the root's capture, seal and
// runRecipe (ADR 0004). The JavaScript is quoted in the generated NetRelishMethods protocol.

import Foundation
import GRDB

extension NetRelish: NetRelishMethods {
    /// A new page Item in Brine. Title defaults to the URL until extraction (P2) fills it.
    @discardableResult
    public func capture(_ db: Database, url: String) throws -> Item {
        let now = Date()
        var item = Item(
            createdAt: now,
            domain: URL(string: url)?.host,
            kind: .page,
            source: .browse,
            state: .brined,
            title: url,
            updatedAt: now,
            url: url
        )
        try item.insert(db)
        NetRelish.onCapture.emit(item)
        return item
    }

    /// Seal an item and announce it at the workbench level.
    @discardableResult
    public func seal(_ db: Database, item: Item) throws -> Item {
        var item = item
        try item.seal(db)
        NetRelish.onSeal.emit(item)
        return item
    }

    public func runRecipe(_ db: Database, recipe: Recipe, items: [Item]) throws -> Batch {
        var recipe = recipe
        return try recipe.run(db, items: items)
    }
}
