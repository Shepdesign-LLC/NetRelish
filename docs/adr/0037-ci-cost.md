# ADR 0037 — What CI stops paying for, and what it still checks

**Status:** proposed · **Date:** 2026-11-18 · **PR:** ci(cost): cancel superseded runs, skip the paid jobs on docs commits, one flavour on a pull request

Every job on the account has failed two to five seconds after being created since about
08:25 UTC today, with no runner assigned and no logs, on `ubuntu-latest` and macOS alike —
the signature of an Actions spending limit at the account level. This ADR is the decision
about what we stop paying for. It trades some pull-request coverage for money, so the
trade is written out rather than summarized.

Nothing here weakens the CodeQL gate, touches a token, or removes a check. Every cut is
either **how often** a paid job runs or **how long** it is allowed to take.

## What was measured

Over the sprint window 2026-11-14 to 2026-11-18: 130 workflow runs, **1,985.2 runner
minutes (33.1 hours)** from 189 jobs on the `xcode-27` (CI) and `macos-26` (CodeQL) labels.
This ADR calls those two labels *paid* throughout because their runner names and group read
as GitHub-hosted larger runners, which are billed per minute even on a public repository —
but that is **not confirmed here**: only the account's billing and runner pages can say, and
it is open question 1 below. If they are standard runners, every minute figure below is
still the wall-clock waste; only the money goes away. The 96 `ubuntu-latest` and 44
`macos-latest` jobs in the same window are free, and `release.yml` and `dmg-preview.yml` did
not run at all, so the whole bill is CI + CodeQL.

- **CodeQL is 1,508.3 min (76.0%)** across 36 jobs — one job, `Analyze (swift)`, averaging
  43.1 min a run. CI is 476.9 min (24.0%) across 153 jobs, averaging 12.9 min a run. One
  CodeQL run costs about 3.3x one entire CI run.
- **41.3 of CodeQL's 49.1 minutes is one step**, `Build both flavours`, on run
  44260985492. Its sibling CI run on the same commit: Build AppStore 2.7, Build Direct
  3.2, Test 5.3, PantryKit 1.6.
- **29 runs were superseded** — a later run on the same branch and event started while
  they were still going. They burned 784.6 paid min, **720.6 of it after** the replacing
  run had started. Neither `ci.yml` nor `codeql.yml` had a `concurrency` block.
- **24 runs fired on commits with no compilable change at all**: 536.9 paid min, split
  between docs/design-prose commits (14 runs, 322.1 min) and genuinely empty commits (10
  runs, 214.8 min — four of them Copilot "Initial plan" placeholders). Neither workflow had
  a path filter. One changelog line cost 67.4 paid minutes.
- The two buckets overlap by 7 runs, so they do not add: their **union is 1,078.2 min, 54.3%
  of the entire bill**, spent on runs that were abandoned mid-flight or analyzing a tree
  with no code change in it.

Minutes are wall-clock job duration. `get_workflow_run_usage` reports 0 billable ms for
every one of these runs, because a larger runner would not appear in the billable map at
all, which is one reason the label question is still open — and is exactly why the spend
was invisible. **No dollar figure appears in this ADR, deliberately:** converting minutes to
money needs the runner SKU and rate from the account's billing page, and nothing we can call
exposes it. Do not let anyone translate these minutes into a figure without that page.

## What changed

### `ci.yml`

- **`concurrency`**, keyed on `github.event.pull_request.number || github.run_id`, cancel
  gated on the event. A new push to a pull request cancels the run it supersedes. The
  fallback is `run_id` and not `github.sha` on purpose: with a sha, a push to main and a
  `workflow_dispatch` on the same commit share a group and one cancels the other, and a run
  on main must never be cancelled. The cost of that choice is that two regen dispatches on
  one commit both pay in full.
