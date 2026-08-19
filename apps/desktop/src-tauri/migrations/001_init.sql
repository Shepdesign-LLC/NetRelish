-- 001_init — the full NetRelish schema (CLAUDE.md §6).
--
-- One `items` table with a `kind` discriminator. Pages, notes, tasks, files
-- and messages share one row shape, one index, one search, one suggestion
-- engine. Do not normalize this into five tables.
--
-- Shipped migrations are never edited. Schema changes get a new NNN file.

CREATE TABLE jars (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  hue         INTEGER NOT NULL,        -- 1..6, maps to --nr-jar-N
  created_at  INTEGER NOT NULL,
  sealed_at   INTEGER                  -- non-null = archived jar
);

CREATE TABLE items (
  id           TEXT PRIMARY KEY,
  jar_id       TEXT REFERENCES jars(id) ON DELETE SET NULL,  -- NULL = Brine
  kind         TEXT NOT NULL CHECK (kind IN
                 ('page','note','task','file','message')),
  url          TEXT,
  title        TEXT NOT NULL,
  body         TEXT,                   -- extracted or authored text
  meta         TEXT,                   -- JSON, kind-specific
  created_at   INTEGER NOT NULL,       -- epoch milliseconds
  touched_at   INTEGER NOT NULL,       -- epoch milliseconds
  sealed_at    INTEGER
);

CREATE INDEX idx_items_jar  ON items(jar_id, touched_at DESC);
CREATE INDEX idx_items_kind ON items(kind, touched_at DESC);
CREATE UNIQUE INDEX idx_items_url ON items(url) WHERE url IS NOT NULL;

CREATE VIRTUAL TABLE items_fts USING fts5(
  title, body,
  content='items', content_rowid='rowid',
  tokenize='porter unicode61'
);

-- External-content FTS5 needs all three triggers. Miss one and the index
-- silently drifts out of sync with `items` — no error, just search that
-- quietly stops matching reality.
CREATE TRIGGER items_fts_ai AFTER INSERT ON items BEGIN
  INSERT INTO items_fts(rowid, title, body)
  VALUES (new.rowid, new.title, new.body);
END;

CREATE TRIGGER items_fts_ad AFTER DELETE ON items BEGIN
  INSERT INTO items_fts(items_fts, rowid, title, body)
  VALUES ('delete', old.rowid, old.title, old.body);
END;

CREATE TRIGGER items_fts_au AFTER UPDATE ON items BEGIN
  INSERT INTO items_fts(items_fts, rowid, title, body)
  VALUES ('delete', old.rowid, old.title, old.body);
  INSERT INTO items_fts(rowid, title, body)
  VALUES (new.rowid, new.title, new.body);
END;

CREATE TABLE tabs (
  id            TEXT PRIMARY KEY,
  jar_id        TEXT REFERENCES jars(id) ON DELETE CASCADE,
  item_id       TEXT REFERENCES items(id),
  opened_at     INTEGER NOT NULL,
  touched_at    INTEGER NOT NULL,
  seal_after    INTEGER                -- epoch; NULL = pinned, never seals
);

CREATE TABLE labels (
  id    TEXT PRIMARY KEY,
  name  TEXT NOT NULL UNIQUE
);

CREATE TABLE item_labels (
  item_id   TEXT REFERENCES items(id) ON DELETE CASCADE,
  label_id  TEXT REFERENCES labels(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, label_id)
);

CREATE TABLE recipes (
  id      TEXT PRIMARY KEY,
  jar_id  TEXT NOT NULL REFERENCES jars(id) ON DELETE CASCADE,
  name    TEXT NOT NULL,
  steps   TEXT NOT NULL               -- JSON array
);

CREATE TABLE embeddings (             -- filled in week 6
  item_id  TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
  vector   BLOB NOT NULL
);
