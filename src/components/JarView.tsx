import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { useCallback, useEffect, useState } from "react";
import { domainOf } from "../lib/format";
import {
  deleteJar,
  jarItems,
  moveItems,
  renameJar,
  setJarShelfLife,
  type Jar,
  type JarItemRow,
} from "../lib/db";

const SHELF_LIVES: { hours: number; label: string }[] = [
  { hours: 24, label: "1 day" },
  { hours: 72, label: "3 days" },
  { hours: 168, label: "1 week" },
  { hours: 336, label: "2 weeks" },
];

/** One engine suggestion (src-tauri/src/suggest.rs). */
interface Suggestion {
  item_id: string;
  title: string;
  url: string | null;
  score: number;
}

const KIND_LABELS: Record<JarItemRow["kind"], string> = {
  page: "Pages",
  note: "Notes",
  task: "Tasks",
  file: "Files",
  message: "Messages",
};
const KIND_ORDER: JarItemRow["kind"][] = [
  "page",
  "note",
  "task",
  "file",
  "message",
];

interface Props {
  jar: Jar;
  jars: Jar[];
  refreshToken: number;
  onOpen(url: string): void;
  onChanged(): void;
  onDeleted(): void;
}

/**
 * One jar's contents, grouped by kind, newest first. Rendered in the stage
 * while the native pane is hidden.
 */
