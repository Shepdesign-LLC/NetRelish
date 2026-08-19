# NetRelish — Master Plan

**Status:** approved decomposition, phase order confirmed
**Date:** 2026-08-18
**Supersedes:** the "Out by design" section of `docs/ROADMAP.md`
**Source:** Ryan's working business plan v1.0 (2026-08-08), off-repo at
`/Volumes/WORK/New Projects/NetRelish/business-plan.md`

This document decomposes the business plan into buildable projects. It is
not a spec. Each project below earns its own spec, plan, and
implementation cycle. This is the map that says what they are and what
order they go in.

---

## 1. What changed

The business plan predates the shipped product. It describes a web SaaS
captured through a browser extension; what shipped was a native macOS
browser where the extension's job is done by the app itself. Roughly 60%
of the plan already exists under different words — `docs/ROADMAP.md`
carries that translation and it stands.

The remaining 40% split on one axis: *does it need a server and an
account?* Four decisions taken 2026-08-18 resolved that axis:

| Decision | Choice |
| :-- | :-- |
| Scope | **Full plan, cloud in parallel** — the SaaS is a co-equal track, not a someday |
| AI layer | **Hosted, metered by plan** — the backend calls a language model; usage is what Pro sells |
| Web app | **Full product + extension** — sign up and use NetRelish in a browser; the Mac app is the premium native client |
| Sync | **Full account sync** — jars, Brine, items and recipes mirror to the account |

### What these decisions cost

Stated plainly, because the cost is real and the plan should not pretend
otherwise:

**Local-first is retired as a positioning claim.** "Nothing leaves the
machine" was simultaneously the engineering moat, the reason `⌘K`
returns in under 50ms, and the marketing line. Full account sync ends it.
What replaces it is "your Pantry, everywhere" — a weaker privacy story
and a stronger product story. This is the trade that makes §18
collaboration and §27's growth flywheel possible at all; neither works
when the data cannot leave.

The consequence is not a code change. It is that CLAUDE.md §4.1 and §4.5,
the netrelish.com privacy copy, and this roadmap must change *together*.
A cloud track built while §4 still reads "no network calls except page
loads" leaves every future session working against contradictory law.
That is why P0 exists and why it is first.

**What does not change:** suggest-never-silently (§4.2), closing is free
(§4.3), the native child webview (§4.4), and the vocabulary in §2. Those
four survive intact and remain law.

---

## 2. What the audit found

The plan, read against the shipped product, sorts into four buckets.

### Shipped, translated

Workspaces→Jars · Ingredients→items · "Relish This"→`⌘J` · save-in-seconds
capture · AI categorization and related-resources→on-device embeddings and
entity extraction · Browser Tab Intelligence→the suggestion strip ·
Recipes · search/filter/sort/tags→`⌘K` and labels · notes · web clipper at
page level. Plus passwords vaulted in the macOS Keychain, which the plan
never asked for.

### Unbuilt, buildable on-device

Gap analysis (§11) · knowledge graph surface (§12) · Relish Report (§15) ·
competitive research (§16) · element-level clipping · version history ·
research sessions (§33).

### Unbuilt, needs a backend

Public collections (§17) · SEO growth loop (§27–28) · Recipe marketplace
(§14, §20) · collaboration and roles (§18) · teams and agency tier (§19) ·
API (§20) · white-label reports (§20) · billing (§19).

### Contradicted CLAUDE.md §4 — now resolved by §1 above

LLM API as the AI layer · cloud sync · accounts · extension as a first-class
capture surface.

---

## 3. Architecture

### The seam that makes this one product

Two existing decisions carry disproportionate weight and should be
understood before anything is built.

**One `items` table with a `kind` discriminator** (CLAUDE.md §6) maps 1:1
onto a single Postgres table with row-level security. Five normalized
tables would have meant five reconciliation problems in the sync layer
instead of one. The schema was load-bearing for weeks 3–8; it is now
load-bearing for the entire cloud track.

**`src/lib/db.ts` is the only module that writes SQL.** That constraint,
written for tidiness, is the seam. It becomes an *interface* with two
implementations — SQLite locally, Supabase remotely — and the React
components above it do not know which they are talking to. This is what
makes the web app a port rather than a rewrite.

### Repository shape

The current repo is a single Tauri app. Three clients and a backend need a
workspace layout:

```
packages/core        types, the item/jar model, query parsing, ranking
packages/ui          Aero Relish design system, extracted from src/styles
apps/desktop         the current Tauri app, moved intact
apps/web             Next.js on Vercel — full product + public SEO pages
apps/extension       MV3, Chrome + Edge
supabase/            schema, RLS policies, Edge Functions
```

npm workspaces. `packages/core` is the contract; if a rule about items,
jars, ranking or query syntax exists in two clients, it lives here instead.

### Stack

