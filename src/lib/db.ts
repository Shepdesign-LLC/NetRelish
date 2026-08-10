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
import { type ParsedQuery } from "./query";

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
  shelf_life_hours: number | null; // NULL = app default (72)
  item_count: number;
}

/** Unarchived jars, oldest first — shelf order is the order they were made. */
export async function listJars(): Promise<Jar[]> {
  return db().select<Jar[]>(
    `SELECT j.id, j.name, j.hue, j.created_at, j.shelf_life_hours,
            count(i.id) AS item_count
     FROM jars j
     LEFT JOIN items i ON i.jar_id = j.id
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
    shelf_life_hours: null,
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
  sealed_at: number | null;
  meta: string | null;
  snippet: string;
}

/** A jar's items, newest touch first; the view groups them by kind, with
 *  sealed items in their own group — sealing tidies INTO the jar, so its
 *  view is exactly where they must remain findable. */
export async function jarItems(jarId: string): Promise<JarItemRow[]> {
  return db().select<JarItemRow[]>(
    `SELECT id, kind, url, title, touched_at, sealed_at, meta,
            substr(coalesce(body, ''), 1, 240) AS snippet
     FROM items
     WHERE jar_id = $1
     ORDER BY touched_at DESC
     LIMIT 500`,
  [jarId],
  );
}

/** Snippet highlight delimiters — control characters no page text uses,
 *  so the UI can split on them without ever trusting HTML. */
export const MARK_START = "\u0001";
export const MARK_END = "\u0002";

/** One Ask-the-Pantry result. tier: 0 active jar, 1 other jars, 2 Brine. */
export interface PantryRow {
  id: string;
  url: string | null;
  title: string;
  kind: Item["kind"];
  jar_id: string | null;
  jar_name: string | null;
  tier: number;
  snippet: string;
}

/**
 * Ask the Pantry. Local results ranked active jar → other jars → Brine;
 * best full-text match first within each. The web fallback is the UI's
 * job — it must never outrank anything local, so it never enters SQL.
 */
export async function pantrySearch(
  q: ParsedQuery,
  activeJarId: string | null,
  limit = 40,
): Promise<PantryRow[]> {
  const where: string[] = [];
  const params: unknown[] = [];
  const bind = (value: unknown): string => {
    params.push(value);
    return `$${params.length}`;
  };

  const tier = `CASE
      WHEN ${bind(activeJarId)} IS NOT NULL AND items.jar_id = $1 THEN 0
      WHEN items.jar_id IS NOT NULL THEN 1
      ELSE 2 END`;

  where.push(`items.sealed_at IS ${q.sealed ? "NOT NULL" : "NULL"}`);
  if (q.kind) where.push(`items.kind = ${bind(q.kind)}`);
  if (q.jar === "brine") {
    where.push(`items.jar_id IS NULL`);
  } else if (q.jar) {
    where.push(
      `items.jar_id IN (SELECT id FROM jars WHERE name LIKE ${bind(q.jar + "%")})`,
    );
  }
  if (q.sinceMs !== null) where.push(`items.touched_at >= ${bind(q.sinceMs)}`);
  if (q.label) {
    where.push(
      `items.id IN (SELECT il.item_id FROM item_labels il
        JOIN labels l ON l.id = il.label_id WHERE l.name = ${bind(q.label)})`,
    );
  }

  if (q.text) {
    const match = q.text
      .split(/\s+/)
      .filter(Boolean)
      .map((term) => `"${term.replaceAll('"', '""')}"`)
      .join(" ");
    return db().select<PantryRow[]>(
      `SELECT items.id, items.url, items.title, items.kind, items.jar_id,
              jars.name AS jar_name, ${tier} AS tier,
              snippet(items_fts, 1, '${MARK_START}', '${MARK_END}', ' … ', 14) AS snippet
       FROM items_fts
       JOIN items ON items.rowid = items_fts.rowid
       LEFT JOIN jars ON jars.id = items.jar_id
       WHERE items_fts MATCH ${bind(match)} AND ${where.join(" AND ")}
       ORDER BY tier, rank
       LIMIT ${bind(limit)}`,
      params,
    );
  }

  // Filter-only browse: no text to match, newest touch first.
  return db().select<PantryRow[]>(
    `SELECT items.id, items.url, items.title, items.kind, items.jar_id,
            jars.name AS jar_name, ${tier} AS tier,
            substr(coalesce(items.body, ''), 1, 200) AS snippet
     FROM items
     LEFT JOIN jars ON jars.id = items.jar_id
     WHERE ${where.join(" AND ")}
     ORDER BY tier, items.touched_at DESC
     LIMIT ${bind(limit)}`,
    params,
  );
}

