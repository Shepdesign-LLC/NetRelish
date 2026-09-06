# NetRelish

> **Savor the web. Get more done.**

A downloadable macOS browser that is also a workstation. Not a browser with
notes bolted on — a browser where everything you touch is already organized.

Direct download, Developer ID signed and notarized. **Not on the App Store.**

This file is the single source of truth: vocabulary, architecture, schema,
conventions, and the eight-week build order. Read it before writing code.

---

## 1. What it is

Chrome gives you tab groups — a coloured rectangle that holds tabs and forgets
everything else. NetRelish gives you **Jars**: a project that holds tabs,
notes, tasks, files and messages together, knows what its subject is, and can
be run as a **Recipe**.

Everything you browse is preserved into **Brine** automatically — extracted,
full-text searchable, offline, forever. Closing a tab stops meaning losing it.

The tagline is the spec. **Savor the web** is the capture half: nothing you
read is lost, everything is preserved and findable. **Get more done** is the
workflow half: jars, recipes, sealing. Every feature serves one or the other.
If a proposed feature serves neither, it doesn't ship.

---

## 2. Vocabulary

Use these words in UI copy, docs and commit messages.

| Word | Meaning | Notes |
| :-- | :-- | :-- |
| **Pantry** | Everything the user has. The home surface. | |
| **Jar** | A project. Holds items of every kind. | The core object. |
| **Jar it** | Verb. `⌘J` on a page, selection, file or message. | The primary gesture. |
| **Recipe** | A runnable workflow attached to a jar. | Recorded, not authored. |
| **Brine** | Everything browsed but not yet sorted. | Preserved, unlabeled. |
| **Seal** | Preserve an untouched tab into its jar and close it. | Never "archive", never "compost". |
| **Label** | A tag on a jar or item. | |
| **Batch** | Everything jarred or sealed in one go. | |
| **Relish** | A jar published for other people. | Followable, forkable. |
| **Flavor** | A theme. Aurora is the default. | Never "skin", never "mode". |
| **NetRelish ID** | The account. | Never "profile" for the account itself. |

The last three were approved 2026-08-19 by the Workstation/iOS design pass
(`docs/design/`). They are the only brand words added since v1, and they were
added because accounts and publishing gave the product concepts it genuinely
did not have a name for.

**Rules**

- Brand words appear in **product surfaces**. Database tables and internal
  types stay boring: `items`, `tabs`, `sources`, `jars`. `Jar` keeps its name
  because it is a real domain object. Nothing else gets cute.
- Never invent new brand words. If a concept seems to need one, stop and ask.
- Never use: workspace, collection, board, space, vault, knowledge graph,
  smart folder, compost, larder, second brain.

---

## 3. Tone

Dry, precise, fast. The personality lives in the system being coherent, not in
jokes. The vocabulary does the work.

- Errors say what broke and how to fix it. They never wink.
- Empty states are invitations to act — the one place warmth is allowed.
- Active voice, sentence case, no filler. A button that says **Seal** produces
  a toast that says **Sealed**.
- Never write a clever line on the critical path. Funny once, irritating on
  the fortieth read.
- Name things by what the user controls, never by how the system is built.

---

## 4. Non-negotiables

1. **Offline is the floor.** SQLite on disk stays the source of truth on the
   Mac, and every feature must work with the network unplugged. Sync is
   additive: it makes the Pantry reachable elsewhere, it never becomes the
   thing the app needs in order to function.

   This is what survives of local-first, and it is the part worth keeping.
   Local is still why `⌘K` returns in under 50ms — that is a read against
   a file on disk, and it must stay one.

   *(Amended 2026-08-18. This clause previously read "Everything is local /
   no network calls except page loads". Ryan reversed it — see §4a and
   `docs/superpowers/specs/2026-08-18-netrelish-master-plan-design.md`.)*

2. **Suggest, never file silently.** The organization engine proposes; the
   user approves with one key. Auto-filing that's wrong 15% of the time
   destroys trust in the jar, and an untrusted knowledge base is dead weight.

