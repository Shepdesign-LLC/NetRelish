/**
 * The only module that writes SQL. Components call these functions and never
 * touch query strings themselves.
 *
 * The database itself is created, migrated and preloaded by the Rust side at
 * startup (tauri.conf.json > plugins > sql > preload), so this module attaches
 * with `Database.get` — calling `load` here would spin up a second connection
 * pool beside the one Rust extraction writes through.
 */
import Database from "@tauri-apps/plugin-sql";

/** Must match DB_URL in src-tauri/src/db.rs — it is the pool's lookup key. */
const DB_URL = "sqlite:netrelish.db";

/** Emitted by Rust after every extraction lands (src-tauri/src/extract.rs). */
export const BRINE_CHANGED = "brine:changed";

/** A row from `items`. Timestamps are epoch milliseconds. */
export interface Item {
  id: string;
  jar_id: string | null;
  kind: "page" | "note" | "task" | "file" | "message";
  url: string | null;
  title: string;
  body: string | null;
  meta: string | null;
  created_at: number;
  touched_at: number;
  sealed_at: number | null;
}

/** A Brine list row: an item plus the snippet the surface shows under it. */
export interface BrineRow {
  id: string;
  url: string | null;
  title: string;
  touched_at: number;
  snippet: string;
}

function db(): Database {
  return Database.get(DB_URL);
}

/** Everything browsed but not yet sorted, newest touch first. */
export async function brineList(limit = 200): Promise<BrineRow[]> {
  return db().select<BrineRow[]>(
    `SELECT id, url, title, touched_at,
            substr(coalesce(body, ''), 1, 240) AS snippet
     FROM items
     WHERE jar_id IS NULL AND kind = 'page' AND sealed_at IS NULL
     ORDER BY touched_at DESC
     LIMIT $1`,
    [limit],
  );
}

/**
 * Full-text search over Brine. Terms are quoted before they reach FTS5 so
 * user input can never be query syntax, and every term must match (AND).
 */
export async function brineSearch(
  query: string,
  limit = 200,
): Promise<BrineRow[]> {
  const match = query
    .split(/\s+/)
    .filter(Boolean)
    .map((term) => `"${term.replaceAll('"', '""')}"`)
    .join(" ");
  if (!match) return brineList(limit);

  return db().select<BrineRow[]>(
    `SELECT items.id, items.url, items.title, items.touched_at,
            snippet(items_fts, 1, '', '', ' … ', 16) AS snippet
     FROM items_fts
     JOIN items ON items.rowid = items_fts.rowid
     WHERE items_fts MATCH $1
       AND items.jar_id IS NULL AND items.kind = 'page'
       AND items.sealed_at IS NULL
     ORDER BY rank
     LIMIT $2`,
    [match, limit],
  );
}

/** How many unsorted pages Brine holds; shown on the rail tile. */
export async function brineCount(): Promise<number> {
  const rows = await db().select<{ n: number }[]>(
    `SELECT count(*) AS n FROM items
     WHERE jar_id IS NULL AND kind = 'page' AND sealed_at IS NULL`,
  );
  return rows[0]?.n ?? 0;
}
