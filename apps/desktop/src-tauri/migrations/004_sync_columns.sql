-- P4 Stage A. Sync metadata on every syncable table.
--
-- Local timestamps stay epoch MILLISECONDS, matching the existing convention.
-- The sync layer converts to timestamptz at the boundary and nowhere else.

ALTER TABLE jars                ADD COLUMN updated_at INTEGER;
ALTER TABLE jars                ADD COLUMN deleted_at INTEGER;
ALTER TABLE jars                ADD COLUMN field_ts   TEXT NOT NULL DEFAULT '{}';

ALTER TABLE items               ADD COLUMN updated_at INTEGER;
ALTER TABLE items               ADD COLUMN deleted_at INTEGER;
ALTER TABLE items               ADD COLUMN field_ts   TEXT NOT NULL DEFAULT '{}';

ALTER TABLE tabs                ADD COLUMN updated_at INTEGER;
ALTER TABLE tabs                ADD COLUMN deleted_at INTEGER;
ALTER TABLE tabs                ADD COLUMN field_ts   TEXT NOT NULL DEFAULT '{}';

ALTER TABLE labels              ADD COLUMN updated_at INTEGER;
ALTER TABLE labels              ADD COLUMN deleted_at INTEGER;
ALTER TABLE labels              ADD COLUMN field_ts   TEXT NOT NULL DEFAULT '{}';

ALTER TABLE recipes             ADD COLUMN updated_at INTEGER;
ALTER TABLE recipes             ADD COLUMN deleted_at INTEGER;
ALTER TABLE recipes             ADD COLUMN field_ts   TEXT NOT NULL DEFAULT '{}';

ALTER TABLE suggestion_feedback ADD COLUMN updated_at INTEGER;
ALTER TABLE suggestion_feedback ADD COLUMN deleted_at INTEGER;
ALTER TABLE suggestion_feedback ADD COLUMN field_ts   TEXT NOT NULL DEFAULT '{}';

-- item_labels is a pure join table: presence is the only fact, so there is
-- nothing to merge field-by-field and no field_ts. It still needs a tombstone,
-- or a label removed on one device returns from a device that never heard.
ALTER TABLE item_labels         ADD COLUMN updated_at INTEGER;
ALTER TABLE item_labels         ADD COLUMN deleted_at INTEGER;

-- embeddings deliberately gets nothing and never syncs: local vectors are
-- MiniLM, the server's are Voyage at a different dimension. Not comparable.

-- Backfill so existing rows sort correctly on the first sync.
UPDATE jars                SET updated_at = COALESCE(updated_at, created_at);
UPDATE items               SET updated_at = COALESCE(updated_at, touched_at, created_at);
UPDATE tabs                SET updated_at = COALESCE(updated_at, touched_at, opened_at);
UPDATE labels              SET updated_at = COALESCE(updated_at, strftime('%s','now') * 1000);
UPDATE recipes             SET updated_at = COALESCE(updated_at, strftime('%s','now') * 1000);
UPDATE suggestion_feedback SET updated_at = COALESCE(updated_at, at);
UPDATE item_labels         SET updated_at = COALESCE(updated_at, strftime('%s','now') * 1000);

CREATE INDEX idx_items_sync ON items (updated_at);
CREATE INDEX idx_jars_sync  ON jars  (updated_at);
CREATE INDEX idx_tabs_sync  ON tabs  (updated_at);

-- THE FTS FIX.
-- items_fts_au fires AFTER UPDATE and re-indexes the row. Once a delete is an
-- UPDATE that sets deleted_at, a tombstoned item would STAY in the FTS index
-- and ⌘K would keep finding it — deleting would appear to do nothing.
-- Replace the trigger so it removes the old entry always and re-inserts only
-- while the row is alive.
DROP TRIGGER IF EXISTS items_fts_au;
CREATE TRIGGER items_fts_au AFTER UPDATE ON items BEGIN
  INSERT INTO items_fts(items_fts, rowid, title, body)
    VALUES ('delete', old.rowid, old.title, old.body);
  INSERT INTO items_fts(rowid, title, body)
    SELECT new.rowid, new.title, new.body WHERE new.deleted_at IS NULL;
END;