3. **Closing is free.** Any action that removes something from view must
   preserve it first. Nothing is ever lost by tidying. This is the whole
   promise — violating it once loses the user permanently.

4. **The preview is a native child webview, not an iframe.** See §5.

5. **The cloud is a co-equal track.** Supabase is the backend, the web app is
   a first-class client, and the extension is a real capture surface. What
   this does *not* license is drift: a server feature ships against the
   schema in §6 and the vocabulary in §2, or it doesn't ship.

### 4a. What may leave the machine

Full account sync was chosen deliberately, which makes this list the
replacement for the old "nothing leaves" promise. It is exhaustive; adding
to it is a decision, not an implementation detail.

| Leaves | Why | Note |
| :-- | :-- | :-- |
| Jars, items, labels, recipes, tabs | Sync | The user's own content, under their account |
| Extracted page text | Sync + hosted AI | Same rows as above; §7 still governs extraction |
| Page text sent for analysis | Summaries, gap analysis, reports | Extracted **page** bodies only — never notes (below). Per-request, cached server-side, shown in the UI while it happens. **Two third parties** receive it: Anthropic for prose and Voyage AI for embeddings. Neither receives anything yet — P1 built the schema, P5 turns them on |
| Account credentials | Sign-in | Email + password, or an OAuth token, to Supabase Auth. This is the account you sign in *with* — not the logins NetRelish stores *for* you, which never leave (below) |
| Licence + subscription state | Billing | |

**Never leaves, under any feature:**

- **Your own writing — on a password account.** Note bodies, and the bodies
  of tasks, are encrypted **client-side** before they sync. The server stores
  ciphertext it cannot read, no AI feature may be given them, and publishing
  a Relish excludes them unless the user explicitly includes one.

  **This does not hold for OAuth accounts, and the UI must say so.** The key
  is derived from the password, so signing in with GitHub leaves nothing to
  derive it from. On an OAuth account, notes are stored like page text: the
  server can read them. That is a real second privacy tier, and it is stated
  here rather than buried because an unqualified promise is exactly the
  failure this section was written to correct — the design mocks claimed
  "we can't read your Pantry" while showing AI that reads it.
  *(Decided 2026-08-19.)*

  Two rules follow. Account settings must show which tier the account is on,
  in plain words, not a padlock icon. And the product may never say "your
  notes are private, even from us" to an OAuth user — that sentence is true
  only on a password account.

  The line is principled, not arbitrary: a note is something you wrote, a
  page is a copy of something already public. That is why pages can be
  analysed and notes cannot, and why the product can honestly say *your
  notes are private, even from us* without pretending the whole Pantry is.

  *(Decided 2026-08-19. The design mocks said sync was end-to-end encrypted
  while showing AI that reads your items; both could not be true. This is
  the resolution — see `docs/design/`.)*
- **Saved website credentials.** Passwords live in the macOS Keychain and are not rows in
  `netrelish.db`. They do not sync, they are never sent for analysis, and no
  server-side feature may read them. Shipped 2026-08-11: the fill path runs
  Rust→page, and the UI layer only ever sees usernames.
- **Private-window browsing.** §7 already forbids extracting it; it therefore
  has nothing to sync. §7 governs the desktop preview webview, so this is
  also a requirement on every other client: the extension must not capture
  in a private or incognito window.
- **Denied URLs.** The deny list is applied before a row exists, so denied
  pages never reach the server for the same reason. Same requirement: the
  extension enforces the list locally, before anything is sent.
- **Telemetry.** There is still none. Accounts make it possible; that is not
  the same as deciding to. Until it is written here, it does not exist.

---

## 5. Architecture

NetRelish is three clients over one backend. The Mac app below is the
premium native client and the only one with a native page pane; the web app
and the extension are P2 and P3 of the master plan.

```
Supabase           Postgres + Auth + RLS + Edge Functions
├── apps/desktop   the Tauri app below — offline-capable, syncs
├── apps/web       Next.js on Vercel — full product + public pages
└── apps/extension MV3 — capture only
```

The rest of this section describes the desktop client specifically.

