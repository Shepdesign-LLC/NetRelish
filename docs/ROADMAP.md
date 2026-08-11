# Roadmap & positioning

The business layer of NetRelish, translated from Ryan's working business
plan ([business-plan.md](business-plan.md), v1.0, Aug 2026) into the
vocabulary and architecture of the shipped product.

**Ground rules.** CLAUDE.md remains law. Where the plan says Workspace,
the product says **Jar**; where it says Ingredient, the product says
item; where it describes cloud SaaS mechanics, the local-first
architecture wins. The plan's *vision* is adopted; its *mechanics* are
translated. This repo is private; if it ever goes public, pull
`business-plan.md` first.

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

### Next — post-launch, all local

- **Passwords** — save and fill logins, vaulted in the **macOS
  Keychain** — never in `netrelish.db`, never near FTS or the engine.
  The fill path runs Rust→page; the UI layer only ever sees usernames.
  Detection is a suggestion, saving and filling are user gestures
  (suggest-never-silently applies to credentials most of all). Import
  from Safari/Chrome via their CSV export. Requested by Ryan
  2026-08-11 — the daily-driver feature.
- **Gap analysis** — the plan's "What am I missing?" (§11). A fifth
  engine layer: cluster a jar's items by topic, name the clusters,
  report thin coverage. Same rules as every engine output: on-device,
  a suggestion, never auto-applied.
- **Element-level clipping** — `⌘J` on a selection already preserves
  the page; promote selections to first-class snippets on the item.
- **Email** — `kind='message'` via IMAP (CLAUDE.md §12; the schema has
  been waiting since week 2).
- **PWA companion** for reading your Pantry from a phone (§12).
- **netrelish.com** on the real domain; download page feeds the ladder.

### Later — at scale

- **Billing** — freemium per the plan's §19: free tier generous enough
  to live in, Pro ~$15/mo. License keys via Supabase (§10) — a table
  with four columns, still no user data in the cloud.
- **Website reports** — the plan's Relish Report (§15), built as local
  analysis of a URL you visit. Transparent scoring. Premium candidate.
  Ryan names it when it's scheduled.
- **Knowledge-graph surface** — a visual map over the entity and
  embedding data the engine already keeps.
- **Sharing / public collections / marketplace** — the plan's growth
  loop (§14, §17, §27). Revisit at 1,000 users per CLAUDE.md §12;
  publishing is opt-in export, never sync-by-default.
- **Teams / agency tier** — client jars, roles, white-label reports
  (plan §18). A different product; earns its way in only after
  individuals retain.

### Out by design

From CLAUDE.md §4, restated because the plan contradicts them:

- **No accounts, no cloud backend, no telemetry.** Local is the
  engineering moat — instant search, offline everything, privacy as a
  consequence. Sync, if ever, is end-to-end encrypted blobs (§10).
- **No LLM API in the product.** The AI layer is on-device (§8). The
  plan's "AI should support the product, not become it" survives
  translation; its cloud mechanics don't.
- **No extension as the product.** The product is the browser.
- **No plan vocabulary in the UI.** Jar, Brine, Seal, Batch, Recipe,
  Pantry — CLAUDE.md §2 is the only dictionary.

## Metrics that matter (plan §30, kept)

Activation (first item preserved), time-to-value, second-jar creation,
weekly actives, items per active user, suggestion acceptance rate,
recipe reuse, retention. No telemetry means these are measured through
opt-in feedback and download/update counts, not spyware — the
constraint is the brand.
