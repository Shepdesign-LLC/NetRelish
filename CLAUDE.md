# CLAUDE.md — NetRelish

Native macOS browser with a pantry. Swift. Mac App Store. This file is the contract. If a task conflicts with it, stop and ask Ryan.

## Who you're working with
- **Ryan** designs, decides, and runs demos. He works from chat and the built app, not a terminal. Every PR you open must include a demo he can run by launching the app — if it can't be demoed, it isn't done.
- **You** implement, test, and open PRs. Never ask Ryan to run commands, edit files by hand, or read a stack trace. If something fails, fix it and re-demo.
- **System Designer** (designfirst.io) is the design of record for the data model. The MSON bundle lives at `/design/NetRelish.json`. Model changes start there; you regenerate Swift from it, never the reverse.
- **`/design/DESIGN_MANIFEST.md` + `/design/tokens.css`** are the design of record for everything visual. Read them before touching any UI.

## Non-negotiables
1. **One `Item` table.** `kind` is the discriminator (`page · note · task · file · message`). Never per-kind tables or models.
2. **Brine is a query, not a place.** `jar == nil && state == .brined`.
3. **Seal is an action, not a place.** It stamps `sealedAt`, freezes the `.webarchive`, closes the tab, fires `onSeal`, and runs the jar's default Recipe. Nothing else mutates a sealed snapshot.
4. **Intelligence reads sealed snapshots only.** No Foundation Models, MLX, or any model call ever receives a live `WKWebView`, its DOM, or a logged-in session. There is no agent in the browser.
5. **Browsing data never leaves the device.** The only network calls are: page loads, StoreKit, RFC 3161 timestamping (Pro provenance), and a one-time license activation for the direct build. Add an endpoint and you've broken this rule.
6. **Every jar is a profile.** One `WKWebsiteDataStore` per jar. Cookies and sessions never cross jars.
7. **Every Recipe is an App Intent.** If it can't appear in Shortcuts, it isn't a Recipe.
8. **Open-core.** Code is MIT. `logo.svg`, `logo-cog.svg`, the name, and the App Store listing are all rights reserved and excluded from the license.

## Stack (locked)
| Layer | Choice |
|---|---|
| Language / UI | Swift 6, SwiftUI, AppKit where SwiftUI can't |
| OS floor | macOS 27 |
| Web engine | WKWebView only. No Chromium. |
| Storage | GRDB.swift over SQLite. FTS5 for text, sqlite-vec for embeddings. Migrations in `Sources/Pantry/Migrations/`. |
| Intelligence | Foundation Models first. MLX Swift behind an opt-in flag. |
| Extraction | Defuddle (MIT) injected at capture for `body`. Never SingleFile (AGPL). |
| Distribution | Mac App Store (primary) + Developer ID (`Pickle` and direct license). One codebase, `#if DIRECT_BUILD`. |
| Billing | StoreKit 2 in App Store build. Paddle or Lemon Squeezy (merchant of record) in direct build. |
| Site | Separate repo `netrelish-site`, Astro static, plain CSS from `tokens.css`. |

## Brand (locked — Brand Lock v1.1, full rules in `/design/DESIGN_MANIFEST.md`)
- `logo.svg` (app icon, titlebar) and `logo-cog.svg` (site, About window, onboarding). Never redrawn, recolored, or cropped.
- Neutral base, system type, hairlines. The product is the hero; the brand is carried by the mark and the objects, not by color washes.
- Relish (`--relish-500`, `#93E413`) is the single accent and appears **only** in the exhaustive placement list in the manifest. Anywhere else is a bug.
- Jar icons (`#nr-jar`) wherever a jar is meant. System line icons (SF Symbols) for everything else. No emoji in UI.
- One drip in the app: the Seal animation. Nowhere else.
- Never: dark-green glass surfaces, gradient text in the product, relish as a background, cheesy pantry puns in headlines.

## Vocabulary (use these words in code, UI, and commits)
Pantry · Jar (project, has a shelf life; also a profile) · Brine (where idle tabs sink; pinned never sink) · Sunk · Seal · Recipe (recorded, replayed with ⌘R; each is an App Intent) · Shelf (the jar rail) · Bench (the web panes) · Inspector · Ask the Pantry · Pickle (a jar with a local dev environment; direct build only).

## Schema → Swift mapping (when regenerating from MSON)
| MSON | Swift |
|---|---|
| `property` `string / number / boolean / date / object` | `String / Double / Bool / Date / Data` (JSON) |
| enum type | `enum Name: String, Codable, CaseIterable` |
| `link` | optional relationship (`var jar: Jar?` via foreign key) |
| `collection` `["T"]` | `[T]` via join or FK, with inverse |
| `method` | `func` on the record; body mirrors the JS behavior in the bundle |
| `event` | `AsyncStream<T>` on the record + `NotificationCenter` name |
| `_inherit` | protocol conformance + shared columns; `Pickle: Jar` is table-per-hierarchy on `jars` with `kind` |

## Repo layout
```
/design/            NetRelish.json (MSON), DESIGN_MANIFEST.md, tokens.css, symbols.svg, logo.svg, logo-cog.svg
/docs/              Plan and roadmap, phase acceptance criteria, /adr/
/Sources/Pantry/    Models, Migrations, Store (GRDB), Intelligence, Intents
/Sources/Bench/     WKWebView hosting, tabs, profiles, capture, seal
/Sources/Shelf/     Jars, smart jars, tray
/Sources/UI/        SwiftUI views; Tokens.swift + Symbols.swift GENERATED from /design — never hand-edited
/Sources/Pickle/    DIRECT_BUILD only. OrbStack/Docker client, GitHub OAuth device flow
/Tests/
```

## How to work
- Branch per phase task: `p1/shelf-rail`, `p2/seal-webarchive`. Small PRs. Conventional commits.
- Every PR body has: **What**, **Demo** (steps in the built app), **Rule check** (which non-negotiables it touches), **Brand check** (which manifest sections it touches).
- Tests for Store and Intelligence are required. UI tests for capture → jar → seal.
- Never commit secrets. Timestamping and license endpoints come from `Config.xcconfig`, gitignored.
- Performance budgets are in `/docs/NetRelish_Plan_and_Roadmap.md` §5. Measure before you claim.
- When a decision isn't covered here, propose it in the PR as a one-line ADR under `/docs/adr/`. Don't silently pick.

## Roadmap anchors
- 12-week native roadmap → Mac App Store v1.0, launch target **Dec 14, 2026**. P1 closes Oct 2.
- Tiers: Free + Pro ($39/yr or $99 lifetime — "Buy once, use forever.").
- Deferred: iPhone Duo companion (post-1.0), Notebook/highlights (1.1), Pickle (1.2, direct build only).

## Retired (do not resurrect)
Tauri, React, Vite, Rust core, the Tauri IPC layer, "not App Store", the dark-green glass UI from the September design export, gradient text outside the site hero, SingleFile.
