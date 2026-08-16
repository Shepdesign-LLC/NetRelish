import BrandMark from "./BrandMark";
import MasonJar from "./MasonJar";
import type { Jar } from "../lib/db";

interface Props {
  jars: Jar[];
  activeJarId: string | null;
  /** Items added in the last seven days — the Brine pill says "this week". */
  weekCount: number;
  totalPreserved: number;
  onOpenBrine(): void;
  onSelectJar(id: string): void;
  onNewJar(): void;
}

/** The four things the product does, in the order they happen to you. */
const PANTRY: { title: string; body: string; icon: "jar" | "bowl" | "lock" | "ladle" }[] = [
  {
    icon: "jar",
    title: "Jars are projects",
    body: "Every project gets a jar. Its pages, notes, tasks and files live together — open a jar and your whole context comes back.",
  },
  {
    icon: "bowl",
    title: "Idle tabs sink into Brine",
    body: "Tabs you stop touching sink after their jar's shelf life instead of piling up. Pinned tabs never sink.",
  },
  {
    icon: "lock",
    title: "Nothing is ever lost",
    body: "Sunk pages are sealed with their scroll position, form state and history. Reopen one and it's exactly where you left it.",
  },
  {
    icon: "ladle",
    title: "Recipes replay your work",
    body: "Record a routine once — windows, splits, steps — then run it with ⌘R. Recipes are recorded, not authored.",
  },
];

function PantryIcon({ kind }: { kind: (typeof PANTRY)[number]["icon"] }) {
  if (kind === "jar") return <MasonJar hue={1} width={34} />;
  if (kind === "bowl")
    return (
      <svg width="40" height="36" viewBox="0 0 20 18" aria-hidden="true">
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
          fill="oklch(0.653 0.061 124.6)"
        />
        {/* Rising bubbles — the brine is doing something. */}
        <circle cx="7.5" cy="3.6" r="1.1" fill="oklch(0.834 0.224 130.9 / 0.55)" />
        <circle cx="11" cy="2.2" r="0.8" fill="oklch(0.834 0.224 130.9 / 0.4)" />
        <circle cx="13.4" cy="4.2" r="0.6" fill="oklch(0.834 0.224 130.9 / 0.3)" />
      </svg>
    );
  if (kind === "lock")
    return (
      <svg width="30" height="36" viewBox="0 0 10 12" aria-hidden="true">
        <path
          d="M2 5 V3.5 a3 3 0 0 1 6 0 V5"
          fill="none"
          stroke="var(--nr-text-soft)"
          strokeWidth="1.4"
        />
        <rect x="1" y="5" width="8" height="6" rx="1.5" fill="var(--nr-text-soft)" />
      </svg>
    );
  return (
    /* The ladle — recipes. */
    <svg width="38" height="38" viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M16 3 V12"
        stroke="var(--nr-text-soft)"
        strokeWidth="1.8"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M9 12 H21 A6 6 0 0 1 9 12 Z"
        fill="oklch(0.653 0.061 124.6)"
      />
    </svg>
  );
}

/**
 * The new-tab surface.
 *
 * The one screen that floats directly on the Aurora with no chrome panel
 * of its own, so its ink is light (§9's light-ink scale) rather than the
 * olive used on glass. Built from the Aero Relish Home mock.
 *
 * It doubles as the product's only explainer: a first-run reader lands
 * here, and "HOW THE PANTRY WORKS" is where the vocabulary gets taught.
 */
export default function HomeView({
  jars,
  activeJarId,
  weekCount,
  totalPreserved,
  onOpenBrine,
  onSelectJar,
  onNewJar,
}: Props) {
  return (
    <div className="nr-home">
      <header className="nr-home__hero">
        <span className="nr-home__mark">
          <BrandMark size={104} />
        </span>
        <div>
          <h1 className="nr-home__wordmark">NetRelish</h1>
          <p className="nr-home__tagline">
            The browser that preserves your work
          </p>
        </div>
      </header>

      <section className="nr-home__panel" aria-label="How the Pantry works">
        <div className="nr-home__panel-head">
          <span className="nr-kicker">How the Pantry works</span>
          <span className="nr-home__rule" aria-hidden="true" />
        </div>
        <div className="nr-home__cols">
          {PANTRY.map((c) => (
            <article key={c.title} className="nr-home__col">
              <span className="nr-home__col-icon">
                <PantryIcon kind={c.icon} />
              </span>
              <h2>{c.title}</h2>
              <p>{c.body}</p>
            </article>
          ))}
        </div>
      </section>

      <div className="nr-home__foot-row">
        <section className="nr-home__shelf" aria-label="Your shelf">
          <span className="nr-kicker nr-kicker--light">Your shelf</span>
          <div className="nr-home__jars">
            {jars.map((j) => (
              <button
                key={j.id}
                type="button"
                className="nr-home__jar"
                data-active={j.id === activeJarId || undefined}
                title={`Open ${j.name}`}
                onClick={() => onSelectJar(j.id)}
              >
                <MasonJar
                  hue={j.hue}
                  initial={j.name[0]?.toUpperCase()}
                  width={52}
                  glowing={j.id === activeJarId}
                />
                <span>
                  {j.name} · {j.item_count}
                </span>
              </button>
            ))}
            <button
              type="button"
              className="nr-home__jar nr-home__jar--new"
              onClick={onNewJar}
            >
              {/* The empty slot is jar-shaped, not a rounded box — it reads
                  as a jar you haven't filled yet. */}
              <span className="nr-home__jar-new">
                <MasonJar hue={1} width={52} outline />
                <span className="nr-home__jar-plus" aria-hidden="true">
                  ＋
                </span>
              </span>
              <span>New jar</span>
            </button>
          </div>
        </section>

        <section className="nr-home__brine" aria-label="In the Brine">
          <span className="nr-kicker nr-kicker--electric">In the Brine</span>
          <button type="button" className="nr-home__brine-pill" onClick={onOpenBrine}>
            <svg width="22" height="19" viewBox="0 0 20 18" aria-hidden="true">
              <rect
                x="1"
                y="5.5"
                width="18"
                height="3"
                rx="1.5"
                fill="oklch(0.925 0.056 118.4)"
              />
              <path
                d="M3 8.5 H17 V9.5 A7 7 0 0 1 3 9.5 Z"
                fill="oklch(0.653 0.061 124.6)"
              />
            </svg>
            <span className="nr-home__brine-text">
              {weekCount} thing{weekCount === 1 ? "" : "s"} preserved this week
            </span>
            <span className="nr-home__brine-open">OPEN →</span>
          </button>
        </section>
      </div>

      <p className="nr-home__caption">
        {totalPreserved} things preserved, none of them lost
      </p>
    </div>
  );
}
