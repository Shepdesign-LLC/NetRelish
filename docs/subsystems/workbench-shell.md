---
title: Workbench shell — the window's chrome, the Shelf's tiles, Seal's overlay and the jar fill
type: subsystem
created: 2026-11-18
updated: 2026-11-24
sources:
  - code: Sources/App/NetRelishApp.swift
  - code: Sources/App/Workbench.swift
  - code: Sources/Bench/TabStrip.swift
  - code: Sources/Bench/WindowChrome.swift
  - code: Sources/Bench/ShellRows.swift
  - code: Sources/Bench/BrineView.swift
  - code: Sources/Bench/Seal/SealOverlay.swift
  - code: Sources/Bench/Seal/SealAnchors.swift
  - code: Sources/Bench/Seal/SealedPill.swift
  - code: Sources/Shelf/JarFill.swift
  - code: Sources/Shelf/ShelfView.swift
  - code: Sources/UI/JarGlyph.swift
  - code: Sources/UI/FloatShadow.swift
  - code: Tests/NetRelishTests/ShellMeasureTests.swift
  - code: Tests/NetRelishTests/Seal/SealPhaseTests.swift
verified_at: 6306c6e
---

# Workbench shell

How the main window's chrome is put together since the facelift: the title strip with the
tabs, the address row, the bottom bar, the Shelf's jar tiles, the drawn jar, ⌘K, the Seal
overlay and the jar-fill drip. What it should look like is the manifest's
(`design/DESIGN_MANIFEST.md` v2.1, §4, §8, §8.1, §9, §10); what was decided, and what the
comp shows that isn't built, is `docs/adr/0035-workbench-facelift.md`. This page doesn't
copy either. Moving tabs and jars with the mouse is [[rearranging]]; compiling any of it is
[[building-without-a-mac]].

## Where things are

| Part | Code |
|---|---|
| The window's rows, the Panel's slide, ⌘K as an overlay | `ContentView` (`Sources/App/NetRelishApp.swift:372`) |
| The measures that aren't tokens | `NRShell` (`Sources/Bench/ShellRows.swift:15`), pinned by `ShellMeasureTests` |
| Title strip, address row and field, bottom bar | `TitleRow`, `SearchRow`, `AddressField`, `BottomBar` (`Sources/Bench/ShellRows.swift:40`, `:94`, `:182`, `:366`) |
| The tabs, their widths, the jar's chip | `TabStrip` (`Sources/Bench/TabStrip.swift:63`), `TabStripLayout` (`Sources/Bench/TabStrip.swift:15`) |
| The window's buttons on the 44pt strip | `WindowButtons.place` (`Sources/Bench/WindowChrome.swift:97`) |
| The Shelf's tiles | `JarTile` (`Sources/Shelf/ShelfView.swift:460`) |
| The drawn jar and its shades | `NRFilledJar` (`Sources/UI/JarGlyph.swift:255`), `JarPaint.edge300` / `edgeInk` (`Sources/UI/JarGlyph.swift:70`, `:88`) |
| The float shadow | `nrFloat(cornerRadius:)` (`Sources/UI/FloatShadow.swift:47`) |
| Seal's phases | `Workbench.sealActiveTab` (`Sources/App/Workbench.swift:1129`), `sealPhase` (`:1113`) |
| Seal's one overlay | `SealOverlay` (`Sources/Bench/Seal/SealOverlay.swift:27`), placed by `sealOverlay(_:)` and fed by `sealAnchor(_:)` (`Sources/Bench/Seal/SealAnchors.swift:43`, `:34`) |
| The jar-fill drip | `JarFillDriver` (`Sources/Shelf/JarFill.swift:27`), started by `Workbench.fillJar(_:)` (`Sources/App/Workbench.swift:1244`) |

## Seal: the Workbench decides, the overlay presents

`sealActiveTab` publishes `.started` on the key press and `.frozen` or `.failed` when the
write returns; the overlay plays phase A on the first and phase B on the second, never
sooner than `SealTiming.minimumA` after A (`Sources/Bench/Seal/SealOverlay.swift:225`).
Nothing in the overlay decides when anything happens to the Pantry: every effect of Seal
has already happened when it starts B. The overlay only paces the picture, then calls
`releaseSealedTab` when the chip leaves and `sealPresentationEnded` when it lands.

## Traps

> ⚠️ **The tab closes when the write returns. Never move the close to match the motion.**
> Non-negotiable 3. The comp closes it at +640ms; the app can't, because the write can fail
> and Seal from Shortcuts has no motion. So the Workbench keeps a picture of the closed tab,
> `sealHeldTab`, which the strip draws at its old place through `stripTabs`
> (`Sources/App/Workbench.swift:1230`). A 4s safety task (`endSealLater`, `:1209`) lets go of it
> if no overlay does.

