import { superellipseClip } from "../lib/superellipse";

const TILE = 34;

export interface JarSummary {
  id: string;
  name: string;
  hue: string;
  itemCount: number;
}

interface Props {
  jars: JarSummary[];
  activeJarId: string | null;
  brineCount: number;
  onSelectJar(id: string | null): void;
  onOpenBrine(): void;
}

/**
 * The shelf. Brine sits at the top — it is where everything starts — then the
 * jars below it, newest last. Tiles are superellipses, not border-radius.
 */
export default function JarRail({
  jars,
  activeJarId,
  brineCount,
  onSelectJar,
  onOpenBrine,
}: Props) {
  const clip = superellipseClip(TILE, 4);

  return (
    <nav className="nr-rail" aria-label="Shelf">
      <button
        type="button"
        className="nr-rail__tile nr-rail__tile--brine"
        style={{ clipPath: clip }}
        title={`Brine — ${brineCount} unsorted`}
        onClick={onOpenBrine}
      >
        <span aria-hidden="true">◍</span>
        <span className="nr-visually-hidden">Brine, {brineCount} unsorted</span>
      </button>

      <hr className="nr-rail__split" />

      {jars.map((jar) => {
        const isActive = jar.id === activeJarId;
        return (
          <button
            key={jar.id}
            type="button"
            className="nr-rail__tile"
            data-active={isActive || undefined}
            style={{ clipPath: clip, ["--tile-hue" as string]: jar.hue }}
            aria-pressed={isActive}
            title={`${jar.name} — ${jar.itemCount} items`}
            onClick={() => onSelectJar(isActive ? null : jar.id)}
          >
            <span aria-hidden="true">{jar.name.slice(0, 1).toUpperCase()}</span>
            <span className="nr-visually-hidden">{jar.name}</span>
          </button>
        );
      })}
    </nav>
  );
}
