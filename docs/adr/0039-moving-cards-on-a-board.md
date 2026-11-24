# ADR 0039 — Moving cards on a jar board

**Status:** proposed · **Date:** 2026-11-24 · **PR:** docs(adr): moving cards on a jar board

Ryan, 2026-11-24: *"We used to move around the widgits in the main space, but it went away."*

It did not go away. It was never in the app, and the opposite was written down three
times on purpose. This ADR says what is actually true, what each version of the feature
would cost, and asks Ryan to pick one.

## 1 · Nothing was removed

`JarBoard.swift:78` makes a card `.draggable`, so a card can be picked up and dropped on
a jar on the Shelf. There is no `.dropDestination` anywhere in that file, and the whole
app has exactly two — `TabStrip.swift:233` (a tab onto a tab) and `ShelfView.swift:190`
(anything onto a jar tile). Neither is on the board.

`git log -S` over `--all` finds no commit in the repository's history where
`dropDestination` appears in `JarBoard.swift`, and none where `onMove` appears anywhere
in `Sources/`. The `.draggable` arrived with the v5 window (`d9fee89`, #95) and has not
changed since.

**What Ryan is remembering is `docs/design/netrelish-workstation.html`**, the Zest-bundle
prototype, where board tiles (`:733`) and notes (`:729`) are both `draggable="true"` and
a relish line shows where a card will land (`:189`). `docs/design/README.md` calls that
file "the **destination**, not a sprint."

## 2 · The board was designed not to move. It is written down three times

This is the part that matters, and it is why this ADR is a decision rather than a bug.

| Where | What it says |
|---|---|
| `design/DESIGN_MANIFEST.md:129` | "A query: the board moves nothing." |
| `Sources/Bench/JarBoard.swift:5` | the same rule, in the file header |
| `PantryStore.kept(_:inJar:)` | "A query, like the smart jars: the jar board reads it, and nothing moves." |

A jar board is a **query**, the same shape as Brine, Today, Sealed and Sinking soon. Its
kept half returns `Item.filter(jarId == …).order(updatedAt.desc)`. That is why cards
appear to reshuffle whenever anything touches an item: nothing is holding them in place,
by design.

Making a card stay where it is put contradicts a stated rule in three files. That is
allowed — rules get revised — but it is a manifest change with Ryan's sign-off, not an
oversight to patch.

## 3 · The board is two grids, and they cost completely differently

`JarBoard` renders two sections, each with its own `LazyVGrid`:

| Section | Source | Line | Has an order to store? |
|---|---|---|---|
| **Open tabs** | `workbench.tabs` | `JarBoard.swift:69` | Yes — `Tab.sortOrder`, NOT NULL on `tabs` (`Schema.swift:76`) |
| **Kept** | `workbench.jarItems` | `JarBoard.swift:106` | **No.** `items` has no order column at all (`Schema.swift:42-58`) |

**The tab tiles look free and are not.** `Tab.sortOrder` exists, but it is the *strip's*
order: the board and the strip read the same `workbench.tabs` array. Reorder a tile on
the board and the tab strip visibly reorders too, and the reverse. If those should be
independent, tabs need a second stored order — the same new-column cost as items, not a
freebie.

**The kept cards need a model change.** Adding a position to `Item` means editing
`design/NetRelish.json` in System Designer (the schema entry and the model), regenerating
`Item.swift` and `Schema.swift` (CI diffs them, `ci.yml:176-177`), and hand-writing a V4
migration. CLAUDE.md non-negotiable 1 rules out the obvious shortcut: no `BoardCard`
table, no per-kind ordering table.

Three homes survive that rule — a `number` on each record (two independent sequences,
matching the two-section render), a JSON id-list on `Jar` (V3 is the precedent for
reading JSON out of a blob column), or a key inside `Item.meta` (no index, `json_extract`
to order, and every future `meta` migration must preserve it).

**And a smart jar's board is computed, so a stored order has nowhere to live there at
all.** Whatever is decided has to say what happens on Brine, Today, Sealed and Sinking
soon.

## 4 · The thing in the prototype that moves is the notes

The v5 spec's §7.2 drag table has five rows. The app built four and half of the fifth.
The one unbuilt row is **"Note · Another note · Reorder within the jar."**

ADR 0028 already noticed and recorded why: *"Notes can't be dragged yet because the app
has no notes yet (ADR 0012)."*

In the prototype, the relish insertion indicator at `:189` is styled on `.note`. There is
no `.tile.dragover` rule at all. So the cards Ryan remembers dragging around the main
space are, in the file he is remembering, **the note cards** — and notes do not exist in
the app yet.

**That makes this the same decision as notes in the Panel, not a separate one.** And the
cost of notes was misstated earlier today: `items.body` is an existing column
(`Schema.swift:45`), `ItemKind` already has `note` (`Types.swift:20`), and `Item` already
carries `jarId`. A note is `Item(kind: .note, body:, jarId:)` with no schema change. ADR
0012 deferred notes on a schema change that is not needed, which is recorded on PR #116
and should be revisited on its own merits.

## 5 · Design law has no mark for "it will land here"

An insertion indicator is **not** on §4's exhaustive relish list. The nearest entry, §4
#9, is "a `--lip-h` bar on the leading edge of the jar tile or tab a drag would land on"
— a mark drawn **on a target object**, and only those two objects are named. A line in
the gap *between* two cards is a different thing on a different surface. Taking the
prototype's relish line would mean widening #9 or adding a numbered entry, and §4 makes
that a version bump with a changelog line: **manifest v2.2**.

The jar's own colour is not a way around it. It has its own closed list of seven
placements, and exactly one touches a board card: "the border of a board card under the
pointer." An insertion line is outside that list too. It is arguably the smaller stretch
— the card border is already where a jar's colour meets the board — but the manifest
grants nothing by inference.

The prototype's cards also lift and shadow on hover (`translateY(-3px)`, a 26px shadow,
`:188`). That has no manifest basis: §6 allows exactly one float shadow on an enumerated
set — the ⌘K palette, menus, sheets — and a dragged card is not on it. §1.5 says depth
comes from hairlines, layering and motion, not added surface effects. The only scale bump
the manifest specifies anywhere is the Shelf tile's 1 → 1.05 → 1 during a jar fill, and
§7 pins the drip to two placements, "Nowhere else."

