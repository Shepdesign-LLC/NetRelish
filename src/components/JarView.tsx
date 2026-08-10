import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { useCallback, useEffect, useState } from "react";
import { domainOf } from "../lib/format";
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
  type Jar,
  type JarItemRow,
  type Label,
  type Recipe,
} from "../lib/db";
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
 * One jar's contents, grouped by kind, newest first. Rendered in the stage
 * while the native pane is hidden.
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
  const live = visible.filter((r) => r.sealed_at === null);
  const sealed = visible.filter((r) => r.sealed_at !== null);
  const grouped = KIND_ORDER.map(
    (kind) => [kind, live.filter((r) => r.kind === kind)] as const,
  ).filter(([, list]) => list.length > 0);

  const taskState = (row: JarItemRow): { done: boolean; due: number | null } => {
    try {
      const m = JSON.parse(row.meta ?? "{}") as { done?: boolean; due?: number };
      return { done: !!m.done, due: m.due ?? null };
    } catch {
      return { done: false, due: null };
    }
  };

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

      {labels.filter((l) => l.uses > 0).length > 0 && (
        <div className="nr-jarview__labels" role="group" aria-label="Filter by label">
          {labels
            .filter((l) => l.uses > 0)
            .map((l) => (
              <button
                key={l.id}
                type="button"
                className="nr-jarview__label-chip"
                aria-pressed={labelFilter === l.name}
                data-active={labelFilter === l.name || undefined}
                onClick={() =>
                  setLabelFilter((f) => (f === l.name ? null : l.name))
                }
              >
                {l.name} <span>{l.uses}</span>
              </button>
            ))}
        </div>
      )}

      <RecipesPanel
        jarId={jar.id}
        refreshToken={refreshToken}
        recording={recording}
        onStartRecording={onStartRecording}
        onSaveRecording={onSaveRecording}
        onDiscardRecording={onDiscardRecording}
        onRun={onRunRecipe}
      />

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
                      className="nr-brine__row"
                      data-done={task?.done || undefined}
                      title={
                        row.kind === "task"
                          ? "Toggle done"
                          : row.kind === "note"
                            ? "Edit note"
                            : row.kind === "file"
                              ? "Open file"
                              : undefined
                      }
                      onClick={() => openRow(row)}
                    >
                      <span className="nr-brine__title">
                        {task ? (task.done ? "☑ " : "☐ ") : ""}
                        {row.title}
                      </span>
                      <span className="nr-brine__domain">
                        {task?.due
                          ? `due ${new Date(task.due).toLocaleDateString("en-CA")}`
                          : domainOf(row.url)}
                      </span>
                      <span className="nr-brine__snippet">{row.snippet}</span>
                    </button>
                  </li>
                );
              })}
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
