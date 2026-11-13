# NetRelish docs/ wiki contract

> This directory is a **wiki maintained by an LLM**: linked markdown pages, not a pile of
> flat documents and not a separate site.
> This file defines the rules. **Change the structure only with the user's approval.**

The repository root `CLAUDE.md` tells the agent *how to work*. This file says *how to
keep the documentation*. Where they overlap, link -- do not copy the text across.

## Why this shape

A single large document loses three things.

1. **Progressive disclosure** -- answering one question means reading all of it.
   `index.md` (small) then 2-3 relevant pages is far cheaper
2. **A sync mechanism** -- no way to compute which document drifted from the code
3. **A single source of truth** -- the same fact in several documents will diverge

So every page carries `verified_at` (the commit it was checked against), and an update
reads **only what changed since that commit** instead of re-reading everything.

## Language

Pages are written in **English**. Frontmatter keys, `[[link]]` targets, file paths and the
`/docs-*` commands stay as they are, whatever the language of the prose. Page file names
may be in English; the linter and hooks handle non-ASCII names. To change the language,
change this line -- every agent working on this repository reads it before writing.

## Pages are categorised by access pattern

| | Categories |
|---|---|
| **Exploratory** | `concepts` `architecture` `subsystems` `decisions` |
| **Lookup** | `reference` `operations` |
| **Historical** | `history` |

**Exploratory** pages are read when you do not know where to look, so `index.md` and
`[[links]]` must be dense. **Lookup** pages are opened when you already know -- tables,
kept short. Decide which kind a new page is before writing it.

## Layout

```
docs/
├── CLAUDE.md      this file
├── index.md       table of contents + reading order
├── log.md         work log (append-only)
├── raw/           source material that exists neither in code nor in pages
│
├── concepts/       Domain and product concepts. Mostly survive code changes
├── architecture/   System structure, data model, main flows
├── subsystems/     Per-subsystem implementation
├── decisions/      Why it was decided that way (ADRs, known defects)
├── reference/      Schemas, APIs, env vars -- documents you look values up in
├── operations/     Install, deploy, checks, incident response
├── history/        Development history, lessons, migrated records
```

## What in docs/ is not the wiki

`docs/` held records before the wiki did, and they stay exactly as they are:

| Path | What it is |
|---|---|
| `adr/` | decisions, one per file. The record of *why*. Never rewritten |
| `design/` | the design handoffs and prototypes |
| `superpowers/` | dated specs and plans |
| `voice/` | the house and product voice guides |
| `releases/` | release notes |
| `KICKOFF.md` `ROADMAP.md` `NetRelish_Plan_and_Roadmap.md` `PantryKit_Groundwork.md` `RELEASING.md` `SYSTEM_DESIGNER.md` `notarization.md` | planning and how-to documents |

A wiki page **points at** these (by path, in backticks) and does not copy them. The
linter skips them: the list is `DEFAULT_EXCLUDE_DIRS` in `.claude/scripts/docs-lint.py`.
A new top-level document in `docs/` that is not a wiki page has to be added there, or the
linter reports it as a page with no frontmatter.

The repository's copy of the linter differs from the plugin's in two places, both marked
`NetRelish:` in the file: that exclude list, and `swift` in the list of code extensions
whose citations are checked. If the copy is refreshed from the plugin, put both back.

A wiki page says how the code is put together and where it bites. An ADR says what was
decided and who decided it. When a page needs a decision, it names the ADR.

## Page format

```yaml
---
title: Page title
type: concept | architecture | subsystem | decision | reference | operation | history
created: YYYY-MM-DD
updated: YYYY-MM-DD          # the day the body actually changed
sources:
  - code: src/services/search.py      # path from the repository root
  - raw:  YYYY-MM-DD_meeting-notes.md
  - ext:  https://...
verified_at: <short sha>              # the commit this page was checked against
---
```

Rules:

