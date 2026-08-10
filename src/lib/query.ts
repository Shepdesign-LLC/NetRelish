/**
 * The Ask-the-Pantry query syntax. Filters are word-shaped tokens pulled out
 * of the typed text; whatever remains is the full-text search.
 *
 *   jar:meridian     items in jars whose name starts with "meridian"
 *   jar:brine        unsorted items only
 *   kind:page        page | note | task | file | message
 *   is:sealed        sealed items only (hidden by default)
 *   since:7d         touched in the last N h(ours) | d(ays) | w(eeks)
 */

export interface ParsedQuery {
  /** Free text left after filters are removed. */
  text: string;
  /** Jar name prefix, or "brine" for unsorted-only. */
  jar: string | null;
  kind: "page" | "note" | "task" | "file" | "message" | null;
  sealed: boolean;
  /** Lower bound on touched_at, epoch ms. */
  sinceMs: number | null;
}

const KINDS = new Set(["page", "note", "task", "file", "message"]);

const UNIT_MS: Record<string, number> = {
  h: 3_600_000,
  d: 86_400_000,
  w: 604_800_000,
};

export function parseQuery(raw: string, now = Date.now()): ParsedQuery {
  const parsed: ParsedQuery = {
    text: "",
    jar: null,
    kind: null,
    sealed: false,
    sinceMs: null,
  };
  const rest: string[] = [];

  for (const token of raw.trim().split(/\s+/)) {
    const [, key, value] = token.match(/^(jar|kind|is|since):(.*)$/) ?? [];
    if (key === "jar" && value) {
      parsed.jar = value.toLowerCase();
    } else if (key === "kind" && KINDS.has(value)) {
      parsed.kind = value as ParsedQuery["kind"];
    } else if (key === "is" && value === "sealed") {
      parsed.sealed = true;
    } else if (key === "since") {
      const m = value.match(/^(\d+)([hdw])$/);
      if (m) parsed.sinceMs = now - Number(m[1]) * UNIT_MS[m[2]];
      else rest.push(token); // not our syntax; treat as search text
    } else if (token) {
      rest.push(token);
    }
  }

  parsed.text = rest.join(" ");
  return parsed;
}

/** True when the query has nothing to act on at all. */
export function isEmptyQuery(q: ParsedQuery): boolean {
  return !q.text && !q.jar && !q.kind && !q.sealed && q.sinceMs === null;
}
