// Tab+Behavior.swift — hand-written mirror of the diagram's Tab.sink (ADR 0004).
// Sinking is how a tab becomes Brine: an Item with no jar, state brined, carrying the
// web view's interaction state so it can be restored with scroll and history intact.

import Foundation
import GRDB

extension Tab: TabMethods {
    /// Keys inside `Item.meta` for a sunk tab.
    public enum MetaKey {
        public static let interactionState = "interactionState"   // base64 of WKWebView.interactionState
        public static let originJar = "originJar"
    }

    @discardableResult
    public mutating func sink(_ db: Database) throws -> Item {
        let now = Date()
        var meta: [String: Any] = [:]
        if let state = interactionState, !state.isEmpty {
            meta[MetaKey.interactionState] = state.base64EncodedString()
        }
        if let jarId { meta[MetaKey.originJar] = jarId }
        var item = Item(
            createdAt: now,
            domain: url.flatMap { URL(string: $0)?.host },
            kind: .page,
            meta: try JSONSerialization.data(withJSONObject: meta),
            source: .browse,
            state: .brined,
            title: (title?.isEmpty == false ? title : url) ?? "Untitled",
            updatedAt: now,
            url: url
        )
        try item.insert(db)
        Tab.onSunk.emit(item)
        _ = try delete(db)
        return item
    }
}

public extension Item {
    /// The interaction state a sunk tab carried, if any.
    var sunkInteractionState: Data? {
        guard let meta, let obj = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
              let b64 = obj[Tab.MetaKey.interactionState] as? String else { return nil }
        return Data(base64Encoded: b64)
    }

    /// The jar the tab sank from, if any.
    var sunkOriginJarId: String? {
        guard let meta, let obj = try? JSONSerialization.jsonObject(with: meta) as? [String: Any] else { return nil }
        return obj[Tab.MetaKey.originJar] as? String
    }
}