- **A free `changes` job** (`ubuntu-latest`) whose output gates the four `xcode-27` jobs —
  `build` (both flavours), `test`, `pantrykit` — with `if:`. It is a **denylist**
  (`.github/workflows/ci.yml:116`): `docs/`, `zest/`, `.claude/`, `.github/CODEOWNERS`,
  `.github/codeql/`, the other five workflows (every `.github/workflows/*.yml` except
  `ci.yml` itself), `design/DESIGN_MANIFEST.md`, root `*.md`, `LICENSE`, `.gitignore`,
  `Config.xcconfig.example`. Anything it does not recognize runs the paid jobs, and an
  unusable base (a dispatch, a new branch, a force push) fails **open** onto them.
  `design/**` and `scripts/**` are deliberately *not* in it: `Tests/NetRelishTests` reads
  `design/tokens.css` and both logos from the repo root, and `Tests/GeneratorTests` runs the
  generator scripts against `design/NetRelish.json` and `design/symbols.svg`.
  A **fifth paid job arrives with PR #103**, the accessibility pass's `ui-tests` ("UI tests
  (capture → jar → seal)", on its own `NetRelish UI Tests` scheme). It is not on `main`, so
  it is not in this branch's `ci.yml`, and it takes the same `needs:`/`if:` pair the day
  that branch lands.
- **The gate fails open at the job level as well as inside the script.** Each paid job's
  condition is `!cancelled() && (needs.changes.result != 'success' ||
  needs.changes.outputs.code == 'true')` (`.github/workflows/ci.yml:209`), so only a clean
  `code=false` skips it. The status function is load-bearing: with none, GitHub skips a job
  whose `needs:` failed whatever the `if:` says, and **a skipped job reports as a passing
  required check** — so a `changes` job that died for a reason its filter never sees (a failed
  checkout, a dead runner, its own `timeout-minutes: 5`) would have handed a pull request a
  green merge with none of the four paid jobs run. That is the same fail-open-to-mergeable
  hazard this ADR flags below for `paths-ignore`, arriving through the back door.
  `!cancelled()` and not `always()`, so a superseded run still starts no builds. The
  remaining red check in that case is `What changed` itself, which is new and not on the
  required list — see open question 6.
- **`generated-files` and `gate-tests` are ungated**, and must stay that way. They are free,
  and they are the two jobs that still prove something on a commit where every paid job is
  skipped — docs-only, root Markdown, or `design/DESIGN_MANIFEST.md` alone:
  `generated-files` that `Sources/UI/Tokens.swift` matches `design/tokens.css` and
  `Sources/Pantry/Models` matches `design/NetRelish.json`; `gate-tests` that the gate
  enforces what it claims, reading `docs/adr` for real (a docs-only PR that duplicates an
  ADR number still fails).
- A job-level `if:` rather than a workflow-level `paths-ignore` for a second reason: a
  workflow skipped by a path filter reports *nothing*, so a required check sits "Expected"
  forever and the pull request cannot merge. A job skipped by `if:` reports as skipped,
  which branch protection accepts.
- **`timeout-minutes` on the five jobs that had none** (`generated-files` 30, `build` 25,
  `test` 30, `pantrykit` 20, `gate-tests` 10 — three of those five entries are paid, `build`
  twice over), and **5 on the new `changes` job**. The default is 360 minutes on the dearest
  runners GitHub sells.
  `generated-files` is the one figure here with no measurement behind it, and it is a free
  standard runner, so its bound buys no money — it is 30 rather than 20 so that a slow
  `brew install xcodegen` cannot red an otherwise-green pull request.

### `codeql.yml`

- **`concurrency`**, same shape, with the cancel gated on the event as well as keyed per
  pull request. A run on main is the default-branch alert baseline the Security tab reads,
  and the weekly run is the only thing that scans the paths the filter below skips; neither
  may ever be cancelled.
- **`paths-ignore`** on both `push` and `pull_request`: `docs/**`, `design/**`, `zest/**`,
  `**.md`. Safe here and nowhere else, because this job reads the *generated* Swift — which
  is committed — and never its sources, so a real token or model change arrives under
  `Sources/` in the same commit, and `generated-files` is ungated and reds the pull request
  when one did not. **The two lists are deliberately different**: this one skips the whole
  of `design/**`, while `ci.yml`'s denylist treats only `design/DESIGN_MANIFEST.md` as
  inert, because CI's tests read `design/tokens.css`, `design/NetRelish.json`,
  `design/symbols.svg` and both logos for real. `**.md` and not `**/*.md`: GitHub's `**` is
  a character wildcard, so `**/*.md` needs a literal slash and never matches a root-level
  `CHANGELOG.md` — the one commit in the last 120 (`ce47d71`) that this entry exists to
  catch. The cron takes no filter, so the whole tree is still scanned weekly.
- **One flavour on a pull request**, both on main and on the weekly scan. See the next
  section.
