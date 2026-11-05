// Provenance.swift — proof of what a sealed page said, and when (Pro, ADR 0022).
//
// Two parts, both about the frozen `.webarchive` and never the live page:
//   · the fingerprint: SHA-256 of the saved copy's bytes, worked out on this Mac;
//   · the timestamp: an RFC 3161 token from a timestamp authority, signing that fingerprint.
// Like a summary, provenance is metadata about a sealed page, kept in `Item.meta["provenance"]`.
// The snapshot, `body` and `sealedAt` are never touched (non-negotiable 3).

import CryptoKit
import Foundation
import GRDB

/// Where a sealed page's provenance stands.
public struct Provenance: Sendable, Equatable {
    /// How many times the authority may fail a page before it's marked failed.
    public static let maxAttempts = 3

    public enum Status: String, Sendable, Equatable {
        /// Fingerprinted; the timestamp is still to come.
        case fingerprinted
        /// Fingerprinted and timestamped.
        case stamped
        /// The authority failed `maxAttempts` times. Not retried on its own.
        case failed
    }

    /// SHA-256 of the saved copy, lowercase hex.
    public var fingerprint: String
    public var status: Status
    /// The timestamp, once the authority has granted one.
    public var timestamp: Timestamp?
    /// The authority's host, for the proof ("timestamp.digicert.com").
    public var authority: String?
    /// Failed requests so far.
    public var attempts: Int

    public init(fingerprint: String, status: Status = .fingerprinted, timestamp: Timestamp? = nil,
                authority: String? = nil, attempts: Int = 0) {
        self.fingerprint = fingerprint
        self.status = status
        self.timestamp = timestamp
        self.authority = authority
        self.attempts = attempts
    }

    /// The fingerprint of a saved copy.
    public static func fingerprint(of archive: Data) -> String {
        SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
    }

    /// The fingerprint's bytes, for a timestamp request.
    public var digest: [UInt8] {
        var bytes: [UInt8] = []
        var index = fingerprint.startIndex
        while index < fingerprint.endIndex {
            let next = fingerprint.index(index, offsetBy: 2, limitedBy: fingerprint.endIndex) ?? fingerprint.endIndex
            if let byte = UInt8(fingerprint[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        return bytes
    }
}

extension Item {
    /// The key inside `Item.meta` that holds provenance. Other keys in `meta` are left alone.
    public static let provenanceMetaKey = "provenance"

    /// The provenance stored on this item, if any.
    public var provenance: Provenance? {
        guard let meta, let obj = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
              let entry = obj[Item.provenanceMetaKey] as? [String: Any],
              let fingerprint = entry["sha256"] as? String,
              let status = (entry["status"] as? String).flatMap(Provenance.Status.init(rawValue:)) else { return nil }
        let timestamp = (entry["token"] as? String).flatMap { Data(base64Encoded: $0) }
            .flatMap { try? Timestamp(token: $0) }
        return Provenance(fingerprint: fingerprint, status: status, timestamp: timestamp,
                          authority: entry["authority"] as? String, attempts: entry["attempts"] as? Int ?? 0)
    }

    /// Stores `provenance` in `meta`, keeping every other key.
    public mutating func setProvenance(_ provenance: Provenance) {
        var obj = (meta.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        var entry: [String: Any] = ["sha256": provenance.fingerprint, "status": provenance.status.rawValue]
        if let stamp = provenance.timestamp {
            entry["token"] = stamp.token.base64EncodedString()
            // Readable copies of what the token says; the token is what counts.
            entry["time"] = ISO8601DateFormatter().string(from: stamp.time)
            entry["serial"] = stamp.serial
        }
        if let authority = provenance.authority { entry["authority"] = authority }
        if provenance.attempts > 0 { entry["attempts"] = provenance.attempts }
        obj[Item.provenanceMetaKey] = entry
        meta = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }
}

extension PantryStore {
    /// Sealed pages with a saved copy whose provenance isn't finished: no fingerprint yet, or
    /// (when `stamping`) a fingerprint still waiting for its timestamp. Newest seal first.
    public func awaitingProvenance(_ db: Database, stamping: Bool) throws -> [Item] {
        let waiting = stamping ? "('fingerprinted')" : "()"
        return try Item.fetchAll(db, sql: """
            SELECT * FROM items
            WHERE state = ? AND sealedAt IS NOT NULL AND snapshotPath IS NOT NULL
              AND (meta IS NULL
                   OR json_extract(CAST(meta AS TEXT), '$.provenance.status') IS NULL
                   OR json_extract(CAST(meta AS TEXT), '$.provenance.status') IN \(waiting))
            ORDER BY sealedAt DESC
            """, arguments: [ItemState.sealed.rawValue])
    }

    /// Stores provenance on a sealed item. Returns false if the item is gone, not sealed, or
    /// already holds exactly this.
    @discardableResult
    public func recordProvenance(_ db: Database, _ provenance: Provenance, for itemId: String) throws -> Bool {
        guard var item = try Item.fetchOne(db, key: itemId), item.state == .sealed else { return false }
        guard item.provenance != provenance else { return false }
        item.setProvenance(provenance)
        try item.update(db)
        return true
    }

    /// The fingerprint of an item's saved copy as it is on disk now.
    public func fingerprint(of item: Item) throws -> String {
        guard let path = item.snapshotPath else { throw CocoaError(.fileNoSuchFile) }
        return Provenance.fingerprint(of: try snapshots.read(path))
    }
}