export default function JarView({
  jar,
  jars,
  refreshToken,
  onOpen,
  onChanged,
  onDeleted,
}: Props) {
  const [rows, setRows] = useState<JarItemRow[] | null>(null);
  const [selection, setSelection] = useState<string[]>([]);
  const [renaming, setRenaming] = useState(false);
  const [draftName, setDraftName] = useState(jar.name);
  const [moveTarget, setMoveTarget] = useState<string>("brine");
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [reviewing, setReviewing] = useState(false);

  const refresh = useCallback(async () => {
    setRows(await jarItems(jar.id));
    setSelection([]);
  }, [jar.id]);

  useEffect(() => {
    void refresh();
  }, [refresh, refreshToken]);

  // The engine proposes; nothing is filed without a hand on a key (§8).
  useEffect(() => {
    let stale = false;
    void invoke<Suggestion[]>("suggest_for_jar", { jarId: jar.id }).then(
      (s) => {
        if (!stale) setSuggestions(s);
      },
    );
    return () => {
      stale = true;
    };
  }, [jar.id, refreshToken]);

  const acceptSuggestions = useCallback(
    async (ids: string[]) => {
      await moveItems(ids, jar.id);
      await invoke("suggestion_feedback", {
        jarId: jar.id,
        itemIds: ids,
        action: "accepted",
      });
      setSuggestions((s) => s.filter((x) => !ids.includes(x.item_id)));
      await refresh();
      onChanged();
    },
    [jar.id, refresh, onChanged],
  );

  const rejectSuggestion = useCallback(
    async (id: string) => {
      await invoke("suggestion_feedback", {
        jarId: jar.id,
        itemIds: [id],
        action: "rejected",
      });
      setSuggestions((s) => s.filter((x) => x.item_id !== id));
    },
    [jar.id],
  );

  const toggle = useCallback((id: string) => {
    setSelection((sel) =>
      sel.includes(id) ? sel.filter((s) => s !== id) : [...sel, id],
    );
  }, []);

  const commitRename = useCallback(async () => {
    const name = draftName.trim();
    setRenaming(false);
    if (!name || name === jar.name) {
      setDraftName(jar.name);
      return;
    }
    await renameJar(jar.id, name);
    onChanged();
  }, [draftName, jar.id, jar.name, onChanged]);

  const removeJar = useCallback(async () => {
    const n = rows?.length ?? 0;
    const sure = await ask(
      n === 0
        ? `Delete the jar “${jar.name}”?`
        : `Delete the jar “${jar.name}”? Its ${n} item${n === 1 ? "" : "s"} return to Brine — nothing is lost.`,
      { title: "Delete jar", kind: "warning", okLabel: "Delete jar" },
    );
    if (!sure) return;
    await deleteJar(jar.id);
    onDeleted();
  }, [jar.id, jar.name, rows, onDeleted]);

  const moveSelection = useCallback(async () => {
    await moveItems(selection, moveTarget === "brine" ? null : moveTarget);
    await refresh();
    onChanged();
  }, [selection, moveTarget, refresh, onChanged]);

  const live = (rows ?? []).filter((r) => r.sealed_at === null);
  const sealed = (rows ?? []).filter((r) => r.sealed_at !== null);
  const grouped = KIND_ORDER.map(
    (kind) => [kind, live.filter((r) => r.kind === kind)] as const,
  ).filter(([, list]) => list.length > 0);

  return (
    <section className="nr-jarview" aria-label={`Jar: ${jar.name}`}>
      <header className="nr-jarview__bar">
        <span
          className="nr-jarview__dot"
          style={{ background: `var(--nr-jar-${jar.hue})` }}
          aria-hidden="true"
        />
        {renaming ? (
          <input
            className="nr-jarview__rename"
            value={draftName}
            aria-label="Jar name"
            autoFocus
            onChange={(e) => setDraftName(e.target.value)}
            onBlur={() => void commitRename()}
            onKeyDown={(e) => {
              if (e.key === "Enter") void commitRename();
              if (e.key === "Escape") {
                setDraftName(jar.name);
                setRenaming(false);
              }
            }}
          />
        ) : (
          <button
            type="button"
            className="nr-jarview__name"
            title="Rename jar"
            onClick={() => {
              setDraftName(jar.name);
              setRenaming(true);
            }}
          >
            {jar.name}
          </button>
        )}
        <span className="nr-jarview__count">
          {rows === null
            ? ""
            : `${rows.length} item${rows.length === 1 ? "" : "s"}`}
        </span>
        <label className="nr-jarview__shelf">
          Shelf life
          <select
            aria-label="Shelf life — how long this jar's tabs stay open"
            value={jar.shelf_life_hours ?? 72}
            onChange={(e) => {
              void setJarShelfLife(jar.id, Number(e.target.value)).then(
                onChanged,
              );
            }}
          >
            {SHELF_LIVES.map((s) => (
              <option key={s.hours} value={s.hours}>
                {s.label}
              </option>
            ))}
          </select>
        </label>
        <button
          type="button"
          className="nr-jarview__delete"
          onClick={() => void removeJar()}
        >
          Delete jar
        </button>
      </header>

      {suggestions.length > 0 && (
        <div className="nr-jarview__suggest">
          <div className="nr-jarview__suggest-bar">
            <span>
              {suggestions.length} thing{suggestions.length === 1 ? "" : "s"} in
              Brine look{suggestions.length === 1 ? "s" : ""} like{" "}
              {suggestions.length === 1 ? "it belongs" : "they belong"} here
            </span>
            <button
              type="button"
              onClick={() =>
                void acceptSuggestions(suggestions.map((s) => s.item_id))
              }
            >
              Add all
            </button>
            <button
              type="button"
              aria-expanded={reviewing}
              onClick={() => setReviewing((r) => !r)}
            >
              Review
            </button>
          </div>
          {reviewing && (
            <ul className="nr-jarview__suggest-list">
              {suggestions.map((s) => (
                <li key={s.item_id}>
                  <span className="nr-jarview__suggest-title">{s.title}</span>
                  <span className="nr-brine__domain">{domainOf(s.url)}</span>
                  <button
                    type="button"
                    onClick={() => void acceptSuggestions([s.item_id])}
                  >
                    Add
                  </button>
                  <button
                    type="button"
                    onClick={() => void rejectSuggestion(s.item_id)}
                  >
                    Not this jar
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      {selection.length > 0 && (
        <div className="nr-jarview__actions">
          <span>
            {selection.length} selected — move to
          </span>
          <select
            aria-label="Move destination"
            value={moveTarget}
            onChange={(e) => setMoveTarget(e.target.value)}
          >
            <option value="brine">Brine</option>
            {jars
              .filter((j) => j.id !== jar.id)
              .map((j) => (
                <option key={j.id} value={j.id}>
                  {j.name}
                </option>
              ))}
          </select>
          <button type="button" onClick={() => void moveSelection()}>
            Move
          </button>
        </div>
      )}

      {rows !== null && rows.length === 0 && (
        <div className="nr-brine__empty">
          <p>
            An empty jar. Browse with it open, or jar pages from Brine with
            ⌘J — everything you put here stays searchable together.
          </p>
        </div>
      )}

      <div className="nr-jarview__groups">
        {grouped.map(([kind, list]) => (
          <section key={kind} aria-label={KIND_LABELS[kind]}>
            <h2 className="nr-jarview__kind">{KIND_LABELS[kind]}</h2>
            <ul className="nr-brine__list">
              {list.map((row) => (
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
        ))}

        {sealed.length > 0 && (
          <section aria-label="Sealed">
            <h2 className="nr-jarview__kind">
              Sealed — preserved exactly as left
            </h2>
            <ul className="nr-brine__list">
              {sealed.map((row) => (
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
                    className="nr-brine__row nr-brine__row--sealed"
                    title="Reopen — restores the page where you left it"
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
        )}
      </div>
    </section>
  );
}
