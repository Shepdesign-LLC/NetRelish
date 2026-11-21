---
title: Workbench shell — the window's chrome, the Shelf's tiles, Seal's overlay and the jar fill
type: subsystem
created: 2026-11-18
updated: 2026-11-21
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
verified_at: 766ec58
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
| The window's rows, the Panel's slide, ⌘K as an overlay | `ContentView` (`Sources/App/NetRelishApp.swift:187`) |
| The measures that aren't tokens | `NRShell` (`Sources/Bench/ShellRows.swift:15`), pinned by `ShellMeasureTests` |
| Title strip, address row and field, bottom bar | `TitleRow`, `SearchRow`, `AddressField`, `BottomBar` (`Sources/Bench/ShellRows.swift:40`, `:94`, `:182`, `:366`) |
| The tabs, their widths, the jar's chip | `TabStrip` (`Sources/Bench/TabStrip.swift:63`), `TabStripLayout` (`Sources/Bench/TabStrip.swift:15`) |
| The window's buttons on the 44pt strip | `WindowButtons.place` (`Sources/Bench/WindowChrome.swift:97`) |
| The Shelf's tiles | `JarTile` (`Sources/Shelf/ShelfView.swift:289`) |
| The drawn jar and its shades | `NRFilledJar` (`Sources/UI/JarGlyph.swift:255`), `JarPaint.edge300` / `edgeInk` (`Sources/UI/JarGlyph.swift:70`, `:88`) |
| The float shadow | `nrFloat(cornerRadius:)` (`Sources/UI/FloatShadow.swift:33`) |
| Seal's phases | `Workbench.sealActiveTab` (`Sources/App/Workbench.swift:1075`), `sealPhase` (`:1059`) |
| Seal's one overlay | `SealOverlay` (`Sources/Bench/Seal/SealOverlay.swift:27`), placed by `sealOverlay(_:)` and fed by `sealAnchor(_:)` (`Sources/Bench/Seal/SealAnchors.swift:42`, `:34`) |
| The jar-fill drip | `JarFillDriver` (`Sources/Shelf/JarFill.swift:27`), started by `Workbench.fillJar(_:)` (`Sources/App/Workbench.swift:1186`) |

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
> (`Sources/App/Workbench.swift:1162`), and `sealHeldFrontTab` (`:1179`) keeps that picture
> in front and the address field on its address until the chip leaves. A 4s safety task
> (`endSealLater`, `:1141`) lets go of it if no overlay does.

> ⚠️ **The failure line waits for phase B.** `reportSealFailure` (`Sources/App/Workbench.swift:1127`)
> says "Couldn’t seal this page" no sooner than 700ms after the press. A test that checks
> `fillStatus` after a failed Seal must wait for it, as `SealPhaseTests` does.

> ⚠️ **`.sealOverlay(workbench)` must stay before `.ignoresSafeArea`** in `ContentView`
> (`Sources/App/NetRelishApp.swift:227`). Inside the safe-area change, the overlay covers
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
> container over the strip: it would lie over every tab and could take their drag, drop,
> right-click and hover. It is reapplied on resize, leaving full screen and becoming key.

> ⚠️ **A double-click on the title strip is AppKit's.** `WindowDragArea`
> (`Sources/Bench/WindowChrome.swift:139`) only drags. Reading `AppleActionOnDoubleClick` to
> do it ourselves is a read of a system-written default, which the privacy manifest has no
> reason for ([[privacy-and-sandbox]]), and a second handler zooms twice, which looks like
> nothing happening.

> ⚠️ **The address field's real `TextField` must keep the click and stay in the
> accessibility tree.** Idle with a page in front, its text is clear and the styled host and
> path are an overlay that takes no hits (`AddressField`, `Sources/Bench/ShellRows.swift:182`).
> At opacity 0, VoiceOver loses "Address" and a click can't place the caret.

> ⚠️ **The Panel's inset changes once, after the slide** (`ContentView`'s
> `.task(id: workbench.showPanel)`, `Sources/App/NetRelishApp.swift:236`). A real page
> reflows once and never per frame. Animating the inset itself would resize the web view on
> every frame.

> ⚠️ **⌘K is an overlay, not a sheet, so nothing gives the keyboard back when it closes.**
> `ContentView` hands it to the page in front (`Sources/App/NetRelishApp.swift:295`). A new
> overlay with a text field needs the same, or typing goes nowhere until the page is
> clicked.

> ⚠️ **Measures live in `NRShell`, tokens in `Sources/UI/Tokens.swift`.** That file is
> generated from `design/tokens.css` by `scripts/gen-tokens.swift`; a new layout measure goes
> in `NRShell` (ADR 0034) so the generator need not learn a name. `ShellMeasureTests` pins
> the manifest's numbers: change one, change the test with it.

> ⚠️ **A view at opacity 0 leaves the accessibility tree.** A smart-jar row's Restore or Open
> button fades in on hover, so the row carries the action itself (`SmartJarRowView`,
> `Sources/Bench/BrineView.swift:219`). Any hover-only control needs the same.

> ⚠️ **Work a chip's arguments out before the view builder, never inside it.** The tab strip's
> `ScrollViewReader` is deep — reader, scroll view, `HStack`, `ForEach`, the chip and its
> modifiers — and when the per-chip width test and state lookups sat inside the `ForEach` as
> well, the Swift type-checker ran out of time on the whole thing: `Release-Direct` and the
> UI-test build both failed with *"unable to type-check this expression in reasonable time"* at
> `TabStrip.swift`, and blamed symbols in **three other files** that were perfectly fine
> (`held`, `shownTab`, `order` all exist). It had passed on the commit before, so it sat right
> on the limit and tipped over with the machine's mood. `ChipPlan`
> (`Sources/Bench/TabStrip.swift:57`) settles each chip's part as plain code first. Add an
> inline ternary or set lookup back into that `ForEach` and you are spending the margin again.
>
> The shape of that failure is worth knowing on its own: a type-check timeout reports as
> *"cannot find X in scope"* in files you never touched. Check whether the symbol exists before
> believing it.
