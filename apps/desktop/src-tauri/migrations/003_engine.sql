-- 003_engine — Week 6. The correction layer: what the user said about our
-- suggestions. Rejections weight future scoring — the engine learns THEIR
-- boundaries, not a generic notion of topic.
--
-- (The embeddings table itself shipped in 001 — the schema was load-bearing
-- from day one.)

CREATE TABLE suggestion_feedback (
  item_id  TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  jar_id   TEXT NOT NULL REFERENCES jars(id) ON DELETE CASCADE,
  action   TEXT NOT NULL CHECK (action IN ('accepted', 'rejected')),
  at       INTEGER NOT NULL,
  PRIMARY KEY (item_id, jar_id)
);
