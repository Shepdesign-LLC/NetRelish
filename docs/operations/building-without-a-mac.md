---
title: Building without a Mac — CI is the compiler
type: operation
created: 2026-11-13
updated: 2026-11-13
sources:
  - code: .github/workflows/ci.yml
  - code: .github/workflows/regen-project.yml
  - code: project.yml
  - code: scripts/gen-symbols.swift
  - code: scripts/gen-pantry.swift
  - code: design/symbols.svg
  - code: design/NetRelish.json
verified_at: 65fedfd
---

# Building without a Mac

Most work on this repository is written in a cloud session on Linux. There is no Swift
toolchain and no Xcode there, so nothing can be compiled or run locally. The pull request's
CI is the compiler and the test runner. This page is the routine, and what goes wrong.
[[rearranging]] is an example of work done this way.

## The routine

| Step | Where |
|---|---|
| Write the code and its tests | the session |
| Push, and open a draft pull request early | CI starts on the pull request |
| If a Swift file was added, removed or moved: regenerate the Xcode project | `.github/workflows/regen-project.yml`, started by hand with the branch name (`.github/workflows/regen-project.yml:19`) |
| Read the result of each job and fix | `.github/workflows/ci.yml` |

`.github/workflows/ci.yml` runs five things. "Generated files match their sources"
(`.github/workflows/ci.yml:31`) runs on `macos-latest` and is quick. The two builds, the
tests and the PantryKit package run on `xcode-27` (`.github/workflows/ci.yml:68`), the
only image with the macOS 27 SDK, and can sit in the queue for a long time.

The web tools under `zest/` are the exception: they are plain HTML and their Playwright
suites do run in the session.

## Traps

> ⚠️ **A new Swift file makes the committed Xcode project stale.** `NetRelish.xcodeproj`
> is generated from `project.yml` by XcodeGen, which only runs on a Mac, and CI fails if
> the committed project differs from a fresh one. After adding, removing or moving a
> Swift file, run the `.github/workflows/regen-project.yml` workflow on the branch. It pushes a commit to
> that branch.

> ⚠️ **After `.github/workflows/regen-project.yml` runs, the branch has a commit you do not have.** Fetch
> and put your new commits on top of it before pushing again, or the push is rejected.

> ⚠️ **Generated Swift cannot be regenerated in the session.** `Sources/UI/Tokens.swift`,
> `Sources/UI/Symbols.swift` and `Sources/Pantry/Models/` come from Swift scripts under
> `scripts/`. A change to their source (`design/tokens.css`, `design/symbols.svg`,
> `design/NetRelish.json`) needs the generated file changed by hand to exactly what the
> script would write. CI prints the difference if it is not exact.

> ⚠️ **Renaming a symbol touches four places.** The id in `design/symbols.svg`, the case
> in `Sources/UI/Symbols.swift`, the `required` list in `scripts/gen-symbols.swift`, and
> the expected list in `Tests/NetRelishTests/SymbolTests.swift`. Miss the `required` list
> and the generator itself fails.

> ⚠️ **Do not change the model from here.** `design/NetRelish.json` is exported from System
> Designer, which Ryan runs by hand. Editing the JSON in the repository leaves his project
> behind it. When a feature needs a field, keep the data somewhere that needs no schema
> change (`Item.meta` is the usual place) or write the exact lines for him to paste in an
> ADR, as ADR 0030 does.

> ⚠️ **Swift 6 with complete concurrency checking is on** (`project.yml`). `Workbench` is
> `@MainActor`. A `static let` on a type that is not `Sendable`, or a captured `var` in a
> closure that may run elsewhere, is a compile error, not a warning, and the session will
> not tell you.

> ⚠️ **Some checks on a pull request are not `.github/workflows/ci.yml`.** "Vercel Security Review" reports
> only that findings exist and links to the Vercel dashboard, which a cloud session cannot
> read. On pull request 89 a bot also marked a draft ready for review seconds after it was
> opened. Check the draft state after opening one.
