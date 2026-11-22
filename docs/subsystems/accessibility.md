---
title: Accessibility — what VoiceOver hears, and what works without a mouse
type: subsystem
created: 2026-11-18
updated: 2026-11-21
sources:
  - code: Sources/UI/Accessibility.swift
  - code: Sources/UI/Components.swift
  - code: Sources/App/NetRelishApp.swift
  - code: Sources/App/Workbench.swift
  - code: Sources/App/PaletteView.swift
  - code: Sources/Bench/ShellRows.swift
  - code: Sources/Bench/TabStrip.swift
  - code: Sources/Bench/BrineView.swift
  - code: Sources/Bench/JarBoard.swift
  - code: Sources/Bench/BenchView.swift
  - code: Sources/Bench/ComparisonView.swift
  - code: Sources/Shelf/ShelfView.swift
  - code: Sources/App/WelcomeSheet.swift
  - code: Sources/App/UITestFixture.swift
  - code: Tests/NetRelishUITests/CaptureJarSealUITests.swift
  - code: Tests/NetRelishTests/Accessibility/UITestFixtureAccessibilityTests.swift
verified_at: 6306c6e
---

# Accessibility

P5's criterion is that VoiceOver alone can finish **capture → jar → seal**
(`docs/NetRelish_Plan_and_Roadmap.md` §5). What that needed, and the four decisions it
forced, are in ADR 0036. This page is how it is put together. The window it sits on is
[[workbench-shell]]; the menus and drag it gives keyboard routes to are [[rearranging]].

## The three pieces

| Piece | Where | What it does |
|---|---|---|
| `NRAnnounce.post(_:priority:)` | `Sources/UI/Accessibility.swift:15` | Speaks a result nothing on screen announces. Posts `.announcementRequested` against the key window, so it is silent when no window is up. |
| `nrSystemAccessibility()` | `Sources/UI/Accessibility.swift:40` | Hands SwiftUI's live `accessibilityReduceMotion` to the design system's `\.nrReduceMotion`. Applied once per window root (`Sources/App/NetRelishApp.swift:96`, `:221`, `:228`). |
| `nrFocusRing(cornerRadius:inset:)` | `Sources/UI/Components.swift:114` | The one `--nr-focus` ring (manifest §4, placement 7), with its own `@FocusState` and `focusEffectDisabled()`. `NRFocusRing` (`:82`) is the same ring where the caller already tracks focus. |

## What gets spoken, and by whom

Spoken lines are user-facing copy and live as named statics beside the code that fires
them, so a test pins each one: `Workbench.capturedLine` (`Sources/App/Workbench.swift:1586`),
`sealedLine(jarName:)` (`:1210`), `sankLine(titles:)` (`:1074`),
`ShelfView.boardLine(jarName:)`, `JarTile.movedLine(jarName:)`,
`SmartJarRowView.restoreAnnouncement(jarName:)` (`Sources/Bench/BrineView.swift:207`),
`CommandSpeech` (`Sources/App/NetRelishApp.swift:330`), `WelcomeText.spoken(_:)`
(`Sources/App/WelcomeSheet.swift:43`, a card of the welcome sheet, [[welcome]]).

> ⚠️ **A result is spoken once, by one owner.** The address row's status line speaks every
> `fillStatus` change itself (`Sources/Bench/ShellRows.swift:156`), so nothing may also
> announce what `Workbench.report(_:)` already showed. A second announcement is not a
> duplicate word on screen — VoiceOver says the whole sentence twice.

> ⚠️ **Announcements are dropped unless the app is active** (the default `announcer`,
> `Sources/App/Workbench.swift`, and the key-window guards in the views). A Seal run from
> Shortcuts while another app is in front must not talk. Tests replace `announcer`, so they
> see every line regardless.

Priority is `.high` for the result of something the person just did (capture, a move, Seal,
a failure) and `.medium` for what happens on its own (a tab sinking).

## Reading an element

Each row, tile, chip and card is **one** element: `.accessibilityElement(children: .ignore)`
and then an explicit label, value, hint and traits. The label is the name
(`ShelfView.spokenValue`-style statics compose the value), the value carries state, and the
hint says what pressing it does.

> ⚠️ **A hover-only control is never the only route to its action**, because a view at
> opacity 0 leaves the accessibility tree ([[workbench-shell]] carries that trap). So
> Brine's row and the tab chip hold the action themselves, as a named
> `accessibilityAction`, and the drawn button stays for the pointer
> (`Sources/Bench/BrineView.swift`, `Sources/Bench/TabStrip.swift`).

> ⚠️ **The held sealed tab is hidden from VoiceOver.** During Seal's phase B the strip draws
> a copy of the sealed tab (`Workbench.sealHeldTab`). It is `accessibilityHidden(true)` as
> well as hit-test-free, or VoiceOver finds two tabs with one title and offers actions on a
> tab that is already gone. The copy is a picture and nothing else: since the v2.1.1
> security correction the address row, its spoken connection hint and the selected tab all
> follow the page in front, never the copy ([[workbench-shell]]).

