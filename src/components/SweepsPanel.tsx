import { useEffect, useState } from "react";
import { listSweeps, type SweepBatch } from "../lib/db";

interface Props {
  refreshToken: number;
  onUndo(batchId: string): void;
}

function ago(ts: number): string {
  const mins = Math.max(1, Math.round((Date.now() - ts) / 60_000));
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  return `${hours}h ago`;
}

/** Recent sweeps, each undoable for 24 hours. One sweep = one Batch. */
export default function SweepsPanel({ refreshToken, onUndo }: Props) {
  const [sweeps, setSweeps] = useState<SweepBatch[] | null>(null);

  useEffect(() => {
    void listSweeps().then(setSweeps);
  }, [refreshToken]);

  if (sweeps === null) return null;

  return (
    <div className="nr-sweeps">
      {sweeps.length === 0 ? (
        <p className="nr-sweeps__none">
          No recent sweeps. Tabs past their shelf life are preserved and
          closed automatically; each sweep lands here, undoable for a day.
        </p>
      ) : (
        <ul className="nr-sweeps__list">
          {sweeps.map((s) => (
            <li key={s.batch_id} className="nr-sweeps__row">
              <div className="nr-sweeps__what">
                <span>
                  Sealed {s.count} tab{s.count === 1 ? "" : "s"} · {ago(s.sealed_at)}
                </span>
                <span className="nr-sweeps__titles">{s.titles}</span>
              </div>
              <button type="button" onClick={() => onUndo(s.batch_id)}>
                Undo
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
