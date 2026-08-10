import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useCallback, useEffect, useRef, useState } from "react";
import { BRINE_CHANGED, brineSearch, type BrineRow } from "../lib/db";
import { domainOf } from "../lib/format";
import SweepsPanel from "./SweepsPanel";

interface Props {
  activeJarName: string | null;
  selection: string[];
  refreshToken: number;
  onSelectionChange(selection: string[]): void;
  onOpen(url: string): void;
  onJarSelection(): void;
  onUndoSweep(batchId: string): void;
}

/**
 * Everything browsed but not yet sorted, newest first. Rendered in the stage
 * while the native preview pane is hidden — never on top of it (nothing
 * drawn inside .nr-stage survives a visible page).
 */
export default function BrineView({
  activeJarName,
  selection,
  refreshToken,
  onSelectionChange,
  onOpen,
  onJarSelection,
  onUndoSweep,
}: Props) {
  const [query, setQuery] = useState("");
  const [rows, setRows] = useState<BrineRow[] | null>(null);
  const [sweepsOpen, setSweepsOpen] = useState(false);
  const [denyOpen, setDenyOpen] = useState(false);
  const [denyText, setDenyText] = useState("");
  const [denySaved, setDenySaved] = useState(false);
  const queryRef = useRef(query);
  queryRef.current = query;

  const refresh = useCallback(async () => {
    setRows(await brineSearch(queryRef.current));
  }, []);

  // Results as you type, lightly debounced; refreshToken covers moves made
  // from outside (⌘J batches, jar deletions).
  useEffect(() => {
    const t = window.setTimeout(() => {
      void refresh();
    }, 80);
    return () => window.clearTimeout(t);
  }, [query, refresh, refreshToken]);

  // New extractions land live while the list is open.
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen(BRINE_CHANGED, () => void refresh()).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [refresh]);

  const toggle = useCallback(
    (id: string) => {
      onSelectionChange(
        selection.includes(id)
          ? selection.filter((s) => s !== id)
          : [...selection, id],
      );
    },
    [selection, onSelectionChange],
  );

  const toggleDenyList = useCallback(async () => {
    if (!denyOpen) {
      setDenyText(await invoke<string>("denylist_get"));
      setDenySaved(false);
    }
    setDenyOpen((open) => !open);
  }, [denyOpen]);

  const saveDenyList = useCallback(async () => {
    await invoke("denylist_set", { contents: denyText });
    setDenySaved(true);
  }, [denyText]);

  return (
    <section className="nr-brine" aria-label="Brine">
      <header className="nr-brine__bar">
        <input
          type="search"
          className="nr-brine__search"
          placeholder="Search everything you've read"
          aria-label="Search Brine"
          value={query}
          autoFocus
          spellCheck={false}
          onChange={(event) => {
            setQuery(event.target.value);
          }}
        />
        <button
          type="button"
          className="nr-brine__deny-toggle"
          aria-expanded={sweepsOpen}
          onClick={() => setSweepsOpen((o) => !o)}
        >
          Sweeps
        </button>
        <button
          type="button"
          className="nr-brine__deny-toggle"
          aria-expanded={denyOpen}
          onClick={() => void toggleDenyList()}
        >
          Deny list
        </button>
      </header>

      {sweepsOpen && (
        <SweepsPanel refreshToken={refreshToken} onUndo={onUndoSweep} />
      )}

      {denyOpen && (
        <div className="nr-brine__deny">
          <p className="nr-brine__deny-hint">
            Pages whose address contains a line below are never preserved.
          </p>
          <textarea
            className="nr-brine__deny-editor"
            aria-label="Deny list, one pattern per line"
            value={denyText}
            spellCheck={false}
            rows={8}
            onChange={(event) => {
              setDenyText(event.target.value);
              setDenySaved(false);
            }}
          />
          <div className="nr-brine__deny-actions">
            <button type="button" onClick={() => void saveDenyList()}>
              Save
            </button>
            {denySaved && <span role="status">Saved</span>}
          </div>
        </div>
      )}

      {selection.length > 0 && (
        <div className="nr-brine__batch">
          <span>
            {selection.length} selected
          </span>
          <button
            type="button"
            disabled={!activeJarName}
            title={activeJarName ? "⌘J" : "Open a jar on the shelf first"}
            onClick={onJarSelection}
          >
            {activeJarName ? `Jar into ${activeJarName}` : "No jar open"}
          </button>
          <button type="button" onClick={() => onSelectionChange([])}>
            Clear
          </button>
        </div>
      )}

      {rows !== null && rows.length === 0 && (
        <div className="nr-brine__empty">
          {query.trim() ? (
            <p>No matches. Search finds whole words from a page's title or text.</p>
          ) : (
            <p>
              Nothing here yet. Open a page — everything you read lands in
              Brine, ready to find later.
            </p>
          )}
        </div>
      )}

      <ul className="nr-brine__list">
        {(rows ?? []).map((row) => (
          <li key={row.id} className="nr-brine__item">
            <input
              type="checkbox"
              className="nr-brine__pick"
              aria-label={`Select ${row.title}`}
              checked={selection.includes(row.id)}
              onChange={() => toggle(row.id)}
            />
            <button
              type="button"
              className="nr-brine__row"
              onClick={() => row.url && onOpen(row.url)}
            >
              <span className="nr-brine__title">{row.title}</span>
              <span className="nr-brine__domain">{domainOf(row.url)}</span>
              <span className="nr-brine__snippet">{row.snippet}</span>
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
