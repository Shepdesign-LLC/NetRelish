-- 002_sealing — Week 5. Tabs become real, jars get a shelf life, and a
-- sweep can always be undone because sealed tabs are marked, not deleted.
--
-- Shipped migrations are never edited. Schema changes get a new NNN file.

-- NULL = the app default (72 hours). Stored per jar so a fast-moving jar
-- can seal daily while a reference jar keeps tabs for weeks.
ALTER TABLE jars ADD COLUMN shelf_life_hours INTEGER;

-- A tab is preserved state, not a live process: enough to put the page
-- back exactly as it was. url/scroll live here (not on items) because they
-- are viewing state, not content.
ALTER TABLE tabs ADD COLUMN url TEXT;
ALTER TABLE tabs ADD COLUMN scroll_y REAL NOT NULL DEFAULT 0;
ALTER TABLE tabs ADD COLUMN position INTEGER NOT NULL DEFAULT 0;

-- A sweep stamps its batch id instead of deleting rows; Undo clears the
-- stamp and the whole batch stands back up, open, in order. Rows are
-- purged only after the 24h undo window lapses.
ALTER TABLE tabs ADD COLUMN sealed_batch TEXT;
ALTER TABLE tabs ADD COLUMN sealed_at INTEGER;

CREATE INDEX idx_tabs_open ON tabs(sealed_batch, position)
  WHERE sealed_batch IS NULL;
