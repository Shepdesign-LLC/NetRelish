import { invoke } from "@tauri-apps/api/core";
import BrandMark from "./BrandMark";

export interface Status {
  text: string;
  action?: { label: string; run(): void };
}

/** What the vault knows about the current page — hosts and usernames only,
 *  never password material (see src-tauri/src/commands/credentials.rs). */
export interface LoginProbe {
  host: string;
  has_login: boolean;
  usernames: string[];
}

interface Props {
  jarName: string | null;
  jarHue: number | null; // 1..6, null = Brine
  url: string;
  status: Status | null;
  canNavigate: boolean;
  canReload: boolean;
  login: LoginProbe | null;
  onUrlChange(value: string): void;
  onNavigate(): void;
  onReleaseJar(): void;
  onFillLogin(): void;
  onSaveLogin(): void;
}

/** The omnibox input id — App focuses it on ⌘L (menu:open-location). */
export const OMNIBOX_ID = "nr-omnibox";

/**
 * The titlebar, per the design system's main window: the mark, round glass
 * back/forward/reload (real ones), the centered address pill, and the jar
 * chip — Relish Pour when a jar is open, since it's the active thing.
 */
export default function TitleBar({
  jarName,
  jarHue,
  url,
  status,
  canNavigate,
  canReload,
  login,
  onUrlChange,
  onNavigate,
  onReleaseJar,
  onFillLogin,
  onSaveLogin,
}: Props) {
  const canFill = (login?.usernames.length ?? 0) > 0;
  return (
    <header className="nr-titlebar" data-tauri-drag-region>
      <div className="nr-titlebar__lead" />

      {/* The mark. Not a control — it does nothing, so it stays a drag
          region like the rest of the bar. No wordmark: the mark carries the
          brand on its own, so it's sized to be seen. */}
      <div className="nr-brand" data-tauri-drag-region>
        <BrandMark size={30} />
      </div>

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

      {/* Reload has no key equivalent — ⌘R is Run Recipe. This button is the
          only way in, so it never hides. */}
      <button
        type="button"
        className="nr-navbtn"
        title="Reload"
        disabled={!canReload}
        onClick={() => void invoke("preview_reload")}
      >
        {/* r=5 about (7.5,7.5): a 330° sweep clockwise from the upper right,
            with the head pointing into the 30° gap it leaves. */}
        <svg width="15" height="15" viewBox="0 0 15 15" aria-hidden="true">
          <path
            d="M10.71 3.67A5 5 0 1 1 8.37 2.58"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.7"
          />
          <path d="M10.93 3.03 8.09 4.16 8.65 1Z" fill="currentColor" />
        </svg>
        <span className="nr-visually-hidden">Reload</span>
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
        {login?.has_login && (
          <button
            type="button"
            className="nr-omnibar__key"
            data-can-fill={canFill || undefined}
            title={
              canFill
                ? `Fill ${login.usernames[0]} — ⌘⇧F`
                : "Save the login you've typed — ⌘⇧S"
            }
            onClick={canFill ? onFillLogin : onSaveLogin}
          >
            <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
              <circle
                cx="4.5"
                cy="7"
                r="2.6"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.6"
              />
              <path
                d="M7 7 h5.5 M10.5 7 v2.4 M12.5 7 v1.6"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.6"
                strokeLinecap="round"
              />
            </svg>
            <span className="nr-visually-hidden">
              {canFill ? "Fill saved login" : "Save typed login"}
            </span>
          </button>
        )}
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
