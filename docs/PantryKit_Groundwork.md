# PantryKit groundwork — the extraction map for Duo

**Date:** 2026-10-31 · companion to ADR 0009. What ships now: a root `Package.swift`
building `Sources/Pantry` as the `PantryKit` library (macOS 27 + iOS 17), a package test
target mirroring the store round-trip tests, and a CI job that builds, tests, and
cross-compiles the module for iOS on every PR and push to main (proven live on the first
unlocked run: three tests green on macOS, iOS compile clean). No source file changed; the Mac app and
its generated xcodeproj are untouched. This document is the audit that justified that
shape, and the map for the Duo PR that follows.

## The core is already clean

A file-by-file audit of `Sources/Pantry` (25 files), each verdict re-checked by an
adversarial second pass:

- **24 of 25 files compile for iOS as-is.** The module closes over Foundation, GRDB,
  CryptoKit and AppIntents. No AppKit symbol appears anywhere — no `NS*` UI type, no
  `NSWorkspace`, no `Process`, no `NSApplication`.
- **The one constraint:** `Store/JarProfile.swift` imports WebKit for
  `WKWebsiteDataStore(forIdentifier:)` / `.remove(forIdentifier:)` — both exist on iOS,
  but only at iOS 17+. The package declares `.iOS("17.0")`, so the file compiles ungated.
  The cleaner long-term cut is to move the `WKWebsiteDataStore` factory to Bench and keep
  only the pure `storeIdentifier` UUIDv5 mapping (frozen namespace
  `6B0F5C2A-9F3E-4F0E-8C3B-2A7D1E5F9C11`) in the kit — a Duo-PR decision.
- **Zero sibling coupling:** no file references App, Bench, Shelf, UI or Vault types.
  The seal/capture flows delegate outward by design (snapshot freeze and tab close live
  in Bench; `Workbench` injects closures).
- **GRDB usage is iOS-compatible throughout:** `DatabaseQueue`, `DatabaseMigrator`,
  records/associations, and the external-content FTS5 table (`items_fts`,
  porter+unicode61, synchronize triggers) queried with `FTS5Pattern` + `bm25`. Apple's
  system SQLite on iOS ships FTS5.
- **App Intents are cross-platform** (iOS 16+), so non-negotiable 7 — every Recipe is an
  App Intent — holds on both platforms.

## Contracts to keep stable across the extraction

- NotificationCenter names minted by `PantryEvent`: `NetRelish.Item.onSealed`,
  `NetRelish.Tab.onSunk`, `NetRelish.Jar.onItemDropped`, `NetRelish.Recipe.onRunFinished`,
  `NetRelish.Batch.onFinished`, `NetRelish.NetRelish.onCapture`,
  `NetRelish.NetRelish.onSeal`.
- `Sources/Pantry/Models` is **generated** from `design/NetRelish.json`
  (`swift scripts/gen-pantry.swift`); CI diffs it. Model changes start in System
  Designer, never in the Swift.
- `.webarchive` snapshots (`SnapshotStore`) are loadable by `WKWebView` on iOS — the
  format carries over.
- `Tests/PantryKitTests` mirrors three tests from `Tests/PantryTests` by hand — no CI
  diff enforces the lockstep (deliberately: three tests don't earn extraction tooling).
  When those tests change in `PantryTests`, change the copies too.

## Known work left for the Duo PR (deliberately not groundwork)

- `PantryStore.shared` hard-codes the `NetRelish` Application Support subdirectory and
  `fatalError`s on open failure; Duo likely wants an app-group container and softer
  failure. The `init(path:)` / `init(inMemory:)` initializers are already
  location-agnostic.
- Sync layer (roadmap: Automerge/iCloud) — nothing in the module presumes single-device
  beyond "the source of truth on this Mac" in comments.
- `sqlite-vec` and Foundation Models / MLX are named in the stack but referenced nowhere
  in `Sources/Pantry` yet; nothing to port, and the "intelligence reads sealed snapshots
  only" boundary (non-negotiable 4) is not yet encoded in this module.
- JarProfile factory split (above), if Duo wants an iOS floor below 17 — otherwise moot.

## How the rest of the app sits, for later

Only `Pantry` is a real module today; `project.yml` folds App/UI/Shelf/Bench/Vault into
the single app target, so those folders cross-reference freely without imports.

- **Bench** (mac web hosting): the single hard Pantry call in the core is
  `JarProfile.dataStore(for:)` in `WebView.swift` (non-negotiable 6). Seal/capture data
  flows out through injected closures — the boundary survives extraction.
- **Shelf**: platform-clean in itself but leans on UI tokens and Vault/App types; not
  liftable as-is.
- **UI**: self-contained; core needs only mechanical `NSColor`→`UIColor` guards except
  `Symbols.swift`, whose `NSImage(data:)` SVG decode has no `UIImage` equivalent on
  iOS — the symbol pipeline is the real UI porting job. The `DesignKit/` subtree is
  `#if DEBUG` Mac tooling, never shared.
- **App**: `Workbench.swift` and `PaletteMatcher.swift` are portable as written (closures
  isolate the web view); `NetRelishApp.swift` and `DesignKitSnapshot.swift` are
  mac-only-by-design.
- **Vault**: Keychain-only identity card (`kSecAttrSynchronizable=false`, ADR 0006).
  Keychain API is cross-platform, but `ContactsImport` (macOS Me card) and `FormFill`
  (`callAsyncJavaScript` on the Mac's web view) are per-platform by nature.

## Build-system facts that shaped the manifest

- The xcodeproj is generated by XcodeGen from `project.yml`; CI regenerates and diffs
  the whole project directory. Hand-editing it is forbidden — which is why the package
  is path-based and the project untouched.
- Names `Pantry`, `PantryTests`, `NetRelishTests`, `GeneratorTests` are taken by native
  targets; the package therefore uses `PantryKit` / `PantryKitTests`
  (`Tests/PantryKitTests`, a separate directory from `Tests/PantryTests`).
- Every CI xcodebuild names `-project` and `-scheme` explicitly, and none of the other
  jobs runs bare `swift build`, so the root manifest changes nothing for them. The
  `pantrykit` job is the one that does, on the `xcode-27` image for the same SDK reason
  as `build`. Its iOS cross-compile sets the destination with `--triple`/`--sdk` —
  injected `-Xswiftc -sdk/-target` flags do not work on Xcode 27's SwiftPM, whose
  swift-build backend appends its own macOS SDK/target after them.
- GRDB is declared `from: "7.0.0"` in both build systems. The workspace pins 7.11.1 in
  `NetRelish.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; the
  package resolves fresh in CI (a root `Package.resolved` is gitignored to avoid two
  drifting lockfiles — revisit if the package grows consumers beyond CI).
- Open `NetRelish.xcodeproj` to work on the app, as always. Opening the repo *folder* in
  Xcode now opens the package instead — nothing breaks, but it's not the app.
