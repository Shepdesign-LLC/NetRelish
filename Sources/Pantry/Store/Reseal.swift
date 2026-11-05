// Reseal.swift — a page's seals over time. Sealing a page again never touches the earlier
// seal (non-negotiable 3): it makes a new sealed item with its own saved copy, and the two
// are compared side by side.

import Foundation
import GRDB

extension PantryStore {
    /// Every sealed item for a page, newest seal first.
    public func seals(_ db: Database, url: String) throws -> [Item] {
        try Item.filter(Item.Columns.url == url && Item.Columns.state == ItemState.sealed && Item.Columns.sealedAt != nil)
            .order(Item.Columns.sealedAt.desc)
            .fetchAll(db)
    }

    /// The seal of the same page just before this one, if there is one.
    public func previousSeal(_ db: Database, before item: Item) throws -> Item? {
        guard let url = item.url, let sealedAt = item.sealedAt else { return nil }
        return try Item.filter(Item.Columns.url == url && Item.Columns.state == ItemState.sealed
                               && Item.Columns.sealedAt < sealedAt && Item.Columns.id != item.id)
            .order(Item.Columns.sealedAt.desc)
            .fetchOne(db)
    }
}