```
NetRelish.app
├── Chrome UI            React 18 + Vite + TypeScript, ships in the bundle
│   ├── Sidebar          tabs, Brine, jar orbs — glass, per the design system
│   ├── Titlebar         back/forward, address pill, jar chip (⌘K)
│   └── Stage            an empty div — a hole for the native pane
├── Rust core            SQLite, extraction, webview positioning
└── Preview webview      a real child WKWebView
```

### The preview pane is not in the DOM

`Window::add_child` (tauri `unstable` feature) parents a real WKWebView to the
main window. React renders an empty `.nr-stage` div, a `ResizeObserver`
measures it, Rust positions the webview over that rect.

**Iframes are a dead end for a browser.** `X-Frame-Options` and
`frame-ancestors` mean most of the web refuses to load in one — Google,
GitHub, banks, WordPress admin. Do not "simplify" this back to an iframe.

Consequence: **nothing rendered inside `.nr-stage` survives once a page
loads.** Overlays, palettes and toasts must be siblings, not children.

### Storage

SQLite via `tauri-plugin-sql`, plus FTS5 and (week 6) `sqlite-vec`. One
database at
`~/Library/Application Support/com.netrelish.app/netrelish.db`.

Migrations live in `src-tauri/migrations/NNN_name.sql`, applied in order at
startup, never edited once shipped.

Desktop paths in this file are relative to `apps/desktop/`. The repo is an
npm-workspaces monorepo; `npm run app` from the root still works.

---

## 6. Schema

**The decision everything depends on:** one `items` table with a `kind`
discriminator. Pages, notes, tasks, files and messages share one row shape,
one index, one search, one suggestion engine. Email is not a future feature —
it is `kind = 'message'` in a table that already exists.

Do not normalize this into five tables. It will look tidier and it will cost
you every cross-kind feature in the product.

```sql
CREATE TABLE jars (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  hue         INTEGER NOT NULL,        -- 1..6, maps to --nr-jar-N
  created_at  INTEGER NOT NULL,
  sealed_at   INTEGER                  -- non-null = archived jar
);

CREATE TABLE items (
  id           TEXT PRIMARY KEY,
  jar_id       TEXT REFERENCES jars(id) ON DELETE SET NULL,  -- NULL = Brine
  kind         TEXT NOT NULL CHECK (kind IN
                 ('page','note','task','file','message')),
  url          TEXT,
  title        TEXT NOT NULL,
  body         TEXT,                   -- extracted or authored text
  meta         TEXT,                   -- JSON, kind-specific
  created_at   INTEGER NOT NULL,
  touched_at   INTEGER NOT NULL,
  sealed_at    INTEGER
);

CREATE INDEX idx_items_jar  ON items(jar_id, touched_at DESC);
CREATE INDEX idx_items_kind ON items(kind, touched_at DESC);
CREATE UNIQUE INDEX idx_items_url ON items(url) WHERE url IS NOT NULL;

CREATE VIRTUAL TABLE items_fts USING fts5(
  title, body,
  content='items', content_rowid='rowid',
  tokenize='porter unicode61'
);

CREATE TABLE tabs (
  id            TEXT PRIMARY KEY,
  jar_id        TEXT REFERENCES jars(id) ON DELETE CASCADE,
  item_id       TEXT REFERENCES items(id),
  opened_at     INTEGER NOT NULL,
  touched_at    INTEGER NOT NULL,
  seal_after    INTEGER                -- epoch; NULL = pinned, never seals
);

CREATE TABLE labels (
  id    TEXT PRIMARY KEY,
  name  TEXT NOT NULL UNIQUE
);

CREATE TABLE item_labels (
  item_id   TEXT REFERENCES items(id) ON DELETE CASCADE,
  label_id  TEXT REFERENCES labels(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, label_id)
);

CREATE TABLE recipes (
  id      TEXT PRIMARY KEY,
  jar_id  TEXT NOT NULL REFERENCES jars(id) ON DELETE CASCADE,
  name    TEXT NOT NULL,
  steps   TEXT NOT NULL               -- JSON array
);

CREATE TABLE embeddings (             -- week 6
  item_id  TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
  vector   BLOB NOT NULL
);
```

