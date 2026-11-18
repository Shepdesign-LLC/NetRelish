# ADR 0035 — The workbench facelift

**Status:** proposed · **Date:** 2026-11-18 · **PR:** feat(shell): the workbench facelift

Ryan, Nov 17, on the first draft of the comp: "put our icon on the top left". Ryan, Nov 18, on the comp after review (`docs/design/workbench-facelift/index.html`), answering its eight decisions: "all yes, build it".

**Decision:** the main window is redrawn to the comp, in the language of Ryan's beta art, over the logic the app already has. The structure ADR 0034 built stays (Shelf, Bench, Panel, bottom bar, the jar board, Brine as a pill); what changes is how it is drawn and where relish is allowed. The manifest goes to **v2.1** and `tokens.css` gains the comp's neutrals. Merging this PR is the decision.

## What changed

| # | Decision Ryan approved | In the app now |
|---|---|---|
| 1 | Attached tabs: the front tab white and joined to the Bench, a top lip in the jar's color; tabs behind filled light grey, unbordered | `Sources/Bench/TabStrip.swift` (the strip moves out of `BenchView.swift`), `NRTabLip` and `NRTabShape` in `Sources/UI/Components.swift`, measures in `NRShell` (`Sources/Bench/ShellRows.swift`). `--lip-h` 3 → 5. The 2pt bottom bar goes. |
| 2 | Relish off the chrome | The address row's relish line and the Shelf's section tiles are gone (placements 10 and 12 retire). Zest glyphs go `--nr-fg-2`. Placement 11 narrows to the address field's leading lock (`lock.fill`, https only; a plain-http page shows a neutral globe). `NRBadge` is neutral. The Brine pill lights only for what is new since Brine was last opened (`Workbench.brineFresh`). |
| 3 | The Shelf as a 120pt rail of big jars | `Sources/Shelf/ShelfView.swift`: 100 × 88 tiles, the jar at 58, then Today / Sealed / Sinking soon as 28pt rows, Zest at the bottom, New Jar "+" under the jars. `--shelf-w` 238 → 120. ⌘1–9, ⌃⌘1–4, the menus, reordering and dropping onto a jar all stay. |
| 4 | Idle jars keep their own color; the jar redrawn as line art | `NRFilledJar` in `Sources/UI/JarGlyph.swift`: outline, separate neck, lid (ink when active, grey when idle), flat fill with a meniscus, one highlight, no gradients. Its `size` is now its drawn height. `JarPaint` gains `wash100`, `edge300`, `text700` and `isRelish`. |
| 5 | Seal in two phases | `Workbench.sealPhase` (`.started`, then `.frozen` or `.failed`) in `Sources/App/Workbench.swift` drives one window-level overlay (`Sources/Bench/Seal/SealOverlay.swift`, placed with `sealOverlay(_:)`, fed by `sealAnchor(_:)` from the strip, the address row, the page and the Shelf). The Sealed pill (`Sources/Bench/Seal/SealedPill.swift`). The jar-fill drip (`Workbench.fillJar(_:)`, `Sources/Shelf/JarFill.swift`). `SealDrip.swift` and `sealTrigger` are gone. |
| 6 | Soft shadow only on floating things | `nrFloat(cornerRadius:)` in `Sources/UI/FloatShadow.swift`: light gets the two shadows, dark a hairline. Chrome rows stay flat. |
| 7 | Rows 44 / 44 / 32, the Panel closed at launch | `NRShell.titleH`, `addressH`, `fieldH`, `barH`. The window's minimum is 960 × 600. `Workbench.showPanel` defaults to false under the same key, so anyone who set it keeps their choice. |
| 8 | Ask stays 1.1; ⌘K restyled | `PaletteView` floats as an overlay over a `--nr-canvas` scrim, with the field as a 52pt row in a 12pt-radius float box (the comp's palette; only Ask's field is a pill) and rows grouped Pantry / Open tabs / Commands. It hands the keyboard back to the page in front when it closes, as the sheet did. No Ask UI ships (ADR 0012). |
| Nov 17 | The icon at the top left | The cog mark at 28pt right after the window buttons, opening the jar's board, as before. The window buttons are re-centered on the 44pt strip by a small AppKit helper (`Sources/Bench/WindowChrome.swift`), which leaves AppKit's title-bar container at its own height so it never lies over the tabs. A double-click on the strip is AppKit's title bar's own: the app reads no system setting for it. |

New tokens: `--nr-canvas`, `--nr-rail`, `--nr-tab`, `--nr-tab-hover`, `--nr-float`, `--nr-hairline-soft`, `--nr-jar-line`, `--nr-jar-lid` and `--ease-drip`. `--nr-hairline` is `#E5E5E2`; `--nr-fg-3` is `#6C6C65` / `#96968F` because the old values failed AA as text (dark `#96968F` holds 4.5:1 on `--nr-tab-hover`, where sinking tab titles sit under the pointer). The layout measures that aren't tokens stay in `NRShell`, hand-written, as ADR 0034 did.

## What the comp shows that this PR does not build, and why

