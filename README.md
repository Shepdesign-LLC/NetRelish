# NetRelish

**Savor the web. Get more done.**

A native macOS browser with a pantry. Everything you browse can be kept in a
**Jar** (a project, and a profile), sorted by kind, sealed as a snapshot,
searched on-device, and replayed as a **Recipe**. Idle tabs sink into
**Brine**; pinned ones never do. Nothing you keep leaves your Mac.

Mac App Store first. Open-core: code is MIT; the mark and the name are not.

## Stack

| Layer | Choice |
|---|---|
| Language / UI | Swift 6, SwiftUI, AppKit where SwiftUI can't |
| OS floor | macOS 27 |
| Web engine | WKWebView only. No Chromium. |
| Storage | GRDB.swift over SQLite. FTS5 for text, sqlite-vec for embeddings. |
| Intelligence | Foundation Models first. MLX Swift behind an opt-in flag. |
| Extraction | Defuddle (MIT) injected at capture. Never SingleFile (AGPL). |
| Distribution | Mac App Store (primary) + Developer ID direct build. One codebase, `#if DIRECT_BUILD`. |
| Billing | StoreKit 2 in the App Store build; Paddle or Lemon Squeezy in the direct build. |
| Site | Separate repo `netrelish-site`, Astro static, plain CSS from `tokens.css`. |

The contract is [`CLAUDE.md`](CLAUDE.md). The design of record is
[`design/DESIGN_MANIFEST.md`](design/DESIGN_MANIFEST.md) and
[`design/tokens.css`](design/tokens.css).

## Build

Requires Xcode 27 on macOS 27. Open `NetRelish.xcodeproj` and run the
*NetRelish (App Store)* scheme, or from the command line:

```bash
open "$(scripts/build-app.sh)"
```

Two flavors — *App Store* (StoreKit) and *Direct* (Developer ID, defines
`DIRECT_BUILD`) — each in Debug and Release. Debug builds carry the Design Kit
under *Window → Design Kit*. Endpoints come from `Config.xcconfig` (gitignored;
copy `Config.xcconfig.example`).

Three things are generated and must never be hand-edited; CI fails on drift:

| File | Source | Regenerate |
|---|---|---|
| `Sources/UI/Tokens.swift` | `design/tokens.css` | `swift scripts/gen-tokens.swift design/tokens.css > Sources/UI/Tokens.swift` |
| `Sources/UI/Symbols.swift` | `design/symbols.svg` + logos | `swift scripts/gen-symbols.swift design/symbols.svg design/logo.svg design/logo-cog.svg > Sources/UI/Symbols.swift` |
| `NetRelish.xcodeproj` | `project.yml` | `scripts/gen-project.sh` (needs `brew install xcodegen`) |

The app icon is `Resources/AppIcon.icns`, rendered from `design/logo.svg` by
`scripts/gen-appicon.swift`.

## Plan

[`docs/NetRelish_Plan_and_Roadmap.md`](docs/NetRelish_Plan_and_Roadmap.md) —
twelve weeks to App Store v1.0, launch target December 14, 2026. The session
sequence is [`docs/KICKOFF.md`](docs/KICKOFF.md). Decisions not covered by
`CLAUDE.md` live in [`docs/adr/`](docs/adr/).

The previous Tauri/React/Rust codebase is preserved on the
[`legacy`](https://github.com/Shepdesign-LLC/NetRelish/tree/legacy) branch.
Older documents under `docs/` that describe it are history, not the plan.
