/**
 * Field-level sync stamps.
 *
 * Every local write goes through here. `field_ts` maps column name -> epoch ms
 * of that column's last write, and the server merges field-by-field against it
 * (see supabase/migrations/0006_sync_push_conflict_needs_both_sides.sql). A
 * write path that builds its own SQL without these helpers is a bug: its
 * fields will look infinitely old and always lose the merge.
 */

/** Columns that are sync metadata, never themselves stamped. */
const META = new Set(["id", "updated_at", "deleted_at", "field_ts"]);

export interface Write {
  cols: string[];
  placeholders: string;
  vals: unknown[];
  setClause: string;
}

function build(all: Record<string, unknown>): Write {
  const cols = Object.keys(all);
  return {
    cols,
    placeholders: cols.map((_, i) => `$${i + 1}`).join(", "),
    vals: Object.values(all),
    setClause: cols.map((c, i) => `${c} = $${i + 1}`).join(", "),
  };
}

/** Build an INSERT's columns and values, including sync metadata. */
export function insertWrite(
  fields: Record<string, unknown>,
  now = Date.now(),
): Write {
  const ts: Record<string, number> = {};
  for (const k of Object.keys(fields)) if (!META.has(k)) ts[k] = now;
  return build({ ...fields, updated_at: now, field_ts: JSON.stringify(ts) });
}

/** Build an UPDATE's SET clause, merging new stamps over the previous ones. */
export function updateWrite(
  fields: Record<string, unknown>,
  prevFieldTs: string | null | undefined,
  now = Date.now(),
): Write {
  let ts: Record<string, number> = {};
  if (prevFieldTs) {
    try {
      const parsed: unknown = JSON.parse(prevFieldTs);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        ts = parsed as Record<string, number>;
      }
    } catch {
      // A corrupt stamp loses to anything, which is safer than throwing
      // mid-write and losing the user's edit entirely.
    }
  }
  for (const k of Object.keys(fields)) if (!META.has(k)) ts[k] = now;
  return build({ ...fields, updated_at: now, field_ts: JSON.stringify(ts) });
}

/** A tombstone. Deletes never remove rows — an absent row cannot replicate. */
export function tombstone(
  prevFieldTs: string | null | undefined,
  now = Date.now(),
): Write {
  return updateWrite({ deleted_at: now }, prevFieldTs, now);
}
