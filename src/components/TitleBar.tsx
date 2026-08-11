import { invoke } from "@tauri-apps/api/core";

export interface Status {
  text: string;
  action?: { label: string; run(): void };
}

interface Props {
  jarName: string | null;
  jarHue: number | null; // 1..6, null = Brine
  url: string;
  status: Status | null;
  canNavigate: boolean;
  onUrlChange(value: string): void;
  onNavigate(): void;
  onReleaseJar(): void;
}

/** The omnibox input id — App focuses it on ⌘L (menu:open-location). */
export const OMNIBOX_ID = "nr-omnibox";

/**
 * The titlebar, per the design system's main window: round glass
 * back/forward (real ones), the centered address pill, and the jar chip —
 * Relish Pour when a jar is open, since it's the active thing.
 */
export default function TitleBar({
  jarName,
  jarHue,
  url,
  status,
  canNavigate,
  onUrlChange,
  onNavigate,
  onReleaseJar,
}: Props) {
  return (
    <header className="nr-titlebar" data-tauri-drag-region>
      <div className="nr-titlebar__lead" />

      <button
        type="button"
        className="nr-navbtn"
        title="Back"
        disabled={!canNavigate}
        onClick={() => void invoke("preview_back")}
      >
        <span aria-hidden="true">‹</span>
        <span className="nr-visually-hidden">Back</span>
      </button>
      <button
        type="button"
        className="nr-navbtn"
        title="Forward"
        disabled={!canNavigate}
        onClick={() => void invoke("preview_forward")}
      >
        <span aria-hidden="true">›</span>
        <span className="nr-visually-hidden">Forward</span>
      </button>

      <form
        className="nr-omnibar"
        onSubmit={(event) => {
          event.preventDefault();
          onNavigate();
        }}
      >
        <span className="nr-omnibar__lock" aria-hidden="true">
          <svg width="12" height="14" viewBox="0 0 12 14">
            <path
              d="M2 6 V4 a4 4 0 0 1 8 0 V6"
              fill="none"
              stroke="oklch(0.58 0.133 132.4)"
              strokeWidth="1.6"
            />
            <rect x="1" y="6" width="10" height="7" rx="2" fill="oklch(0.58 0.133 132.4)" />
          </svg>
        </span>
        <input
          id={OMNIBOX_ID}
          type="text"
          value={url}
          spellCheck={false}
          autoCorrect="off"
          autoCapitalize="off"
          placeholder="Search your Pantry, or enter an address"
          aria-label="Address"
          onChange={(event) => onUrlChange(event.target.value)}
        />
      </form>

      <button
        type="button"
        className="nr-jar-chip"
        data-jarred={jarName ? true : undefined}
        title={
          jarName
            ? `New pages land in ${jarName} — click to switch to Brine`
            : "New pages land in Brine. Open a jar to change that."
        }
        onClick={jarName ? onReleaseJar : undefined}
      >
        <span
          className="nr-jar-chip__dot"
          style={{
            background: `radial-gradient(circle at 35% 30%,
              color-mix(in oklab, ${jarHue ? `var(--nr-jar-${jarHue})` : "var(--nr-hue-brine)"} 55%, white),
              color-mix(in oklab, ${jarHue ? `var(--nr-jar-${jarHue})` : "var(--nr-hue-brine)"} 82%, black))`,
          }}
          aria-hidden="true"
        />
        {jarName ?? "Brine"}
      </button>

      <span className="nr-titlebar__status" role="status" aria-live="polite">
        {status?.text}
        {status?.action && (
          <button
            type="button"
            className="nr-titlebar__undo"
            onClick={status.action.run}
          >
            {status.action.label}
          </button>
        )}
      </span>

      <div className="nr-titlebar__trail" />
    </header>
  );
}