| Layer | Choice | Why |
| :-- | :-- | :-- |
| Backend | **Supabase** | Postgres + Auth + RLS + Realtime + Storage + Edge Functions. Already named in CLAUDE.md §10 for license keys; this extends that commitment rather than adding a vendor. |
| Web | **Next.js on Vercel** | Already on Vercel. §28's public pages must be server-rendered to be indexable — that requirement alone rules out an SPA. |
| Extension | **MV3, Vite + TS** | Chrome and Edge per §24. Firefox later. Shares `packages/core`. |
| AI | **Claude via Edge Function** | Server-side, cached in Postgres, metered per plan. |
| Billing | **Stripe** | Standard; feeds the plan gates in §19. |

### Data model

The Postgres schema mirrors CLAUDE.md §6 with three additions:

- `user_id` on every table, with RLS restricting rows to their owner.
- `updated_at` and `deleted_at` on every syncable row — sync needs
  tombstones, because a delete that does not replicate is a resurrection.
- `version` integer per row, for conflict detection.

FTS moves from SQLite FTS5 to Postgres `tsvector` on the server; the local
FTS5 tables stay for offline search on the Mac. Both indexes are derived
from the same `title` and `body` columns, so they cannot disagree about
content — only about availability.

### Sync protocol

The highest-risk engineering in this plan. Design constraints:

- **Last-write-wins per field, not per row.** Two clients editing
  different fields of the same item must both survive.
- **Tombstones, never hard deletes**, until both sides have acknowledged.
- **Brine syncs.** Full account sync was chosen; carving out Brine would
  make "your Pantry, everywhere" a lie on the surface users touch most.
- **Offline is a first-class state on the Mac,** not an error. The app
  works fully disconnected and reconciles on reconnect. This is the one
  piece of local-first that survives, and it is worth keeping.

Sync is deliberately scheduled in Phase 4, after the web app has proven
the API in production. Building the protocol and its first consumer
simultaneously is how sync bugs become permanent.

---

## 4. The twelve projects

| # | Project | Plan § | Depends on |
| :-- | :-- | :-- | :-- |
| P0 | Constitution | — | — |
| P1 | The Core — backend, schema, auth | 24 | P0 |
| P2 | Web app | 7, 23 | P1 |
| P3 | Extension | 9, 25 | P1 |
| P4 | Mac sync | — | P1, P2 |
| P5 | Intelligence — hosted AI | 10, 11, 33 | P1 |
| P6 | Billing | 19, 29 | P1, P5 |
| P7 | Public & growth | 17, 27, 28 | P2 |
| P8 | Relish Reports | 15 | P5 |
| P9 | Competitive research | 16 | P8 |
| P10 | Teams & agency | 18, 20 | P6, P7 |
| P11 | Marketplace | 14, 20 | P7, P6 |
| P12 | Knowledge graph surface | 12 | P2 |

### P0 — Constitution

Rewrite the law before building against it. Amend CLAUDE.md §4 (§4.1 and
§4.5 specifically), §5 (architecture now includes a backend and three
clients), §10 (infrastructure is no longer "none of this is on the
critical path"), and §12 (email, sync, sharing, billing and teams move out
of "Not in v1"). Rewrite `docs/ROADMAP.md`'s "Out by design" section.
Restructure the repo to the monorepo layout with the desktop app moved
intact and still building.

**Also in P0, and blocking everything the Mac app touches: fix
notarization.** `APPLE_PASSWORD` is invalid and CI fails 401. Until that
clears, the Mac app cannot reach a single user — it is a dead asset, and
every hour spent on desktop features before it is fixed is speculative.

**Done when:** CLAUDE.md no longer contradicts itself, `npm run app:build`
works from the new layout, and a notarized build is stapled and verified.

### P1 — The Core

Supabase project. Postgres schema per §3 above. Auth (email + OAuth). RLS
policies with tests proving one user cannot read another's rows. The sync
protocol *specified* — written down, not yet implemented. A typed API
client in `packages/core`.

**Done when:** a signed-in client can create a jar, add an item, search it,
and a second account provably cannot see either.

### P2 — Web app

The full Pantry in a browser: jars, items grouped by kind, `⌘K` with the
same filter syntax, notes, tasks, labels, Brine. Aero Relish design system
from `packages/ui`. Ports the React components from `apps/desktop` against
the remote implementation of the db interface.

