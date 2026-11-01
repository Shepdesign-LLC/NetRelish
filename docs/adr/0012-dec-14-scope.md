# ADR 0012 — What ships on Dec 14, and what moves to 1.1

**Status:** accepted · **Date:** 2026-11-01 · **PR:** docs(adr): the Dec 14 scope

On Nov 1, every v1.0 roadmap item was checked against the code. Four of 19 worked:
Shelf, jars as profiles, Brine and Seal. Six were partly built and nine had not
started. About four weeks are left before App Store submission (around Nov 30),
and roughly ten days of those belong to App Store prep (P5). The whole roadmap
doesn't fit.

**Decision (Ryan, 2026-11-01):** the launch date holds and the scope shrinks.
This replaces the 1.0 lists in `NetRelish_Plan_and_Roadmap.md` §4 and §5 (P3, P4).

## Ships on Dec 14 (1.0)

| Area | What 1.0 includes |
|---|---|
| Already working | Shelf, jars as profiles, Brine, Seal |
| Bench | Links that open a new window or popup work. No split view. |
| Search | Opening a sealed result shows the saved copy, not the live site |
| Smart Jars | Unsorted (Brine), Today, Sealed, Sinking soon, ⌘⇧1–4 |
| Reader view | Reader screen from the Defuddle body, ⌘⇧R |
| Inspector | Kind, source, sealed date, labels |
| Share extension | Capture from Safari or any app with a share sheet |
| Shortcuts | Capture, a full Seal (snapshot + Recipe), jump to a jar, search |
| Recipes | A few built-in Recipes, one per jar, run on Seal and listed in Shortcuts. "Seal & Summarize" uses on-device Foundation Models. |
| Pro | Reseal & diff, provenance export, buying and restoring Pro (StoreKit 2), a license key for the direct build |
| App Store prep | Everything in P5 |

## Moves to 1.1 (January 2027)

Ask the Pantry · content blocker · split view · Jar bundles · semantic search ·
unlimited Recipes · recording a Recipe and replaying it with ⌘R

## Proposed, not decided (Claude)

- **Inspector notes move to 1.1.** Notes need a schema change in System Designer
  first, and the Inspector is still useful at launch without them.
- **The Brine tray (drag a chip onto a jar) ships only if time allows.** Restore
  already covers getting a page out of Brine.

## What this changes outside the code

- The public roadmap page and its changelog must match this list before they
  go live.
- App Store listing (§7): the "Inspector summary" screenshot becomes "Reseal
  diff" or "Smart Jars". The four Apple Intelligence claims in §11 still hold,
  because "Seal & Summarize" ships.
- Pro launches with two features at the same prices in ADR 0003.
