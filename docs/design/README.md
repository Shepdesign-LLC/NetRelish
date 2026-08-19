# Design reference

The mocks live in Claude Design, project
**`d41a5a0f-faca-44bb-8381-b95259fac184`** ("NetRelish branding system"),
readable with the `DesignSync` tool (`list_files`, `get_file`). Two files are
copied here because they are the current targets:

- `Workstation Desktop.dc.html` — six desktop frames
- `support.js` — the Claude Design canvas runtime the `.dc.html` files need in
  order to render. **Generated; do not edit, and do not implement it** — it is
  a preview harness, not product code.

`NetRelish iOS.dc.html` (five iPhone frames) and `ios-frame.jsx` stay in the
Claude Design project; fetch them the same way when iOS is scheduled.

## What these mocks are

The **destination**, not a sprint. `Workstation Desktop` alone spans P5
(AI panel), P7 (Share / Publish a Relish), P8 (Relish Report score) and P10
(roles, presence avatars, activity feed) — plus multi-profile switching,
which appears in no plan and is uncosted.

Build toward them. Do not read them as a next-task list.

## Decisions taken from this pass (2026-08-19)

**Three brand words approved** and now in CLAUDE.md §2: **Relish** (a jar
published for other people), **Flavor** (a theme), **NetRelish ID** (the
account). "Relish" resolves the naming question that was blocking P7.

**The mocks' privacy copy was wrong and is not to be implemented as drawn.**
Both `Workstation Desktop` and `NetRelish iOS` say "end-to-end encrypted — we
can't read your Pantry" on the same screens that show AI summarising, citing
and gap-analysing the user's items. Those cannot both be true.

Resolution, now law in §4a and §10: **note and task bodies are encrypted
client-side and no AI feature may read them; extracted page text stays
readable.** A note is something you wrote; a page is a copy of something
already public.

So when implementing either mock, replace:

| Mock says | Ship instead |
| :-- | :-- |
| "Everything syncs end-to-end encrypted — we can't read your Pantry." | "Your notes are private, even from us." |
| "Sync · E2E ENCRYPTED" | "Sync · encrypted, notes private" |
| "Shared jars sync end-to-end encrypted." | "Shared jars sync encrypted. Notes stay yours." |

One line in the mocks already gets it right and should be kept verbatim:
**"SEARCH IS LOCAL & INSTANT · ASK USES RELISH AI ON YOUR ITEMS ONLY."**

And one detail the mocks got right independently: publishing a Relish shows
notes struck through and marked "NOTE · STAYS PRIVATE". That is exactly the
behaviour §4a now requires.

## Useful details already encoded

- iOS `⌘K` filter chips are the shipped grammar — `jar:`, `kind:`, `since:`,
  `is:sealed`. No new syntax to design.
- Profile avatar is a superellipse tile in the profile's jar-hue gradient.
- Electric `#C4F26B` / `#93E413` stays the accent for account, sync and AI
  surfaces.
- `netrelish://pantry` URL scheme appears in the desktop titlebar.
