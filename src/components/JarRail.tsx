import { type Jar } from "../lib/db";
import { superellipseClip } from "../lib/superellipse";

const TILE = 34;

interface Props {
  jars: Jar[];
  activeJarId: string | null;
  brineCount: number;
  brineActive: boolean;
  onSelectJar(id: string): void;
  onOpenBrine(): void;
  onNewJar(): void;
}

/**
 * The shelf. Brine sits at the top — it is where everything starts — then the
 * jars below it, oldest first, and the quiet + that makes a new one. Tiles
 * are superellipses, not border-radius.
 */
export default function JarRail({
  jars,
  activeJarId,
  brineCount,
  brineActive,
  onSelectJar,
  onOpenBrine,
  onNewJar,
}: Props) {
  const clip = superellipseClip(TILE, 4);

  return (
    <nav className="nr-rail" aria-label="Shelf">
      <button
        type="button"
        className="nr-rail__tile nr-rail__tile--brine"
        data-active={brineActive || undefined}
        aria-pressed={brineActive}
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
            style={{
              clipPath: clip,
              ["--tile-hue" as string]: `var(--nr-jar-${jar.hue})`,
            }}
            aria-pressed={isActive}
            title={`${jar.name} — ${jar.item_count} item${jar.item_count === 1 ? "" : "s"}`}
            onClick={() => onSelectJar(jar.id)}
          >
            <span aria-hidden="true">{jar.name.slice(0, 1).toUpperCase()}</span>
            <span className="nr-visually-hidden">
              {jar.name}, {jar.item_count} item{jar.item_count === 1 ? "" : "s"}
            </span>
          </button>
        );
      })}

      <button
        type="button"
        className="nr-rail__tile nr-rail__tile--new"
        style={{ clipPath: clip }}
        title="New jar"
        onClick={onNewJar}
      >
        <span aria-hidden="true">+</span>
        <span className="nr-visually-hidden">New jar</span>
      </button>
    </nav>
  );
}
