import { superellipseClip } from "../lib/superellipse";
import type { ToolId } from "../lib/bridge";

const TILE = 34;

const TOOLS: { id: ToolId; label: string; glyph: string; hue: string }[] = [
  { id: "mise", label: "Mise", glyph: "M", hue: "var(--nr-hue-mise)" },
  { id: "zest", label: "Zest", glyph: "Z", hue: "var(--nr-hue-zest)" },
  { id: "scale", label: "Scale", glyph: "S", hue: "var(--nr-hue-scale)" },
];

interface Props {
  active: ToolId | null;
  onSelect(tool: ToolId | null): void;
}

export default function PantryRail({ active, onSelect }: Props) {
  const clip = superellipseClip(TILE, 4);

  return (
    <nav className="nr-rail" aria-label="Pantry">
      {TOOLS.map((tool) => {
        const isActive = active === tool.id;
        return (
          <button
            key={tool.id}
            type="button"
            className="nr-rail__tile"
            data-active={isActive || undefined}
            style={{ clipPath: clip, ["--tile-hue" as string]: tool.hue }}
            aria-pressed={isActive}
            title={tool.label}
            onClick={() => onSelect(isActive ? null : tool.id)}
          >
            <span aria-hidden="true">{tool.glyph}</span>
            <span className="nr-visually-hidden">{tool.label}</span>
          </button>
        );
      })}
    </nav>
  );
}
