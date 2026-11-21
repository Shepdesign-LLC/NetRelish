---
title: The welcome sheet — three cards at the first launch
type: subsystem
created: 2026-11-21
updated: 2026-11-21
sources:
  - code: Sources/App/WelcomeSheet.swift
  - code: Sources/App/Workbench.swift
  - code: Sources/App/NetRelishApp.swift
  - code: Sources/App/DesignKitSnapshot.swift
  - code: Tests/NetRelishTests/WelcomeTests.swift
verified_at: 6306c6e
---

# The welcome sheet

P5's onboarding: one sheet, three cards (a jar, Brine, Seal), shown once at the first
launch and again from Help › Welcome to NetRelish. What was decided, the copy and the two
questions left for Ryan are ADR 0038 (`docs/adr/0038-welcome-sheet.md`). This page is how it
is put together. It follows the shape of the Me card's sheet and the Pro sheet; what it
says to VoiceOver follows [[accessibility]], and its one stored key is listed in
[[privacy-and-sandbox]].

## The pieces

| Piece | Where | What it does |
|---|---|---|
| `WelcomeText` | `Sources/App/WelcomeSheet.swift:19` | Every word: the three cards, the buttons, the Help item, "2 of 3" (`:39`) and the line VoiceOver hears for a card (`:43`). |
| `WelcomeSheet` | `Sources/App/WelcomeSheet.swift:54` | The view. It keeps which card is showing and nothing else, and reports how it closed through `done(start)`. |
| The Workbench's welcome state | `Sources/App/Workbench.swift:1662` | `showingWelcome`, the `welcome.seen` flag, and the three calls below. |
| The sheet's place in the window | `Sources/App/NetRelishApp.swift:467` | A `.task` that asks once the window is up, and the `.sheet` with its `onDismiss`. |
| Help's item | `Sources/App/NetRelishApp.swift:112` | Sets `showingWelcome`; it works whether or not the sheet was seen. |

## When it opens, and when it counts as seen

`welcomeAtFirstLaunch()` (`Sources/App/Workbench.swift:1681`) opens the sheet when the app
marked this launch as its own and `welcome.seen` is not set. `closeWelcome(start:)`
(`:1690`) closes it. `welcomeClosed()` (`:1696`) runs from the sheet's `onDismiss`: it sets
`welcome.seen`, and after Start it asks for the address field through `focusAddress()`.

> ⚠️ **Seen means closed, not opened.** The flag is set in `welcomeClosed()`, never where the
> sheet opens. Setting it on open looks simpler and loses the sheet for anyone who quits, or
> crashes, before reading it.

> ⚠️ **The welcome sheet must never open by itself in a test launch.** The UI test's fixture
> empties its defaults on every run (`Sources/App/UITestFixture.swift:87`), so to it every
> launch is the first, and a sheet over the window stops the test at its first step with
> nothing wrong in the app. `welcomesAtLaunch` is false unless the app sets it for its own
> launch (`Sources/App/NetRelishApp.swift:81`), which comes after the fixture's early
> return and reads `isHostingTests`. A new Workbench initializer or a second launch path
> has to keep that.

> ⚠️ **Start asks for the address field only after the sheet has gone.** `closeWelcome`
> only remembers that Start was pressed; `focusAddress()` is called from `onDismiss`. Asked
> for while the sheet is still attached, the request may go to a window that cannot give
> its own fields the keyboard yet (unverified: nothing here has run on a Mac).

> ⚠️ **Only the first call of a launch can open it.** `welcomeAtFirstLaunch()` runs from
> every window's `.task`, and the Workbench is every window's ([[rearranging]] has that
> trap). It clears `welcomesAtLaunch` on its first call, so a second window opened after the
> sheet was closed does not bring it back before `onDismiss` has set the flag.

## The cards

All three cards are drawn at once, one over the other, and only the one in turn is shown
(`Sources/App/WelcomeSheet.swift:100`). The sheet therefore keeps the height of its tallest
card and never resizes between cards. The change is a cross-fade, which is also what Reduce
Motion asks for (manifest §9), so there is no second branch for it.

> ⚠️ **A card that isn't showing is hidden from VoiceOver by name, not by its opacity
> alone.** Each hidden card carries `accessibilityHidden(true)`. Without it VoiceOver may
> still find three headlines in one sheet.

Next and Back change the text under a cursor that stays on the button, so the new card is
announced whole (`Sources/App/WelcomeSheet.swift:92`), at `.high`, as the result of a press.

## The copy is held by tests

`Tests/NetRelishTests/WelcomeTests.swift` pins the three headlines, runs every string
against the banned-word list in `docs/voice/NETRELISH.md`, and ties two claims to the code
that makes them true: "Pinned tabs never sink" to `ShelfLife.shouldSink`, and ⌘S to the
shortcut ⌘K's Seal row carries.

> ⚠️ **A card may say only what the build does.** The house rule is "Never claim more than
> is true". A claim added to a card needs the same kind of test beside it, or it will
> outlive the behavior it describes.

## Pictures without a Mac

The Design Kit snapshot renders the three cards, light and dark
(`Sources/App/DesignKitSnapshot.swift:31`), into the `design-kit-snapshots` artifact of the
Test job as `welcome-1-light.png` and so on. See [[building-without-a-mac]].