**FTS5 external-content tables need all three triggers** — `INSERT`, `UPDATE`
and `DELETE`. Miss one and the index silently drifts out of sync with `items`.
No error, no crash, just search that quietly stops matching reality.

---

## 7. Extraction

On every page load in the preview webview:

1. Inject a content script, run Readability, return title + text + byline.
2. Upsert into `items` with `kind='page'`, `jar_id` = active jar or `NULL`.
3. `items_fts` updates via triggers.

Rules:

- Under 50ms p95. Never block paint.
- Skip URLs matching a user-editable deny list.
- Never extract in a private window.
- Re-visiting a URL updates `touched_at` and refreshes `body`. One row per URL.

---

## 8. The organization engine (week 6)

Four layers, all on-device. The on-device engine is not replaced by the
cloud track — it is what keeps ranking and clustering working with the
network unplugged (§4.1). P5 adds a **fifth, hosted layer** for the things
a 90MB local model cannot do: prose, gap analysis, reports. The two are
complementary, and what may be sent to the hosted one is bounded by §4a.

The four local layers:

1. **Sessions** — pages visited within a time window, with referrer chains
   between them, are one working session. Cheap, and it catches most cases.
2. **Semantics** — extracted text → local ONNX embedding model (~100MB, `ort`
   crate, Apple Silicon) → `sqlite-vec`.
3. **Entities** — domains, repo paths, ticket IDs (`[A-Z]{2,6}-\d+`), client
   names pulled from text.
4. **Correction** — when the user moves an item out of a jar, weight it. The
   engine learns *their* boundaries, not a generic notion of topic.

Output is always a suggestion — *"6 things in Brine look like they belong
here"* — accepted with one key. Never applied automatically.

---

## 9. Conventions

**TypeScript**

- Strict. No `any`. No non-null assertions outside `main.tsx`.
- Function components with a typed `Props` interface directly above them.
- No state library. `useState` and context until something actually hurts.
- All data access goes through `src/lib/db.ts`. Components never write SQL.

**Rust**

- Commands in `src-tauri/src/commands/<domain>.rs`, one domain per file.
- Every command returns `crate::error::Result<T>`. No `unwrap()` in a command
  path.
- Anything touching the filesystem validates containment before writing.

**CSS**

- Plain CSS with custom properties. No Tailwind, no CSS-in-JS.
- All colour in OKLCH. Never hex, never `rgb()`.
- All tokens `--nr-` prefixed, in `src/styles/netrelish.css`.
- App chrome is **aero glass over the Aurora** (brand system v2, §04):
  the window floats the guide's Aurora Sweep; every chrome surface is the
  one glass recipe (fill `rgba(244,248,232,…)`, backdrop blur 28/20,
  hairline `rgba(255,255,255,.55)`, inner highlight) at window/panel/
  control depths; text on glass never lighter than `#33430F`. Actives
  trade glass for Relish Pour with a gloss cap; the active jar tile wears
  its orb. Never stack glass more than two layers deep. The native page
  pane stays opaque — the glass frames the web, it never tints it.
  *(Re-amended Aug 2026: Ryan saw the glass live on netrelish.com and
  chose it for the app, reversing the earlier flat-chrome decision.)*
- **Two surfaces are exceptions to the light glass, and take light ink.**
  Both float on the Aurora rather than sitting on glass, so the
  `#33430F` floor above does not apply to them — it is a rule about ink
  *on glass*, and olive on either of these measures ~1.5:1.
  1. **The titlebar** is dark green glass: `rgba(46,68,22,.85)` →
     `rgba(24,38,11,.85)`, blur 28, hairline `rgba(196,242,107,.28)`,
     inset highlight `rgba(220,250,160,.22)`, 58px. Its controls are
     light-on-dark, its ink is Electric `#C4F26B` (`--nr-electric`), and
     disabled ink is `#6D8050`. The jar chip keeps Relish Pour.
  2. **The Home / new-tab screen**, which has no panel under it at all
     and uses the light-ink scale (`--nr-ink-light`, `…-meta`, `…-chip`).
  Everywhere else, the light glass and the `#33430F` floor still hold.
  *(Amended Aug 2026, "Aero Relish" handoff — the redesign's TitleBar
  revision. The handoff itself kept olive status text on the new dark
  bar; that was a defect and is not reproduced.)*
