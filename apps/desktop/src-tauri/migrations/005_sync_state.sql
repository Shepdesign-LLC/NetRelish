-- P4 Stage C. Where the sync engine keeps its place.
--
-- The pull cursor per table. There is deliberately NO separate outbox: the set
-- of pending local changes is derivable as `updated_at > last_synced_at`, so
-- there is no second structure that can fall out of step with the first.
CREATE TABLE sync_cursors (
  table_name     TEXT PRIMARY KEY,
  last_synced_at INTEGER NOT NULL DEFAULT 0
);

-- Small key/value for engine state. Today it holds one key, `account_id`.
--
-- That key is load-bearing. A local Pantry belongs to whichever account last
-- synced it. If a DIFFERENT account signs in on this Mac, every cursor is
-- meaningless — pulling `updated_at > cursor` against a stranger's rows would
-- interleave two people's Pantries into one database. On an account change the
-- engine resets the cursors and re-pulls from zero.
CREATE TABLE sync_meta (
  key   TEXT PRIMARY KEY,
  value TEXT
);

-- Seed a cursor per syncable table, in FOREIGN KEY ORDER. The engine walks
-- this order for both push and pull so a parent always exists before a child
-- references it: a jar before its items, a label before an item_labels row.
INSERT INTO sync_cursors (table_name, last_synced_at) VALUES
  ('jars', 0),
  ('labels', 0),
  ('items', 0),
  ('item_labels', 0),
  ('tabs', 0),
  ('recipes', 0),
  ('suggestion_feedback', 0);
