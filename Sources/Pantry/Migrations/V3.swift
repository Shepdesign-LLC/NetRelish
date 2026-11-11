// V3.swift — sealed pages whose timestamp was marked failed get another try (ADR 0025).
//
// Until this change the app's check of a timestamp's signature could not pass for any real
// timestamp, so every page it tried was counted as a failure three times and then marked
// failed, which is never retried. Those pages did nothing wrong. This puts them back to
// waiting, with their count cleared, so the next sweep asks again.
//
// Data only; the schema is unchanged. It touches one key inside `meta` and nothing else: the
// saved copy, the text and `sealedAt` stay exactly as Seal left them (non-negotiable 3).

import Foundation
import GRDB

extension PantryMigrations {
    static func registerV3(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3-retry-failed-timestamps") { db in
            try retryFailedTimestamps(db)
        }
    }

    /// Puts every page whose timestamp is marked failed back to fingerprinted-and-waiting.
    /// Every other key in `meta`, and everything else in provenance, is left as it was.
    static func retryFailedTimestamps(_ db: Database) throws {
        try db.execute(sql: """
            UPDATE items
            SET meta = CAST(json_remove(json_set(CAST(meta AS TEXT), '$.provenance.status', ?),
                                        '$.provenance.attempts') AS BLOB)
            WHERE meta IS NOT NULL AND json_valid(CAST(meta AS TEXT))
              AND json_extract(CAST(meta AS TEXT), '$.provenance.status') = ?
            """, arguments: [Provenance.Status.fingerprinted.rawValue, Provenance.Status.failed.rawValue])
    }
}
