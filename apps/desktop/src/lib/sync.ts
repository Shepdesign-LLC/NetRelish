/**
 * P4 Stage C — the sync engine.
 *
 * The database arbitrates. This module decides WHAT to send and WHEN; it never
 * decides who wins a conflict. That rule lives in one plpgsql function per
 * table (supabase/migrations/0005–0009), because three clients each
 * implementing a merge would drift and then corrupt each other.
 *
 * Two clocks, and keeping them apart is the whole correctness story:
 *
 *   field_ts / client_ts  CLIENT INTENT — when the user changed this thing.
 *                         Compared against other clients' intent to pick a
 *                         winner.
 *   updated_at            SERVER RECEIPT — set by the server with now(), used
 *                         only as the pull cursor. A wrong client clock can
 *                         therefore neither win forever nor hide a row.
 *
 * Local timestamps are epoch milliseconds; Postgres uses timestamptz. The
 * conversion happens here at the boundary and nowhere else.
 */

import Database from "@tauri-apps/plugin-sql";
import { createNetRelishClient, type NetRelishClient } from "@netrelish/core";

const DB_URL = "sqlite:netrelish.db";

let _db: Database | null = null;
async function db(): Promise<Database> {
  if (!_db) _db = await Database.get(DB_URL);
  return _db;
}

let _remote: NetRelishClient | null = null;
export function remote(): NetRelishClient {
  if (!_remote) {
    const url = import.meta.env.VITE_SUPABASE_URL;
    const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
    if (!url || !key) {
      throw new Error(
        "Sync is not configured: set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY " +
          "in apps/desktop/.env.local",
      );
    }
    _remote = createNetRelishClient(url, key);
  }
  return _remote;
}

// --- table specs ----------------------------------------------------------

type Mode = "field" | "row";

/** Pinned so a typo in SPECS fails the build rather than at runtime. */
type TableName =
  | "jars" | "labels" | "items" | "item_labels"
  | "tabs" | "recipes" | "suggestion_feedback";
type RpcName =
  | "sync_push" | "sync_push_jars" | "sync_push_labels" | "sync_push_recipes"
  | "sync_push_tabs" | "sync_push_item_labels" | "sync_push_feedback";

interface Spec {
  /** Local table name; identical remotely. */
  table: TableName;
  /** Field-level tables carry field_ts; row-level ones carry client_ts. */
  mode: Mode;
  /** Primary key columns. Composite for the two join-shaped tables. */
  pk: string[];
  /** Columns that travel, excluding sync metadata. */
  cols: string[];
  /** Columns holding epoch-ms timestamps that must become ISO strings. */
  times: string[];
  /** Columns stored as JSON text locally but jsonb remotely. */
  json: string[];
  /** The server-side merge function. */
  rpc: RpcName;
}

/**
 * FOREIGN KEY ORDER. Both push and pull walk this list in order so a parent
 * always exists before a child references it — a jar before its items, a label
 * before an item_labels row. Reordering this array will produce FK violations
 * that only appear on a first sync into an empty account.
 */
const SPECS: Spec[] = [
  {
    table: "jars", mode: "field", pk: ["id"], rpc: "sync_push_jars",
    cols: ["id", "name", "hue", "created_at", "sealed_at", "shelf_life_hours"],
    times: ["created_at", "sealed_at"], json: [],
  },
  {
    table: "labels", mode: "field", pk: ["id"], rpc: "sync_push_labels",
    cols: ["id", "name"], times: [], json: [],
  },
  {
    table: "items", mode: "field", pk: ["id"], rpc: "sync_push",
    cols: ["id", "jar_id", "kind", "url", "title", "body", "meta",
           "created_at", "touched_at", "sealed_at"],
    times: ["created_at", "touched_at", "sealed_at"], json: ["meta"],
  },
  {
    table: "item_labels", mode: "row", pk: ["item_id", "label_id"],
    rpc: "sync_push_item_labels",
    cols: ["item_id", "label_id"], times: [], json: [],
  },
  {
    table: "tabs", mode: "field", pk: ["id"], rpc: "sync_push_tabs",
    cols: ["id", "jar_id", "item_id", "url", "scroll_y", "position",
           "opened_at", "touched_at", "seal_after", "sealed_at", "sealed_batch"],
    times: ["opened_at", "touched_at", "seal_after", "sealed_at"], json: [],
  },
  {
    table: "recipes", mode: "field", pk: ["id"], rpc: "sync_push_recipes",
    cols: ["id", "jar_id", "name", "steps"], times: [], json: ["steps"],
  },
  {
    table: "suggestion_feedback", mode: "row", pk: ["item_id", "jar_id"],
    rpc: "sync_push_feedback",
    cols: ["item_id", "jar_id", "action", "at"], times: ["at"], json: [],
  },
];

