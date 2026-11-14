# ADR 0034 — The window takes the Workstation v5 look

**Status:** proposed · **Date:** 2026-11-14 · **PR:** feat(shell): the Workstation v5 window

Ryan, Nov 14, with the v5 prototype attached: "I want the workbench to look and have the new and same logic like before, just in its modern skin and framework." Then two screenshots of the prototype, dark and light: "Should look like this."

**Decision:** the main window is rebuilt to the v5 layout and colors, in SwiftUI, over the logic the app already has. Nothing a person could do before is gone. This reverses part of ADR 0010 rows 3 and 4 (which kept the v1.2 look), so the manifest goes to **v2.0**. Merging this PR is the decision.

## What changed in the window

| v5 | In the app now |
|---|---|
| Four rows: 48 / 46 / body / 44 | `TitleRow`, `SearchRow`, Shelf · Bench · Panel, `BottomBar`. The system title bar is hidden; its three buttons stay. |
| Tab strip in the title row, led by the jar's chip; tabs 176 wide, pinned 46, always bordered | Built. The tab in front takes the jar's color on its border and bottom edge. Right-click and drag work as before. |
| Full-width address row with a relish top line | Built. One field for every tab, in place of a bar inside each tab. With no page in front, what you type opens in a new tab. |
| Shelf 238 wide, always open, section labels, jar rows with a filled jar and a count | Built. Sections: Jars, Pantry (Today, Sealed, Sinking soon), Zest (a row opens the Zest window on that tool). |
| The jar drawn live, filled in its own color | Built (`NRFilledJar`), all six layers of spec §4. |
| Jar board as the Bench's default view | Built. It shows the jar's open tabs and what the jar keeps. |
| Brine as a pill in the bottom bar | Built. It lights up when something has sunk and opens Brine on the Bench. ⌃⌘1 still works. |
| Six jar colors | The menu and the Panel offer v5's six. Jars keep whatever color they already had. |

## What v5 shows that this PR does not build, and why

| v5 | Why not here |
|---|---|
| Notes (cards, note page, quick note) | Not in 1.0 (ADR 0012). The board's second grid shows what the jar keeps instead: its captured and sealed pages. |
| "Holds 14", per-jar capacity | `Jar` has no capacity field, and the model changes only in System Designer. Every jar is drawn to hold 12 (v5's default; spec §9.1 names a fixed number as the alternative). The Shelf shows a plain count, not "4/12", so nobody reads a limit they can't change. |
| The Dev switch and its panel | That is Mason Jar: direct build only, 1.2 (ADR 0010 row 7, ADR 0029). |
| Seal jar, Archive with Undo, Duplicate, Lock | Seal is per item (non-negotiable 3). The rest need fields the model doesn't have (ADR 0028). |
| Profile avatar, appearance switch | Profiles are uncosted (ADR 0010 row 6). The app follows the Mac's appearance. |
| Guide pages, the onboarding sheet | Their copy is about notes, capacity and sealing a jar. They need new copy for what the app does. |
| Glass and blur, shadows on chrome, Bricolage headings | Still out. The screenshots read as flat color and hairlines, and the app matches them without blur. Bricolage would mean shipping a font file. |
| "Search, or type a web address" | The field says "Type a web address". A search would send what you type to a search engine, and which one is a decision nobody has made (non-negotiable 5 lists the network calls). |

## Decisions for Ryan

1. **Manifest v2.0.** Relish placement 2 (the tab lip) retires; 10–13 arrive: the address row's top line, the address and Zest glyphs, the Shelf's section tiles, the Brine pill while something has sunk. The jar's own color gets a list of its own in §4.
2. **Clicking a jar on the Shelf opens its board**, as in v5. ⌘1–9, Shortcuts and the palette still open the jar on its page, as before. If the Shelf should open the page too, it is one line.
3. **The fixed 12.** If jars should hold a number you set, the next System Designer round needs `capacity` (number) on `Jar`.
4. **The shell's measures** (48, 46, 44, 176, 46) live in `NRShell`, hand-written, because `scripts/gen-tokens.swift` only knows five layout names. Proposed: teach the generator the new names in its own PR and move them to `tokens.css`.
5. **`NRTabLip` and `#nr-lip`** stay in the Design Kit until the next symbols pass; nothing in the window uses them now.

## Rule check

- **NN1:** no new table or kind. The board reads `items` by `jarId`.
- **NN2:** Brine is still a query. The pill opens the same view ⌃⌘1 does.
- **NN3:** nothing here seals. A sealed card opens its saved copy, read only.
- **NN4, NN5:** no model call, no new network call. The address field only loads pages.
- **NN6:** unchanged. Each window still keeps its own web views, one store per jar.

## Not checked in the cloud session

There is no Mac here, so the window was never seen running. Three things to look at first in the demo: the window's three buttons against the 48pt row, dragging a tab in the title row (it must reorder, not move the window), and moving the window by the empty part of that row.
