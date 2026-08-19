import { invoke } from "@tauri-apps/api/core";
import { Fragment, useCallback, useEffect, useRef, useState } from "react";
import { pantrySearch, type PantryRow } from "../lib/db";
import { domainOf, looksLikeUrl, normalizeUrl } from "../lib/format";
import { isEmptyQuery, parseQuery } from "../lib/query";
import { renderSnippet } from "../lib/snippet";
import { superellipseClip } from "../lib/superellipse";

/** A row from semantic_search (src-tauri/src/commands/engine.rs). */
interface SemanticRow {
  id: string;
  url: string | null;
  title: string;
  jar_id: string | null;
  jar_name: string | null;
  snippet: string;
  distance: number;
}

type Row = PantryRow & { semantic?: boolean };

/** Cosine-distance ceiling for "similar" — beyond this it's just noise. */
const SEMANTIC_MAX_DISTANCE = 0.62;

interface Props {
  query: string;
  activeJarId: string | null;
  activeJarHue: number | null; // 1..6, null = Brine
  onQueryChange(query: string): void;
  onOpen(url: string, keepOpen: boolean): void;
  onClose(): void;
}

/** Which tier kicker a row sits under. */
function rowGroup(row: Row, activeJarId: string | null): string {
  if (row.jar_id === null) return "Brine";
  if (activeJarId && row.jar_id === activeJarId) return row.jar_name ?? "This jar";
  return "Other jars";
}

/**
 * Ask the Pantry. A sibling of .nr-stage — the native pane hides while this
 * is up, because no DOM survives on top of it. Local results always rank
 * above the single web fallback row.
 */