// --- conversion -----------------------------------------------------------

const iso = (ms: number | null | undefined): string | null =>
  ms === null || ms === undefined ? null : new Date(ms).toISOString();

const ms = (s: string | null | undefined): number | null =>
  s === null || s === undefined ? null : new Date(s).getTime();

/** field_ts is {column: epoch-ms} locally and {column: ISO} remotely. */
function stampsOut(raw: string | null): Record<string, string> {
  if (!raw) return {};
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { return {}; }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(parsed as Record<string, unknown>)) {
    if (typeof v === "number") out[k] = new Date(v).toISOString();
  }
  return out;
}

function stampsIn(obj: unknown): string {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return "{}";
  const out: Record<string, number> = {};
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    if (typeof v === "string") out[k] = new Date(v).getTime();
  }
  return JSON.stringify(out);
}

type Row = Record<string, unknown>;

function toRemote(spec: Spec, row: Row): Row {
  const out: Row = {};
  for (const c of spec.cols) {
    const v = row[c];
    if (spec.times.includes(c)) out[c] = iso(v as number | null);
    else if (spec.json.includes(c)) out[c] = v ? JSON.parse(String(v)) : null;
    else out[c] = v ?? null;
  }
  out.deleted_at = iso(row.deleted_at as number | null);
  if (spec.mode === "field") {
    out.field_ts = stampsOut(row.field_ts as string | null);
  } else {
    // Row-level tables have no field_ts. updated_at is the client's own
    // assertion time here — the server stores it as client_ts and compares
    // intent to intent (see migration 0009).
    out.client_ts = iso(row.updated_at as number | null);
  }
  return out;
}

function toLocal(spec: Spec, row: Row): Row {
  const out: Row = {};
  for (const c of spec.cols) {
    const v = row[c];
    if (spec.times.includes(c)) out[c] = ms(v as string | null);
    else if (spec.json.includes(c)) out[c] = v === null || v === undefined ? null : JSON.stringify(v);
    else out[c] = v ?? null;
  }
  out.deleted_at = ms(row.deleted_at as string | null);
  out.updated_at = ms(row.updated_at as string | null);
  if (spec.mode === "field") out.field_ts = stampsIn(row.field_ts);
  return out;
}

// --- cursors --------------------------------------------------------------

async function cursor(table: string): Promise<number> {
  const r = await (await db()).select<{ last_synced_at: number }[]>(
    `SELECT last_synced_at FROM sync_cursors WHERE table_name = $1`, [table],
  );
  return r[0]?.last_synced_at ?? 0;
}

async function setCursor(table: string, at: number): Promise<void> {
  await (await db()).execute(
    `INSERT INTO sync_cursors (table_name, last_synced_at) VALUES ($1, $2)
     ON CONFLICT(table_name) DO UPDATE SET last_synced_at = excluded.last_synced_at`,
    [table, at],
  );
}

/**
 * A local Pantry belongs to whichever account last synced it. If a different
 * account signs in on this Mac, every cursor is meaningless — pulling
 * `updated_at > cursor` against a stranger's rows would interleave two
 * people's Pantries into one database. Reset and re-pull from zero.
 */
