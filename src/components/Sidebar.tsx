import { domainOf } from "../lib/format";
import { superellipseClip } from "../lib/superellipse";
import { type Jar, type Tab } from "../lib/db";

interface Props {
  jars: Jar[];
  activeJarId: string | null;
  tabs: Tab[];
  activeTabId: string | null;
  sealingIds: string[];
  brineCount: number;
  totalPreserved: number;
  brineActive: boolean;
  onSelectTab(id: string): void;
  onCloseTab(id: string): void;
  onTogglePin(tab: Tab): void;
  onNewTab(): void;
  onOpenBrine(): void;
  onSelectJar(id: string): void;
  onNewJar(): void;
}

/**
 * The sidebar — the design system's main-window architecture, in our
 * vocabulary. Tabs live here as rows (the active one wears Relish Pour),
 * Brine sits in the Pantry section, and the jar orbs along the footer are
 * the switcher. Glass at panel depth; the Aurora glows through.
 */
export default function Sidebar({
  jars,
  activeJarId,
  tabs,
  activeTabId,
  sealingIds,
  brineCount,
  totalPreserved,
  brineActive,
  onSelectTab,
  onCloseTab,
  onTogglePin,
  onNewTab,
  onOpenBrine,
  onSelectJar,
  onNewJar,
}: Props) {
  const activeJar = jars.find((j) => j.id === activeJarId) ?? null;
  const orbClip = superellipseClip(30, 4);

  return (
    <nav className="nr-side" aria-label="Sidebar">
      <div className="nr-side__head">
        <span
          className="nr-side__jarorb"
          style={{
            background: activeJar
              ? `radial-gradient(circle at 35% 30%,
                  color-mix(in oklab, var(--nr-jar-${activeJar.hue}) 55%, white),
                  color-mix(in oklab, var(--nr-jar-${activeJar.hue}) 82%, black))`
              : `radial-gradient(circle at 35% 30%,
                  color-mix(in oklab, var(--nr-hue-brine) 55%, white),
                  color-mix(in oklab, var(--nr-hue-brine) 82%, black))`,
          }}
          aria-hidden="true"
        />
        <span className="nr-side__jarname">
          {activeJar?.name ?? "Brine"}
        </span>
      </div>

      <button type="button" className="nr-side__newtab" onClick={onNewTab}>
        ＋ New tab
      </button>

      <span className="nr-side__kicker">Today</span>
      <ul className="nr-side__tabs" role="tablist" aria-label="Tabs">
        {tabs.map((tab) => {
          const active = tab.id === activeTabId;
          const pinned = tab.seal_after === null;
          return (
            <li
              key={tab.id}
              className="nr-side__tab"
              data-active={active || undefined}
              data-sealing={sealingIds.includes(tab.id) || undefined}
            >
              <button
                type="button"
                className="nr-side__tab-main"
                role="tab"
                aria-selected={active}
                title={tab.url ?? "New tab"}
                onClick={() => onSelectTab(tab.id)}
              >
                <span className="nr-side__tab-chip" aria-hidden="true">
                  {(domainOf(tab.url)[0] ?? "＋").toUpperCase()}
                </span>
                <span className="nr-side__tab-title">{tab.title}</span>
              </button>
              <button
                type="button"
                className="nr-side__tab-pin"
                title={pinned ? "Pinned — never seals" : "Pin — never seals"}
                aria-pressed={pinned}
                onClick={() => onTogglePin(tab)}
              >
                <span aria-hidden="true">{pinned ? "●" : "○"}</span>
                <span className="nr-visually-hidden">
                  {pinned ? "Unpin tab" : "Pin tab"}
                </span>
              </button>
              <button
                type="button"
                className="nr-side__tab-close"
                title="Close tab — it stays in your Pantry"
                onClick={() => onCloseTab(tab.id)}
              >
                <span aria-hidden="true">×</span>
                <span className="nr-visually-hidden">Close {tab.title}</span>
              </button>
            </li>
          );
        })}
      </ul>

      <span className="nr-side__kicker">Pantry</span>
      <button
        type="button"
        className="nr-side__pantry-row"
        data-active={brineActive || undefined}
        aria-pressed={brineActive}
        onClick={onOpenBrine}
      >
        <span className="nr-side__tab-chip" aria-hidden="true">◍</span>
        <span className="nr-side__tab-title">Brine</span>
        <span className="nr-side__count">{brineCount}</span>
      </button>

      <div className="nr-side__foot">
        <div className="nr-side__orbs" role="group" aria-label="Jars">
          {jars.map((jar) => (
            <button
              key={jar.id}
              type="button"
              className="nr-side__orb"
              data-active={jar.id === activeJarId || undefined}
              style={{
                clipPath: orbClip,
                background: `radial-gradient(circle at 35% 30%,
                  color-mix(in oklab, var(--nr-jar-${jar.hue}) 55%, white),
                  color-mix(in oklab, var(--nr-jar-${jar.hue}) 82%, black))`,
              }}
              title={`${jar.name} — ${jar.item_count} item${jar.item_count === 1 ? "" : "s"}`}
              onClick={() => onSelectJar(jar.id)}
            >
              <span aria-hidden="true">{jar.name[0]?.toUpperCase()}</span>
              <span className="nr-visually-hidden">{jar.name}</span>
            </button>
          ))}
          <button
            type="button"
            className="nr-side__orb nr-side__orb--new"
            style={{ clipPath: orbClip }}
            title="New jar"
            onClick={onNewJar}
          >
            <span aria-hidden="true">＋</span>
            <span className="nr-visually-hidden">New jar</span>
          </button>
        </div>
        <span className="nr-side__caption">
          {totalPreserved.toLocaleString()} things preserved,
          <br />
          none of them lost
        </span>
      </div>
    </nav>
  );
}
