# ADR 0036 — What the app says out loud, and what works without a mouse

**Status:** proposed · **Date:** 2026-11-18 · **PR:** feat(a11y): VoiceOver, the keyboard, and the Mac's accessibility settings

P5's line in `docs/NetRelish_Plan_and_Roadmap.md` §5 is "Accessibility: VoiceOver on
Shelf/Tray/Inspector, full keyboard nav, Reduce Transparency respected", and the phase is
done when "VoiceOver can complete capture → jar → seal". Four things had to be decided to
build that, and none of them is covered by `CLAUDE.md`. Merging this PR is the decision.

In today's app the Tray is **Brine** (the bottom bar's pill and the smart-jar rows) and the
Inspector is the **Panel** (⌘⌥I).

## 1 · The app speaks results that nothing on screen announces

Capture, Seal, a tab sinking, a restore, a jar move and a failure all change state while
the keyboard stays where it was. VoiceOver says nothing about a view that changed somewhere
else, so the app now posts an announcement at those points: `NRAnnounce.post(_:priority:)`
in `Sources/UI/Accessibility.swift`.

- **Spoken lines are user-facing copy** and follow `docs/voice/`. They live as named
  statics next to the code that fires them (`Workbench.capturedLine`, `sealedLine`,
  `sankLine`, `ShelfView.boardLine`, `JarTile.movedLine`, …) so a test can pin them.
- **One line per event.** The status line in the address row speaks every `fillStatus`
  change, so the Workbench never also announces what `report(_:)` already showed.
- **Only in front.** Announcements are dropped unless the app is active, so a Shortcut
  sealing in the background is silent.
- **Priority:** `.high` for the result of something the person just did (Seal, capture,
  a move, a failure), `.medium` for everything that happens on its own (a tab sinking).

## 2 · Keys and menu items, so nothing needs the pointer

Every route that only a drag, a hover or a right-click could reach now also has a menu item
or a VoiceOver action. New keys:

| Key | What | Why it is new |
|---|---|---|
| ⌘L | Bench › Open Location… | There was no way to reach the address field from the keyboard. Safari's key. |
| ⌃Tab / ⌃⇧Tab | Tab › Show Next / Previous Tab | The strip could only be clicked. |
| ⌘[ / ⌘] | Back / Forward | The buttons had no keys. Safari's keys. |

New menu items, all without keys: **Tab › Move Tab to Jar ›** *(jar)*, **Move Tab Left**,
**Move Tab Right**; **Jars › Show Board**, **Move Jar Up**, **Move Jar Down**, and every
jar listed (the first nine keep ⌘1–9). Each announces what it did.

Every way into a jar still plays the jar fill (the `rearranging` trap): the menu's *Move to
Jar*, Brine's *Restore* and *Restore to…* now go through the same path a drop does, so the
drip plays once on each. That is a **new drip on routes that had none** — manifest §7, the
jar-fill placement.

## 3 · The Mac's accessibility settings change what is drawn

Honored live, and nothing changes for anyone who has them off:

| Setting | What changes |
|---|---|
| Reduce Motion | Seal becomes a fade and the jar fill a plain level change, as manifest §8.1 and §9 already said; jars stepping aside on the Shelf jump to their places. `nrSystemAccessibility()` now hands the live setting to `--nr-reduce-motion`'s Swift twin at each window root, where it used to be read once at launch. |
| Reduce Transparency | The ⌘K scrim goes fully opaque; floats keep their edge rather than leaning on the shadow. |
| Increase Contrast | Hairlines go `--nr-fg-3`, `--nr-fg-3` text goes `--nr-fg-2`, and the active jar tile's edge firms to `--relish-700`/`text-700`. Reader's page gets the same under `prefers-contrast: more`. |
| Differentiate Without Color | A sinking tab gets a neutral sink mark beside its title, the Brine pill spells out "N new", the selected ⌘K row and the selected Shelf row take a neutral edge, and Reader's on state takes a filled glyph. |

**No new tokens.** Each surface picks the alternate value locally (`ShellInk` in
`Sources/Bench/ShellRows.swift`). Whether `tokens.css` should carry contrast variants is
left open — see *Still open*.

## 4 · The UI test launches the app with a fixture, in Debug only

`CLAUDE.md` requires "UI tests for capture → jar → seal", and the P5 criterion is that
VoiceOver can complete that path. One XCUITest now walks it through the accessibility tree,
which proves both at once. It needs an app with known jars and a page that loads with no
network, so:

- **`-NRUITestFixture`**, a launch argument read only from `ProcessInfo.arguments`, all of
  it inside `#if DEBUG` (`Sources/App/UITestFixture.swift`, and three `#if DEBUG` call
  sites). Release-AppStore and Release-Direct compile none of it.
- It gives the app an **in-memory Pantry**, its own defaults suite and Keychain service, no
  share inbox, no summarizer, no timestamp authority, Pro unlocked so StoreKit is never
  reached, and two jars. The real Pantry is never opened.
- The page is served from memory on a **`nr-fixture:` scheme handler** installed on each
  tab's configuration. A custom scheme, not `loadHTMLString`, because the same URL has to
  survive being typed, reloaded, restored from Brine and moved to another jar's profile
  (non-negotiable 6 gives each jar its own store).
- **No new endpoint, no localhost, no file read** (non-negotiable 5). Seal needs no http.
- A new scheme, **NetRelish UI Tests**, runs it, and a new CI job runs that. The existing
  Test job and its scheme are unchanged.

## What this does not do

| Not here | Why |
|---|---|
| The onboarding sheet (P5's "3 screens, ends with the user's first Seal") | A separate item, and its copy is undecided. ADR 0034 already set aside the v5 sheet's copy. |
| VoiceOver moving its cursor onto Brine's first row when Brine opens | Auto-focus would draw a focus ring after pointer use. It needs a device check. |
| Contrast variants in `tokens.css` | A design decision for Ryan, not a code one. |
| Pinned-tab reordering by ⌥↑/⌥↓ on the Shelf | More keys than the path needs; the menu items cover it. |

## Still open, for Ryan

1. **Contrast tokens.** Should `design/tokens.css` carry an Increase Contrast set, so the
   alternates stop living in Swift? Today each surface decides, which is four files.
2. **"Sank" wording.** Brine says a captured page "sank" to Brine, which is the drawn copy
   today. VoiceOver now says it out loud, where it reads oddly for something the person
   just captured on purpose.
3. **The system focus ring.** Standard buttons in sheets now draw `--nr-focus` through
   `nrFocusRing(cornerRadius:)` rather than the system accent ring, so the window has one
   focus color (manifest §4, placement 7). If the system ring is wanted in sheets, that is
   one modifier to remove.