export default function Palette({
  query,
  activeJarId,
  activeJarHue,
  onQueryChange,
  onOpen,
  onClose,
}: Props) {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [selected, setSelected] = useState(0);
  const lastFired = useRef(0);
  const generation = useRef(0);

  const run = useCallback(
    async (raw: string) => {
      const mine = ++generation.current;
      const parsed = parseQuery(raw);
      if (isEmptyQuery(parsed)) {
        setRows(null);
        return;
      }
      // Exact matches and semantic neighbours in parallel; semantic rows
      // merge BEHIND every exact match, never above (§11), and never
      // duplicate one.
      const [exact, semantic] = await Promise.all([
        pantrySearch(parsed, activeJarId),
        parsed.text
          ? invoke<SemanticRow[]>("semantic_search", {
              query: parsed.text,
              limit: 8,
            }).catch(() => [] as SemanticRow[])
          : Promise.resolve([] as SemanticRow[]),
      ]);
      const seen = new Set(exact.map((r) => r.id));
      const similar: Row[] = semantic
        .filter((s) => !seen.has(s.id) && s.distance <= SEMANTIC_MAX_DISTANCE)
        .map((s) => ({
          id: s.id,
          url: s.url,
          title: s.title,
          kind: "page" as const,
          jar_id: s.jar_id,
          jar_name: s.jar_name,
          tier: 3,
          snippet: s.snippet,
          semantic: true,
        }));
      // A slower earlier query must never overwrite a newer one.
      if (generation.current === mine) {
        setRows([...exact, ...similar]);
        setSelected(0);
      }
    },
    [activeJarId],
  );

  // Results as you type: the first keystroke fires immediately, the rest
  // trail on an 80ms debounce.
  useEffect(() => {
    const elapsed = performance.now() - lastFired.current;
    if (elapsed >= 80) {
      lastFired.current = performance.now();
      void run(query);
      return;
    }
    const t = window.setTimeout(() => {
      lastFired.current = performance.now();
      void run(query);
    }, 80 - elapsed);
    return () => window.clearTimeout(t);
  }, [query, run]);

  const text = parseQuery(query).text;
  const webTarget = text ? normalizeUrl(text) : "";
  const webLabel = looksLikeUrl(text)
    ? `Open ${text.trim()}`
    : `Search the web for “${text}”`;
  const localRows = rows ?? [];
  const optionCount = localRows.length + (webTarget ? 1 : 0);

  const openIndex = useCallback(
    (index: number, keepOpen: boolean) => {
      if (index < localRows.length) {
        const row = localRows[index];
        if (row.url) onOpen(row.url, keepOpen);
      } else if (webTarget) {
        onOpen(webTarget, keepOpen);
      }
    },
    [localRows, webTarget, onOpen],
  );

  const onKeyDown = useCallback(
    (event: React.KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
      } else if (event.key === "ArrowDown" && optionCount > 0) {
        event.preventDefault();
        setSelected((s) => (s + 1) % optionCount);
      } else if (event.key === "ArrowUp" && optionCount > 0) {
        event.preventDefault();
        setSelected((s) => (s - 1 + optionCount) % optionCount);
      } else if (event.key === "Enter" && optionCount > 0) {
        event.preventDefault();
        openIndex(selected, event.metaKey);
      }
    },
    [optionCount, selected, openIndex, onClose],
  );

  return (
    <div className="nr-palette" role="dialog" aria-label="Ask the Pantry">
      <button
        type="button"
        className="nr-palette__scrim"
        aria-label="Close"
        tabIndex={-1}
        onClick={onClose}
      />
      <div className="nr-palette__panel">
        <div className="nr-palette__inputrow">
          <span
            className="nr-palette__orb"
            style={{
              clipPath: superellipseClip(26, 4),
              background: `radial-gradient(circle at 35% 30%,
                color-mix(in oklab, ${activeJarHue ? `var(--nr-jar-${activeJarHue})` : "var(--nr-hue-brine)"} 55%, white),
                color-mix(in oklab, ${activeJarHue ? `var(--nr-jar-${activeJarHue})` : "var(--nr-hue-brine)"} 82%, black))`,
            }}
            aria-hidden="true"
          />
          <input
            className="nr-palette__input"
            value={query}
            placeholder="Ask the Pantry"
            aria-label="Ask the Pantry"
            autoFocus
            spellCheck={false}
            onChange={(event) => onQueryChange(event.target.value)}
            onKeyDown={onKeyDown}
          />
          <span className="nr-palette__kbd" aria-hidden="true">⌘K</span>
        </div>

        {rows === null ? (
          <div className="nr-palette__hint">
            <p>Search everything you've read. Narrow it with:</p>
            <p>
              <code>jar:name</code> <code>jar:brine</code>{" "}
              <code>kind:page</code> <code>is:sealed</code>{" "}
              <code>since:7d</code>
            </p>
          </div>
        ) : (
          <ul className="nr-palette__list" role="listbox">
            {localRows.length === 0 && (
              <li className="nr-palette__none">Nothing local matches.</li>
            )}
            {localRows.map((row, i) => {
              const group = rowGroup(row, activeJarId);
              const newGroup =
                i === 0 || group !== rowGroup(localRows[i - 1], activeJarId);
              return (
                <Fragment key={row.id}>
                  {newGroup && (
                    <li
                      className="nr-kicker nr-palette__kicker"
                      aria-hidden="true"
                    >
                      {group}
                    </li>
                  )}
                  <li>
                    <button
                      type="button"
                      className="nr-palette__row"
                      role="option"
                      aria-selected={i === selected}
                      data-selected={i === selected || undefined}
                      onMouseEnter={() => setSelected(i)}
                      onClick={(event) => openIndex(i, event.metaKey)}
                    >
                      <span className="nr-palette__toprow">
                        <span className="nr-palette__title">{row.title}</span>
                        <span className="nr-palette__where">
                          {row.semantic && (
                            <span className="nr-palette__similar">
                              similar ·{" "}
                            </span>
                          )}
                          {row.jar_name ?? (row.jar_id ? "" : "Brine")}
                          {row.url ? ` · ${domainOf(row.url)}` : ""}
                        </span>
                      </span>
                      <span className="nr-palette__snippet">
                        {renderSnippet(row.snippet)}
                      </span>
                    </button>
                  </li>
                </Fragment>
              );
            })}
            {webTarget && (
              <li>
                <button
                  type="button"
                  className="nr-palette__row nr-palette__row--web"
                  role="option"
                  aria-selected={selected === localRows.length}
                  data-selected={selected === localRows.length || undefined}
                  onMouseEnter={() => setSelected(localRows.length)}
                  onClick={(event) => openIndex(localRows.length, event.metaKey)}
                >
                  <span className="nr-palette__title">{webLabel}</span>
                  <span className="nr-palette__where">web</span>
                </button>
              </li>
            )}
          </ul>
        )}

        <footer className="nr-palette__keys" aria-hidden="true">
          {rows === null
            ? "↩ OPEN · ⌘↩ OPEN AND KEEP SEARCHING · ESC CLOSE"
            : "↩ OPEN · ⌘↩ OPEN AND KEEP SEARCHING · ESC CLOSE · FILTERS: jar:name kind:page is:sealed since:7d"}
        </footer>
      </div>
    </div>
  );
}