- The one signature move is the **superellipse** tile shape
  (`src/lib/superellipse.ts`). Not `border-radius`. Don't replace it. The
  guide's flavor-jar orb gradients render *inside* the superellipse.

**Commits** — conventional and scoped: `feat(jars):`, `fix(preview):`,
`chore(db):`.

**Quality floor** — every shipped surface is keyboard reachable, has a visible
focus ring, respects `prefers-reduced-motion`, works at 880px wide, and works
in light and dark.

---

## 10. Infrastructure

| Service | When | For |
| :-- | :-- | :-- |
| **GitHub Releases** | shipped | Binaries + signed updater manifest. Free. |
| **Supabase** | P1 | Postgres + Auth + RLS + Edge Functions — sync, accounts, hosted AI, licence state. Bounded by §4a. |
| **Vercel** | P2 | netrelish.com and the web client. |
| **Stripe** | P6 | Plans, metering, licence keys. |

End-to-end encryption is **partial, by design**. Whole-Pantry E2E — "blobs
the server can't read" — stays abandoned: it is incompatible with a hosted
model that has to read page text, and giving that up would mean giving up
what Pro sells. But **notes and task bodies are encrypted client-side**
(§4a), because nothing on the server needs to read them.

Say it precisely in UI copy. "End-to-end encrypted" without qualification is
false and must not ship; "your notes are private, even from us" is true.

As of 2026-08-18 this table is the critical path, not a someday. Supabase is
the backend for sync, auth and the hosted AI layer; Vercel hosts the web app;
Stripe handles billing. The updater endpoint is already configured in
`tauri.conf.json`. What each of these may hold is bounded by §4a.

---

## 11. Build order

The eight weeks below are **done** and describe the shipped desktop app. The
work that follows them is the master plan:
`docs/superpowers/specs/2026-08-18-netrelish-master-plan-design.md` — twelve
projects, six phases. Read it before starting anything new.

Eight weeks. Each has a **demo** — the one thing you can show someone when
it's done. If the demo doesn't work, the week isn't finished.

Build in order. Later weeks read from schema decisions made in earlier ones.

### Week 1 — Shell ✅

**Demo:** a signed, notarized NetRelish.app opens a real page in a native pane.

- [x] Tauri v2 + Vite + React + TypeScript
- [x] macOS window: overlay titlebar, hidden title, 13.0 minimum
- [x] Hardened runtime entitlements (JIT, network client, user-selected files)
- [x] Native child WKWebView via `Window::add_child`
- [x] `ResizeObserver` → `preview_set_bounds` hole tracking
- [x] Shelf rail with superellipse tiles
- [x] CI: build → sign → notarize → staple → draft release

### Week 2 — Brine ✅

**Demo:** browse for ten minutes, then find any page you visited by typing a
phrase from its body text. Offline.

- [x] `tauri-plugin-sql` wired, database at the app support path
- [x] Migration `001_init.sql` — the full schema in §6
- [x] `src/lib/db.ts` — the only module that writes SQL
- [x] Content script injection on preview navigation
- [x] Readability extraction → `items`, `kind='page'`, `jar_id = NULL`
- [x] FTS5 triggers on insert, update **and** delete
- [x] User-editable deny list
- [x] Brine surface: reverse-chronological, title + domain + snippet
- [x] Click a Brine row → reopens in the preview pane

**Acceptance:** extraction under 50ms p95 · 1,000 items → FTS under 10ms ·
quit mid-navigation and relaunch with nothing corrupt · works fully offline
(verify by pulling the network — extraction, `⌘K` and Brine must all still
work).

### Week 3 — Jars ✅

**Demo:** create a jar, browse into it, `⌘J` a page from Brine into it, switch
jars and watch the window change.