## 6 · It would need a keyboard route, not just a drag

ADR 0036 §2: "Every route that only a drag, a hover or a right-click could reach now also
has a menu item or a VoiceOver action." `docs/subsystems/rearranging.md` tightens it — a
context menu cannot be opened from the keyboard without VoiceOver, so a VoiceOver action
alone is out of reach with Keyboard navigation on and no pointer. **A menu-bar item is
required.**

It would sit beside the keyless items that already exist: **Jars › Show Board, Move Jar
Up, Move Jar Down**; **Tab › Move Tab to Jar, Move Tab Left, Move Tab Right**. The board's
tiles and cards already carry per-item VoiceOver actions it could join.

## 7 · What the repo says about adding this to 1.0

There is **no written rule** forbidding additions to 1.0 at three weeks out. Say that
plainly rather than inventing a freeze. There is a procedure — CLAUDE.md: "If a task
conflicts with it, stop and ask Ryan", and "propose it in the PR as a one-line ADR" —
and one precedent, ADR 0033, where Ryan widened 1.0 on Nov 13 for a feature that was
already fully designed and whose code already existed.

But three deferrals in this repo were all made for exactly this reason:

| Deferred | Reason given |
|---|---|
| Inspector notes → 1.1 (ADR 0012) | "Notes need a schema change in System Designer first" |
| Per-jar capacity (ADR 0034) | "`Jar` has no capacity field, and the model changes only in System Designer" |
| Lock, Archive with Undo, Duplicate (ADR 0028) | "Each needs a field the model doesn't have, so they wait for the next System Designer round" |

Board reordering resembles those three. What landed late instead — the facelift (0035)
and the drags (0028) — needed no model change.

There is no board draw budget and no write budget anywhere in the repo. The only frame
budget in §5 predates the board by seven weeks and is written about tabs and the tray.
Worth noting: ADR 0035 deliberately removed the prototype's six-card cap ("every kept
card shows"), so a reorder gesture would run over an unbounded adaptive grid, under no
written budget, on a codebase that has never been run on a Mac.

## 8 · Proposed

**Board cards do not move in 1.0.** Not for want of time — because the board is a query
by design, said three times, and the half Ryan remembers moving is the note cards, which
do not exist yet.

Concretely:

1. **1.0 ships as it is.** A board card can still be dragged onto a jar on the Shelf.
   Nothing is removed.
2. **The ADR 0028 drag table gains a row** saying the board's cards do not move, so the
   next person who asks finds an answer instead of an absence.
3. **Reordering is revisited with notes**, as one decision, because the prototype's
   reorder is a note reorder and §7.2's unbuilt row is the note row. If notes land — and
   they need no schema change — reordering them is the natural second half.
4. **A per-jar order for kept items goes on the next System Designer round**, with Lock,
   Archive with Undo, Duplicate and jar capacity, which are parked for the same reason.

The alternative worth stating, because it is cheap and Ryan may want it: **tab tiles only,
sharing the strip's order.** No model change, no new column. The board and the strip stay
one order, so reordering tiles visibly reorders the strip. It still needs the manifest
v2.2 entry for the insertion mark and a menu-bar route, and it still does nothing on a
smart jar. If what Ryan wants is "I can arrange my open tabs on the board", this is the
version that fits before Dec 14.

## 9 · For Ryan

1. **Decline, defer with notes, or build the tab-tiles-only version?**
2. If anything is built, **what does the insertion mark look like** — relish (a new §4
   entry, v2.2), or the jar's own colour (also a new entry, arguably the smaller stretch)?
3. **What happens on a smart jar's board?** It is computed; a stored order has nowhere
   to live. Hide the affordance, or show it disabled?
4. If tab tiles move, **is the strip moving with them right or wrong?** Right is free;
   wrong costs a second stored order and is no longer the cheap version.

## Sources

- `Sources/Bench/JarBoard.swift:5`, `:69`, `:78`, `:106`
- `Sources/Pantry/Store/PantryStore.swift` — `kept(_:inJar:)`
- `Sources/Pantry/Models/Schema.swift:42-58`, `:76`
- `design/DESIGN_MANIFEST.md:129`, §4, §6, §7, §1.5
- `docs/design/netrelish-workstation.html:189`, `:729`, `:733`
- `docs/adr/0012-*.md`, `0028-right-click-and-drag.md`, `0034-*.md`, `0035-*.md`,
  `0036-accessibility.md` §2
- `docs/subsystems/rearranging.md`
- The Counter comp, on branch `claude/counter-comp` at `1c306d5` — not on `main`. It
  deliberately does not touch the board: "the board stays what you get by clicking a jar."