/* ---------------------------------------------------------------------------
   Tabs and sealing (week 5). A tab is preserved state, not a live process:
   only the active tab occupies the native pane. Sealed tabs keep their rows
   (stamped with a batch id) so Undo can stand the whole sweep back up.
--------------------------------------------------------------------------- */

export const DEFAULT_SHELF_LIFE_HOURS = 72;

export interface Tab {
  id: string;
  jar_id: string | null;
  url: string | null;
  title: string; // resolved from items by url; "New tab" when itemless
  scroll_y: number;
  position: number;
  touched_at: number;
  seal_after: number | null; // NULL = pinned, never seals
}

/** Open tabs in strip order. Title comes from the item row when one exists. */
export async function tabsList(): Promise<Tab[]> {
  return db().select<Tab[]>(
    `SELECT t.id, t.jar_id, t.url, t.scroll_y, t.position, t.touched_at,
            t.seal_after, coalesce(i.title, t.url, 'New tab') AS title
     FROM tabs t
     LEFT JOIN items i ON i.url = t.url
     WHERE t.sealed_batch IS NULL
     ORDER BY t.position`,
  );
}

/** A jar's shelf life in ms, falling back to the app default. */
async function shelfLifeMs(jarId: string | null): Promise<number> {
  if (jarId) {
    const rows = await db().select<{ h: number | null }[]>(
      `SELECT shelf_life_hours AS h FROM jars WHERE id = $1`,
      [jarId],
    );
    if (rows[0]?.h) return rows[0].h * 3_600_000;
  }
  return DEFAULT_SHELF_LIFE_HOURS * 3_600_000;
}

export async function tabCreate(
  jarId: string | null,
  url: string | null,
): Promise<Tab> {
  const now = Date.now();
  const tab: Tab = {
    id: crypto.randomUUID(),
    jar_id: jarId,
    url,
    title: url ?? "New tab",
    scroll_y: 0,
    position: now, // creation order; sparse values keep reordering trivial
    touched_at: now,
    seal_after: now + (await shelfLifeMs(jarId)),
  };
  await db().execute(
    `INSERT INTO tabs (id, jar_id, url, scroll_y, position, opened_at,
                       touched_at, seal_after)
     VALUES ($1, $2, $3, 0, $4, $5, $5, $6)`,
    [tab.id, tab.jar_id, tab.url, tab.position, now, tab.seal_after],
  );
  return tab;
}

/** Touching a tab restarts its shelf life (unless pinned) and can move it
 *  to a new address. */
export async function tabTouch(
  id: string,
  url: string | null | undefined,
  jarId: string | null,
): Promise<void> {
  const now = Date.now();
  const life = await shelfLifeMs(jarId);
  await db().execute(
    `UPDATE tabs SET
       touched_at = $1,
       url = coalesce($2, url),
       seal_after = CASE WHEN seal_after IS NULL THEN NULL ELSE $3 END
     WHERE id = $4`,
    [now, url ?? null, now + life, id],
  );
}

export async function tabSetScroll(id: string, y: number): Promise<void> {
  await db().execute(`UPDATE tabs SET scroll_y = $1 WHERE id = $2`, [y, id]);
}

/** Plain close (⌘W-style): the page is already preserved; the tab just goes. */
export async function tabClose(id: string): Promise<void> {
  await db().execute(`DELETE FROM tabs WHERE id = $1`, [id]);
}

/** Pin = seal_after NULL, the schema's own idiom for "never seals". */
export async function tabSetPinned(
  id: string,
  jarId: string | null,
  pinned: boolean,
): Promise<void> {
  if (pinned) {
    await db().execute(`UPDATE tabs SET seal_after = NULL WHERE id = $1`, [id]);
  } else {
    await db().execute(`UPDATE tabs SET seal_after = $1 WHERE id = $2`, [
      Date.now() + (await shelfLifeMs(jarId)),
      id,
    ]);
  }
}