- **`timeout-minutes: 75`** (observed 49.1). This job injects a tracer into every spawned
  process; a build waiting on a dead plugin server produces no output and no exit.

### `zest-tests.yml`

- `concurrency` re-keyed from `github.ref` to the pull request. **This is a correctness fix,
  not a saving** — both jobs are free. On a push to main `github.ref` was `refs/heads/main`
  for every commit, so two merges landing close together cancelled the first main run, and
  that run is the only check that the merge *commit* is green. A pull request can be green on
  its merge preview and still land a stale `Resources/Zest` after a conflicting merge, and
  nothing else in the repository rebuilds the bundle and diffs it.

### `dmg-preview.yml`

- `concurrency` per pull request (no push or schedule trigger, so there is no run on main to
  protect), `timeout-minutes: 25` on the job, and `timeout-minutes: 3` on the Finder capture
  step — `continue-on-error` turns a failure into a missing `finder.png` but cannot bound a
  hang, and `hdiutil attach` and `open` both wait on Finder.

### `release.yml` and `regen-project.yml`

Unchanged, including comments. `release.yml` has correct triggers (tag-only), timeouts on
both jobs, and `cancel-in-progress: false` on purpose — cancelling mid-notarization wastes
the notary round and can leave a tag with no release. `regen-project.yml` is dispatch-only
and both its jobs are free. There is also a reason not to touch `release.yml` casually:
`dmg-preview.yml` lists it in its `paths`, so a comment-only edit there spends a paid
`xcode-27` job on the pull request.

## What a pull request no longer verifies

**One thing, and it is the CodeQL flavour split.** On a pull request the traced build now
builds Direct alone.

This was checked against the tree rather than assumed. Repo-wide there is exactly one
`#if DIRECT_BUILD` site outside `DEBUG` guards — `Sources/App/NetRelishApp.swift:42-52`,
the `LicenseRelay.configured` switch, whose `#else` is the single line `return .live()`.
`project.yml` and the xcconfigs set no `EXCLUDED_SOURCE_FILE_NAMES` and both schemes build
the same target, so the two flavours compile the same file set. `Sources/App/License.swift`
and `Sources/App/TimestampService.swift` — which hold every call in
`.github/codeql/approved-endpoints.txt` — carry no `#if` at all and are in both. Direct is
the superset, so building it alone leaves one line out of the database, and that line
contains no network API.

| No longer on a pull request | What covers it now |
|---|---|
| App-Store-exclusive code (that one `#else` branch) | The CodeQL run on the push to main, and the weekly scan |
| Code that becomes `DIRECT_BUILD`-exclusive later — `Sources/MasonJar` and its GitHub OAuth device flow (1.2, ADR 0029), which does not exist yet | The same two runs. The day a second `#if DIRECT_BUILD` site lands, reconsider the split |
| Any CodeQL scan of a docs-only, Markdown-only, empty, or `design/**`-only commit | The weekly cron, which takes no path filter and scans the whole tree. Safe in between because the Swift generated from `design/` is **committed**: a real token or model change arrives under `Sources/` in the same commit and re-triggers the scan, and if it did not regenerate, CI's ungated `generated-files` reds the pull request |
| CI's four paid jobs on a docs-only commit | `generated-files` and `gate-tests`, which stay ungated and free, plus the next commit that touches code |

Two second-order effects, said plainly rather than discovered later. Code scanning diffs a
pull request's results against the base, so a one-flavour database can report a baseline
alert in unbuilt code as "fixed" on that pull request and then as new again on main. That is
alert noise in the Security tab, not lost enforcement — the gate is per-run and fails
closed. And a superseded commit now ends with cancelled checks rather than passing ones;
branch protection gates the head commit, whose run always completes, but the Checks tab of
an intermediate commit reads grey.

## Before and after, per push

Minutes on the `xcode-27` and `macos-26` labels, billed per minute if those are
larger-runner labels (open question 1). GitHub bills each job rounded up to the whole minute,
so these are rounded per job, not summed from wall clock.