- Mentioning another page means linking it: `[[page-name]]` (file name, no path)
- No claim without a source. If there is no evidence, write `(unverified)`
- Cite code as `path/to/file:line`. **Do not paste code in.**
  Describe what it does and why, and point at where it lives
- **Write every trap as its own `> ⚠️` paragraph.** A trap is something that bit, or will
  bite, whoever changes this code: an ordering that matters, a setting that must stay, a
  fix that looks wrong but is right. Before a file is edited, the plugin's hook shows the
  `⚠️` paragraphs of the pages that cover it, and nothing else. A trap written as plain
  prose is never shown at the moment it matters
- `updated` is the day the body changed. If you only confirmed the sha and the prose
  still holds, move `verified_at` alone
  - Note that `/docs-lint` reports such a page as **unverified**
    ("sha moved past N code commits with no body change"). That is not a prohibition --
    it marks a *weak* verification. `verified_at` is a declaration, not proof, and this
    is the one place where "did you actually read it?" becomes visible
- **One fact lives on one page.** Link from anywhere else that needs it.
  In particular, a lookup page and an exploratory page must not each carry the same table

## What counts as code

This is how `/docs-sync` and `/docs-status` decide "did the code change".

```
code = the whole repository - { docs , .claude , CLAUDE.md }
```

It is an **exclude list**, not an include list. When a new code directory appears an
include list silently misses it; an exclude list picks it up automatically. If you
change this definition, fix the pathspec in
`.claude/commands/{docs-sync,docs-status}.md` as well.

> Because the docs live in the same repository as the code, **editing only docs still
> moves HEAD.** Without this filter `/docs-status` keeps reporting "N commits behind"
> when there is nothing to do, and then nobody believes it any more.
>
> This is **a filter for judgement, not a version-control exclusion.** `docs/` and
> `.claude/` are committed alongside the code on purpose -- documentation has to travel
> with the repository for whoever clones it to keep it up.

## Workflow

- `/docs-sync` -- read only what changed and update affected pages. **Stop immediately if
  no code changed**
- `/docs-lint` -- orphans, broken links, broken sources, stale, unverified
- `/docs-query` -- answer from the docs only. If it is not there, say so
- `/docs-status` -- commits not yet reflected, stale pages, recent work

## When you change code

| What changed | Page to update |
|---|---|
| Right-click menus, drag, tab icons, anything under `// MARK: Rearranging` in the Workbench | [[rearranging]] |
| The Zest sound kit, the Sound toggle, `zest/tests/sound.js` | [[zest-sound]] |
| CI workflows, `project.yml`, the generator scripts, how generated files are checked | [[building-without-a-mac]] |

The table grows with the wiki. An area with no row has no page yet.

**Rhythm**: run `/docs-sync` right after a deploy or a release -- the moments when
changes pile up. Do not wait to be asked.

**Releases**: a deploy or a release moves no commit, so the plugin cannot see one unless
the line below names it. Write the commands that deploy or release this project as one
regular expression (for example `fastlane|docker compose .* up|npm publish`). When an
agent runs a matching command, the commit hook says `/docs-sync` is due. Leave it empty if
there are none.

release-commands:

## Security

**Never record secret values.** Variable names at most.

**This repository is public.** No real client names, domains, contacts, billing details
or logins on any page; the design handoffs were scrubbed of them when they landed
(`docs/design/README.md`). The timestamping and license addresses are public and already
committed (ADR 0022); nothing else about how the app is released or signed belongs here.

## This wiki grows as you work

docs-mode: grow

It was started small: a skeleton and a page or two. It is filled in where work happens,
not all at once.

- **When you finish work in an area no page covers, add a page for it, or extend the
  nearest page.** What the code does, why it is that way, and every trap you hit as a
  `> ⚠️` paragraph, with `sources` pointing at the files you worked in. Keep it short;
  it will grow. The commit hook names files a commit touched that no page covers yet.
- **Do not document areas you did not work in.** That is what `/project-docs-setup`
  does later, when someone wants the whole picture: it fills the uncovered areas and
  leaves the pages written here alone.
