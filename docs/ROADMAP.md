# Roadmap & positioning

The business layer of NetRelish, translated from Ryan's working business
plan (v1.0, Aug 2026) into the vocabulary and architecture of the
shipped product. The plan itself is deliberately **not in this repo** —
it lives at `/Volumes/WORK/New Projects/NetRelish/business-plan.md`.

**Ground rules.** CLAUDE.md remains law. Where the plan says Workspace,
the product says **Jar**; where it says Ingredient, the product says
item; where it describes cloud SaaS mechanics, those are now
**adopted** rather than translated — see "Reversed on 2026-08-18" below.
The vocabulary translation still holds absolutely. The repo went public
in Aug 2026 and `business-plan.md` was purged from its history first, as
this note had asked. Keep it that way: strategy stays off the public
record.

---

## Positioning

NetRelish sits **between research and execution**. The product answers
one question:

> "I found all this stuff. Now what?"

Every competitor owns a neighboring space — bookmark managers own
saving, Notion owns documents, read-later apps own consuming, AI
assistants own answering. Nobody owns the gap between *found it* and
*used it*. That gap is the product.

The plan's sharpest line is approved for marketing copy:

> **Don't just save the web. Use it.**

The tagline stays **"Savor the web. Get more done."** (CLAUDE.md §1 —
the tagline is the spec). The plan's alternates live in §36 of the plan
as a copy bench for the site.

One metaphor correction, ours wins: in NetRelish the **Pantry is what
you've preserved**, not the internet. The web is the market you shop
in; the Pantry is home.

## Who it's for

The plan's market ladder, unchanged — it's right:

1. **Web designers & developers** — research constantly, repeat
   workflows across clients, feel tab-chaos daily. (This is Ryan.
   The first user is the persona.)
2. **Marketers** — competitor research, SEO research, campaign
   research. Jars are client files.
3. **Business professionals** — market research, vendor comparisons,
   planning.
4. **Students & knowledge workers** — projects, reading lists, topic
   collections.

Sell to 1 first. They already have the problem at high frequency, and
their public output attracts 2–4.

## Translation table

| Business plan says | The product says | Status |
| :-- | :-- | :-- |
| Workspace | **Jar** | shipped |
| Ingredient | item (`page/note/task/file/message`) | shipped |
| Relish This (extension button) | **Jar it** (`⌘J`) | shipped |
| Save-in-seconds capture panel | `⌘J` — zero-UI capture, already organized | shipped |
| Browser Tab Intelligence | the engine's suggestion strip | shipped |
| AI categorization / related resources | on-device embeddings + entities (§8) | shipped |
| Repeatable workflow / Recipe | **Recipe** — recorded, not authored | shipped |
| Web clipper | `⌘J` on a selection | shipped (page-level); element-level is future |
| "What am I missing?" gap analysis | future engine layer — see below | next |
| Relish Report (website analysis) | future feature; naming is Ryan's call when scheduled | later |
| Knowledge graph | entities + embeddings exist; a visual surface is future | later |
| Public collections / marketplace / teams | out until ~1,000 users (CLAUDE.md §12) | later |
| Accounts, cloud backend, LLM API | **not translated** — see "Out by design" | — |

The plan's own thesis — *"NetRelish should live inside the browser"* —
is fulfilled beyond what it asked: the plan wanted an extension riding
in Chrome. NetRelish **is** the browser.

## Roadmap

### Shipped — v0.1

The eight weeks of CLAUDE.md §11: shell, Brine, Jars, Ask the Pantry,
Sealing, the engine, Recipes, notes/tasks/files/labels. Signed +
notarized release pipeline. Aero Relish design system.

### Now — the master plan

Twelve projects, six phases. Summarised here; the spec is authoritative.

| Phase | Projects |
| :-- | :-- |
| 1 Foundation | P0 constitution + monorepo + notarization · P1 backend |
| 2 MVP | P2 web app · P3 extension · P5 hosted intelligence |
| 3 Business | P6 billing · P7 public jars and growth |
| 4 Mac home | P4 sync |
| 5 Premium | P8 Relish Reports · P9 competitive research |
| 6 Scale | P10 teams · P11 marketplace · P12 knowledge graph |

Already shipped and not re-listed above: the eight weeks of CLAUDE.md §11,
and **passwords** (2026-08-11) — save and fill logins vaulted in the macOS
Keychain, never in `netrelish.db`, never near FTS or the engine. The fill
path runs Rust→page; the UI layer only ever sees usernames. Detection is a
suggestion; saving and filling are user gestures. Still wanted: a management
panel, CSV import from Safari/Chrome, a multi-account picker, Touch ID on
reveal, and subdomain matching.

Still unscheduled, still wanted: element-level clipping, email via IMAP, a
PWA companion.

### Reversed on 2026-08-18

This section used to list what the plan asked for and the architecture
refused. Ryan reversed all four. Kept here rather than deleted, because the
reversal is the single most consequential decision in the project:

| Was out | Now | Where |
| :-- | :-- | :-- |
| Accounts, cloud backend | **In** — Supabase, full account sync | P1, P4 |
| LLM API in the product | **In** — hosted, metered by plan | P5 |
| Extension as a capture surface | **In** — MV3, Chrome + Edge | P3 |
| Public collections, marketplace, teams | **In** — scheduled, phases 3 and 6 | P7, P10, P11 |

What survives: the on-device embedding model stays (it does ranking and
clustering offline, and the hosted model does prose — they are
complementary); offline remains the floor; the vocabulary in CLAUDE.md §2 is
unchanged; and §4a now bounds what may leave the machine.

The full decomposition is
`docs/superpowers/specs/2026-08-18-netrelish-master-plan-design.md`.

## Metrics that matter (plan §30, kept)

Activation (first item preserved), time-to-value, second-jar creation,
weekly actives, items per active user, suggestion acceptance rate,
recipe reuse, retention. Accounts make server-side measurement possible
for the first time. What gets measured is not yet decided, and per
§4a nothing is collected until it is written down. Until then: opt-in
feedback and download counts.
