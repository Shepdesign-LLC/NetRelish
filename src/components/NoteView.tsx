import { useCallback, useEffect, useRef, useState } from "react";
import { getItem, updateNote } from "../lib/db";

interface Props {
  noteId: string;
  jarName: string | null;
  onClose(): void;
}

/**
 * The note editor: markdown in, markdown stored. Saves as you type
 * (debounced) — a note is never lost to a forgotten ⌘S.
 */
export default function NoteView({ noteId, jarName, onClose }: Props) {
  const [text, setText] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<number | null>(null);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => {
    void getItem(noteId).then((item) => setText(item?.body ?? ""));
  }, [noteId]);

  const scheduleSave = useCallback(
    (value: string) => {
      setText(value);
      window.clearTimeout(timer.current);
      timer.current = window.setTimeout(() => {
        void updateNote(noteId, value).then(() => setSavedAt(Date.now()));
      }, 700);
    },
    [noteId],
  );

  // Close = flush the pending save first; nothing half-written.
  const close = useCallback(() => {
    window.clearTimeout(timer.current);
    if (text !== null) {
      void updateNote(noteId, text).then(onClose);
    } else {
      onClose();
    }
  }, [noteId, text, onClose]);

  if (text === null) return null;

  return (
    <section className="nr-note" aria-label="Note editor">
      <header className="nr-note__bar">
        <span className="nr-note__where">
          Note{jarName ? ` · ${jarName}` : ""} · markdown
        </span>
        <span className="nr-note__saved" role="status">
          {savedAt ? "Saved" : ""}
        </span>
        <button type="button" onClick={close}>
          Done
        </button>
      </header>
      <textarea
        className="nr-note__editor"
        value={text}
        autoFocus
        spellCheck={true}
        placeholder={"# A title\n\nWrite. The first line names the note."}
        onChange={(e) => {
          setSavedAt(null);
          scheduleSave(e.target.value);
        }}
        onKeyDown={(e) => {
          if (e.key === "Escape") close();
        }}
      />
    </section>
  );
}
