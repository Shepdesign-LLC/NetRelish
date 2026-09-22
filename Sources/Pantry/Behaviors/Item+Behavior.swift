// Item+Behavior.swift — hand-written mirror of the diagram's Item.seal (ADR 0004).
// The JavaScript is quoted in the generated ItemMethods protocol.

import Foundation
import GRDB

extension Item: ItemMethods {
    /// Seal is the one-way move (non-negotiable 3): stamp `sealedAt`, freeze state, fire `onSealed`.
    /// The snapshot freeze and tab close are the Bench's job (P2); the Pantry only records it.
    @discardableResult
    public mutating func seal(_ db: Database) throws -> Item {
        if state == .sealed { return self }
        let now = Date()
        state = .sealed
        sealedAt = now
        updatedAt = now
        try update(db)
        Item.onSealed.emit(self)
        return self
    }
}
