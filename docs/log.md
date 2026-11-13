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
