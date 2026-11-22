# ADR 0038 — The welcome sheet: three cards, then the address field

**Status:** proposed (for Ryan) · **Date:** 2026-11-21 · **PR:** feat(onboarding): the welcome sheet

P5's line is "Onboarding: 3 screens, ends with the user's first Seal"
(`docs/NetRelish_Plan_and_Roadmap.md`, P5). ADR 0034 set the Workstation v5 sheet's copy
aside, because it was about notes and capacity, and ADR 0036 left the sheet as its own item
with its copy undecided. This is that item. Merging the PR is the decision; the copy below is
a first draft for Ryan to change.

## What it is

One sheet, three cards, in the shape the Me card's sheet already has: the cog at 48pt, a
headline, the lines under it, "1 of 3", and one filled button.

| # | Headline | Under it |
|---|---|---|
| 1 | A jar is a project | Each jar keeps its own tabs and its own sign-ins, so one client’s accounts stay out of another’s. Add a jar with the + on the Shelf. |
| 2 | Idle tabs sink into Brine | Leave a tab alone for its jar’s shelf life and it closes by itself. It waits in Brine, on the bottom bar. Pinned tabs never sink. |
| 3 | Seal a page to keep it | Press ⌘S on a page. NetRelish saves a copy of it as it is now, closes the tab and keeps the copy in the jar. Find it again with ⌘K. |

Buttons: **Next**, **Back** from the second card on, and **Start** on the last. Escape
closes it from any card. Help › **Welcome to NetRelish** opens it again.

The middle card is Brine, not Capture, on purpose: a tab that closes by itself is the one
thing in the app that reads as a fault to someone who wasn't told.

## What was decided to build it

1. **Shown once, to everyone, at the first launch of a build that has it.** The flag is
   `welcome.seen` in the app's own defaults. Someone who has used the previews sees it once
   too: they were never shown it.
2. **Seen means closed, not opened.** Quit with the sheet open and it comes back at the next
   launch. Closing it any way, Start or Escape, is the end of it.
3. **Start puts the caret in the address field.** The sheet is over the window, so ⌘S can't
   reach a page while it is up. Start closes it and hands the keyboard to the address field:
   the next thing typed is the first page, and ⌘S on it is the first Seal, played by the
   real Seal motion. **The app does not perform that Seal or pick the page.** See the first
   question below.
4. **It never opens by itself in a test launch.** The UI test's fixture starts from new
   defaults every run, so a first-launch sheet would cover the window at its first step. The
   app marks its own launch as the only one that may open it (`Workbench.welcomesAtLaunch`).
5. **Not in ⌘K.** The v5 spec said "re-openable from the palette". Help is where a Mac app
   keeps this, and ⌘K's rows are things to do to a page or a jar. One line to add if wanted.
6. **A card that changes is said whole.** Next and Back change the text while VoiceOver's
   cursor stays on the button, so the new card is announced: headline, lines, "2 of 3".

## For Ryan

1. **Should the last card end in a real Seal?** As built, it ends with the caret in the
   address field and the person does the rest. Two ways to make the Seal part of the sheet's
   own flow, neither built: (a) Start opens a page that ships inside the app, to seal as
   practice, which needs a bundled page and a way to serve it; (b) a line in the address row
   the first time a page is in front, "Press ⌘S to seal this page", which is a new use of
   that line.
2. **The copy.** Every line above is a draft in the house voice. The tests hold the three
   headlines, so changing one is a one-line change in two places.

## Rule check

- **NN3 (Seal is an action):** untouched. The sheet describes Seal and never calls it.
- **NN5 (nothing leaves the device):** no network call. One new key in the app's own
  defaults, covered by the reason the privacy manifest already declares (`CA92.1`).
- **NN6:** the first card's claim, a jar's own sign-ins, is the rule itself.

## Brand check

- **§2, the mark:** the cog at 48pt, its onboarding placement, never redrawn.
- **§4, relish:** placement 1 only, the one filled button on each card, and placement 7,
  the focus ring. "1 of 3" is `--nr-fg-3`; nothing else carries color.
- **§5, voice:** headlines say what the app does; Pantry words are nouns; no exclamation
  marks. A test holds the cards to the banned-word list.
- **§9, motion:** cards cross-fade over `--t-base`, which is also what Reduce Motion asks for.
- **§12:** no gradients, no emoji, no second accent, no streaks or rewards.
