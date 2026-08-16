import MasonJar from "./MasonJar";

interface Props {
  /** This jar's shelf life, spelled the way the header spells it. */
  shelfLabel: string;
}

/**
 * The quiet explainer in the jar's right rail.
 *
 * Four lines saying what the system does with your things, from the Aero
 * Relish mocks. It exists because the vocabulary (jar, Brine, seal, label)
 * is only obvious once someone has told you — and §3 says empty states and
 * explainers are the one place warmth is allowed.
 *
 * Copy is verbatim from the handoff; §2–3 spec the vocabulary, so it is not
 * mine to reword.
 */
export default function PantryLogic({ shelfLabel }: Props) {
  return (
    <aside className="nr-legend" aria-label="Pantry logic">
      <span className="nr-kicker">Pantry logic</span>

      <div className="nr-legend__row">
        <span className="nr-legend__icon">
          <MasonJar hue={1} width={12} />
        </span>
        <p>A jar is one project. Its pages, notes, tasks and files stay together.</p>
      </div>

      <div className="nr-legend__row">
        <span className="nr-legend__icon">
          {/* The brine bowl. */}
          <svg width="15" height="13" viewBox="0 0 20 18" aria-hidden="true">
            <rect
              x="1"
              y="5.5"
              width="18"
              height="3"
              rx="1.5"
              fill="oklch(0.855 0.055 118.6)"
            />
            <path
              d="M3 8.5 H17 V9.5 A7 7 0 0 1 3 9.5 Z"
              fill="oklch(0.704 0.082 121.8)"
            />
          </svg>
        </span>
        <p>
          Tabs untouched past this jar's shelf life — <b>{shelfLabel}</b> — sink
          into Brine. Pinned tabs never sink.
        </p>
      </div>

      <div className="nr-legend__row">
        <span className="nr-legend__icon">
          {/* The lock — sealing. */}
          <svg width="10" height="12" viewBox="0 0 10 12" aria-hidden="true">
            <path
              d="M2 5 V3.5 a3 3 0 0 1 6 0 V5"
              fill="none"
              stroke="var(--nr-text-soft)"
              strokeWidth="1.4"
            />
            <rect
              x="1"
              y="5"
              width="8"
              height="6"
              rx="1.5"
              fill="var(--nr-text-soft)"
            />
          </svg>
        </span>
        <p>
          Sealed pages reopen exactly where you left them. Nothing is lost by
          tidying.
        </p>
      </div>

      <div className="nr-legend__row">
        <span className="nr-legend__icon">
          {/* The tag. */}
          <svg width="13" height="13" viewBox="0 0 14 14" aria-hidden="true">
            <path
              d="M1.5 4 A2 2 0 0 1 3.5 2 H7.7 L13 7 L7.7 12 H3.5 A2 2 0 0 1 1.5 10 Z"
              fill="oklch(0.653 0.061 124.6)"
            />
            <circle cx="4.6" cy="5" r="1.1" fill="var(--nr-glass-fill)" />
          </svg>
        </span>
        <p>Tags season a jar for search. Click a tag's ✕ above to remove it.</p>
      </div>
    </aside>
  );
}