- [x] Jar CRUD, hue assigned round-robin from `--nr-jar-1..6`
- [x] Shelf rail renders real jars with live counts
- [x] Active-jar state — new pages extract with that `jar_id`
- [x] `⌘J` on the current page
- [x] `⌘J` on a Brine multi-selection → jars as a **Batch**
- [x] Jar view: items grouped by kind, newest first
- [x] Move items between jars, and back to Brine
- [x] Jar chip in the titlebar reflects the active jar

**Acceptance:** jar switch under 100ms at 5,000 items · deleting a jar sends
its items to Brine and never deletes them · every action keyboard reachable.

### Week 4 — Ask the Pantry ✅

**Demo:** `⌘K`, type a half-remembered phrase, land on the exact page — with
the web fallback below it, not above.

- [x] `⌘K` palette, sibling of `.nr-stage`
- [x] Ranking: active jar → other jars → Brine → web
- [x] Results as you type, 80ms debounce
- [x] Filters: `jar:name`, `kind:page`, `is:sealed`, `since:7d`
- [x] Snippet highlighting via FTS5 `snippet()`
- [x] Enter opens; `⌘Enter` opens without closing the palette
- [x] Empty state explains the syntax rather than apologizing

**Acceptance:** first keystroke to first result under 50ms at 10,000 items ·
web results never outrank a local match · Escape never loses typed input.

### Week 5 — Sealing ✅

**Demo:** leave tabs open for three days. They preserve themselves and close.
Reopen one from its jar exactly as it was.

- [x] `tabs` table tracking `touched_at` and `seal_after`
- [x] Per-jar shelf life, default 3 days; pinned tabs never seal
- [x] Background sweep on launch and hourly
- [x] Seal = ensure extracted → set `sealed_at` → close tab
- [x] Reopen restores URL and scroll position
- [x] **Batch** view of one sweep, undoable for 24h
- [x] Toast: "Sealed 12 tabs into Meridian Rebuild" → Undo

**Acceptance:** no tab ever closes before its content is in `items` · Undo
restores the whole batch, open, in order · sweeping 200 tabs never freezes
the UI.

This is the feature that gets screenshotted. Make the animation good and make
Undo genuinely reliable.

### Week 6 — The engine ✅

**Demo:** open a jar. It says *"9 things in Brine look like they belong here."*
It's right about most of them.

- [x] ONNX embedding model bundled, `ort` crate, Apple Silicon
- [x] `sqlite-vec` loaded
- [x] Embed on extraction; backfill existing items in the background
- [x] Session detection — time window + referrer chains
- [x] Entity extraction — domains, `[A-Z]{2,6}-\d+`, repo paths
- [x] Suggestion strip in the jar header, one key to accept all
- [x] Rejections weighted into future scoring
- [x] Semantic results merged into `⌘K` behind exact matches

**Acceptance:** under 200ms per item, off the UI thread · backfill resumable
across quits · suggestions never applied without approval · model adds no more
than ~120MB to the bundle.

### Week 7 — Recipes ✅

**Demo:** run a saved recipe. Four tabs open in the right layout, it walks you
through three steps, output lands back in the jar.

- [x] `recipes` table, JSON steps
- [x] Recorder — work normally, "Save as Recipe", steps reconstructed
- [x] Step kinds: `open`, `split`, `task`, `note`, `collect`, `seal`
- [x] Runner UI — current step, skip, back, finish
- [x] `{{date}}`, `{{jar}}`, `{{url}}` interpolation
- [x] `⌘R` runs a recipe in the active jar
- [x] Split layout with synced scroll

**Acceptance:** a recorded recipe replays to the same end state · cancelling
mid-run leaves no orphan tabs or half-written items · recipe JSON is readable
and hand-editable.

### Week 8 — Notes, tasks, ship ✅

**Demo:** a jar holding tabs, notes, tasks and files, all searchable together,
on a machine that has never been online.

- [x] In-jar markdown notes, `kind='note'`
- [x] Tasks with due dates, `kind='task'`
- [x] Drag a local file into a jar → `kind='file'`, path watched
- [x] Labels: create, assign, filter
- [x] Full keyboard map + shortcut sheet
- [x] Light theme parity pass
- [x] Updater wired (keys generated, pipeline ready; enrolment done and
      CI signing proven Aug 2026 — but notarization still fails 401 on an
      invalid `APPLE_PASSWORD`, see docs/RELEASING.md)