Capture in the web app is **paste-a-URL** (§23's "Save URL"): the server
fetches the page, extracts it, and files it. This is the only place the
server fetches a page on the user's behalf — the extension (P3) extracts
client-side instead — and it exists so the web app is usable on day one,
before the extension ships and on browsers it never will.

Explicitly *not* included: the native preview pane. The web app opens
links in tabs like any web app. §4.4's native-webview rule is a desktop
rule and does not travel.

**Done when:** a stranger with no Mac can sign up, create a jar, paste a
URL, and find that page by a phrase from its body.

### P3 — Extension

MV3 for Chrome and Edge. "Jar it" — the plan's §9 capture panel, one
click, choose a jar, add a note, save. Readability extraction runs
client-side in the content script and posts the extracted text, so the
server never fetches the page itself. Keyboard shortcut matching `⌘J`.

**Done when:** capture from any page in under two seconds, and the item
appears in the web app without a refresh.

### P4 — Mac sync

The Rust sync engine implementing P1's protocol. Sign-in UI in the
desktop app. Reconciliation, tombstones, conflict resolution, offline
queue. This is where the existing local SQLite meets the account.

**Done when:** a jar created on the Mac appears in the web app, an edit on
the web appears on the Mac, a change made offline survives reconnection,
and a delete on either side does not resurrect.

### P5 — Intelligence

Hosted language-model features, called from an Edge Function, cached in
Postgres, metered per plan:

- Summaries and key points (§10)
- Categorization and suggested tags (§10)
- **Gap analysis** (§11) — the plan's "What am I missing?", the single
  sharpest idea in the document
- **Ask your own research** (§33) — answers cited to the user's own items

The on-device MiniLM stays on the Mac for offline clustering and ranking.
It cannot write prose; that is what the hosted model is for. The two are
complementary, not redundant.

**Done when:** a jar of 40 items produces a coverage report naming what is
thin, and it is right often enough to be worth reading.

### P6 — Billing

Stripe. Free / Pro / Agency / Business per §19 and §29. Metering wired to
P5's usage. License keys for the Mac app. Plan gates enforced server-side,
never client-side.

**Done when:** a user can subscribe, hit a limit, upgrade, and cancel.

### P7 — Public & growth

Public jars, server-rendered and indexable. Creator pages. Fork and
follow. The §28 URL structure. Quality controls per §34's Risk 5 — no
auto-publishing of low-quality generated collections.

**Done when:** a public jar is indexable, forkable, and converts a visitor
into a signup.

### P8 — Relish Reports

Website intelligence per §15: design, technology, SEO, accessibility,
performance, marketing. Transparent scoring — the user can see how each
number was computed, per the plan's own insistence. Premium feature and
one-time-sale surface (§20).

**Done when:** a URL produces a report a designer would send to a client.

### P9 — Competitive research

Multi-site comparison built on P8: technology, design patterns, pricing,
features, messaging, SEO, CTAs, positioning (§16). The agency wedge.

### P10 — Teams & agency

Roles per §18 (Owner, Editor, Contributor, Viewer, Client). Client jars.
White-label reports. API access (§20).

### P11 — Marketplace

Recipes published, forked, and sold (§14, §20). Revenue share.

### P12 — Knowledge graph surface

A visual map over the entity and embedding data the engine already keeps
(§12). Deliberately last: the data exists, the surface is a nice-to-have,
and nothing depends on it.

---

## 5. Phase order

**Phase 1 — Foundation.** P0 → P1.
Nothing is safe to build until the law is rewritten and the schema exists.
Notarization is fixed here or the Mac app stays unreachable.

**Phase 2 — The plan's own MVP.** P2 + P3 + P5.
This is precisely §23's feature list and §38 Step 1's instruction. At the
end, a stranger signs up in a browser, installs the extension, jars
something, and gets a summary — the whole §41 core loop, no Mac required.

**Phase 3 — Make it a business.** P6 + P7.
Billing turns it into revenue; public jars turn it into distribution.
§27's flywheel needs both or neither.

**Phase 4 — Bring the Mac home.** P4.
Deliberately not earlier. Sync built against an API already proven in
production is a different and much smaller risk than sync built against an
API being designed at the same time.

**Phase 5 — The premium wedge.** P8 → P9.
The strongest features in the plan and the clearest one-time sale — and
worthless without users to sell them to.

**Phase 6 — Scale.** P10, P11, P12.

---

## 6. Open questions

**Vocabulary.** CLAUDE.md §2 forbids "workspace" and "collection" and
forbids inventing brand words without asking. A public jar needs a name.
The plan proposes "Shared Relish." This is Ryan's call and P7 is blocked
on it — though not until Phase 3, so there is time.

**Effort.** The eight weeks that produced the Mac app produced roughly one
of these twelve projects' worth of surface. Phase 1–2 alone is a
substantial build. Recorded here so it is not discovered in month three.

**Metrics.** §30's metric list assumed no telemetry was possible. With
accounts, it is. What gets measured — and what is promised not to be — is
a P0 decision that has not been made.

---

## 7. Risks

| Risk | Mitigation |
| :-- | :-- |
| Sync conflicts corrupt real data. Ryan's database is production data. | Field-level LWW, tombstones, and a full backup before P4's first run. Phase 4 placement is itself the mitigation. |
| AI cost outruns revenue (plan §34 Risk 2) | Cache aggressively, meter from day one in P5 rather than retrofitting in P6, small models for classification. |
| Twelve projects becomes twelve half-projects (§34 Risk 3) | Each project ships to a stated done-when before the next starts. Phases are gates, not suggestions. |
| Local-first users feel betrayed by the sync reversal | Offline stays first-class. Say the change plainly in release notes rather than letting it be discovered. |
| The Mac app diverges from the product while sync waits until Phase 4 | Accepted deliberately. The alternative — sync first — risks the data. |

---

*Each project earns its own spec before implementation. This document is
the map, not the territory.*
