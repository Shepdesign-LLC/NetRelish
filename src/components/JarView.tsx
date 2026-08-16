import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { useCallback, useEffect, useState } from "react";
import { domainOf } from "../lib/format";
import MasonJar from "./MasonJar";
import { openPath } from "@tauri-apps/plugin-opener";
import {
  assignLabel,
  createNoteItem,
  createTask,
  deleteJar,
  itemIdsWithLabel,
  jarItems,
  listLabels,
  moveItems,
  renameJar,
  setJarShelfLife,
  toggleTaskDone,
  unassignLabel,
  type Jar,
  type JarItemRow,
  type Label,
  type Recipe,
} from "../lib/db";
import PantryLogic from "./PantryLogic";
import RecipesPanel from "./RecipesPanel";

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

const startOfDay = (d: Date) =>
  new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

/** DUE FRI within the week, DUE AUG 21 beyond it. */
function dueLabel(due: number): string {
  const d = new Date(due);
  const days = Math.round((startOfDay(d) - startOfDay(new Date())) / 86_400_000);
  const style: Intl.DateTimeFormatOptions =
    days >= 0 && days < 7
      ? { weekday: "short" }
      : { month: "short", day: "numeric" };
  return `DUE ${d.toLocaleDateString("en-US", style).toUpperCase()}`;
}

