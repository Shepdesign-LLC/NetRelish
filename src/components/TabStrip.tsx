import { domainOf } from "../lib/format";
import { type Tab } from "../lib/db";

interface Props {
  tabs: Tab[];
  activeTabId: string | null;
  /** Tab ids currently animating shut (a sweep in progress). */
  sealingIds: string[];
  onSelect(id: string): void;
  onClose(id: string): void;
  onTogglePin(tab: Tab): void;
  onNewTab(): void;
}

/**
 * The strip. Every tab here is already preserved — closing one costs
 * nothing, which is why the close button doesn't ask. A pinned tab (○/●)
 * never seals.
 */
export default function TabStrip({
  tabs,
  activeTabId,
  sealingIds,
  onSelect,
  onClose,
  onTogglePin,
  onNewTab,
}: Props) {
  return (
    <div className="nr-tabstrip" role="tablist" aria-label="Tabs">
      {tabs.map((tab) => {
        const pinned = tab.seal_after === null;
        const active = tab.id === activeTabId;
        return (
          <div
            key={tab.id}
            className="nr-tab"
            data-active={active || undefined}
            data-sealing={sealingIds.includes(tab.id) || undefined}
          >
            <button
              type="button"
              className="nr-tab__main"
              role="tab"
              aria-selected={active}
              title={tab.url ?? "New tab"}
              onClick={() => onSelect(tab.id)}
            >
              <span className="nr-tab__title">{tab.title}</span>
              <span className="nr-tab__domain">{domainOf(tab.url)}</span>
            </button>
            <button
              type="button"
              className="nr-tab__pin"
              title={pinned ? "Pinned — never seals. Click to unpin." : "Pin — never seals"}
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
              className="nr-tab__close"
              title="Close tab — it stays in your Pantry"
              onClick={() => onClose(tab.id)}
            >
              <span aria-hidden="true">×</span>
              <span className="nr-visually-hidden">Close {tab.title}</span>
            </button>
          </div>
        );
      })}
      <button
        type="button"
        className="nr-tabstrip__new"
        title="New tab (⌘T)"
        onClick={onNewTab}
      >
        <span aria-hidden="true">+</span>
        <span className="nr-visually-hidden">New tab</span>
      </button>
    </div>
  );
}
