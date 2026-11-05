// Reseal.swift — a page's seals over time. Sealing a page again never touches the earlier
// seal (non-negotiable 3): it makes a new sealed item with its own saved copy, and the two
// are compared side by side.

import Foundation
import GRDB

extension PantryStore {
    /// Every sealed item for a page, newest seal first. Two seals stamped in the same
    /// millisecond fall back to the order they were written, so the order is always stable.
    public func seals(_ db: Database, url: String) throws -> [Item] {
        try Item.filter(Item.Columns.url == url && Item.Columns.state == ItemState.sealed && Item.Columns.sealedAt != nil)
            .order(Item.Columns.sealedAt.desc, Column("rowid").desc)
            .fetchAll(db)
    }

    /// The seal of the same page just before this one, if there is one.
    public func previousSeal(_ db: Database, before item: Item) throws -> Item? {
        guard let url = item.url, item.sealedAt != nil else { return nil }
        let all = try seals(db, url: url)
        guard let index = all.firstIndex(where: { $0.id == item.id }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}
