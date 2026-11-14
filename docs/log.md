# Work log

Append-only. Newest entries at the bottom.

---

## [2026-11-13] setup | docs/ wiki scaffolded

- Categories: concepts - architecture - subsystems - decisions - reference - operations - history
- Baseline commit: `65fedfd`
- Created: `docs/{CLAUDE,index,log}.md`, `raw/`, 4 `.claude/commands/docs-*`,
  and `.claude/scripts/docs-lint.py`

## [2026-11-13] started in grow mode

- Two pages, written from the code just worked in (pull request 89):
  `subsystems/rearranging.md` and `operations/building-without-a-mac.md`
- Nothing was split or moved. The existing documents in `docs/` (ADRs, design handoffs,
  plans, voice guides, release notes, planning documents) are not wiki pages and are
  excluded from the linter by default; `docs/CLAUDE.md` lists them
- `release-commands:` left empty: releases run from a tag in GitHub Actions, not from a
  command an agent runs
- The rest of the app has no page yet. Pages are added as work touches an area

## [2026-11-13] zest-sound added

- `subsystems/zest-sound.md`, written with the commit that added the kit (`27b385f`)

## [2026-11-13] rearranging re-checked

- Against `5a2b9a6` (Seal and a moved tab; Close Other Tabs in one write). One trap added:
  after an await, check the tab's jar again. Line citations moved with the code

## [2026-11-13] rearranging re-checked; the linter checks Swift

- Against `7d472f8` (a page left behind in another window). One trap added
- `.claude/scripts/docs-lint.py`: `swift` added to the code extensions it checks citations
  for. This and the exclude list are the two local changes to the vendored linter

## [2026-11-13] rearranging re-checked

- Against `d0cdaeb` (Reader view and a moved tab). The await trap now names Reader view too

## [2026-11-13] zest-sound re-checked

- Against `3287635` (the studio, ZestImage and Zest MD simplified). The kit and how it is
  wired are unchanged. Two test traps added: fixed ports, and `offsetParent` inside `<details>`

## [2026-11-13] zest-sound re-checked

- Against `f859210` (ZestMail simplified; the studio's switch renamed Palette). Prose unchanged

## [2026-11-13] both pages re-checked

- `rearranging` against `b55a895` (closed tabs' pages in another window). `zest-sound`
  against `da319b6` (a one-line README change)

## [2026-11-13] zest-sound re-checked

- Against `b20ba68` (the Zest MD export menu no longer repeats the main button). The sound
  steps use the Markdown copy item, which stays. Prose unchanged

## [2026-11-13] linter: a third local change

- `.claude/scripts/docs-lint.py` matched `verified_at` to git's `%h` by exact text, so a full
  commit id (or a longer abbreviation, once git lengthens `%h`) counted the whole history
  against a page. It now matches by prefix. Checked with a 40-, 10- and 7-character id at
  HEAD (not stale) and two older ids (1 and 7 commits, the same as `git log <id>..HEAD`)

## [2026-11-13] releasing-a-preview added

- A page for cutting a preview, written while preparing 0.5.0: the order (notes, run, then
  tag), and the three states of the license address. The Release workflow gained a
  **Leave Pro unlocked** switch (ADR 0031)

## [2026-11-13] three pages moved to the squash commit

- Pull request 89 was squash-merged as `2c4c510`, so every page verified on its branch read
  as one commit stale. Each page's sources are byte for byte the same at its old
  `verified_at` and at `2c4c510` (checked with `git diff`), so `verified_at` moved alone.
  This will happen after every squash merge of a branch that touched a page's sources

## [2026-11-13] zest-window added

- A page for the Zest window host (ADR 0033 moved ADR 0015's Zest window into 1.0): the
  zest:// scheme and its path rules, Zest's reserved store, the offline rule list, the stub,
  where links go, and the gating of the page commands while the window is key. Ten traps,
  among them the scheme handler's isolation, realpath over `resolvingSymlinksInPath`, and
  `pageInFront` rather than `benchTab`

## [2026-11-13] zest-window: review fixes

- A download link to the web is now routed as a web link, never a `WKDownload`; gating
  follows the main window, so a color panel or save panel no longer switches it off; a web
  link brings forward the registered main window, not the first window in the list; the
  jar that spells Zest's UUID moves under a namespace of its own; the integration tests use
  throwaway stores. The page now says plainly what CI doesn't show (storage surviving a
  relaunch, IndexedDB) and that `zest/build.sh --app` is phase 2's, not yet written. Four
  new traps

## [2026-11-13] rearranging and building-without-a-mac re-verified

- The Zest review fixes grew Workbench's Zest block by nine lines, so rearranging's
  Workbench citations below it moved by nine; nothing they describe changed. project.yml
  changed only in a comment, so building-without-a-mac's `verified_at` moved alone

## [2026-11-14] zest-window: the bundle is real

- `Resources/Zest` now holds the built tools (143 files, 6.89 MB), so the page and ADR 0033
  describe what exists instead of what phase 2 would write. New rows for content types and
  Help › Acknowledgments; `ZestBundleTests` and the policy check in `zest/tests/inapp.js`
  under Tests. Four new traps: `zest/tests/inapp.js` parses the policy and types out of
  `Sources/Zest/ZestFiles.swift`, no `'unsafe-eval'`, a new extension needs a type, and
  `NOTICE` is edited at the root only

## [2026-11-14] building-without-a-mac re-verified

- Since `a9ac3a1`, `project.yml` changed only in a comment (the Zest folder reference is now
  described as generated, not to be generated), and the page cites no line below it, so
  `verified_at` moved alone. Help › Acknowledgments adds `Sources/App/Acknowledgments.swift`:
  the page's first trap applies, and the Xcode project is regenerated before merge

## [2026-11-14] zest-window: review fixes; rearranging re-verified

- zest-window: a Printing row (File › Print… for the tool in front), the tool's view now
  takes WebRTC away in every frame, and two traps: the rule list and the policy don't stop
  peer connections, and `window.print()` does nothing in the Zest window. The bundle is
  7,250,832 bytes (6.91 MB), NOTICE having grown by the appendix of what mermaid.min.js
  bundles; ADR 0033's size follows. Citations into ZestWebView, ZestWindow, Workbench and
  NetRelishApp moved with the new lines
- rearranging: Workbench grew by two lines above its Rearranging block (`printZest`), so its
  citations below line 164 moved by two; nothing they describe changed