/** The most recent sealed tab for a URL — how a jar reopen knows where the
 *  reader left off. */
export async function lastSealedScroll(url: string): Promise<number> {
  const rows = await db().select<{ scroll_y: number }[]>(
    `SELECT scroll_y FROM tabs
     WHERE url = $1 AND sealed_batch IS NOT NULL
     ORDER BY sealed_at DESC LIMIT 1`,
    [url],
  );
  return rows[0]?.scroll_y ?? 0;
}

/** Reopening something sealed makes it live again. */
export async function unsealUrl(url: string): Promise<void> {
  await db().execute(
    `UPDATE items SET sealed_at = NULL WHERE url = $1`,
    [url],
  );
}

export interface SweepResult {
  batchId: string;
  count: number;
  /** Jar names swept into, for the toast; empty string stands for Brine. */
  jarNames: string[];
  sealedTabIds: string[];
}

/**
 * The sweep. Set-based SQL throughout — 200 tabs is four statements, not
 * 200 round trips, so the UI never freezes.
 *
 * A tab is overdue when its seal_after has passed. It seals only if its
 * page is already in `items` — no tab ever closes before its content is
 * preserved. Deny-listed pages are the one exception: the user asked for
 * them to never be kept, so their tabs close without a trace. Overdue tabs
 * whose extraction failed stay open for the next sweep to retry.
 */
export async function sweepDue(denyPatterns: string[]): Promise<SweepResult | null> {
  const now = Date.now();
  const overdue = await db().select<
    { id: string; url: string | null; jar_id: string | null; jar_name: string | null }[]
  >(
    `SELECT t.id, t.url, t.jar_id, j.name AS jar_name
     FROM tabs t LEFT JOIN jars j ON j.id = t.jar_id
     WHERE t.sealed_batch IS NULL
       AND t.seal_after IS NOT NULL AND t.seal_after < $1`,
    [now],
  );
  if (overdue.length === 0) return null;

  const denied = (url: string) => {
    const lower = url.toLowerCase();
    return denyPatterns.some((p) => lower.includes(p));
  };
  const preserved = await db().select<{ url: string }[]>(
    `SELECT url FROM items WHERE url IN (SELECT url FROM tabs
       WHERE sealed_batch IS NULL AND seal_after IS NOT NULL AND seal_after < $1)`,
    [now],
  );
  const inItems = new Set(preserved.map((r) => r.url));

  const sealable = overdue.filter(
    (t) => !t.url || inItems.has(t.url) || denied(t.url),
  );
  if (sealable.length === 0) return null;

  const batchId = crypto.randomUUID();
  const ids = sealable.map((t) => t.id);
  const slots = ids.map((_, i) => `$${i + 3}`).join(", ");

  // Stamp the batch. Rows survive for Undo; the strip filters them out.
  await db().execute(
    `UPDATE tabs SET sealed_batch = $1, sealed_at = $2 WHERE id IN (${slots})`,
    [batchId, now, ...ids],
  );
  // Seal the items, and file Brine items into their tab's jar — that is
  // what "preserve an untouched tab into its jar" means. Items the user
  // already filed somewhere else are not second-guessed.
  await db().execute(
    `UPDATE items SET
       sealed_at = coalesce(sealed_at, $1),
       jar_id = coalesce(jar_id,
         (SELECT t.jar_id FROM tabs t
          WHERE t.url = items.url AND t.sealed_batch = $2
          ORDER BY t.sealed_at DESC LIMIT 1))
     WHERE url IN (SELECT url FROM tabs WHERE sealed_batch = $2)`,
    [now, batchId],
  );

  const jarNames = [...new Set(sealable.map((t) => t.jar_name ?? ""))];
  return { batchId, count: sealable.length, jarNames, sealedTabIds: ids };
}

/** Undo a sweep: the whole batch stands back up, open, in strip order. */
export async function undoSweep(batchId: string): Promise<number> {
  await db().execute(
    `UPDATE items SET sealed_at = NULL
     WHERE url IN (SELECT url FROM tabs WHERE sealed_batch = $1)`,
    [batchId],
  );
  const result = await db().execute(
    `UPDATE tabs SET sealed_batch = NULL, sealed_at = NULL,
       seal_after = $1
     WHERE sealed_batch = $2`,
    [Date.now() + DEFAULT_SHELF_LIFE_HOURS * 3_600_000, batchId],
  );
  return result.rowsAffected;
}

