interface Props {
  jarName: string | null;
  jarHue: number | null; // 1..6, null = Brine
  url: string;
  status: string | null; // transient action feedback ("Jarred into X")
  onUrlChange(value: string): void;
  onNavigate(): void;
}

export default function TitleBar({
  jarName,
  jarHue,
  url,
  status,
  onUrlChange,
  onNavigate,
}: Props) {
  const dotColor = jarHue ? `var(--nr-jar-${jarHue})` : "var(--nr-hue-brine)";

  return (
    <header className="nr-titlebar" data-tauri-drag-region>
      <div className="nr-titlebar__lead" />

      <button type="button" className="nr-jar-chip" title="Where new pages land">
        <span
          className="nr-jar-chip__dot"
          style={{ background: dotColor }}
          aria-hidden="true"
        />
        {jarName ?? "Brine"}
      </button>

      <form
        className="nr-omnibar"
        onSubmit={(event) => {
          event.preventDefault();
          onNavigate();
        }}
      >
        <input
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

      {/* Toasts cannot float over the native page pane, so action feedback
          lives here in the chrome, always visible. */}
      <span className="nr-titlebar__status" role="status" aria-live="polite">
        {status}
      </span>

      <div className="nr-titlebar__trail" />
    </header>
  );
}