---

## 12. Not in v1

Each is a week or more, none is on the critical path.

| | Why not now |
| :-- | :-- |
| Email (`kind='message'`) | Schema already supports it. Gmail API needs Google's security review — money and a month of calendar time. Start with IMAP, after the cloud track lands. |
| iOS | App Store only, and Guideline 2.5.6 forces WKWebView. Ship a PWA companion after the web app lands. |
| Extensions *for* NetRelish | Enormous surface area. Probably never. (NetRelish's own capture extension is P3 and is a different thing.) |
| Windows / Linux | Different webview, different signing, different bugs. Not until Mac is loved. |

**Moved out of this section on 2026-08-18** — cloud sync (P4), sharing and
teams (P7, P10), and billing (P6) are now scheduled work in the master plan,
not deferred ideas.

The business layer — positioning, target markets, pricing, and the
future feature list — lives in `docs/ROADMAP.md`, which translates
Ryan's working business plan into this file's vocabulary and
architecture. Where they conflict, this file wins.

The plan itself is **not in this repo** and never should be: it was
purged from history when the repo went public (Aug 2026). It lives at
`/Volumes/WORK/New Projects/NetRelish/business-plan.md`, beside the
brand assets.

---

## 13. Warnings

- **Apple Developer enrolment blocks everything.** $99/yr, 24–48h approval,
  and every signing step waits on it. *(Done Aug 2026 — Team ID
  `D9QDJ44773`. Kept here because it gates any fresh machine or account.)*
- **Back up the updater private key.** Lose it and you can never push an
  update to an installed copy. There is no recovery path. *(Verified
  Aug 2026: retrievable copies in iCloud Drive → NetRelish and
  `~/.tauri/`, plus a write-only GitHub secret for CI.)*
- **Week 2's schema is load-bearing.** Weeks 3–8 all read from `items`.
  Changing `kind` or the FTS setup later means migrating real user data.
- **Never seal before extracting.** A sealed tab whose content didn't reach
  `items` is exactly the data loss this product exists to prevent.
- **Never point a test build at the real identifier.** Migrations are one-way
  and shared by every build on the machine. On 2026-08-19 a release test
  build applied a new migration to the installed app's database; the
  installed app knew nothing of that migration and then aborted in sqlx on
  every launch — a crash dialog, not a degraded feature. `npm run app:test`
  exists for this and costs nothing.
- **Don't render overlays inside `.nr-stage`.** The native webview covers it.

---

## 14. Commands

```bash
npm install         # once, at the root — installs every workspace
npm run app         # dev, hot reload, devtools
npm run app:build   # local release build — WRITES THE REAL PANTRY
npm run app:test    # isolated build: own identifier, own database
npm run typecheck   # types, all workspaces
npm test            # vitest unit tests, all workspaces
cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml
npm run tauri -w @netrelish/desktop icon <1024px.png>   # regenerate icons
```

Requires Rust stable, Xcode Command Line Tools, Node 20+.

**`npm test` and `npm run app:test` are unrelated.** The first runs vitest; the
second builds an isolated Tauri app. Nothing above builds or launches the app
as a side effect of running tests.

Unit tests are deliberately narrow: `src/lib/auth.test.ts` pins the §4a tier
decisions — which keyring call each path makes, and therefore whether a note
can leave this Mac readable. That is the one piece of logic worth holding
without a running app. Do not grow this into a UI test suite; the demos in §11
are what prove a surface works.

**Never test a migration with `app:build`.** It carries the real identifier,
so it opens the real Pantry — and migrations are one-way and shared. Use
`app:test`, which builds "NetRelish Test" under `com.netrelish.app.test`
and gets its own Application Support directory.

See `docs/notarization.md` before touching anything in `apps/desktop/src-tauri/`.

---

*Code MIT. Brand — name, wordmark, vocabulary — all rights reserved.*