export interface SweepBatch {
  batch_id: string;
  sealed_at: number;
  count: number;
  titles: string;
}

/** Recent sweeps still inside the 24h undo window, newest first. */
export async function listSweeps(): Promise<SweepBatch[]> {
  return db().select<SweepBatch[]>(
    `SELECT t.sealed_batch AS batch_id, max(t.sealed_at) AS sealed_at,
            count(*) AS count,
            group_concat(coalesce(i.title, t.url), ' · ') AS titles
     FROM tabs t LEFT JOIN items i ON i.url = t.url
     WHERE t.sealed_batch IS NOT NULL
     GROUP BY t.sealed_batch
     ORDER BY sealed_at DESC`,
  );
}

/** Sealed tab rows older than the undo window have served their purpose. */
export async function purgeExpiredSweeps(): Promise<void> {
  await db().execute(
    `DELETE FROM tabs WHERE sealed_batch IS NOT NULL AND sealed_at < $1`,
    [Date.now() - 24 * 3_600_000],
  );
}

export async function setJarShelfLife(
  id: string,
  hours: number | null,
): Promise<void> {
  await db().execute(`UPDATE jars SET shelf_life_hours = $1 WHERE id = $2`, [
    hours,
    id,
  ]);
}

/* ---------------------------------------------------------------------------
   Recipes (week 7): runnable workflows attached to a jar. Steps are JSON —
   readable, hand-editable, recorded rather than authored.
--------------------------------------------------------------------------- */

export interface Recipe {
  id: string;
  jar_id: string;
  name: string;
  steps: string; // JSON array of RecipeStep (src/lib/recipes.ts)
}

export async function listRecipes(jarId: string): Promise<Recipe[]> {
  return db().select<Recipe[]>(
    `SELECT id, jar_id, name, steps FROM recipes WHERE jar_id = $1 ORDER BY name`,
    [jarId],
  );
}

export async function createRecipe(
  jarId: string,
  name: string,
  steps: string,
): Promise<Recipe> {
  const recipe: Recipe = { id: crypto.randomUUID(), jar_id: jarId, name, steps };
  await db().execute(
    `INSERT INTO recipes (id, jar_id, name, steps) VALUES ($1, $2, $3, $4)`,
    [recipe.id, recipe.jar_id, recipe.name, recipe.steps],
  );
  return recipe;
}

export async function updateRecipeSteps(id: string, steps: string): Promise<void> {
  await db().execute(`UPDATE recipes SET steps = $1 WHERE id = $2`, [steps, id]);
}

export async function deleteRecipe(id: string): Promise<void> {
  await db().execute(`DELETE FROM recipes WHERE id = $1`, [id]);
}

/** A markdown note in a jar; returns the new item's id. */
export async function createNoteItem(
  jarId: string | null,
  text: string,
): Promise<string> {
  const now = Date.now();
  const id = crypto.randomUUID();
  await db().execute(
    `INSERT INTO items (id, jar_id, kind, title, body, created_at, touched_at)
     VALUES ($1, $2, 'note', $3, $4, $5, $5)`,
    [id, jarId, text.split("\n")[0].slice(0, 120) || "Note", text, now],
  );
  return id;
}

/* ---------------------------------------------------------------------------
   Notes, tasks, files, labels (week 8). All of them are rows in `items` —
   the schema's one big bet — so search, jars and the engine already know
   how to hold them.
--------------------------------------------------------------------------- */

export async function updateNote(id: string, text: string): Promise<void> {
  await db().execute(
    `UPDATE items SET title = $1, body = $2, touched_at = $3 WHERE id = $4`,
    [text.split("\n")[0].slice(0, 120) || "Note", text, Date.now(), id],
  );
}

