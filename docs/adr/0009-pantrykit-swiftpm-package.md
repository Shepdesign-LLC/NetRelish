# ADR 0009 — PantryKit: the Pantry core as a SwiftPM package

**Status:** proposed · **Date:** 2026-10-31 · **PR:** duo-prep: pantrykit groundwork

The Duo companion (1.1, Q1 2027) needs the Pantry core on iPhone. A file-by-file audit of
all 25 files in `Sources/Pantry` found zero coupling to the app's other modules and exactly
one platform constraint: `Store/JarProfile.swift` uses `WKWebsiteDataStore(forIdentifier:)`,
an iOS 17+ API. Everything else is Foundation, GRDB, CryptoKit and AppIntents — all
cross-platform. The full map is in `docs/PantryKit_Groundwork.md`.

**Options**
1. **Path-based SwiftPM package over `Sources/Pantry`, no file moves.** A root
   `Package.swift` defines library `PantryKit` (named so because the xcodeproj already owns
   `Pantry` and `PantryTests`) with platforms macOS 27 + iOS 17 — the technical floor; Duo
   may raise it. `project.yml`, the generated xcodeproj and the Mac build are untouched; CI
   gains a job proving `swift build`, `swift test` and an iOS compile of the module.
2. Restructure SwiftPM-first now: move files, rename the framework, make the app consume
   the package. Touches the generated project and every target right as P4 starts.

**Decision:** option 1. The same files build two ways — framework for the Mac app today,
package for Duo tomorrow. Convergence (the app importing PantryKit instead of the `Pantry`
framework) is a decision for the Duo PR, not for groundwork.
