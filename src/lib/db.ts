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

/** A jar with its live item count, as the shelf rail shows it. */
export interface Jar {
  id: string;
  name: string;
  hue: number; // 1..6, maps to --nr-jar-N
  created_at: number;
  item_count: number;
}

/** Unarchived jars, oldest first — shelf order is the order they were made. */
export async function listJars(): Promise<Jar[]> {
  return db().select<Jar[]>(
    `SELECT j.id, j.name, j.hue, j.created_at, count(i.id) AS item_count
     FROM jars j
     LEFT JOIN items i ON i.jar_id = j.id AND i.sealed_at IS NULL
     WHERE j.sealed_at IS NULL
     GROUP BY j.id
     ORDER BY j.created_at`,
  );
}

/** Create a jar; the hue rotates through --nr-jar-1..6 in creation order. */
export async function createJar(name: string): Promise<Jar> {
  const counted = await db().select<{ n: number }[]>(
    `SELECT count(*) AS n FROM jars`,
  );
  const jar: Jar = {
    id: crypto.randomUUID(),
    name,
    hue: ((counted[0]?.n ?? 0) % 6) + 1,
    created_at: Date.now(),
    item_count: 0,
  };
  await db().execute(
    `INSERT INTO jars (id, name, hue, created_at) VALUES ($1, $2, $3, $4)`,
    [jar.id, jar.name, jar.hue, jar.created_at],
  );
  return jar;
}

export async function renameJar(id: string, name: string): Promise<void> {
  await db().execute(`UPDATE jars SET name = $1 WHERE id = $2`, [name, id]);
}

/**
 * Delete a jar. Its items return to Brine via the schema's ON DELETE SET
 * NULL — nothing the user preserved is ever deleted by tidying.
 */
export async function deleteJar(id: string): Promise<void> {
  await db().execute(`DELETE FROM jars WHERE id = $1`, [id]);
}

/** An item row as the jar view lists it. */
export interface JarItemRow {
  id: string;
  kind: Item["kind"];
  url: string | null;
  title: string;
  touched_at: number;
  snippet: string;
}

/** A jar's items, newest touch first; the view groups them by kind. */
export async function jarItems(jarId: string): Promise<JarItemRow[]> {
  return db().select<JarItemRow[]>(
    `SELECT id, kind, url, title, touched_at,
            substr(coalesce(body, ''), 1, 240) AS snippet
     FROM items
     WHERE jar_id = $1 AND sealed_at IS NULL
     ORDER BY touched_at DESC
     LIMIT 500`,
  [jarId],
  );
}

/** Move items into a jar, or back to Brine (null). The Batch gesture. */
export async function moveItems(
  ids: string[],
  jarId: string | null,
): Promise<void> {
  if (ids.length === 0) return;
  const slots = ids.map((_, i) => `$${i + 2}`).join(", ");
  await db().execute(
    `UPDATE items SET jar_id = $1 WHERE id IN (${slots})`,
    [jarId, ...ids],
  );
}
