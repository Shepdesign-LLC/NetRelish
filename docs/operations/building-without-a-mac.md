---
title: Building without a Mac — CI is the compiler
type: operation
created: 2026-11-13
updated: 2026-11-21
sources:
  - code: .github/workflows/ci.yml
  - code: .github/workflows/codeql.yml
  - code: .github/workflows/zest-tests.yml
  - code: .github/workflows/dmg-preview.yml
  - code: .github/workflows/regen-project.yml
  - code: project.yml
  - code: scripts/gen-symbols.swift
  - code: scripts/gen-pantry.swift
  - code: design/symbols.svg
  - code: design/NetRelish.json
  - code: Resources/PrivacyInfo.xcprivacy
  - code: Sources/ShareExtension/PrivacyInfo.xcprivacy
verified_at: 0d45775
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

`.github/workflows/ci.yml` runs seven things. Three are free: "What changed"
(`.github/workflows/ci.yml:48`), "Generated files match their sources"
(`.github/workflows/ci.yml:153`) and the CodeQL gate self-test
(`.github/workflows/ci.yml:390`). The two builds (`.github/workflows/ci.yml:195`), the tests
(`.github/workflows/ci.yml:261`), the UI tests (`.github/workflows/ci.yml:297`) and the
PantryKit package (`.github/workflows/ci.yml:352`) run on `xcode-27`, the only image with
the macOS 27 SDK, and can sit in the queue for a long time.

**The builds, the tests and the PantryKit package run only when the commit can change what
they compile** (ADR 0037). "What changed" diffs against the base and sets one output they
depend on, through the `needs:`/`if:` pair on each of them
(`.github/workflows/ci.yml:201`, `:210`); a commit touching nothing but `docs/`, `zest/`,
`.claude/`, a root `*.md` or the other workflows skips them, and the three free jobs still
run. CodeQL skips the same kind of commit through its own `paths-ignore`
(`.github/workflows/codeql.yml:241`), analyzes one flavour on a pull request and both on
`main` and in the weekly scan, and CI (`.github/workflows/ci.yml:32`), CodeQL
(`.github/workflows/codeql.yml:273`), the Zest suites
(`.github/workflows/zest-tests.yml:24`) and the disk-image preview
(`.github/workflows/dmg-preview.yml:36`) each cancel a superseded pull-request run.

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

> ⚠️ **A skipped job is not a skipped workflow.** CI gates its paid jobs with `needs:` and
> `if:` rather than a workflow-level `paths-ignore`, because a workflow a path filter skips
> reports nothing at all, and a required check that reports nothing sits "Expected" forever
> and blocks the merge. A job skipped by `if:` reports as skipped, which branch protection
> accepts. The CodeQL workflow does use `paths-ignore`, so **the day `Analyze (swift)` is made a
> required check, that filter has to become a job-level gate too** (ADR 0037).

> ⚠️ **`ui-tests` is not behind the gate.** It has no `needs:`/`if:` pair
> (`.github/workflows/ci.yml:297`), so it takes an `xcode-27` runner on every pull request,
> a docs-only one included: it ran on the release-notes pull request for 0.6.0 while the
> builds and the tests were skipped. The gate was written on one branch and the job on
> another, and ADR 0037 says the job takes the same pair when it lands. It hasn't yet.
> Giving it the pair is a change to CI, and Ryan's to approve.

> ⚠️ **"What changed" must fail open.** Every path through its filter either names the files
> it found or sets `code=true`: no usable base, a diff that will not run, a bad regex. Being
> wrong there costs minutes; being wrong the other way skips the compiler on a commit that
> changed code, on a green run. Two real failure modes are written out in the step's own
> comments — a `grep -q` pipeline that dies of `SIGPIPE` on a large diff, and an empty diff
> read as a change. Keep the here-string and the explicit exit-status `case`. The gate fails
> open at the job level too, and has to: each paid job's `if:` runs it on anything but a clean
> `code=false`, because GitHub skips a job whose `needs:` failed whatever the condition says,
> and a skipped job reports as a *passing* required check — so a `changes` job that merely
> died would otherwise let a pull request merge with no paid job run at all.

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

> ⚠️ **Only the app's privacy manifest goes in `Resources/`.** Everything in `Resources/` is
> copied flat into the app's Contents/Resources (`project.yml:85`), so a second
> `PrivacyInfo.xcprivacy` anywhere in the app's folders fails the build with "Multiple
> commands produce". XcodeGen treats a `.xcprivacy` it doesn't know as a resource of the
> target whose folder holds it: the Share extension's sits in `Sources/ShareExtension`, the
> Pantry framework's in `Sources/Pantry`. CI checks all three landed in the built app. What
> they say is [[privacy-and-sandbox]].

> ⚠️ **Some checks on a pull request are not `.github/workflows/ci.yml`.** "Vercel Security Review" reports
> only that findings exist and links to the Vercel dashboard, which a cloud session cannot
> read. On pull request 89 a bot also marked a draft ready for review seconds after it was
> opened. Check the draft state after opening one.
