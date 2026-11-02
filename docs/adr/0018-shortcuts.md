# ADR 0018 — What NetRelish's Shortcuts do

**Status:** proposed · **Date:** 2026-11-02 · **PR:** feat(shortcuts): Capture, a full Seal, Open a Jar, Search

ADR 0012 puts four Shortcuts in 1.0: Capture, a full Seal (snapshot + Recipe), jump to a jar, and search. All four are App Intents, listed in an `AppShortcutsProvider`, so they're in Shortcuts, Spotlight and Siri with no setup (non-negotiable 7).

- **Capture in NetRelish** (URL) puts the page in Brine, as ⌘D does, with "Shortcuts" as its source. Web links only.
- **Seal in NetRelish** (link, jar; both optional) is the same Seal as ⌘S, through one shared `PantryStore.sealPage`: snapshot frozen, `sealedAt` stamped, `onSeal` fired, the jar's default Recipe run (non-negotiable 3).
  - With a link, the page is loaded off screen (`HeadlessPage`) in the jar's own profile, so it has that jar's sign-ins and no other's (non-negotiable 6). No popups, downloads, media or hand-offs to other apps; 30 seconds to load, then it fails and seals nothing.
  - With no jar named, it seals into the jar the page was last kept in, else the active jar, else the first on the Shelf.
  - With no link, it seals the page in front, into the jar named if there is one, else the tab's jar. If the page is loaded in a live web view, that's ⌘S on the live tab; if not (no window, or a tab not shown yet), the tab's page is loaded off screen. Either way the tab closes, as ⌘S closes it.
  - A Shortcut cancelled while its page loads keeps nothing.
- **Open a Jar** (jar) brings NetRelish forward on that jar.
- **Search Your Pantry** (text) is ⌘K's full-text search, returning up to 20 items (limited in SQL) with title, link, whether it's sealed, and where it is.

Nothing here involves a model (non-negotiable 4), and the only network use is loading the page you named (non-negotiable 5). What a Shortcut does with the results is up to the person who built it. The old `SealIntent`, which stamped `sealedAt` without a snapshot or Recipe, is removed.
