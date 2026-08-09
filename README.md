# NetRelish

The browser for people who build the web.

A native macOS browser with the NetRelish Pantry — Mise, Zest, Scale — running
as first-class panels, and a filesystem bridge that writes generated tokens,
`theme.json` and ACF PHP straight into the open project. No clipboard.

**Status:** week 1 — shell, native preview pane, bridge seam, signed release
pipeline. Not yet a usable browser.

---

## Quickstart

```bash
npm install
npm run app          # tauri dev
```

Requires Rust (`rustup`), Xcode Command Line Tools, and Node 20+.

| Command | Does |
| :-- | :-- |
| `npm run app` | Dev build with hot reload and devtools |
| `npm run app:build` | Local release build (unsigned unless env vars are set) |
| `npm run typecheck` | Frontend types only |

---

## Architecture

```
NetRelish.app
├── Chrome UI          React + Vite, ships inside the bundle
│   ├── Pantry rail    Mise · Zest · Scale, superellipse tiles
│   ├── Tool panels    iframes over the existing embed protocol
│   └── Stage          an empty div; a hole for the native pane
├── Rust core          project state, disk writes, webview positioning
└── Preview webview    a real child WKWebView, not an iframe
```

Two things here are load-bearing and easy to get wrong:

**The preview is a native child webview.** `Window::add_child`, gated behind
tauri's `unstable` feature. Iframes cannot render the web — most sites refuse
to load in one. React draws a hole, a `ResizeObserver` measures it, Rust puts
the webview over it.

**Disk writes go through one command.** `write_project_files` enforces
containment inside the project root, backs up anything it overwrites into
`.nr-backup/`, and writes atomically via temp-file-and-rename. The frontend
must show a diff and get confirmation before calling it — the command does not
prompt.

### The bridge

The Pantry tools speak the same postMessage protocol as the web build, plus
one desktop-only message:

```js
// from inside Zest / Mise / Scale
parent.postMessage({
  type: "nr:export",
  tool: "zest",
  files: [{ path: "theme/assets/css/_tokens.css", contents: css }],
}, "*");
```

The shell replies `nr:export:ack` with a write report, or `nr:export:nack`
with a reason. Web builds simply never receive a reply and fall back to
copy-to-clipboard, so a single build serves both hosts.

Only origins listed in `TOOL_ORIGINS` are honoured. Without that check any
page loaded in a panel could write to the user's project.

---

## Roadmap

- [x] **1** — Shell, notarized pipeline, preview pane, bridge seam
- [ ] **2** — Project model, SQLite persistence, project switcher
- [ ] **3** — Tool panes against live Mise / Zest / Scale
- [ ] **4** — Export bridge with real diff sheet
- [ ] **5** — Navigation: back/forward, loading state, error pages
- [ ] **6** — Entitlement check against `nr_pantry_access`
- [ ] **7** — Updater, crash-safe state, shortcuts
- [ ] **8** — Buffer

Deliberately **not** in v1: tabs, bookmarks, history, downloads, Supabase,
clipping, team sync.

---

## Docs

- [`docs/notarization.md`](docs/notarization.md) — certificates, secrets,
  verification, and the failure modes worth knowing in advance

---

## Licence

Code MIT. Brand — name, wordmark, Pantry identity — all rights reserved.
