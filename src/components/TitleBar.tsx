interface Props {
  projectName: string | null;
  url: string;
  onUrlChange(value: string): void;
  onNavigate(): void;
  onPickProject(): void;
}

export default function TitleBar({
  projectName,
  url,
  onUrlChange,
  onNavigate,
  onPickProject,
}: Props) {
  return (
    <header className="nr-titlebar" data-tauri-drag-region>
      <div className="nr-titlebar__lead" />

      <button type="button" className="nr-project" onClick={onPickProject}>
        <span className="nr-project__dot" aria-hidden="true" />
        {projectName ?? "Open a project"}
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
          placeholder="Search or enter address"
          aria-label="Address"
          onChange={(event) => onUrlChange(event.target.value)}
        />
      </form>

      <div className="nr-titlebar__trail" />
    </header>
  );
}