export async function getItem(id: string): Promise<Item | null> {
  const rows = await db().select<Item[]>(
    `SELECT * FROM items WHERE id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

/** A task: meta carries { due: epoch-ms | null, done: bool }. */
export async function createTask(
  jarId: string | null,
  title: string,
  due: number | null,
): Promise<void> {
  const now = Date.now();
  await db().execute(
    `INSERT INTO items (id, jar_id, kind, title, meta, created_at, touched_at)
     VALUES ($1, $2, 'task', $3, $4, $5, $5)`,
    [crypto.randomUUID(), jarId, title, JSON.stringify({ due, done: false }), now],
  );
}

export async function toggleTaskDone(id: string): Promise<void> {
  await db().execute(
    `UPDATE items SET
       meta = json_set(coalesce(meta, '{}'), '$.done',
                       NOT coalesce(json_extract(meta, '$.done'), 0)),
       touched_at = $1
     WHERE id = $2`,
    [Date.now(), id],
  );
}

const TEXT_EXTENSIONS = new Set([
  "txt", "md", "markdown", "ts", "tsx", "js", "jsx", "rs", "css", "html",
  "json", "yaml", "yml", "toml", "sh", "py", "sql", "csv",
]);

/** Text files under this size get their content into `body` for search. */
export function isSearchableFile(name: string): boolean {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  return TEXT_EXTENSIONS.has(ext);
}

/** A dropped file becomes kind='file'; url holds its file:// address. */
export async function createFileItem(
  jarId: string | null,
  path: string,
  body: string | null,
): Promise<void> {
  const now = Date.now();
  const name = path.split("/").pop() ?? path;
  const url = `file://${path}`;
  await db().execute(
    `INSERT INTO items (id, jar_id, kind, url, title, body, meta, created_at, touched_at)
     VALUES ($1, $2, 'file', $3, $4, $5, $6, $7, $7)
     ON CONFLICT(url) WHERE url IS NOT NULL DO UPDATE SET
       jar_id = excluded.jar_id, body = excluded.body,
       meta = excluded.meta, touched_at = excluded.touched_at`,
    [crypto.randomUUID(), jarId, url, name, body, JSON.stringify({ path }), now],
  );
}

/** Mark a watched file's fate: still there, changed, or gone. */
export async function markFileStatus(
  id: string,
  missing: boolean,
): Promise<void> {
  await db().execute(
    `UPDATE items SET meta = json_set(coalesce(meta, '{}'), '$.missing', $1)
     WHERE id = $2`,
    [missing, id],
  );
}

export async function listFileItems(): Promise<
  { id: string; path: string }[]
> {
  return db().select<{ id: string; path: string }[]>(
    `SELECT id, json_extract(meta, '$.path') AS path
     FROM items WHERE kind = 'file' AND path IS NOT NULL`,
  );
}

/* Labels: create, assign, filter (§6 tables from day one). */

export interface Label {
  id: string;
  name: string;
  /** How many items wear it, for the chip row. */
  uses: number;
}

export async function listLabels(): Promise<Label[]> {
  return db().select<Label[]>(
    `SELECT l.id, l.name, count(il.item_id) AS uses
     FROM labels l LEFT JOIN item_labels il ON il.label_id = l.id
     GROUP BY l.id ORDER BY l.name`,
  );
}

/** Assign a label (created on first use) to a set of items. */
export async function assignLabel(
  name: string,
  itemIds: string[],
): Promise<void> {
  const clean = name.trim().toLowerCase();
  if (!clean || itemIds.length === 0) return;
  await db().execute(
    `INSERT OR IGNORE INTO labels (id, name) VALUES ($1, $2)`,
    [crypto.randomUUID(), clean],
  );
  for (const itemId of itemIds) {
    await db().execute(
      `INSERT OR IGNORE INTO item_labels (item_id, label_id)
       SELECT $1, id FROM labels WHERE name = $2`,
      [itemId, clean],
    );
  }
}

export async function unassignLabel(
  name: string,
  itemIds: string[],
): Promise<void> {
  for (const itemId of itemIds) {
    await db().execute(
      `DELETE FROM item_labels WHERE item_id = $1
       AND label_id IN (SELECT id FROM labels WHERE name = $2)`,
      [itemId, name.trim().toLowerCase()],
    );
  }
}

/** Item ids in a jar wearing a given label — the jar view's filter. */
export async function itemIdsWithLabel(name: string): Promise<string[]> {
  const rows = await db().select<{ item_id: string }[]>(
    `SELECT il.item_id FROM item_labels il
     JOIN labels l ON l.id = il.label_id WHERE l.name = $1`,
    [name.trim().toLowerCase()],
  );
  return rows.map((r) => r.item_id);
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