| In the comp | Why not here |
|---|---|
| Ask the Pantry (field, answer, cited cards) | 1.1, not 1.0 (ADR 0012). Decision 8 says so. |
| The Sink motion (tabs dip, a chip falls to the Brine pill) | Not one of the eight decisions. Tabs still sink as they do today; the Brine pill lights for them. |
| Favicons | A separate decision: the comp's own note says it would read `<link rel=icon>` from the loaded page (no new endpoint), but nobody has decided it. Tabs keep the picked symbol or the site's first letter. |
| Restore All in Brine | A new command, not a redraw. |
| A smart jar keeping the jar's tabs on screen | A behavior change: today a smart jar shows its own list. |
| The comp's 300pt Panel | `--inspector-w` stays 322. |
| `--shadow-float-1` (Ask's result cards) | Ask is 1.1. Only the one float shadow ships. |
| Redrawing the DEBUG Design Kit gallery | It keeps compiling against the same component inits; it isn't redrawn. |
| Jar-switch motion beyond the tile (the tabs cross-fading out and in with a 6pt slide, the lip's color fading, the Bench cross-fading) | The tile's wash, edge, lid and a 320ms bump are built. Re-keying the Bench to cross-fade would rebuild the page's web view; it needs its own pass. Manifest §9 says what is built. |
| Keeping the sealed page on screen through phase B (a snapshot over the Bench until the chip leaves) | The strip keeps the sealed tab in front and the field keeps its address (`Workbench.sealHeldFrontTab`), but the Bench shows the next tab's page from write return, and the page blink lands on it. A `takeSnapshot` over the page is the follow-up. |
| The board's fixed 3-column grid, at most 6 kept cards with "Show all N", and its tab tile's `--nr-tab` square | The grid stays adaptive (cards at least 252pt), so it holds with the Panel open; every kept card shows; the tab tile uses `TabIcon`. |
| Tabs at 7pt (front) and 11pt (behind) from the strip's top in a 45pt scroller | They sit at 6 and 10 in the 44pt strip, so the front tab ends on the strip's hairline without overflowing into the address row. 1pt higher than the comp. |
| `--fg-2` at `#56564F` / `#B5B5AF`, as the comp renders it | Not in the comp's token-delta list, so `--nr-fg-2` stays `#66665F` / `#A8A8A2`. Changing it is a separate token change. |
| `--jar-gloss` (`#E3E3DF` / `#34342F`) | The glass highlight uses `--nr-hairline`, within a step of it; no new token. The in-liquid stripe is built. |

## Seal, and non-negotiable 3

The comp closes the tab 640ms into phase B. The app closes it when the Pantry write returns, as it always has, because the motion must never change when or whether Seal's effects happen. What that costs:

- The Bench switches to the next tab's page at write return, which can be before the drops drain.
- The tab strip draws a copy of the sealed tab, which takes no clicks (`Workbench.stripTabs`, `sealHeldTab`), until the flying chip leaves. While it does, that copy stays the front tab (white, with its lip) and the address field keeps the sealed page's address (`Workbench.sealHeldFrontTab`), so the Sealed pill lands on the page that was sealed. The overlay releases it; a 4s safety task in the Workbench releases it if no overlay does (an inactive window, or Seal from Shortcuts with no window).
- On a write faster than 700ms the page switches while phase A is still playing. Phase B still waits for 700ms, and so does the failure line ("Couldn’t seal this page"), which the Workbench says no sooner than 700ms after the press. Only the line waits.

## Rule check

- **NN1:** no new table or kind.
- **NN2:** Brine is still a query. The pill's new "fresh" count compares `updatedAt` with a date kept in the app's defaults (`brine.seenAt`); first launch after the update stamps now, so nothing lights.
- **NN3:** Seal still stamps `sealedAt`, freezes the web archive, closes the tab at write return, fires `onSeal` and runs the jar's Recipe. The motion is presentation only; the strip holds a copy of the closed tab, which can't be clicked, for at most 4s.
- **NN4, NN5:** no model call, no new network call.
- **NN6:** unchanged. One data store per jar.
- **NN7:** unchanged. Seal from Shortcuts plays nothing and does what it did.

## Brand check

Manifest v2.1 touches §3 (the new neutrals; dark is never green), §4 (placements 10 and 12 retire, 6, 11 and 13 narrow, 4 gains the Sealed pill; the jar's color has a new list and a shade rule), §6 (one float shadow on floating things; tabs r 8, cards r 10), §7 (`#nr-lip` is back, in the jar's color), §8 (Shelf, the jar drawn, title strip, tabs, address row, board, Panel, bottom bar, badge, palette, Seal in two phases, jar fill, empty states), §9 (`--ease-drip`, the Panel slide, tab motion, Reduce Motion) and §10 (the window's composition, 960 × 600, the Panel closed).

## Not checked in the cloud session

There is no Mac here, so the window was never seen running. Look first, in the demo, at: the window buttons on the 44pt strip (they can flicker or reset after full screen), the front tab covering the strip's hairline, the ⌘K field taking keyboard focus over a page and giving it back when it closes, the Seal overlay drawing above the page (its anchors, from the tabs inside the strip and the jars inside the Shelf's column, merge with the strip's and the column's own), dragging a tab onto a tab and onto a jar and right-clicking a tab across its whole height, a double-click on the strip's top 28pt (the system title bar's height) zooming exactly once, and Reduce Motion.