async function guardAccount(accountId: string): Promise<void> {
  const d = await db();
  const r = await d.select<{ value: string }[]>(
    `SELECT value FROM sync_meta WHERE key = 'account_id'`,
  );
  const known = r[0]?.value;
  if (known && known !== accountId) {
    await d.execute(`UPDATE sync_cursors SET last_synced_at = 0`);
  }
  await d.execute(
    `INSERT INTO sync_meta (key, value) VALUES ('account_id', $1)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
    [accountId],
  );
}

// --- push / pull ----------------------------------------------------------

async function pushTable(spec: Spec): Promise<number> {
  const since = await cursor(spec.table);
  const rows = await (await db()).select<Row[]>(
    `SELECT * FROM ${spec.table} WHERE updated_at > $1 ORDER BY updated_at`,
    [since],
  );
  if (rows.length === 0) return 0;

  const payload = rows.map((r) => toRemote(spec, r));
  const args: Record<string, unknown> = { payload };
  // Only items forks prose, and only it needs to know when the client last
  // agreed with the server.
  if (spec.mode === "field") args.client_synced_at = iso(since) ?? new Date(0).toISOString();

  // The generated types name each function individually; this loop dispatches
  // over a list, so the call is necessarily dynamic. The cast is confined to
  // this one line and the names it can take are pinned by RpcName above.
  const rpc = remote().rpc as unknown as (
    fn: RpcName,
    args: Record<string, unknown>,
  ) => Promise<{ error: { message: string } | null }>;
  const { error } = await rpc(spec.rpc, args);
  if (error) throw new Error(`push ${spec.table}: ${error.message}`);
  return rows.length;
}

async function pullTable(spec: Spec): Promise<number> {
  const since = await cursor(spec.table);
  // Same reason as pushTable's rpc cast: the table is chosen at runtime from
  // SPECS, which the generated per-table types cannot model.
  const from = remote().from as (
    t: string,
  ) => ReturnType<NetRelishClient["from"]>;
  const { data, error } = await from(spec.table)
    .select("*")
    .gt("updated_at", iso(since) ?? new Date(0).toISOString())
    .order("updated_at", { ascending: true });
  if (error) throw new Error(`pull ${spec.table}: ${error.message}`);
  if (!data || data.length === 0) return 0;

  const d = await db();
  let high = since;
  for (const remoteRow of data as Row[]) {
    const local = toLocal(spec, remoteRow);
    const cols = Object.keys(local);
    const ph = cols.map((_, i) => `$${i + 1}`).join(", ");
    const set = cols
      .filter((c) => !spec.pk.includes(c))
      .map((c) => `${c} = excluded.${c}`)
      .join(", ");
    await d.execute(
      `INSERT INTO ${spec.table} (${cols.join(", ")}) VALUES (${ph})
       ON CONFLICT(${spec.pk.join(", ")}) DO UPDATE SET ${set}`,
      cols.map((c) => local[c]),
    );
    const u = local.updated_at as number;
    if (u > high) high = u;
  }
  await setCursor(spec.table, high);
  return data.length;
}

export interface SyncResult {
  pushed: Record<string, number>;
  pulled: Record<string, number>;
  error?: string;
}

/**
 * One full cycle. Push before pull so local intent reaches the server before
 * we ask what changed — otherwise a local edit made since the last sync would
 * be overwritten by the pull and lost before it was ever sent.
 */
export async function syncNow(accountId: string): Promise<SyncResult> {
  const result: SyncResult = { pushed: {}, pulled: {} };
  try {
    await guardAccount(accountId);
    for (const spec of SPECS) result.pushed[spec.table] = await pushTable(spec);
    for (const spec of SPECS) result.pulled[spec.table] = await pullTable(spec);
  } catch (e) {
    // Offline is a normal state, not an error. A failed cycle leaves every
    // cursor untouched, so nothing is lost and the next attempt retries it.
    result.error = e instanceof Error ? e.message : String(e);
  }
  return result;
}
