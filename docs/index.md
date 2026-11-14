# NetRelish -- documentation

A native macOS browser with a pantry: jars hold your tabs, idle tabs sink into Brine, and Seal keeps a page as it was.

This directory is a wiki maintained by an LLM: linked markdown pages, nothing outside the
repository. The rules are in [`CLAUDE.md`](CLAUDE.md).

## Start here

The repository's contract is the root `CLAUDE.md`; read that first, always. Then:

1. [[building-without-a-mac]] -- how anything here gets compiled and tested, before you write a line
2. [[rearranging]] -- the first subsystem written up, and a worked example of the routine

The wiki was started on 2026-11-13 and grows where work happens, so most of the app has
no page yet. For what was decided and why, the records are in `docs/adr/`; for where the
product is going, `docs/ROADMAP.md`.

---

## concepts

Nothing here yet.

## architecture

Nothing here yet.

## subsystems

- [[zest-sound]] -- the sound kit inlined in the four Zest web tools, the Sound toggle, and how its suite runs
- [[rearranging]] -- right-click menus and drag on the Shelf and tab strip; what moves, what is left behind, and the multi-window trap

## decisions

Decisions are recorded in `docs/adr/`, one file each, and are not wiki pages. Nothing here yet.

## reference

- [[privacy-and-sandbox]] -- what each bundle declares to macOS and App Store Connect (privacy manifests, entitlements, Info.plist answers), and what a web page can ask for

## operations

- [[building-without-a-mac]] -- CI is the compiler: regenerating the Xcode project, generated files, and the checks that are not CI
- [[releasing-a-preview]] -- cutting a signed, notarized preview, and what decides whether Pro is locked in it

## history

Nothing here yet.

---

## Using this wiki

```
/docs-sync     right after a deploy or release -- reads only what changed since verified_at
/docs-lint     integrity check (orphans, broken links, broken sources, stale, unverified)
/docs-query    ask the docs. If it is not there, the answer says so
/docs-status   commits not yet reflected, stale pages, recent work
```

Every page carries `verified_at`, the commit it was checked against. Change code, run
`/docs-sync`.
