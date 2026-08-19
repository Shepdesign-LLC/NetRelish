interface Props {
  onClose(): void;
}

const MAP: [string, string][] = [
  ["⌘K", "Ask the Pantry — search everything, filters and all"],
  ["⌘L", "Focus the address bar"],
  ["⌘J", "Jar this page, or the Brine selection"],
  ["⌘T", "New tab"],
  ["⌘1–9", "Switch to a jar by shelf position"],
  ["⌘R", "Run the active jar's recipe"],
  ["⌘⇧F", "Fill the saved login for this site"],
  ["⌘⇧S", "Save the login you've typed on this page"],
  ["⌘/", "This sheet"],
  ["↩ / ⌘↩", "In the palette: open · open and keep searching"],
  ["Esc", "Close the palette or this sheet — typed input survives"],
];

/** The keyboard map. A sibling of the stage, like every overlay. */
export default function ShortcutSheet({ onClose }: Props) {
  return (
    <div className="nr-palette" role="dialog" aria-label="Keyboard shortcuts">
      <button
        type="button"
        className="nr-palette__scrim"
        aria-label="Close"
        tabIndex={-1}
        onClick={onClose}
      />
      <div className="nr-palette__panel nr-sheet">
        <h2 className="nr-sheet__title">Keyboard</h2>
        <table className="nr-sheet__table">
          <tbody>
            {MAP.map(([keys, what]) => (
              <tr key={keys}>
                <td className="nr-sheet__keys">{keys}</td>
                <td>{what}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <footer className="nr-palette__keys">
          Every action is also reachable by Tab — the keyboard is never
          required, only faster.
        </footer>
      </div>
    </div>
  );
}
