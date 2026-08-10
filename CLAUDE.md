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

1. **Everything is local.** SQLite on disk. No network calls except page
   loads, the updater check, and (later) a license check. No telemetry, no
   analytics, no account.

   This is an engineering constraint, not a marketing position. Local is why
   `⌘K` returns in under 50ms, and cutting sync is why this ships in eight
   weeks instead of five months. Privacy is a consequence — a good line for
   the website, but not the reason it's in the architecture.

2. **Suggest, never file silently.** The organization engine proposes; the
   user approves with one key. Auto-filing that's wrong 15% of the time
   destroys trust in the jar, and an untrusted knowledge base is dead weight.

3. **Closing is free.** Any action that removes something from view must
   preserve it first. Nothing is ever lost by tidying. This is the whole
   promise — violating it once loses the user permanently.

4. **The preview is a native child webview, not an iframe.** See §5.

5. **No cloud in v1.** Not Supabase, not anything. If a task seems to need a
   server, an account, or a network call, stop and say so. It's out of scope
   by design, not by oversight.

---

## 5. Architecture

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

Four layers, all on-device:

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
| **GitHub Releases** | Week 8 | Binaries + signed updater manifest. Free. |
| **Vercel** | Week 8+ | netrelish.com, download page. Updater endpoint moves here when you want nicer URLs. |
| **Supabase** | When billing starts | License keys, Stripe webhooks. A table with four columns. |
| **Supabase (E2E sync)** | Post-launch, if asked for | Encrypted blobs the server can't read. Optional, paid, never default. |

None of this is on the critical path, and none of it touches browsing data.
The updater endpoint is already configured in `tauri.conf.json`.

---

## 11. Build order

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
quit mid-navigation and relaunch with nothing corrupt · nothing leaves the
machine (verify with `lsof -i` or Little Snitch).

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
- [x] Updater wired (keys generated, pipeline ready — public build waits
      on Apple Developer enrolment, see docs/RELEASING.md)

---

## 12. Not in v1

Each is a week or more, none is on the critical path.

| | Why not now |
| :-- | :-- |
| Email (`kind='message'`) | Schema already supports it. Gmail API needs Google's security review — money and a month of calendar time. Start with IMAP, after launch. |
| Cloud sync | Needs accounts and a server. Do it encrypted-on-device or not at all. |
| iOS | App Store only, and Guideline 2.5.6 forces WKWebView. Ship a PWA companion after Mac lands. |
| Sharing / teams | A different product. Revisit at 1,000 users. |
| Billing | Free during beta. Gate once there's something worth paying for. |
| Extensions | Enormous surface area. Probably never. |
| Windows / Linux | Different webview, different signing, different bugs. Not until Mac is loved. |

---

## 13. Warnings

- **Apple Developer enrolment blocks everything.** $99/yr, 24–48h approval,
  and every signing step waits on it.
- **Back up the updater private key.** Lose it and you can never push an
  update to an installed copy. There is no recovery path.
- **Week 2's schema is load-bearing.** Weeks 3–8 all read from `items`.
  Changing `kind` or the FTS setup later means migrating real user data.
- **Never seal before extracting.** A sealed tab whose content didn't reach
  `items` is exactly the data loss this product exists to prevent.
- **Don't render overlays inside `.nr-stage`.** The native webview covers it.

---

## 14. Commands

```bash
npm run app         # dev, hot reload, devtools
npm run app:build   # local release build
npm run typecheck   # frontend types
cargo check --manifest-path src-tauri/Cargo.toml
npm run tauri icon <1024px.png>   # regenerate the app icon set
```

Requires Rust stable, Xcode Command Line Tools, Node 20+.

See `docs/notarization.md` before touching anything in `src-tauri/`.

---

*Code MIT. Brand — name, wordmark, vocabulary — all rights reserved.*
