# ADR 0033 — Zest ships in 1.0

**Status:** accepted for timing (Ryan, Nov 13); the defaults below are proposals for Ryan · **Date:** 2026-11-13 · **PR:** feat(zest): the Zest window host

## What Ryan decided

Nov 13: "Zest in the app now." The Zest tools ship inside NetRelish.app in the Dec 14 1.0
build, as ADR 0015 designed them for 1.1.

## What it changes

ADR 0015 is the design, and it holds. This moves its timing and nothing else.

| Where | Was | Now |
|---|---|---|
| ADR 0015, "Before Dec 14 vs after" | "Nothing Zest-related goes into the Dec 14 binary." | Superseded. The Zest window, the bundled tools, the rule list, the open and save panels, Seal gating and the root LICENSE are in 1.0. |
| ADR 0015, the 1.1 row | 1.1 (Jan 2027): the Zest window and everything with it | Moved to 1.0. The 1.2 and 1.3+ rows are unchanged: the bridge, Finder file types, Save to jar and the Quick Look extension stay in 1.2. |
| ADR 0015, the Dec 1–14 spike | A one-day spike on a branch never merged | Replaced by `ZestHostIntegrationTests`, which runs in CI on every pull request: localStorage on `zest://`, the rule list blocking a fetch, the frozen stub. Clipboard, downloads, ZestImage font embedding and bundle size are measured in phase 2. |
| ADR 0012, scope of 1.0 | No Zest | Adds the Zest window. Nothing else in ADR 0012 moves. |
| CLAUDE.md, Roadmap anchors and repo layout | Zest window deferred to 1.1 | In 1.0; `/Sources/Zest/` and `/Resources/Zest/` are listed. |
| `docs/ROADMAP.md` | Zest under 1.1 | Zest under 1.0. |

## How it is built

Two phases, so the app work and the tools' work don't wait on each other.

1. **The host (this ADR's pull request).** `Sources/Zest/`: the read-only `zest://app/`
   scheme handler, Zest's own data store, the rule list, the frozen stub, the window with
   its switcher, the open and save panels, and the gating of Seal, Capture and Fill from Me
   while the Zest window is key. `Resources/Zest/` is a folder reference in `project.yml`,
   holding only its README until phase 2. Root `LICENSE`. How it fits together:
   `docs/subsystems/zest-window.md`.
2. **The tools (phase 2).** `zest/build.sh --app` fills `Resources/Zest/` (studio at the
   root, then `mail/`, `md/`, `image/`), vendors DOMPurify, KaTeX, Mermaid and the fonts
   with `VENDOR.lock.json`, and adds the `IN_APP` switches inside each tool. `NOTICE`, with
   the third-party list, is written then, from the lock.

## Defaults chosen, for Ryan to confirm (ADR 0015's open questions)

These were picked so the build can go ahead. Each is a proposal until Ryan says yes.

1. **Colors and type.** The tools keep their own colors and type inside a plain NetRelish
   window frame: neutral surface, a system segmented switcher, no relish. As the Bench
   never restyles a page.
2. **Icons in menus.** NetRelish's menus and the switcher use plain text and SF Symbols,
   never the fruit icons.
3. **"Recipe."** Zest uses no "Recipe" word today (checked with grep), so there is nothing
   to rename. It stays that way: in NetRelish a Recipe always runs in Shortcuts.
4. **Names and marks.** Not decided. Whether Zest, ZestMail, Zest MD, ZestImage and the
   fruit icons are reserved like the NetRelish mark is still open. Until it is, the root
   `LICENSE` excludes only what CLAUDE.md non-negotiable 8 names, and says the Zest names
   and icons are pending this decision.

ADR 0015's questions 5 (Pro unlocking Zest's offline extras) and 6 (screenshots as the demo)
are untouched: question 6 no longer applies, because the app shows Zest from 1.0.

## Rule check

- **NN1:** no new kind, no model change.
- **NN2/NN3:** the Zest window is not a tab, so it can't sink. Seal is disabled while it's in front.
- **NN4:** no model sees a Zest page; the tools' Claude drafting stays on zest.netrelish.com.
- **NN5:** no endpoint. The rule list blocks every http(s), ws(s) and file load in a Zest
  view, the scheme sends a Content-Security-Policy with no web origin in it, and a clicked
  web link opens as an ordinary page load in a jar, which NN5 already allows.
- **NN6:** Zest's store is reserved in `JarProfile`, beside the jars' derivation, so no jar
  id maps to it; tested.
- **NN7:** no Recipe in Zest.
- **NN8:** root `LICENSE`: MIT for the code, with the rights-reserved items stated.

## Risks

ADR 0015's risks stand. Two are now on the calendar for 1.0 rather than 1.1:

1. **App Review (rule 3.1.1).** A leftover Upgrade or pricing link in a tool fails review.
   Phase 2's `IN_APP` switches and the static scan are what stop it, before P6.
2. **Calendar.** Phase 2 competes with P5 (App Store prep). If it isn't merged by Nov 30,
   the Zest window can be hidden from the Window menu for 1.0 without removing the host.
