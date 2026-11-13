# ADR 0028 — Right-click and drag on the Shelf and the tab strip

**Status:** proposed · **Date:** 2026-11-13 · **PR:** feat(shelf): right-click menus and drag for jars and tabs

Ryan, Nov 13: start with "right-click functionality and the capability of moving objects", and "the jars should be able to be moved around as well, but still limited in their movement". This is the Workstation v5 handoff's Phase 3 (`docs/design/workstation-v5/docs/01-SPEC.md` §7.1 and §7.2), built on the Shelf and tab strip the app has today. It needs no change to the model.

## What moves

| Drag | Onto | Result |
|---|---|---|
| A jar | Along the Shelf | It changes places. It slides up and down the rail and nowhere else, and stops at both ends. |
| A tab | Another tab | It takes that tab's place in the strip. |
| A tab | A jar on the Shelf | It moves to the end of that jar's strip. |
| A Brine row | A jar on the Shelf | It reopens in that jar. The item stays in Brine, as with Restore. |

Notes can't be dragged yet because the app has no notes yet (ADR 0012).

**Moving a tab to another jar does not move its sign-in.** Every jar has its own cookies and sessions (non-negotiable 6). The tab keeps its address, lets go of its web view, and loads again in the new jar. Its saved history and form state are dropped for the same reason. A Brine row restored into a jar other than the one it sank from also comes back without them.

**Jars use their own gesture, not the system drag.** That is what keeps a jar on the rail: the system drag would let it be carried anywhere. Move Up and Move Down in the jar's menu do the same thing from the keyboard.

## Right-click

- **A jar:** New Tab in this jar, Edit Jar…, a row of six colors, Move Up, Move Down.
- **A tab:** Pin or Unpin, a row of eight icons, Copy Link, Move to Jar, Close, Close Other Tabs.
- **A Brine row:** Restore to each jar.

v5 also lists Lock (a tab that can't be closed), Archive with Undo, Duplicate, and jar capacity. Each needs a field the model doesn't have, so they wait for the next System Designer round.

## Decisions for Ryan

1. **The drop mark is relish placement 9** (manifest v1.3): a `--lip-h` relish bar on the leading edge of the jar or tab a drag would land on, shown only during the drag. It is v5's "3px inset bar in relish". If relish should not go there, it becomes `--nr-fg-2` and the manifest line comes out.
2. **A tab's icon is kept in UserDefaults for now**, by tab id, and forgotten when the tab closes, sinks or is sealed. `Tab` has no place for it. Proposed for the next System Designer round: a `glyph` string on `Tab`, as `Jar` already has. When it lands, the icon moves there and this store goes.
3. **Tab icons are SF Symbols**, not v5's drawn set, per manifest §7. v5's WordPress logo has no system symbol; "Build" (a hammer) stands in.
4. **The six menu colors** share one lightness and chroma (`oklch(72% 0.14 h)`), so no jar is louder than another. Any other color is still in Edit Jar….

## Rule check

- **NN1:** no new table or kind.
- **NN2:** Brine is still a query. Dropping a row on a jar opens a tab; it doesn't move the item.
- **NN5:** nothing leaves the device. Copy Link writes to the clipboard.
- **NN6:** a moved tab starts clean in the new jar's store, as above.
