import { ask } from "@tauri-apps/plugin-dialog";
import { useCallback, useEffect, useState } from "react";
import { domainOf } from "../lib/format";
import {
  deleteJar,
  jarItems,
  moveItems,
  renameJar,
  type Jar,
  type JarItemRow,
} from "../lib/db";

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

  const refresh = useCallback(async () => {
    setRows(await jarItems(jar.id));
    setSelection([]);
  }, [jar.id]);

  useEffect(() => {
    void refresh();
  }, [refresh, refreshToken]);

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

  const grouped = KIND_ORDER.map(
    (kind) => [kind, (rows ?? []).filter((r) => r.kind === kind)] as const,
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
        <button
          type="button"
          className="nr-jarview__delete"
          onClick={() => void removeJar()}
        >
          Delete jar
        </button>
      </header>

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
      </div>
    </section>
  );
}