> ⚠️ **The held picture is an animation anchor and nothing else.** It is never the selected
> tab, and the address row never reads it: the address, the lock and its spoken hint, and
> the selection all follow the live Bench content, `benchTab` (`Sources/App/Workbench.swift:206`),
> from the moment the tab closes (manifest v2.1.1, a security correction). Before it,
> `sealHeldFrontTab` kept the sealed page's address and lock in the row while another page
> was already in front. Don't bring it back, and don't count a tab's place in `stripTabs`:
> the strip counts places in `workbench.tabs` (`Sources/Bench/TabStrip.swift:107`), so the
> picture is never one of them. `SealPhaseTests` holds this.

> ⚠️ **The failure line waits for phase B.** `reportSealFailure` (`Sources/App/Workbench.swift:1185`)
> says "Couldn’t seal this page" no sooner than 700ms after the press. A test that checks
> `fillStatus` after a failed Seal must wait for it, as `SealPhaseTests` does.

> ⚠️ **`.sealOverlay(workbench)` must stay before `.ignoresSafeArea`** in `ContentView`
> (`Sources/App/NetRelishApp.swift:428`). Inside the safe-area change, the overlay covers
> the title strip and reads every anchor in the window's own space. Move it after, and the
> overlay no longer spans the title strip, so the band and the drops are drawn against a
> space that doesn't match where the tabs are (`(unverified)` in a running build).

> ⚠️ **`sealAnchor(_:)` adds to its children's anchors; it must never replace them.** It is
> a `transformAnchorPreference` (`Sources/Bench/Seal/SealAnchors.swift:34`). The strip
> publishes `.tabStrip` around tabs that publish `.tab(id)`, and the Shelf's column
> publishes `.shelfJars` around jars that publish `.jar(id)`. A plain `anchorPreference` on
> the container would drop the tabs, `SealScene.make` would find no front tab, and Seal
> would play nothing.

> ⚠️ **`WindowButtons.place` leans on AppKit's private title-bar layout**
> (`Sources/Bench/WindowChrome.swift:97`). It moves the three buttons, and grows the
> title-bar container only by the point or two the buttons need. Never stretch the
> container, or the title-bar view inside it, over the strip: it lies over every tab and
> takes their drag. It is reapplied on resize, leaving full screen and becoming key.
>
> **This already happened.** The facelift (`8de5828`) set `titlebar.frame = container.bounds`,
> which is the full window width, so a ~30pt band covered the mark and the top of every
> 44pt tab. A tab could not be dragged onto a jar from then until the width was clamped to
> `NRShell.markLeading` (`Sources/Bench/WindowChrome.swift:119`). Right-click and hover
> survived — a transparent title bar has no control to consume them — so only the drag
> went, which is why nothing looked deleted. `RearrangingUITests.testDraggingATabOntoAJarMovesIt`
> is the test that holds it.

> ⚠️ **A double-click on the title strip is AppKit's.** `WindowDragArea`
> (`Sources/Bench/WindowChrome.swift:139`) only drags. Reading `AppleActionOnDoubleClick` to
> do it ourselves is a read of a system-written default, which the privacy manifest has no
> reason for ([[privacy-and-sandbox]]), and a second handler zooms twice, which looks like
> nothing happening.

> ⚠️ **The address field's real `TextField` must keep the click and stay in the
> accessibility tree.** Idle with a page in front, its text is clear and the styled host and
> path are an overlay that takes no hits (`AddressField`, `Sources/Bench/ShellRows.swift:231`).
> At opacity 0, VoiceOver loses "Address" and a click can't place the caret.

> ⚠️ **The Panel's inset changes once, after the slide** (`ContentView`'s
> `.task(id: workbench.showPanel)`, `Sources/App/NetRelishApp.swift:437`). A real page
> reflows once and never per frame. Animating the inset itself would resize the web view on
> every frame.

> ⚠️ **⌘K is an overlay, not a sheet, so nothing gives the keyboard back when it closes.**
> `ContentView` hands it to the page in front (`Sources/App/NetRelishApp.swift:515`). A new
> overlay with a text field needs the same, or typing goes nowhere until the page is
> clicked.

> ⚠️ **Measures live in `NRShell`, tokens in `Sources/UI/Tokens.swift`.** That file is
> generated from `design/tokens.css` by `scripts/gen-tokens.swift`; a new layout measure goes
> in `NRShell` (ADR 0034) so the generator need not learn a name. `ShellMeasureTests` pins
> the manifest's numbers: change one, change the test with it.

> ⚠️ **A view at opacity 0 leaves the accessibility tree.** A smart-jar row's Restore or Open
> button fades in on hover, so the row carries the action itself (`SmartJarRowView`,
> `Sources/Bench/BrineView.swift:343`). Any hover-only control needs the same.