| Push | Before | After | Where it goes |
|---|---|---|---|
| Docs, root-level Markdown, `design/DESIGN_MANIFEST.md`, or an empty commit | ~65 | **0** | CodeQL not triggered; CI's four paid jobs skipped, its three free jobs (`changes`, `generated-files`, `gate-tests`) still run |
| Any other `design/**` file — `tokens.css`, `NetRelish.json`, `symbols.svg`, either logo | ~65 | **~15** | CodeQL not triggered (`paths-ignore` skips `design/**` entire); CI's four paid jobs still run, because its tests read these files |
| Code push, run to completion | ~65 | **~45** | CodeQL 50 → ~30 (one flavour); CI unchanged at ~15 |
| Code push, superseded ~2 min in | ~65 | **~11** | Cancelled instead of completing |
| Push to main (merge) | ~65 | ~65 | Deliberately unchanged: both flavours, never cancelled |
| A job that hangs | up to 1,800 | **≤175** | `timeout-minutes` everywhere |

Line by line, so the estimates can be argued with:

- **Before, ~65** = CI 15 (Build AppStore 3, Build Direct 4, Test 6, PantryKit 2) + CodeQL
  50. Every row above counts the four paid jobs this branch has. **PR #103 adds a fifth**,
  `ui-tests`, at an **estimated ~6** billed minutes a push — an estimate and not a
  measurement, because it ran once in the sprint window and never got a runner, but its
  scheme builds the same target set in the same configuration as `Test`, so its floor is
  Test's compile plus the UI run. It arrives gated on `changes` exactly as these are, so it
  raises the "code push" rows by about 6 and leaves the docs-only row at 0.
- **CodeQL 50 → ~30** divides the 41.3-minute dual build by CI's untraced 2.7/3.2 split
  (46/54), putting Direct at about 22 of the 41. Honest range 10 to 19 minutes saved, not a
  point estimate: the two invocations share one DerivedData, so the second may already reuse
  part of the first. **Measure it on the first run after this merges before quoting a number.**
- **Hang exposure** is 4 × 360 = **1,440** for CI's four paid jobs — `build` (twice),
  `test` and `pantrykit` all sat at the 360 default — plus 360 for CodeQL, so **1,800**
  today. After: 25 + 25 + 30 + 20 = **100** for CI plus 75 for CodeQL, so **175**.
  PR #103's `ui-tests` already carries `timeout-minutes: 30`, so it adds 30 to both
  columns, not 360 to the first. `dmg-preview.yml`'s paid `xcode-27` job is excluded from
  that row, because its `paths` allowlist did not fire once in the window; when it does
  fire it goes from the same 360 default to 25. The free jobs are not counted: a hung free
  job costs no money, it just never reports. It is insurance, and given the account is
  already over a limit, one past hang would explain a large slice of the bill on its own.

Against the sprint: the concurrency groups and the path filters together address the
**1,078.2 minutes (54.3%)** that went to superseded or no-change runs. Treat 720.6 of that as
a near-ceiling rather than a refund — a real cancellation takes seconds to propagate.

## What was deliberately not cut

| Not cut | Why |
|---|---|
| The CodeQL gate, its self-test, the custom queries, the code-scanning upload | `scripts/codeql_gate.py` is what enforces non-negotiable 5 (ADR 0026, ADR 0022). `gate-tests` stays on free `ubuntu-latest` and stays ungated, because a gate whose only proof of correctness lives inside the job that is currently red is not proven at all |
| The `pull_request` trigger on CodeQL | That trigger *is* the gate. A scan that only runs post-merge reports instead of gating |
| The push-to-main CodeQL run, although the same tree was analyzed on its pull request | It is the default-branch baseline. Code scanning's alert state and "fixed" detection are per-ref; without it only the weekly cron refreshes the Security tab, so alerts would sit stale for up to seven days and never close |
| The weekly cron | One run a week, and it is what still scans the paths the new filters skip. It is also the canary for the macOS-image risk the `codeql.yml` header documents |
| ADR 0024's token split | No permission added, no token widened, `persist-credentials: false` kept on every checkout including the new `changes` job, and `regen-project.yml`'s two-job split untouched — the job that can write still runs nothing from the branch |
| Both build flavours in CI | The privacy-manifest step asserts the App Store bundle carries no `NRLicenseActivationURL` and the Direct bundle carries an https one. Half that assertion disappears if a flavour goes. Unlike CodeQL this is minutes, not 41 |
| `fail-fast: false` on the build matrix | Cancelling Direct when AppStore fails saves ~4 min on an already-failing push and hides a Direct-only break behind the AppStore one, buying a second full cycle to find it |
| The Design Kit render and its snapshot upload on every pull request | Not a check, so it was tempting — but it is the artifact Ryan looks at, and `CLAUDE.md` makes a runnable demo part of every PR. Seconds on a runner that is already paid for |
| The Finder capture in `dmg-preview.yml` | `preview.png` is our own drawing from `layout.json` and cannot disprove anything. `finder.png` is the only artifact showing real Finder honoring the `.DS_Store` `dmgbuild` wrote. It got a step timeout instead of a deletion |
| `release.yml`'s dmg-preview trigger | `dmg-preview.yml` is the only pre-merge exercise of `scripts/dmg/make-dmg.sh`, which the release also calls. About six minutes per 17 days against a release failing at notarization time |
| Merging `ui-tests` into `test`, once PR #103 lands it | ~4 billed min a push, and the two schemes do compile the identical target set — but it collapses two check names, and a branch-protection rule naming a check that no longer exists blocks merges forever. Not three weeks before Dec 14. Left for Ryan below |
| Caching SwiftPM's resolved packages | ~1-3 min a push, unmeasured, possibly swallowed by per-minute rounding — against a cache a same-repo branch can write and a later job restores, feeding dependency *source* into a job that compiles and runs it. Explicitly not in `release.yml` (the signed build must resolve from the lockfile) and not in `codeql.yml`, which is the one job that disables SwiftPM's manifest sandbox. Left for Ryan below |
| An allowlist trigger (`on: push: paths:`) anywhere | A directory someone adds later — a new `Sources/` module, a new `Resources/` folder — would silently never be built. The denylist fails open onto the paid jobs, which is the behaviour you want when you are wrong |
| A path filter on `zest-tests.yml` | Its allowlist is correct for a one-subsystem suite and it is free either way |

