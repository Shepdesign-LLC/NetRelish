interface Props {
  jarName: string | null;
  url: string;
  onUrlChange(value: string): void;
  onNavigate(): void;
}

export default function TitleBar({
  jarName,
  url,
  onUrlChange,
  onNavigate,
}: Props) {
  return (
    <header className="nr-titlebar" data-tauri-drag-region>
      <div className="nr-titlebar__lead" />

      <button type="button" className="nr-jar-chip">
        <span className="nr-jar-chip__dot" aria-hidden="true" />
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

      <div className="nr-titlebar__trail" />
    </header>
  );
}
