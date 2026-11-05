// Summary.swift — what Seal & Summarize leaves on a sealed page, and the only text it may read.
//
// Non-negotiable 4: intelligence reads sealed snapshots only. `SealedText` can only be made
// from an Item that is already sealed, out of the text frozen with it at Seal (the Defuddle
// `body`). Nothing here can reach a live web view, its DOM, or a signed-in session.

import Foundation
import GRDB

/// Why this Mac can't write summaries right now, in a way that won't fix itself.
public enum SummaryUnavailable: String, Sendable, Equatable {
    /// Apple Intelligence is turned off in System Settings.
    case appleIntelligenceOff
    /// This Mac can't run Apple Intelligence.
    case deviceNotEligible
}

/// Where a sealed page's summary stands.
public enum SummaryState: Sendable, Equatable {
    /// How many times the model may fail a page before it's marked failed.
    public static let maxAttempts = 3

    /// The jar's Recipe asked for one and it hasn't been written yet. Never stored: it is
    /// worked out from the Recipe that ran (`PantryStore.summaryState`).
    case pending
    /// The summary.
    case done(String)
    /// The page had no article text to summarize.
    case noText
    /// This Mac can't summarize right now. Tried again whenever summaries are swept.
    case unavailable(SummaryUnavailable)
    /// The model failed this many times, which can be passing (busy, rate-limited in the
    /// background). Tried again on the next sweep, until `SummaryState.maxAttempts`.
    case retrying(attempts: Int)
    /// The model failed `maxAttempts` times. Not retried on its own.
    case failed
}

extension Item {
    /// The key inside `Item.meta` that holds the summary. Other keys in `meta` are left alone.
    public static let summaryMetaKey = "summary"

    /// The summary stored on this item, if one was written. `.pending` is never stored.
    public var storedSummary: SummaryState? {
        guard let meta, let obj = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
              let entry = obj[Item.summaryMetaKey] as? [String: Any],
              let status = entry["status"] as? String else { return nil }
        switch status {
        case "done":
            guard let text = entry["text"] as? String, !text.isEmpty else { return nil }
            return .done(text)
        case "noText":
            return .noText
        case "unavailable":
            return (entry["reason"] as? String).flatMap(SummaryUnavailable.init(rawValue:)).map { .unavailable($0) }
        case "retry":
            return (entry["attempts"] as? Int).map { .retrying(attempts: $0) }
        case "failed":
            return .failed
        default:
            return nil
        }
    }

    /// No summary yet, due another try, or set aside because this Mac couldn't summarize.
    var isAwaitingSummary: Bool {
        switch storedSummary {
        case nil, .unavailable?, .retrying?: true
        case .pending?, .done?, .noText?, .failed?: false
        }
    }

    /// Stores `state` in `meta`, keeping every other key. `.pending` clears the entry.
    /// Labels-style metadata: the frozen snapshot, `body` and `sealedAt` are never touched.
    public mutating func setStoredSummary(_ state: SummaryState) {
        var obj = (meta.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        switch state {
        case .pending: obj[Item.summaryMetaKey] = nil
        case .done(let text): obj[Item.summaryMetaKey] = ["status": "done", "text": text]
        case .noText: obj[Item.summaryMetaKey] = ["status": "noText"]
        case .unavailable(let why): obj[Item.summaryMetaKey] = ["status": "unavailable", "reason": why.rawValue]
        case .retrying(let attempts): obj[Item.summaryMetaKey] = ["status": "retry", "attempts": attempts]
        case .failed: obj[Item.summaryMetaKey] = ["status": "failed"]
        }
        meta = obj.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }
}

/// The text of a sealed page, as a summarizer may read it: the title and the article text
/// frozen at Seal, trimmed to what an on-device model can take in at once.
public struct SealedText: Sendable, Equatable {
    public let itemId: String
    public let title: String
    public let text: String

    /// About 1,500 tokens of article: well inside the on-device model's context, with room
    /// for the instructions and the answer.
    public static let characterLimit = 6_000

    /// Nil unless the item is sealed and has article text.
    public init?(_ item: Item) {
        guard item.state == .sealed, item.sealedAt != nil,
              let body = item.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
        self.init(itemId: item.id, title: item.title, text: SealedText.trim(body, to: SealedText.characterLimit))
    }

    private init(itemId: String, title: String, text: String) {
        self.itemId = itemId
        self.title = title
        self.text = text
    }

    /// The same page, cut shorter, for a model that couldn't fit it.
    public func shortened(to limit: Int) -> SealedText {
        SealedText(itemId: itemId, title: title, text: SealedText.trim(text, to: limit))
    }

    /// The first `limit` characters, cut back to the last whole word.
    static func trim(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        if let space = head.lastIndex(where: \.isWhitespace), head.distance(from: head.startIndex, to: space) > limit / 2 {
            return String(head[..<space])
        }
        return String(head)
    }
}

// MARK: - Which sealed pages want a summary

extension PantryStore {
    /// The built-in Recipe every jar runs on Seal unless it has another (ADR 0012, ADR 0020).
    public static let sealAndSummarizeRecipeId = "seal-summarize"

    /// Sealed pages whose last Recipe run had a summarize step, and that have no summary yet,
    /// are due another try, or were set aside because this Mac couldn't summarize. Newest
    /// seal first. Finished pages are filtered out in SQLite, so this stays cheap as the
    /// Pantry grows.
    public func awaitingSummary(_ db: Database) throws -> [Item] {
        let candidates = try Item.fetchAll(db, sql: """
            SELECT DISTINCT items.* FROM items
            JOIN batches ON batches.id = items.batchId
            JOIN steps ON steps.recipeId = batches.recipeId
            WHERE steps.action = ? AND items.state = ? AND items.sealedAt IS NOT NULL
              AND (items.meta IS NULL
                   OR json_extract(CAST(items.meta AS TEXT), '$.summary.status') IS NULL
                   OR json_extract(CAST(items.meta AS TEXT), '$.summary.status') IN ('unavailable', 'retry'))
            ORDER BY items.sealedAt DESC
            """, arguments: [StepAction.summarize.rawValue, ItemState.sealed.rawValue])
        return candidates.filter { $0.isAwaitingSummary }
    }

    /// Where an item's summary stands, for the Panel: what's stored, else `.pending` if the
    /// Recipe that ran on it asked for one, else nil (no summary is coming).
    public func summaryState(_ db: Database, of itemId: String) throws -> SummaryState? {
        guard let item = try Item.fetchOne(db, key: itemId), item.state == .sealed else { return nil }
        if let stored = item.storedSummary { return stored }
        guard let batchId = item.batchId else { return nil }
        let asked = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM steps JOIN batches ON steps.recipeId = batches.recipeId
            WHERE batches.id = ? AND steps.action = ?
            """, arguments: [batchId, StepAction.summarize.rawValue]) ?? 0
        return asked > 0 ? .pending : nil
    }

    /// Stores a summary state on a sealed item. Returns false if the item is gone or not sealed.
    @discardableResult
    public func recordSummary(_ db: Database, _ state: SummaryState, for itemId: String) throws -> Bool {
        guard var item = try Item.fetchOne(db, key: itemId), item.state == .sealed else { return false }
        guard item.storedSummary != state else { return false }
        item.setStoredSummary(state)
        try item.update(db)
        return true
    }
}
