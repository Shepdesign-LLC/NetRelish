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