## Still open, for Ryan

1. **Is `macos-26` a larger-runner label on this account?** The whole CodeQL bill rests on
   it. If it is an org or repo larger-runner label, the cheapest fix in the repository is one
   line — `macos-latest`, which `ci.yml` records as still being macOS 26 — and it takes
   CodeQL's remaining ~30 min a run to zero, on main and the weekly scan too. It was not
   changed here, for two reasons: it cannot be verified from a session with no Mac and no
   Actions settings page, and `macos-latest` is a *moving* label — the day GitHub promotes it
   to macOS 27, the traced build returns to the "Bad CPU type in executable" failure that
   `codeql.yml`'s header documents at length. Check Settings → Actions → Runners. If it is a
   larger-runner label, the durable fix is an explicit standard macOS 26 label, which today
   collides with it.
2. **Copilot code review.** Not an Actions cost and not in this ADR's scope, but it is a
   second spend line: `copilot-pull-request-reviewer` ran about 50 times in seven days —
   five full-diff reviews on PR #102 inside 28 minutes — and PR #94 records the Copilot
   monthly quota already exhausted on 2026-11-14. It is billed as premium requests. The lever
   is a repository or org Copilot setting, not a repo file.
3. **The Vercel `zest` project.** 86 deployments in seven days, 70 of them previews, and
   every one of the six main-branch commits checked touched zero files under `zest/`. At
   about 5 seconds a build it is roughly 7 minutes a week, so it is not the bill — but an
   Ignored Build Step (`git diff --quiet HEAD^ HEAD -- ../zest`) is free to set and removes
   no check, since the Zest suites live in `zest-tests.yml`. Worth confirming separately that
   `MAILPRESS_TOKEN` is set on that project: `zest/api/claude.js` spends Anthropic credits
   per call and sits on a custom domain outside the project's SSO protection. It fails closed
   without the token.
4. **Merging `ui-tests` into `test`** once PR #103 lands it, and **the SwiftPM cache** — both costed above, both
   left out, both reasonable to take later. The cache needs its action pinned by commit hash
   like every other action in these files; a guessed hash is worse than no cache.
5. **The weekly cron fires late.** It is configured `'17 6 * * 1'` and its one run in the
   window started 15:36 UTC — a roughly nine-hour scheduler delay. Worth knowing before
   anyone reasons about when the full-tree scan lands.
6. **Make `What changed` a required check.** It is the one check that goes red when the gate
   itself breaks. The four paid jobs are deliberately *run* rather than skipped in that case,
   so nothing merges unbuilt — but a required `What changed` is what makes that red block the
   merge instead of merely being visible. Branch protection is a repository setting, not a
   file in here. Add it only once this branch is on `main`: a required check whose name no run
   produces blocks every merge forever.
