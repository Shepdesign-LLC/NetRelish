# NetRelish

> **Savor the web. Get more done.**

A downloadable macOS browser that is also a workstation.

Chrome gives you tab groups — a coloured rectangle that holds tabs and forgets
everything else. NetRelish gives you **Jars**: a project that holds tabs,
notes, tasks, files and messages together, knows what its subject is, and can
be run as a **Recipe**.

Everything you browse is preserved into **Brine** automatically — extracted,
full-text searchable, offline, forever. Closing a tab stops meaning losing it.

Everything lives on your machine — no account, no server, no sync.

Direct download, Developer ID signed and notarized. Not on the App Store.

---

## Status

Week 1 of 8. The shell runs and renders pages in a native WKWebView. It is not
yet a browser you'd use.

See the build order in [`CLAUDE.md`](CLAUDE.md#11-build-order).

---

## Quickstart

```bash
npm install
npm run app
```

Requires Rust stable, Xcode Command Line Tools, Node 20+.

| Command | Does |
| :-- | :-- |
| `npm run app` | Dev build, hot reload, devtools |
| `npm run app:build` | Local release build |
| `npm run typecheck` | Frontend types |

---

## Working on this

Read [`CLAUDE.md`](CLAUDE.md) first. It's the whole spec — vocabulary,
architecture, schema, conventions, the eight-week build order, and the five
things that are non-negotiable.

Two that catch people out:

**The preview pane is not in the DOM.** It's a real child WKWebView positioned
over a hole in the layout. Iframes cannot render the web — most sites refuse
to load in one. Overlays must be siblings of `.nr-stage`, never children.

**One `items` table, discriminated by `kind`.** Pages, notes, tasks, files and
messages share a row shape, an index and a search. Email is not a future
feature — it's `kind = 'message'` in a table that already exists.

---

## Docs

| | |
| :-- | :-- |
| [`CLAUDE.md`](CLAUDE.md) | The spec. Read before writing code. |
| [`docs/notarization.md`](docs/notarization.md) | Certificates, secrets, verification, failure modes. |

---

## Licence

Code MIT. Brand — name, wordmark, vocabulary — all rights reserved.
