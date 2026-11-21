# Work log

Append-only. Newest entries at the bottom.

---

## [2026-11-13] setup | docs/ wiki scaffolded

- Categories: concepts - architecture - subsystems - decisions - reference - operations - history
- Baseline commit: `65fedfd`
- Created: `docs/{CLAUDE,index,log}.md`, `raw/`, 4 `.claude/commands/docs-*`,
  and `.claude/scripts/docs-lint.py`

## [2026-11-13] started in grow mode

- Two pages, written from the code just worked in (pull request 89):
  `subsystems/rearranging.md` and `operations/building-without-a-mac.md`
- Nothing was split or moved. The existing documents in `docs/` (ADRs, design handoffs,
  plans, voice guides, release notes, planning documents) are not wiki pages and are
  excluded from the linter by default; `docs/CLAUDE.md` lists them
- `release-commands:` left empty: releases run from a tag in GitHub Actions, not from a
  command an agent runs
- The rest of the app has no page yet. Pages are added as work touches an area

## [2026-11-13] zest-sound added

- `subsystems/zest-sound.md`, written with the commit that added the kit (`27b385f`)

## [2026-11-13] rearranging re-checked

- Against `5a2b9a6` (Seal and a moved tab; Close Other Tabs in one write). One trap added:
  after an await, check the tab's jar again. Line citations moved with the code

## [2026-11-13] rearranging re-checked; the linter checks Swift

- Against `7d472f8` (a page left behind in another window). One trap added
- `.claude/scripts/docs-lint.py`: `swift` added to the code extensions it checks citations
  for. This and the exclude list are the two local changes to the vendored linter

## [2026-11-13] rearranging re-checked

- Against `d0cdaeb` (Reader view and a moved tab). The await trap now names Reader view too

## [2026-11-13] zest-sound re-checked

- Against `3287635` (the studio, ZestImage and Zest MD simplified). The kit and how it is
  wired are unchanged. Two test traps added: fixed ports, and `offsetParent` inside `<details>`

## [2026-11-13] zest-sound re-checked