function agoLabel(ts: number): string {
  const mins = Math.max(1, Math.round((Date.now() - ts) / 60_000));
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

/** file:///Users/you/Clients/X -> ~/Clients/X */
function fileLabel(url: string | null): string {
  if (!url) return "";
  return decodeURI(url)
    .replace(/^file:\/\//, "")
    .replace(/^\/Users\/[^/]+/, "~");
}

interface Props {
  jar: Jar;
  jars: Jar[];
  refreshToken: number;
  recording: boolean;
  onOpen(url: string): void;
  onOpenNote(id: string): void;
  onChanged(): void;
  onDeleted(): void;
  onStartRecording(): void;
  onSaveRecording(name: string): Promise<void>;
  onDiscardRecording(): void;
  onRunRecipe(recipe: Recipe): void;
}

/**
 * One jar's contents. The header floats directly on the Aurora in light
 * ink; the items live in one glass panel, grouped by kind with sealed
 * pages inline wearing a SEALED chip; recipes and the sealing contract
 * sit in the right rail.
 */
export default function JarView({
  jar,
  jars,
  refreshToken,
  recording,
  onOpen,
  onOpenNote,
  onChanged,
  onDeleted,
  onStartRecording,
  onSaveRecording,
  onDiscardRecording,
  onRunRecipe,
}: Props) {
  const [rows, setRows] = useState<JarItemRow[] | null>(null);
  const [selection, setSelection] = useState<string[]>([]);
  const [renaming, setRenaming] = useState(false);
  const [draftName, setDraftName] = useState(jar.name);
  const [moveTarget, setMoveTarget] = useState<string>("brine");
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [reviewing, setReviewing] = useState(false);
  const [taskDraft, setTaskDraft] = useState("");
  const [taskDue, setTaskDue] = useState("");
  const [labels, setLabels] = useState<Label[]>([]);
  const [labelDraft, setLabelDraft] = useState("");
  const [labelFilter, setLabelFilter] = useState<string | null>(null);
  const [labelledIds, setLabelledIds] = useState<string[] | null>(null);

  const refresh = useCallback(async () => {
    setRows(await jarItems(jar.id));
    setLabels(await listLabels());
    setSelection([]);
  }, [jar.id]);

  useEffect(() => {
    void refresh();
  }, [refresh, refreshToken]);

  // Label filter: resolve which items wear the chip.
  useEffect(() => {
    if (!labelFilter) {
      setLabelledIds(null);
      return;
    }
    void itemIdsWithLabel(labelFilter).then(setLabelledIds);
  }, [labelFilter, refreshToken]);

  const addTask = useCallback(async () => {
    const title = taskDraft.trim();
    if (!title) return;
    await createTask(
      jar.id,
      title,
      taskDue ? new Date(`${taskDue}T12:00:00`).getTime() : null,
    );
    setTaskDraft("");
    setTaskDue("");
    await refresh();
    onChanged();
  }, [taskDraft, taskDue, jar.id, refresh, onChanged]);

  const newNote = useCallback(async () => {
    const id = await createNoteItem(jar.id, "");
    onChanged();
    onOpenNote(id);
  }, [jar.id, onChanged, onOpenNote]);

  const labelSelection = useCallback(async () => {
    await assignLabel(labelDraft, selection);
    setLabelDraft("");
    await refresh();
    onChanged();
  }, [labelDraft, selection, refresh, onChanged]);

  /** Strip a label off every item in this jar. Labels only season items —
   *  removing one never touches the items themselves, so this needs no
   *  confirmation and stays consistent with "closing is free". */
  const removeLabel = useCallback(
    async (name: string) => {
      const ids = await itemIdsWithLabel(name);
      await unassignLabel(name, ids);
      setLabelFilter((f) => (f === name ? null : f));
      await refresh();
      onChanged();
    },
    [refresh, onChanged],
  );

  /** What clicking a row means depends on what the row is. */
  const openRow = useCallback(
    (row: JarItemRow) => {
      if (row.kind === "note") onOpenNote(row.id);
      else if (row.kind === "task") {
        void toggleTaskDone(row.id).then(refresh);
      } else if (row.kind === "file") {
        const path = row.url?.replace(/^file:\/\//, "");
        if (path) void openPath(path).catch(() => {});
      } else if (row.url) onOpen(row.url);
    },
    [onOpen, onOpenNote, refresh],
  );

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

  // The one key that accepts them all — A, when no field has focus.
  useEffect(() => {
    if (suggestions.length === 0) return;
    const onKey = (event: KeyboardEvent) => {
      const t = event.target as HTMLElement | null;
      if (
        t &&
        (t.tagName === "INPUT" ||
          t.tagName === "TEXTAREA" ||
          t.tagName === "SELECT" ||
          t.isContentEditable)
      )
        return;
      if (
        event.key === "a" &&
        !event.metaKey &&
        !event.ctrlKey &&
        !event.altKey
      ) {
        event.preventDefault();
        void acceptSuggestions(suggestions.map((s) => s.item_id));
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [suggestions, acceptSuggestions]);

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

  const visible = (rows ?? []).filter(
    (r) => labelledIds === null || labelledIds.includes(r.id),
  );
  const grouped = KIND_ORDER.map(
    (kind) => [kind, visible.filter((r) => r.kind === kind)] as const,
  ).filter(([, list]) => list.length > 0);

  const taskState = (row: JarItemRow): { done: boolean; due: number | null } => {
    try {
      const m = JSON.parse(row.meta ?? "{}") as { done?: boolean; due?: number };
      return { done: !!m.done, due: m.due ?? null };
    } catch {
      return { done: false, due: null };
    }
  };

  const shelfLabel =
    SHELF_LIVES.find((s) => s.hours === (jar.shelf_life_hours ?? 72))?.label ??
    `${jar.shelf_life_hours}h`;
  const usedLabels = labels.filter((l) => l.uses > 0);

  const kindChip = (row: JarItemRow, task: { done: boolean } | null) => {
    if (row.kind === "note")
      return (
        <span className="nr-jarview__chip nr-jarview__chip--note" aria-hidden="true">
          ≡
        </span>
      );
    if (row.kind === "task")
      return (
        <span
          className="nr-jarview__chip nr-jarview__chip--task"
          data-done={task?.done || undefined}
          aria-hidden="true"
        >
          {task?.done ? "✓" : ""}
        </span>
      );
    if (row.kind === "file")
      return (
        <span className="nr-jarview__chip nr-jarview__chip--file" aria-hidden="true">
          ▤
        </span>
      );
    return (
      <span className="nr-jarview__chip nr-jarview__chip--page" aria-hidden="true">
        {(domainOf(row.url)[0] ?? "•").toUpperCase()}
      </span>
    );
  };

  const rowMeta = (row: JarItemRow, task: { due: number | null } | null) => {
    if (row.kind === "task")
      return task?.due ? (
        <span className="nr-jarview__due">{dueLabel(task.due)}</span>
      ) : null;
    if (row.kind === "note")
      return (
        <span className="nr-brine__domain">edited {agoLabel(row.touched_at)}</span>
      );
    if (row.kind === "file")
      return <span className="nr-brine__domain">{fileLabel(row.url)}</span>;
    return <span className="nr-brine__domain">{domainOf(row.url)}</span>;
  };

  return (
    <section className="nr-jarview" aria-label={`Jar: ${jar.name}`}>
      <div className="nr-jarview__main">
        <header className="nr-jarview__bar">
          <MasonJar hue={jar.hue} initial={jar.name[0]?.toUpperCase()} />
          <div className="nr-jarview__title-block">
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
            <div className="nr-jarview__meta">
              <span>
                {rows === null
                  ? ""
                  : `${rows.length} item${rows.length === 1 ? "" : "s"} · shelf life ${shelfLabel}`}
              </span>
              {usedLabels.map((l) => (
                /* Two controls, side by side rather than nested — a button
                   inside a button is invalid and the inner one stops being
                   reachable. The wrapper only draws the chip. */
                <span key={l.id} className="nr-jarview__label-chip">
                  <button
                    type="button"
                    className="nr-jarview__label-name"
                    aria-pressed={labelFilter === l.name}
                    data-active={labelFilter === l.name || undefined}
                    onClick={() =>
                      setLabelFilter((f) => (f === l.name ? null : l.name))
                    }
                  >
                    {l.name} <span>{l.uses}</span>
                  </button>
                  <button
                    type="button"
                    className="nr-jarview__label-remove"
                    title={`Remove ${l.name} from every item in this jar`}
                    onClick={() => void removeLabel(l.name)}
                  >
                    <span aria-hidden="true">✕</span>
                    <span className="nr-visually-hidden">
                      Remove label {l.name}
                    </span>
                  </button>
                </span>
              ))}
            </div>
          </div>
          <button
            type="button"
            className="nr-jarview__record"
            disabled={recording}
            onClick={onStartRecording}
          >
            <span className="nr-jarview__record-dot" aria-hidden="true" />
            {recording ? "Recording" : "Record recipe"}
          </button>
        </header>

        {suggestions.length > 0 && (
          <div className="nr-jarview__suggest">
            <div className="nr-jarview__suggest-bar">
              <span className="nr-jarview__suggest-icon" aria-hidden="true">
                ✦
              </span>
              <span className="nr-jarview__suggest-text">
                {suggestions.length} thing{suggestions.length === 1 ? "" : "s"} in
                Brine look{suggestions.length === 1 ? "s" : ""} like{" "}
                {suggestions.length === 1 ? "it belongs" : "they belong"} here
              </span>
              <button
                type="button"
                className="nr-jarview__suggest-review"
                aria-expanded={reviewing}
                onClick={() => setReviewing((r) => !r)}
              >
                Review
              </button>
              <button
                type="button"
                className="nr-jarview__suggest-accept"
                onClick={() =>
                  void acceptSuggestions(suggestions.map((s) => s.item_id))
                }
              >
                Add all
                <span className="nr-kbd" aria-hidden="true">A</span>
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

        <div className="nr-jarview__make">
          <button type="button" onClick={() => void newNote()}>
            New note
          </button>
          <form
            className="nr-jarview__task-add"
            onSubmit={(e) => {
              e.preventDefault();
              void addTask();
            }}
          >
            <input
              placeholder="Add a task"
              aria-label="New task"
              value={taskDraft}
              onChange={(e) => setTaskDraft(e.target.value)}
            />
            <input
              type="date"
              aria-label="Due date"
              value={taskDue}
              onChange={(e) => setTaskDue(e.target.value)}
            />
            <button type="submit" disabled={!taskDraft.trim()}>
              Add
            </button>
          </form>
        </div>

        {rows !== null && rows.length === 0 && (
          <div className="nr-brine__empty">
            <p>
              An empty jar. Browse with it open, or jar pages from Brine with
              ⌘J — everything you put here stays searchable together.
            </p>
          </div>
        )}

        {grouped.length > 0 && (
          <div className="nr-jarview__groups">
            {grouped.map(([kind, list]) => (
              <section key={kind} aria-label={KIND_LABELS[kind]}>
                <h2 className="nr-kicker nr-jarview__kind">
                  {KIND_LABELS[kind]} · {list.length}
                </h2>
                <ul className="nr-brine__list">
                  {list.map((row) => {
                    const task = row.kind === "task" ? taskState(row) : null;
                    return (
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
                          className="nr-brine__row nr-jarview__row"
                          data-done={task?.done || undefined}
                          title={
                            row.kind === "task"
                              ? "Toggle done"
                              : row.kind === "note"
                                ? "Edit note"
                                : row.kind === "file"
                                  ? "Open file"
                                  : row.sealed_at !== null
                                    ? "Reopen — restores the page where you left it"
                                    : undefined
                          }
                          onClick={() => openRow(row)}
                        >
                          {kindChip(row, task)}
                          <span className="nr-brine__title">{row.title}</span>
                          {row.sealed_at !== null && (
                            <span
                              className="nr-jarview__sealed-chip"
                              title="Sealed — reopens exactly where you left it"
                            >
                              <svg
                                width="8"
                                height="10"
                                viewBox="0 0 10 12"
                                aria-hidden="true"
                              >
                                <path
                                  d="M2 5 V3.5 a3 3 0 0 1 6 0 V5"
                                  fill="none"
                                  stroke="currentColor"
                                  strokeWidth="1.4"
                                />
                                <rect
                                  x="1"
                                  y="5"
                                  width="8"
                                  height="6"
                                  rx="1.5"
                                  fill="currentColor"
                                />
                              </svg>
                              sealed
                            </span>
                          )}
                          {rowMeta(row, task)}
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </section>
            ))}
          </div>
        )}
      </div>

      <aside className="nr-jarview__rail" aria-label="Jar tools">
        <RecipesPanel
          jarId={jar.id}
          refreshToken={refreshToken}
          recording={recording}
          onSaveRecording={onSaveRecording}
          onDiscardRecording={onDiscardRecording}
          onRun={onRunRecipe}
        />

        <div className="nr-jarview__railcard">
          <span className="nr-kicker">Shelf life</span>
          <label className="nr-jarview__shelf">
            Untouched tabs seal into this jar after{" "}
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
            </select>{" "}
            and close. Pinned tabs never seal. Nothing is ever lost by tidying.
          </label>
        </div>

        <PantryLogic shelfLabel={shelfLabel} />

        <button
          type="button"
          className="nr-jarview__delete"
          onClick={() => void removeJar()}
        >
          Delete jar
        </button>
      </aside>

      {selection.length > 0 && (
        <div className="nr-jarview__actions">
          <span>{selection.length} selected — move to</span>
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
          <input
            placeholder="or label as…"
            aria-label="Label name"
            value={labelDraft}
            onChange={(e) => setLabelDraft(e.target.value)}
          />
          <button
            type="button"
            disabled={!labelDraft.trim()}
            onClick={() => void labelSelection()}
          >
            Label
          </button>
        </div>
      )}
    </section>
  );
}