> ⚠️ **The address field's real `TextField` must stay in the tree and keep the click.** The
> styled host and path are an overlay that takes no hits. At opacity 0 VoiceOver loses
> "Address" and the caret cannot be placed (`Sources/Bench/ShellRows.swift`).

Two rotors exist, both in the namespace form: "Jars" over the Shelf's tiles
(`Sources/Shelf/ShelfView.swift:145`) and "Changes" over a reseal diff
(`Sources/Bench/ComparisonView.swift:102`).

> ⚠️ **A rotor entry needs `accessibilityRotorEntry(id:in:)` on the view and a matching
> `@Namespace`.** The id-only initializer leans on `.id()` being in the same scope, which a
> `ForEach` inside a `ScrollView` does not guarantee. Both rotors use the namespace.

## The keyboard

`ShelfFocus` (`Sources/Shelf/ShelfView.swift:46`) names the Shelf's stops and
`focusOrder(jarIds:)`/`neighbor(of:in:by:)` step between them with the arrow keys, stopping
at both ends rather than wrapping. The tab strip has the same shape with
`TabStrip.neighbor(of:in:offset:)`, and `TabCycle.neighbor(of:in:step:)`
(`Sources/App/NetRelishApp.swift:318`) backs ⌃Tab. Rows and chips take focus with
`.focusable(interactions: .activate)`, so Space and Return press them; each region is a
`focusSection()` so focus arrives as a whole.

New keys and menu items are the table in ADR 0036. ⌘L goes through
`Workbench.focusAddress()` (`Sources/App/Workbench.swift:1558`), a counter the address row
watches (`Sources/Bench/ShellRows.swift:160`), because the field is in another view.

> ⚠️ **Every menu route into a jar must play the jar fill.** Tab › Move Tab to Jar
> (`Sources/App/NetRelishApp.swift:192`), the tab's own Move to Jar
> (`Sources/Bench/TabStrip.swift:269`) and Brine's Restore all take the drop's path so
> `fillJar(_:)` runs exactly once. A plain `moveTab` is silent and leaves the jar unfilled.
> The same trap, from the drag side, is in [[rearranging]].

## The Mac's settings

Reduce Motion, Reduce Transparency, Increase Contrast and Differentiate Without Color each
change something; the table is in ADR 0036. The alternates are picked per surface —
`ShellInk` (`Sources/Bench/ShellRows.swift:609`) is the shared pair for hairlines and edges
— because `tokens.css` carries no contrast set yet.

> ⚠️ **Read the settings from SwiftUI's environment, not once at launch.**
> `\.nrReduceMotion`'s default is `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`,
> read when the value is first created, so without `nrSystemAccessibility()` at the window
> root the whole app keeps whatever the setting was at launch. The Design Kit overrides
> `\.nrReduceMotion` further in on purpose, so its toggle still wins.

## The UI test

`Tests/NetRelishUITests/CaptureJarSealUITests.swift` walks the path twice (through Brine's
Restore to…, and through Tab › Move Tab to Jar) using accessibility identifiers and labels
only, which is why it is also the VoiceOver proof. It runs under its own scheme,
**NetRelish UI Tests**, in its own CI job; the existing Test job is untouched. See
[[building-without-a-mac]].

> ⚠️ **The fixture is `#if DEBUG` on both sides.** `Sources/App/UITestFixture.swift` is
> wholly inside it, and so are its three call sites (`Sources/App/NetRelishApp.swift:71`,
> `Sources/Bench/WebView.swift:35` and `:159`). It switches on only from
> `ProcessInfo.arguments`, never a default or an environment variable, so nothing a page or
> a file can set turns it on.

> ⚠️ **Every launch argument the UI test passes is a `-key value` pair.** AppKit reads the
> command line as defaults, two at a time. A flag with no value takes the next key as its
> value and leaves that key's `YES` standing alone; AppKit takes a lone argument for a file to
> open, and a launch that opens a file opens no main window. The test then fails with "The
> main window didn't open" and nothing in the app is wrong. `-NRUITestFixture` is passed as
> `-NRUITestFixture YES` for this reason only: the app reads that the flag is there
> (`Sources/App/UITestFixture.swift:19`), not its value.

> ⚠️ **The fixture's jars are not the Shelf's first two.** Every Pantry, in memory or not,
> starts with Read Later and Reference (`Sources/Pantry/Models/Seed.swift:10`), and `newJar`
> leaves the jar it made in front. So `UITestFixture.stock` finds Juniper Bakery by name to
> put it in front, and Meridian is ⌘4, not ⌘2. `activate(index: 0)` here opens the test's
> page in Read Later, and the test says "The page didn't open in Juniper Bakery's tabs" about
> a page that opened. `UITestFixtureAccessibilityTests.jarsAndTheirKeys` holds the fixture and
> the key the UI test presses together.

> ⚠️ **XCUITest cannot fire a named VoiceOver action** — there is no public macOS API. The
> test right-clicks the row and picks the same-named menu item, which is why each VoiceOver
> action has a menu item with the same words. Rename one and rename both.