- Against `f859210` (ZestMail simplified; the studio's switch renamed Palette). Prose unchanged

## [2026-11-13] both pages re-checked

- `rearranging` against `b55a895` (closed tabs' pages in another window). `zest-sound`
  against `da319b6` (a one-line README change)

## [2026-11-13] zest-sound re-checked

- Against `b20ba68` (the Zest MD export menu no longer repeats the main button). The sound
  steps use the Markdown copy item, which stays. Prose unchanged

## [2026-11-13] linter: a third local change

- `.claude/scripts/docs-lint.py` matched `verified_at` to git's `%h` by exact text, so a full
  commit id (or a longer abbreviation, once git lengthens `%h`) counted the whole history
  against a page. It now matches by prefix. Checked with a 40-, 10- and 7-character id at
  HEAD (not stale) and two older ids (1 and 7 commits, the same as `git log <id>..HEAD`)

## [2026-11-13] releasing-a-preview added

- A page for cutting a preview, written while preparing 0.5.0: the order (notes, run, then
  tag), and the three states of the license address. The Release workflow gained a
  **Leave Pro unlocked** switch (ADR 0031)

## [2026-11-13] three pages moved to the squash commit

- Pull request 89 was squash-merged as `2c4c510`, so every page verified on its branch read
  as one commit stale. Each page's sources are byte for byte the same at its old
  `verified_at` and at `2c4c510` (checked with `git diff`), so `verified_at` moved alone.
  This will happen after every squash merge of a branch that touched a page's sources

## [2026-11-13] privacy-and-sandbox added

- A reference page for P5's sandbox and privacy review (ADR 0032): the three privacy
  manifests and their reasons, the entitlements and what uses each, the Info.plist keys that
  answer a question, and what a web page can ask for in 1.0. `building-without-a-mac` gained
  a trap on where a `.xcprivacy` must live. `docs/notarization.md` lost a row that blamed a
  JIT entitlement WKWebView doesn't need

## [2026-11-13] zest-window added

- A page for the Zest window host (ADR 0033 moved ADR 0015's Zest window into 1.0): the
  zest:// scheme and its path rules, Zest's reserved store, the offline rule list, the stub,
  where links go, and the gating of the page commands while the window is key. Ten traps,
  among them the scheme handler's isolation, realpath over `resolvingSymlinksInPath`, and
  `pageInFront` rather than `benchTab`

## [2026-11-13] zest-window: review fixes

- A download link to the web is now routed as a web link, never a `WKDownload`; gating
  follows the main window, so a color panel or save panel no longer switches it off; a web
  link brings forward the registered main window, not the first window in the list; the
  jar that spells Zest's UUID moves under a namespace of its own; the integration tests use
  throwaway stores. The page now says plainly what CI doesn't show (storage surviving a
  relaunch, IndexedDB) and that `zest/build.sh --app` is phase 2's, not yet written. Four
  new traps

## [2026-11-13] rearranging and building-without-a-mac re-verified

- The Zest review fixes grew Workbench's Zest block by nine lines, so rearranging's
  Workbench citations below it moved by nine; nothing they describe changed. project.yml
  changed only in a comment, so building-without-a-mac's `verified_at` moved alone

## [2026-11-14] zest-window: the bundle is real

- `Resources/Zest` now holds the built tools (143 files, 6.89 MB), so the page and ADR 0033
  describe what exists instead of what phase 2 would write. New rows for content types and
  Help › Acknowledgments; `ZestBundleTests` and the policy check in `zest/tests/inapp.js`
  under Tests. Four new traps: `zest/tests/inapp.js` parses the policy and types out of
  `Sources/Zest/ZestFiles.swift`, no `'unsafe-eval'`, a new extension needs a type, and
  `NOTICE` is edited at the root only

## [2026-11-14] building-without-a-mac re-verified

- Since `a9ac3a1`, `project.yml` changed only in a comment (the Zest folder reference is now
  described as generated, not to be generated), and the page cites no line below it, so
  `verified_at` moved alone. Help › Acknowledgments adds `Sources/App/Acknowledgments.swift`:
  the page's first trap applies, and the Xcode project is regenerated before merge

## [2026-11-14] zest-window: review fixes; rearranging re-verified

- zest-window: a Printing row (File › Print… for the tool in front), the tool's view now
  takes WebRTC away in every frame, and two traps: the rule list and the policy don't stop
  peer connections, and `window.print()` does nothing in the Zest window. The bundle is
  7,250,832 bytes (6.91 MB), NOTICE having grown by the appendix of what mermaid.min.js
  bundles; ADR 0033's size follows. Citations into ZestWebView, ZestWindow, Workbench and
  NetRelishApp moved with the new lines
- rearranging: Workbench grew by two lines above its Rearranging block (`printZest`), so its
  citations below line 164 moved by two; nothing they describe changed

## [2026-11-14] the Workstation v5 window: citations moved

- ADR 0034 rebuilt the main window (four rows, the wide Shelf, tabs in the title row, the
  jar board), so `ShelfView`, `BenchView`, `Workbench`, `NetRelishApp` and `ZestWindow`
  all grew. rearranging (15 citations), zest-window (4) and privacy-and-sandbox (2) had
  their line numbers moved to the same lines' new places; nothing those lines do changed.
  rearranging's one "rail" now reads "the list of jars"

## [2026-11-18] the workbench facelift: workbench-shell, citations moved

- New page [[workbench-shell]] for the facelift (ADR 0035, manifest v2.1): where the title
  strip, tabs, address row, bottom bar, Shelf tiles, drawn jar, Seal overlay, jar fill and
  ⌘K live, and eleven traps (the close stays at write return and the strip holds a picture
  of the tab; the failure line waits for phase B; `.sealOverlay` before `.ignoresSafeArea`;
  `sealAnchor` merges with its children's anchors; the window buttons lean on AppKit's
  private title bar; the double-click is AppKit's; the address field's real TextField; the
  Panel inset changes once; ⌘K gives the keyboard back; measures in `NRShell`; hover-only
  controls and VoiceOver). A row for it in `docs/CLAUDE.md`, a link in the index
- rearranging: the tab strip moved to `Sources/Bench/TabStrip.swift` and `JarRow` became
  `JarTile`; every citation re-cited, and one trap added: every way into a jar plays the jar
  fill through `fillJar(_:)`
- privacy-and-sandbox: the Brine pill's `brine.seenAt` date joins the NetRelish.app row
  under `CA92.1`; tab icons, the Panel and Export Proof re-cited; a trap: only read defaults
  the app wrote itself (why the title strip's double-click is AppKit's)
- zest-window (3) and releasing-a-preview (1): citations into Workbench and NetRelishApp
  moved; nothing those lines do changed
- Checked against the working tree on top of `38edcae`, before the facelift was committed:
  move `verified_at` to the facelift's commit, and re-cite, if its lines move on the way in

## [2026-11-18] CI cost: the paid runners stop paying for abandoned and no-change runs

- Measured first (ADR 0037): 1,985 runner minutes on the `xcode-27` and `macos-26` labels
  over Nov 14–18, of which **1,078 (54%)** went to runs that were superseded mid-flight or
  were analyzing a docs-only or literally empty commit. 76% of all of it is one job, CodeQL's
  `Analyze (swift)`, and 41 of its 49 minutes is the single "Build both flavours" step
- building-without-a-mac: CI now runs six things, three of them free; the four paid
  `xcode-27` jobs are gated on a free "What changed" job; CodeQL filters the same commits,
  analyzes one flavour on a pull request and both on `main` and weekly; four workflows cancel
  superseded pull-request runs. Two traps: a skipped job is not a skipped workflow (a required
  check that reports nothing blocks the merge, which is why CI gates with `if:` and why
  the CodeQL workflow's `paths-ignore` has to become a job gate the day `Analyze (swift)` is
  required), and the gate must fail open — a `grep -q` pipeline dying of `SIGPIPE` on a
  large diff once read as "nothing changed" on a green run, and each paid job's `if:` now
  runs on anything but a clean `code=false`, because a job skipped for a *failed* `needs:`
  reports as a passing required check
- The cost cut is its own branch and its own pull request, so it can merge the moment Actions
  runs again. The accessibility pass (PR #103) brings a fifth paid job, `ui-tests`; it is not
  on `main`, so it is not in this branch's CI workflow, and it takes the same `needs:`/`if:` pair when
  that branch lands. ADR 0037 says so in its arithmetic rather than leaving the next reader
  to notice
- Open, and only Ryan can close it: whether `xcode-27` and `macos-26` are billed larger
  runners or free standard ones. GitHub's run-usage API reports 0 billable ms for every
  standard macOS job on this public repository and omits the `xcode-27` jobs from the billable
  map altogether, while their runner names and group read as hosted larger runners. Settings →
  Actions → Runners, and the billing page's per-SKU breakdown, are the only places that say.
## [2026-11-18] accessibility: a new page, and citations into four others

- New page [[accessibility]] for the P5 pass (ADR 0036): the three pieces (`NRAnnounce`,
  `nrSystemAccessibility()`, `nrFocusRing`), who speaks a result and why only one owner may,
  how a row is read as one element, the keyboard's focus order and the new keys, what each of
  the Mac's four accessibility settings changes, and the UI test's Debug-only fixture. Nine
  traps, among them: one owner per spoken result; announcements dropped unless the app is in
  front; the held sealed tab hidden from VoiceOver; a rotor entry needs its namespace; every
  menu route into a jar plays the fill; read the settings from the environment, not once at
  launch; the fixture is `#if DEBUG` on both sides; XCUITest can't fire a VoiceOver action, so
  each action needs a menu item with the same words. A row for it in `docs/CLAUDE.md`, a link
  in the index
- rearranging: a row and a trap for the keyboard routes that now sit beside the drag
  (Tab › Move Tab to Jar, Move Tab Left/Right, Jars › Move Jar Up/Down, Brine's Restore to…),
  all of them through `drop(_:onJar:)` so the jar fill plays once
- building-without-a-mac: CI runs six things now; the UI tests are their own job and scheme.
  A trap: a new target or scheme in `project.yml` is as stale-making as a new Swift file,
  because the committed project holds `xcshareddata/xcschemes/`
- workbench-shell: unchanged. Its hover-at-opacity-0 trap is linked, not copied
