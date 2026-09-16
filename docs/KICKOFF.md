# NetRelish — Claude Code Kickoff (P0 → P1)

One prompt per session. Paste each block verbatim. Each ends with something Ryan can see by launching the app.

## Before prompt 0 — put the files in the repo
Claude Code can't fetch these. Drop them in first:
```
CLAUDE.md                      (repo root — replaces the existing one)
/design/DESIGN_MANIFEST.md
/design/tokens.css
/design/symbols.svg            (if missing, prompt 0 creates it from the manifest §7)
/design/logo.svg
/design/logo-cog.svg
/design/NetRelish.json         (System Designer export or GitHub sync)
/docs/NetRelish_Plan_and_Roadmap.md   (if recovered; otherwise prompt 0 stubs it)
```

---

## 0 · Design system bridge (run this first, before any feature work)
> Read `CLAUDE.md`, `/design/DESIGN_MANIFEST.md`, `/design/tokens.css`, and `/design/symbols.svg` (if `symbols.svg` is missing, author it from manifest §7: `#nr-jar`, `#nr-jar-smart`, `#nr-jar-pickle`, `#nr-seal`, `#nr-lip`, `#nr-drip`, `#nr-sink` as `<symbol>` elements using `currentColor`, hairline-weight, 24×24 viewBox). Before any feature work, build the design system as Swift:
> - `Sources/UI/Tokens.swift` — a code generator script at `/scripts/gen-tokens.swift` reads `tokens.css` and emits `NRColor`, `NRSpace`, `NRRadius`, `NRType`, `NRMotion` enums. OKLCH → Display P3 `Color` with light + dark via a dynamic `NSColor`. Every custom property maps to exactly one static. Run it; commit the output; add a CI step that fails if regenerated output differs from the committed file.
> - `Sources/UI/Shapes.swift` — `Superellipse(n: 5)` as a reusable `Shape`; `JarShape` with superellipse shoulders per manifest §6.
> - `Sources/UI/Symbols.swift` — loads each `symbols.svg` symbol and both logos as template `Image`s.
> - A DEBUG-only `DesignKit` window (Window menu → Design Kit) rendering every token, symbol, and every component state from manifest §8 side by side, light/dark toggle, Reduce Motion toggle, plus a live Seal animation trigger.
> Do not touch `logo.svg` or `logo-cog.svg`. Do not invent tokens not in `tokens.css`. If `/docs/NetRelish_Plan_and_Roadmap.md` is missing, stub it with §5 performance budgets left as TODO for Ryan. Open PR `design-system: swift token bridge`. Demo: Window → Design Kit shows the palette, the mark, the cog, a jar, the tab lip, and the drip.

## 1 · Retire the old stack
> Read `CLAUDE.md`. It replaces every prior decision. Remove the Tauri, React, Vite, and Rust code from the repo — move it to a `legacy/` branch, not a folder. Delete `package.json`, `src-tauri/`, `src/`, `vite.config.*`. Keep `/design`, `/docs`, `.github`, `README.md`. Rewrite `README.md` in one screen: what NetRelish is, the stack table from `CLAUDE.md`, how to build, link to the plan. Open a PR titled `p0: retire tauri` with a Rule check section. No new code in this PR.

*(If the repo is already Swift-only, skip 1 and say so in the PR for 2.)*

## 2 · Scaffold the Mac app
> Create an Xcode project `NetRelish.xcodeproj` at the repo root: macOS 27 target, Swift 6 strict concurrency, SwiftUI app lifecycle, App Sandbox on, Hardened Runtime on, bundle id `com.shepdesign.netrelish`. Two configurations: `AppStore` and `Direct` (defines `DIRECT_BUILD`). Add SwiftPM dependencies: GRDB.swift, KeyboardShortcuts. Add a `Pantry` target (library) and `NetRelish` target (app). Set the app icon from `/design/logo.svg` at all required sizes via `iconutil`. Create `Config.xcconfig.example` and gitignore `Config.xcconfig`. Add a GitHub Actions workflow that builds both configurations on macOS 27 runners and runs tests. Fold the prompt-0 `Sources/UI` into the app target. Open PR `p0: scaffold`. Demo: the app launches to an empty window with the icon in the Dock and Window → Design Kit works.

