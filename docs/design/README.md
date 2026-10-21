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

## Zest-bundle prototypes (2026-10)

Two more files arrived with the Zest bundle (2026-10) and live here:

- `netrelish-workstation.html` — standalone interactive HTML prototype of the
  workstation: right-click context menus and drag-and-drop of tabs, jars and
  brine rows. It needs no runtime; open it in a browser. Same caveat as the
  `.dc.html` mocks: a destination, not a sprint.
- `netrelish-design-kit.html` — Design Kit v1.1, a single page built on the
  Brand Lock v1.1 tokens (dated 2026-09-15).

Privacy copy check (per the banned lines below): both files were grepped for
"end-to-end encrypted", "we can't read", and "E2E". Neither carries any of the
banned copy — the only string match is the hex colour `#E2ECC2` in the design
kit, which is not copy.

**Decision taken from this pass (2026-10-21, Ryan):** notes take Markdown,
not rich text — the ZestMail text-block grammar exactly (`**bold**`,
`*italic*`, `` `code` ``, `[link](url)`, blank line = paragraph; MAIL-PRESS.md
§2.2). Plain-text storage, so "Send to Zest MD" is lossless and one grammar
serves the whole line. The workstation prototype implements it: note pages
render the Markdown and switch to the raw source on click; links are
http(s)-only and open in a new tab.

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
