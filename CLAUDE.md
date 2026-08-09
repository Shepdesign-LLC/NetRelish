# NetRelish

A downloadable macOS browser that is also a workstation. Not a browser with
notes bolted on — a browser where everything you touch is already organized.

Distributed as a direct download with a Developer ID signature. **Not on the
App Store.** No account, no server, no sync. Everything lives on the user's
machine.

---

## What it is, in one paragraph

Chrome gives you tab groups: a coloured rectangle that holds tabs and forgets
everything else. NetRelish gives you **Jars** — a project that holds tabs,
notes, tasks, files and messages together, knows what its subject is, and can
be **run** as a **Recipe**. Everything you browse is preserved into **Brine**
automatically, full-text searchable offline, forever. Closing a tab stops
meaning losing it.

---

## Vocabulary — use these words in code, UI and commits

| Word | Meaning | Notes |
| :-- | :-- | :-- |
| **Pantry** | Everything the user has. The home surface. | |
| **Jar** | A project. Holds items of every kind. | The core object. |
| **Jar it** | Verb. `⌘J` on a page, selection, file or message. | The primary gesture. |
| **Recipe** | A runnable workflow attached to a jar. | Recorded, not authored. |
| **Brine** | Everything browsed but not yet sorted. | Preserved, unlabeled. |
| **Seal** | Preserve an untouched tab into its jar and close it. | Never say "archive" or "compost". |
| **Label** | A tag on a jar or item. | |
| **Batch** | Everything jarred in one session. | |

Rules:

- Brand words appear in **UI copy, docs and product surfaces**.
- Database tables and internal types stay boring: `items`, `tabs`, `sources`,
  `jars`. `Jar` is a real domain object so it keeps its name. Nothing else
  gets cute.
- Never invent new brand words. If a concept needs one, ask.
- Never use: workspace, collection, board, space, vault, knowledge graph,
  smart folder, compost, larder.

---

## Tone

Dry, precise, fast. The personality lives in the *system* being coherent, not
in jokes. The vocabulary does the work.

- Errors say what broke and how to fix it. They never wink.
- Empty states are invitations to act, and they're the one place a little
  warmth is allowed.
- Active voice, sentence case, no filler. A button that says **Seal** produces
  a toast that says **Sealed**.
- Never write a clever line on the critical path. Funny once, irritating on
  the fortieth read.

---

## Non-negotiables

1. **Local only.** No network calls except page loads, the updater, and
   entitlement checks. No telemetry. No analytics. Software that sees every
   page you visit does not phone home. This is the product's spine, not a
   preference.
2. **Suggest, never file silently.** The organization engine proposes; the
   user approves with one key. Auto-filing that's wrong 15% of the time
   destroys trust in the jar, and an untrusted knowledge base is dead weight.
3. **Closing is free.** Any action that removes something from view must
   preserve it first. Nothing is ever lost by tidying.
4. **The preview is a native child webview**, not an iframe. See below.
5. **No cloud in v1.** Not Supabase, not anything. If a feature needs a
   server, it isn't v1.

---

## Architecture

```
NetRelish.app
├── Chrome UI            React 18 + Vite + TypeScript, ships in the bundle
│   ├── Shelf rail       Brine + jars, superellipse tiles
│   ├── Titlebar         jar chip + omnibox (⌘K)
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

Consequence: nothing rendered inside `.nr-stage` is visible once a page loads.
Overlays must be siblings, not children.

### Storage

SQLite via `tauri-plugin-sql`, plus FTS5 and `sqlite-vec`. One database at
`~/Library/Application Support/com.netrelish.app/netrelish.db`.

**The schema decision everything depends on:** one `items` table with a `kind`
discriminator. Pages, notes, tasks, files and messages are the same row shape.
One index, one search, one suggestion engine. Email is not a separate feature
built later — it is `kind = 'message'` in a table that already exists.

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
  id     TEXT PRIMARY KEY,
  name   TEXT NOT NULL UNIQUE
);

CREATE TABLE item_labels (
  item_id   TEXT REFERENCES items(id) ON DELETE CASCADE,
  label_id  TEXT REFERENCES labels(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, label_id)
);

CREATE TABLE recipes (
  id       TEXT PRIMARY KEY,
  jar_id   TEXT NOT NULL REFERENCES jars(id) ON DELETE CASCADE,
  name     TEXT NOT NULL,
  steps    TEXT NOT NULL              -- JSON array
);

CREATE TABLE embeddings (              -- week 6
  item_id  TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
  vector   BLOB NOT NULL
);
```

Migrations live in `src-tauri/migrations/NNN_name.sql`, applied in order at
startup, never edited once shipped.

### Extraction

On every page load in the preview webview:

1. Inject a content script, run Readability, return title + text + byline.
2. Insert into `items` with `kind='page'`, `jar_id = active jar or NULL`.
3. Update `items_fts`.

Target: under 50ms, never blocking the paint. Skip URLs matching a
user-editable deny list. Never extract from private windows.

### The organization engine (week 6)

Four layers, all on-device:

1. **Sessions** — pages within a time window with referrer chains between them
   are one working session. Cheap, catches most cases.
2. **Semantics** — extracted text → local ONNX embedding model (~100MB, `ort`
   crate, Apple Silicon) → `sqlite-vec`.
3. **Entities** — domains, repo names, ticket IDs (`[A-Z]{2,6}-\d+`), client
   names pulled from text.
4. **Correction** — when the user moves an item out of a jar, weight it. The
   engine learns *their* boundaries.

Output is always a suggestion: *"6 things in Brine look like they belong
here"*, approved with one key.

---

## Code conventions

**TypeScript**

- Strict mode. No `any`. No non-null assertions outside `main.tsx`.
- Components are function components with a typed `Props` interface above them.
- No state library. `useState` and context until something actually hurts.
- Data access goes through `src/lib/db.ts` — components never write SQL.

**Rust**

- Commands live in `src-tauri/src/commands/<domain>.rs`, one domain per file.
- Every command returns `crate::error::Result<T>`. Never `unwrap()` in a
  command path.
- Anything touching the filesystem validates containment before writing.

**CSS**

- Plain CSS with custom properties. No Tailwind, no CSS-in-JS.
- All colour is OKLCH. Never hex, never `rgb()`.
- All tokens are `--nr-` prefixed and live in `src/styles/netrelish.css`.
- App chrome is deliberately quiet: no gradients, no glass, no accent colour
  outside the shelf rail. The frame surrounds someone else's content all day.
- The one signature move is the **superellipse** tile shape
  (`src/lib/superellipse.ts`). Not `border-radius`. Don't replace it.

**Commits**

Conventional commits, scoped: `feat(jars):`, `fix(preview):`, `chore(db):`.

---

## Quality floor

Every shipped surface: keyboard reachable, visible focus ring,
`prefers-reduced-motion` respected, works at 880px wide, works in light and
dark.

---

## Commands

```bash
npm run app         # dev, hot reload, devtools open
npm run app:build   # local release build
npm run typecheck   # frontend types
cargo check --manifest-path src-tauri/Cargo.toml
```

Requires Rust stable, Xcode Command Line Tools, Node 20+.

---

## Before you build

- Read `docs/ROADMAP.md`. Build the current week only. Do not skip ahead —
  later weeks depend on schema decisions made in earlier ones.
- Read `docs/notarization.md` before touching anything in `src-tauri/`.
- If a task seems to need a server, an account, or a network call, stop and
  say so. It's out of scope by design, not by oversight.