## 3 · Generate the Pantry from MSON
> Read `/design/NetRelish.json`. Using the Schema → Swift mapping in `CLAUDE.md`, generate `Sources/Pantry/Models/*.swift` — one file per schema (`Item`, `Jar`, `Recipe`, `Step`, `Label`, `Batch`, `Pickle`, `NetRelish`) as GRDB `Codable` records, plus `Sources/Pantry/Migrations/V1.swift` creating the tables with FTS5 on `items(title, excerpt, body)` and the indexes listed in the schema. `Pickle` is table-per-hierarchy on `jars` with a `kind` column. Method bodies mirror the JavaScript behaviors in the bundle. Events are `AsyncStream`s. Write tests: create an Item, seal it, assert `sealedAt` set and FTS finds a body phrase. Add `Sources/Pantry/Intents/SealIntent.swift` and `CaptureIntent.swift` as App Intents that call the same methods. Open PR `p0: pantry from mson`. Demo: run the Shortcuts app, find "Capture in NetRelish", run it with a URL, then launch NetRelish and see the Item count in the window title.

## 4 · Confirm P0 done
> Verify the schema round-trips MSON → Swift → SQLite with zero hand edits, and tokens round-trip `tokens.css` → `Tokens.swift` the same way. Change one property in `/design/NetRelish.json` and one value in `/design/tokens.css`, regenerate both, and show the diff is confined to generated files. Post the diff in the PR. If any hand edit was required, stop and list them for Ryan.

## 5 · Start P1 — the Shelf
> Build the Shelf per manifest §8: a `NRSpace.shelfW` rail on the leading edge listing Jars from the Pantry, `#nr-jar` per row, ⌘1–9 to switch, `NRColor.relish100` tint on the active jar, a New Jar button at the bottom. Each Jar owns a `WKWebsiteDataStore` keyed by its id (non-negotiable 6). Bench is a single `WKWebView` for now, bound to the active jar's data store. Open PR `p1: shelf`. Demo: create two jars, log into GitHub in one, switch to the other, confirm it's logged out.

## 6 · P1 — Tabs, lip, and Brine
> Add tabs to the Bench per manifest §8: `NRSpace.tabH`, active tab carries `#nr-lip` in `NRColor.relish500` (the only tab with any relish). Pinned tabs never sink. Implement shelf life on `Jar` and the sink timer: an idle tab past its jar's shelf life moves to Brine (`jar == nil && state == .brined`, non-negotiable 2) preserving scroll position, form state, and history via `WKWebView.interactionState`. Add a Brine smart jar at the bottom of the Shelf. Open PR `p1: tabs and brine`. Demo: set a jar's shelf life to 60s, open three tabs, pin one, wait, watch two sink and the pinned one stay; open Brine and restore one with scroll intact.

---

## After each session
Ryan runs the demo. Pass → merge. Fail → paste the failure back with **"fix and re-demo."** Never fix by hand.

## Rhythm
One prompt, one PR, one demo. P0 is five PRs (0–4). P1 is roughly six. P1 closes Oct 2; v1.0 ships to the App Store Dec 14.

## Parity features already slotted (from the Sept 15 competitive review)
| Feature | Phase |
|---|---|
| Jars are profiles | P1 (prompt 5) |
| Smart jars (Unsorted · Today · Sealed · Sinking soon), ⌘⇧1–4 | P2 |
| Kind detection at capture (URL/MIME → `Item.kind` + meta) | P2 |
| Reader view (Defuddle body, ⌘⇧R) | P2 |
| Content blocker (`WKContentRuleList`, EasyList, per-jar toggle) | P2 |
| Notebook — `Highlight` schema, inline notes | 1.1 |
| Pickle — local WP dev jar, OrbStack/Docker, GitHub OAuth | 1.2, direct build only |
