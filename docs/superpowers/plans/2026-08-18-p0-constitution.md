# P0 — Constitution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite NetRelish's stated law so it no longer contradicts the cloud decision, restructure the repo into an npm-workspaces monorepo with the desktop app still building, and clear the notarization blocker.

**Architecture:** Documentation first (CLAUDE.md, ROADMAP, README), then a pure `git mv` of the desktop app into `apps/desktop`, then the build glue that the move breaks (package.json workspaces, `.gitignore` anchoring, CI paths). No source code changes — `src/**` and `src-tauri/src/**` move byte-identical. `packages/core` and `packages/ui` are deliberately NOT created here: nothing consumes them until P2, and empty packages are YAGNI.

**Tech Stack:** npm workspaces, Tauri v2, Vite, GitHub Actions, `gh` CLI.

**Verification model:** This task is configuration and prose, not feature code, so there are no unit tests to write first. The equivalent of a failing test is a build command that must fail before a change and pass after. Every task states the exact command and its expected output. The load-bearing check is Task 7: a full `npm run app:build` producing a `.app`.

**Out of scope, deliberately:**
- `site/` stays at the repo root. Vercel's project has Root Directory = `site`; moving it breaks a live deployment for zero P0 benefit. It gets absorbed by `apps/web` in P2.
- No `packages/*` yet (see Architecture).
- No schema or Supabase work — that is P1.

---

## File Structure

| Path | Change | Responsibility |
| :-- | :-- | :-- |
| `CLAUDE.md` | modify §4, §5, §10, §11, §12, §14 | The law. Must stop contradicting the cloud decision. |
| `docs/ROADMAP.md` | rewrite "Out by design" + "Roadmap" | Business layer, re-sorted against the master plan. |
| `README.md` | modify status + privacy claims | Public face; currently claims "no account, no server, no sync". |
| `package.json` | rewrite | Workspaces root. Delegates scripts to `apps/desktop`. |
| `apps/desktop/package.json` | create | The desktop app's own manifest (was the root one). |
| `apps/desktop/**` | `git mv` from root | `src/`, `src-tauri/`, `scripts/`, `index.html`, `vite.config.ts`, `tsconfig.json`. |
| `.gitignore` | modify | `src-tauri/…` patterns are root-anchored and stop matching after the move. |
| `.claude/launch.json` | modify | Dev server command must reach the workspace. |
| `.github/workflows/release.yml` | modify | Rust cache path + `projectPath` for tauri-action. |
| `docs/RELEASING.md` | modify | Paths, and mark notarization proven once it is. |

---

### Task 1: Amend CLAUDE.md §4 — the non-negotiables

This is the task that matters most. Everything else in P0 is mechanics.

**Files:**
- Modify: `CLAUDE.md:73-98` (§4)

- [ ] **Step 1: Confirm the contradiction exists (the "failing test")**

Run: `grep -n "Everything is local\|No cloud in v1" CLAUDE.md`
Expected: two hits, at roughly lines 75 and 92. If these are gone, someone already did this task — stop and re-read the file.

- [ ] **Step 2: Replace §4.1**

Find this block:

```markdown
1. **Everything is local.** SQLite on disk. No network calls except page
   loads, the updater check, and (later) a license check. No telemetry, no
   analytics, no account.

   This is an engineering constraint, not a marketing position. Local is why
   `⌘K` returns in under 50ms, and cutting sync is why this ships in eight
   weeks instead of five months. Privacy is a consequence — a good line for
   the website, but not the reason it's in the architecture.
```

Replace with:

```markdown
1. **Offline is the floor.** SQLite on disk stays the source of truth on the
   Mac, and every feature must work with the network unplugged. Sync is
   additive: it makes the Pantry reachable elsewhere, it never becomes the
   thing the app needs in order to function.

   This is what survives of local-first, and it is the part worth keeping.
   Local is still why `⌘K` returns in under 50ms — that is a read against
   a file on disk, and it must stay one.

   *(Amended 2026-08-18. This clause previously read "Everything is local /
   no network calls except page loads". Ryan reversed it — see §4a and
   `docs/superpowers/specs/2026-08-18-netrelish-master-plan-design.md`.)*
```

- [ ] **Step 3: Replace §4.5**

Find this block:

```markdown
5. **No cloud in v1.** Not Supabase, not anything. If a task seems to need a
   server, an account, or a network call, stop and say so. It's out of scope
   by design, not by oversight.
```

Replace with:

```markdown
5. **The cloud is a co-equal track.** Supabase is the backend, the web app is
   a first-class client, and the extension is a real capture surface. What
   this does *not* license is drift: a server feature ships against the
   schema in §6 and the vocabulary in §2, or it doesn't ship.
```

- [ ] **Step 4: Add §4a — what may leave the machine**

Immediately after the numbered list in §4 (before the `---` that closes the
section), add:

```markdown
### 4a. What may leave the machine

Full account sync was chosen deliberately, which makes this list the honest
replacement for the old "nothing leaves" promise. It is exhaustive; adding
to it is a decision, not an implementation detail.

| Leaves | Why | Note |
| :-- | :-- | :-- |
| Jars, items, labels, recipes, tabs | Sync | The user's own content, under their account |
| Extracted page text | Sync + hosted AI | Same rows as above; §7 still governs extraction |
| Item text sent for analysis | Summaries, gap analysis, reports | Per-request, cached server-side, shown in the UI while it happens |
| Licence + subscription state | Billing | |

**Never leaves, under any feature:**

- **Credentials.** Passwords live in the macOS Keychain and are not rows in
  `netrelish.db`. They do not sync, they are never sent for analysis, and no
  server-side feature may read them. Shipped 2026-08-11: the fill path runs
  Rust→page, and the UI layer only ever sees usernames.
- **Private-window browsing.** §7 already forbids extracting it; it therefore
  has nothing to sync.
- **Denied URLs.** The deny list is applied before a row exists, so denied
  pages never reach the server for the same reason.
- **Telemetry.** There is still none. Accounts make it possible; that is not
  the same as deciding to. Until it is written here, it does not exist.
```

- [ ] **Step 5: Verify the section is internally consistent**

Run: `sed -n '73,140p' CLAUDE.md`
Expected: §4.1 reads "Offline is the floor", §4.2/§4.3/§4.4 are untouched
(suggest-never-silently, closing is free, native child webview), §4.5 reads
"co-equal track", and §4a follows. Read it end to end — no sentence should
still assert that nothing leaves the machine.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'MSG'
docs(law): §4 admits the cloud — offline is the floor, not the ceiling

§4.1 no longer claims everything is local; §4.5 no longer forbids the
cloud. New §4a lists exhaustively what may leave the machine and what
never does — credentials, private windows, denied URLs, telemetry.

§4.2, §4.3 and §4.4 are untouched and remain law.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: Amend CLAUDE.md §5, §10, §11, §12, §14

**Files:**
- Modify: `CLAUDE.md` (§5 architecture, §10 infrastructure, §11 build order, §12 not-in-v1, §14 commands)

- [ ] **Step 1: §5 — add the clients above the existing diagram**

At the top of §5, immediately after the `## 5. Architecture` heading, insert:

````markdown
NetRelish is three clients over one backend. The Mac app below is the
premium native client and the only one with a native page pane; the web app
and the extension are P2 and P3 of the master plan.

```
Supabase           Postgres + Auth + RLS + Edge Functions
├── apps/desktop   the Tauri app below — offline-capable, syncs
├── apps/web       Next.js on Vercel — full product + public pages
└── apps/extension MV3 — capture only
```

The rest of this section describes the desktop client specifically.
````

- [ ] **Step 2: §5 — note the monorepo under "Storage"**

At the end of §5's Storage subsection, after the sentence about migrations,
append:

```markdown
Desktop paths in this file are relative to `apps/desktop/`. The repo is an
npm-workspaces monorepo; `npm run app` from the root still works.
```

- [ ] **Step 3: §10 — replace the closing paragraph**

Find:

```markdown
None of this is on the critical path, and none of it touches browsing data.
The updater endpoint is already configured in `tauri.conf.json`.
```

Replace with:

```markdown
As of 2026-08-18 this table is the critical path, not a someday. Supabase is
the backend for sync, auth and the hosted AI layer; Vercel hosts the web app;
Stripe handles billing. The updater endpoint is already configured in
`tauri.conf.json`. What each of these may hold is bounded by §4a.
```

- [ ] **Step 4: §11 — point at the master plan**

At the very top of §11, after the heading, insert:

```markdown
The eight weeks below are **done** and describe the shipped desktop app. The
work that follows them is the master plan:
`docs/superpowers/specs/2026-08-18-netrelish-master-plan-design.md` — twelve
projects, six phases. Read it before starting anything new.
```

- [ ] **Step 5: §12 — re-sort the out-of-scope table**

Replace the table body rows for Email, Cloud sync, Sharing/teams and Billing
so the table reads:

```markdown
| | Why not now |
| :-- | :-- |
| Email (`kind='message'`) | Schema already supports it. Gmail API needs Google's security review — money and a month of calendar time. Start with IMAP, after the cloud track lands. |
| iOS | App Store only, and Guideline 2.5.6 forces WKWebView. Ship a PWA companion after the web app lands. |
| Extensions *for* NetRelish | Enormous surface area. Probably never. (NetRelish's own capture extension is P3 and is a different thing.) |
| Windows / Linux | Different webview, different signing, different bugs. Not until Mac is loved. |

**Moved out of this section on 2026-08-18** — cloud sync (P4), sharing and
teams (P7, P10), and billing (P6) are now scheduled work in the master plan,
not deferred ideas.
```

- [ ] **Step 6: §14 — update the commands for the monorepo**

Replace the code block in §14 with:

````markdown
```bash
npm install         # once, at the root — installs every workspace
npm run app         # dev, hot reload, devtools
npm run app:build   # local release build
npm run typecheck   # types, all workspaces
cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml
npm run tauri -w @netrelish/desktop icon <1024px.png>   # regenerate icons
```
````

- [ ] **Step 7: Verify no stale paths remain**

Run: `grep -n "src-tauri/" CLAUDE.md | grep -v "apps/desktop"`
Expected: only §5's migrations line (`src-tauri/migrations/NNN_name.sql`) and
§9's Rust conventions line (`src-tauri/src/commands/`), both of which Step 2
already scoped with "Desktop paths in this file are relative to
`apps/desktop/`". Anything else is a miss — fix it.

- [ ] **Step 8: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'MSG'
docs(law): §5, §10, §11, §12, §14 catch up with the cloud track

Three clients over one backend; infrastructure is the critical path
now, not a someday; §11 points at the master plan; sync, sharing,
teams and billing leave "Not in v1" because they are scheduled work.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: Rewrite docs/ROADMAP.md and README.md

**Files:**
- Modify: `docs/ROADMAP.md` ("Ground rules", "Roadmap", "Out by design", "Metrics")
- Modify: `README.md` (Status section, privacy claim)

- [ ] **Step 1: ROADMAP — replace the "Out by design" section entirely**

Find the section beginning `### Out by design` and ending at the
`## Metrics that matter` heading. Replace the whole section with:

```markdown
### Reversed on 2026-08-18

This section used to list what the plan asked for and the architecture
refused. Ryan reversed all four. Kept here rather than deleted, because the
reversal is the single most consequential decision in the project:

| Was out | Now | Where |
| :-- | :-- | :-- |
| Accounts, cloud backend | **In** — Supabase, full account sync | P1, P4 |
| LLM API in the product | **In** — hosted, metered by plan | P5 |
| Extension as a capture surface | **In** — MV3, Chrome + Edge | P3 |
| Public collections, marketplace, teams | **In** — scheduled, phases 3 and 6 | P7, P10, P11 |

What survives: the on-device embedding model stays (it does ranking and
clustering offline, and the hosted model does prose — they are
complementary); offline remains the floor; the vocabulary in CLAUDE.md §2 is
unchanged; and §4a now bounds what may leave the machine.

The full decomposition is
`docs/superpowers/specs/2026-08-18-netrelish-master-plan-design.md`.
```

- [ ] **Step 2: ROADMAP — replace the "Roadmap" section's Next/Later lists**

Replace everything between `### Next — post-launch, all local` and
`### Reversed on 2026-08-18` with:

```markdown
### Now — the master plan

Twelve projects, six phases. Summarised here; the spec is authoritative.

| Phase | Projects |
| :-- | :-- |
| 1 Foundation | P0 constitution + monorepo + notarization · P1 backend |
| 2 MVP | P2 web app · P3 extension · P5 hosted intelligence |
| 3 Business | P6 billing · P7 public jars and growth |
| 4 Mac home | P4 sync |
| 5 Premium | P8 Relish Reports · P9 competitive research |
| 6 Scale | P10 teams · P11 marketplace · P12 knowledge graph |

Already shipped and not re-listed above: the eight weeks of CLAUDE.md §11,
and **passwords** (2026-08-11) — save and fill logins vaulted in the macOS
Keychain, never in `netrelish.db`, never near FTS or the engine. The fill
path runs Rust→page; the UI layer only ever sees usernames. Detection is a
suggestion; saving and filling are user gestures. Still wanted: a management
panel, CSV import from Safari/Chrome, a multi-account picker, Touch ID on
reveal, and subdomain matching.

That paragraph is load-bearing: CLAUDE.md §4a's credentials rule depends on
this being the written-down description of how passwords work. Do not drop
it when rewriting this section.

Still unscheduled, still wanted: element-level clipping, email via IMAP, a
PWA companion.
```

- [ ] **Step 3: ROADMAP — fix the "Ground rules" paragraph**

In the "Ground rules" paragraph, replace the sentence:

```
where it describes cloud SaaS mechanics, the local-first
architecture wins. The plan's *vision* is adopted; its *mechanics* are
translated.
```

with:

```
where it describes cloud SaaS mechanics, those are now
**adopted** rather than translated — see "Reversed on 2026-08-18" below.
The vocabulary translation still holds absolutely.
```

- [ ] **Step 4: ROADMAP — fix the Metrics paragraph**

Replace:

```
No telemetry means these are measured through
opt-in feedback and download/update counts, not spyware — the
constraint is the brand.
```

with:

```
Accounts make server-side measurement possible for the first time. What
gets measured is not yet decided, and per §4a nothing is collected until it
is written down. Until then: opt-in feedback and download counts.
```

- [ ] **Step 5: README — replace the Status section**

Find:

```markdown
## Status

Week 1 of 8. The shell runs and renders pages in a native WKWebView. It is not
yet a browser you'd use.

See the build order in [`CLAUDE.md`](CLAUDE.md#11-build-order).
```

Replace with:

```markdown
## Status

All eight weeks of the desktop app are complete: Brine, Jars, `⌘K`, sealing,
the suggestion engine, Recipes, and notes/tasks/files/labels. v0.1.0 is
signed and notarized.

Next is the cloud track — a web app, a capture extension, and sync. See
[`CLAUDE.md`](CLAUDE.md#11-build-order) and the master plan in
[`docs/superpowers/specs/`](docs/superpowers/specs/).
```

- [ ] **Step 6: README — fix the privacy claim**

Replace the line:

```
Everything lives on your machine — no account, no server, no sync.
```

with:

```
Works fully offline — your Pantry is a file on your Mac. Sign in and it
follows you to the web.
```

- [ ] **Step 7: Verify no stale local-first claims survive**

Run: `grep -rn "no account\|no server\|no sync\|nothing leaves\|No cloud" README.md docs/ROADMAP.md CLAUDE.md`
Expected: zero hits, except inside the historical "Reversed on 2026-08-18"
table in ROADMAP.md and the amendment notes in CLAUDE.md §4.1, which are
describing the past deliberately.

- [ ] **Step 8: Commit**

```bash
git add README.md docs/ROADMAP.md
git commit -m "$(cat <<'MSG'
docs(roadmap): the reversal, on the record

ROADMAP's "Out by design" becomes "Reversed on 2026-08-18" — kept
rather than deleted, because the reversal is the most consequential
decision in the project. README stops claiming no account, no server,
no sync, and stops saying week 1 of 8.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: Move the desktop app into `apps/desktop`

Pure `git mv`. No file contents change in this task — that is what makes it
reviewable.

**Files:**
- Move: `src/`, `src-tauri/`, `scripts/`, `index.html`, `vite.config.ts`, `tsconfig.json` → `apps/desktop/`

- [ ] **Step 1: Confirm the tree is clean**

Run: `git status --porcelain`
Expected: empty. If not, commit or stash first — a dirty tree makes a
rename commit unreadable.

- [ ] **Step 2: Move everything**

```bash
mkdir -p apps/desktop
git mv src apps/desktop/src
git mv src-tauri apps/desktop/src-tauri
git mv scripts apps/desktop/scripts
git mv index.html apps/desktop/index.html
git mv vite.config.ts apps/desktop/vite.config.ts
git mv tsconfig.json apps/desktop/tsconfig.json
```

- [ ] **Step 3: Verify git sees renames, not deletes**

Run: `git status --porcelain | grep -c '^R'`
Expected: a number ≥ 70. If you see `D`/`??` pairs instead of `R`, the moves
lost history — reset and redo with `git mv`.

- [ ] **Step 4: Commit the move alone**

```bash
git add -A
git commit -m "$(cat <<'MSG'
refactor(repo): move the desktop app to apps/desktop

Pure rename, no content changes — the build glue follows in the next
commit. Keeping the move by itself is what makes it reviewable.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: Workspaces manifests and `.gitignore`

The move breaks the build. This task fixes it.

**Files:**
- Create: `apps/desktop/package.json`
- Modify: `package.json` (becomes the workspaces root)
- Modify: `.gitignore`
- Modify: `.claude/launch.json`

- [ ] **Step 1: Prove the build is broken (the "failing test")**

Run: `npm run typecheck`
Expected: FAIL — `tsc` cannot find `tsconfig.json` at the root, or reports
`error TS18003: No inputs were found`. This is the state Task 5 fixes.

- [ ] **Step 2: Create `apps/desktop/package.json`**

```json
{
  "name": "@netrelish/desktop",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview",
    "tauri": "tauri",
    "app": "tauri dev",
    "app:build": "tauri build",
    "typecheck": "tsc --noEmit",
    "predev": "node scripts/ensure-model.mjs",
    "prebuild": "node scripts/ensure-model.mjs"
  },
  "dependencies": {
    "@tauri-apps/api": "^2.1.1",
    "@tauri-apps/plugin-dialog": "^2.2.0",
    "@tauri-apps/plugin-opener": "^2.2.5",
    "@tauri-apps/plugin-sql": "^2.4.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@mozilla/readability": "^0.6.0",
    "@tauri-apps/cli": "^2.1.0",
    "@types/node": "^26.2.0",
    "@types/react": "^18.3.12",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.4",
    "typescript": "^5.7.2",
    "vite": "^6.0.3"
  }
}
```

- [ ] **Step 3: Replace the root `package.json`**

```json
{
  "name": "netrelish",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "workspaces": [
    "apps/*",
    "packages/*"
  ],
  "scripts": {
    "dev": "npm run dev -w @netrelish/desktop",
    "app": "npm run app -w @netrelish/desktop",
    "app:build": "npm run app:build -w @netrelish/desktop",
    "tauri": "npm run tauri -w @netrelish/desktop",
    "typecheck": "npm run typecheck --workspaces --if-present"
  }
}
```

Note: `workspaces` lists `packages/*` even though no package exists yet. npm
tolerates a glob that matches nothing, and P1 will add the first one.

- [ ] **Step 4: Fix `.gitignore` anchoring**

A pattern containing an internal slash is anchored to the `.gitignore`'s own
directory, so `src-tauri/target/` stops matching once the app moves. Replace
these four lines:

```
src-tauri/target/
src-tauri/gen/
src-tauri/*.key
src-tauri/updater.key
src-tauri/updater.key.pub
src-tauri/models/
```

with:

```
apps/desktop/src-tauri/target/
apps/desktop/src-tauri/gen/
apps/desktop/src-tauri/*.key
apps/desktop/src-tauri/updater.key
apps/desktop/src-tauri/updater.key.pub
# the embedding model is fetched by scripts/ensure-model.mjs, not committed
apps/desktop/src-tauri/models/
```

and delete the now-duplicated trailing comment line
`# the embedding model is fetched by scripts/ensure-model.mjs, not committed`
along with the old `src-tauri/models/` entry at the bottom of the file.

- [ ] **Step 5: Update `.claude/launch.json`**

```json
{
  "version": "0.0.1",
  "configurations": [
    {
      "name": "netrelish-frontend",
      "runtimeExecutable": "npm",
      "runtimeArgs": ["run", "dev", "-w", "@netrelish/desktop"],
      "port": 5273
    }
  ]
}
```

- [ ] **Step 6: Reinstall so npm links the workspace**

Run: `rm -rf node_modules && npm install`
Expected: completes, and `node_modules/@netrelish/desktop` exists as a
symlink to `apps/desktop`.

Verify: `ls -l node_modules/@netrelish/`
Expected: `desktop -> ../../apps/desktop`

- [ ] **Step 7: Confirm the build is fixed**

Run: `npm run typecheck`
Expected: PASS, no output (tsc is silent on success).

- [ ] **Step 8: Confirm the model script still resolves**

`ensure-model.mjs` computes `root = dirname(dirname(__file__))`, which is now
`apps/desktop` — so `join(root, "src-tauri", "models")` still lands correctly.

Run: `node apps/desktop/scripts/ensure-model.mjs`
Expected: either downloads, or prints nothing and exits 0 because both files
already exist at `apps/desktop/src-tauri/models/`.

Verify: `ls -la apps/desktop/src-tauri/models/`
Expected: `all-MiniLM-L6-v2.onnx` (≥80MB) and `tokenizer.json`.

- [ ] **Step 9: Confirm Rust still builds**

Run: `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`
Expected: `Finished` with no errors. Warnings are acceptable.

If `cargo` is not on PATH, run `export PATH="$HOME/.cargo/bin:$PATH"` first.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "$(cat <<'MSG'
build(repo): npm workspaces — root delegates, desktop owns its deps

Root package.json becomes a workspaces root; apps/desktop gets its own
manifest. .gitignore's src-tauri/ patterns were root-anchored and had
silently stopped matching after the move — re-anchored to apps/desktop.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: Update CI for the new paths

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `docs/RELEASING.md` (paths only; the notarization status is Task 8)

- [ ] **Step 1: Point the Rust cache at the new workspace**

In `.github/workflows/release.yml`, find:

```yaml
      - uses: swatinem/rust-cache@v2
        with:
          workspaces: ./src-tauri -> target
```

Replace with:

```yaml
      - uses: swatinem/rust-cache@v2
        with:
          workspaces: ./apps/desktop/src-tauri -> target
```

- [ ] **Step 2: Tell tauri-action where the app lives**

In the same file, find the `with:` block of the `tauri-apps/tauri-action@v0`
step:

```yaml
        with:
          args: --target aarch64-apple-darwin
```

Replace with:

```yaml
        with:
          projectPath: apps/desktop
          args: --target aarch64-apple-darwin
```

Leave `npm ci` as-is: it runs at the root and installs every workspace, which
is what we want.

- [ ] **Step 3: Update paths in RELEASING.md**

Replace every occurrence of `src-tauri/tauri.conf.json` with
`apps/desktop/src-tauri/tauri.conf.json`, and `~/.tauri/` references stay as
they are (those are home-directory paths, not repo paths).

Run to find them: `grep -n "src-tauri" docs/RELEASING.md`
Expected after editing: every hit is prefixed `apps/desktop/`.

- [ ] **Step 4: Validate the workflow file parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')"`
Expected: `yaml ok`

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml docs/RELEASING.md
git commit -m "$(cat <<'MSG'
ci(release): follow the app to apps/desktop

rust-cache workspace path and tauri-action projectPath. npm ci stays at
the root — it installs every workspace.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 7: Prove the whole thing still builds

The load-bearing verification. Everything before this was necessary; this is
what says it worked.

**Files:** none — verification only.

- [ ] **Step 1: Clean typecheck from the root**

Run: `npm run typecheck`
Expected: PASS, silent.

- [ ] **Step 2: Full release build**

Run: `export PATH="$HOME/.cargo/bin:$PATH" && npm run app:build`
Expected: Vite builds to `apps/desktop/dist`, cargo compiles, and the run
ends with a bundling line naming a `.app` and a `.dmg`.

This takes several minutes on a cold Rust cache. If it fails at the very
last step with *"A public key has been found, but no private key"*, that is
expected and harmless — it means the bundles built and only the updater
signature was skipped. To include it:
`export TAURI_SIGNING_PRIVATE_KEY="$(cat ~/.tauri/netrelish.key)"`.

- [ ] **Step 3: Confirm the app exists**

Run: `ls -la apps/desktop/src-tauri/target/release/bundle/macos/`
Expected: `NetRelish.app`.

- [ ] **Step 4: Confirm nothing untracked leaked into git**

Run: `git status --porcelain`
Expected: empty. If `apps/desktop/src-tauri/target/` or `models/` show up,
Task 5 Step 4's `.gitignore` fix is wrong — go back and fix the anchoring.

- [ ] **Step 5: Launch it once**

Run: `open apps/desktop/src-tauri/target/release/bundle/macos/NetRelish.app`
Expected: the window opens on the Aurora with the sidebar and titlebar. Load
a page to confirm the native pane still works. Quit when satisfied.

- [ ] **Step 6: Tag the checkpoint**

```bash
git tag p0-monorepo-verified
```

No commit — this task changed no files. The tag marks the last commit as the
one where the monorepo was proven to build.

---

### Task 8: Clear the notarization blocker

**This task cannot be completed without Ryan.** Apple only issues
app-specific passwords to the account holder, interactively, at
appleid.apple.com. Do not attempt to work around it.

**Files:**
- Modify: `docs/RELEASING.md` (status section, once proven)

- [ ] **Step 1: Confirm the blocker is still real**

Run: `gh run list --workflow=release.yml --limit 5`
Expected: the most recent run shows `failure`. Confirm the cause:

Run: `gh run view --log-failed --job $(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId') 2>&1 | grep -i "notariz\|401" | head`
Expected: `HTTP status code: 401. Invalid credentials.`

If this now passes, skip to Step 5.

- [ ] **Step 2: Confirm which Apple ID the secret should authenticate**

The Apple ID is `ryanshepherd93@gmail.com`, **not** `ryan@shepdesign.com` —
a previous run failed with "account does not exist" because of exactly this.

Run: `gh secret list | grep APPLE`
Expected: `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`,
`APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`
all listed. Presence proves nothing about validity — that mistake has
already been made once on this repo.

- [ ] **Step 3: Ask Ryan for a fresh app-specific password**

Give them exactly this, and stop until they respond:

> Go to **appleid.apple.com** → sign in as **ryanshepherd93@gmail.com** →
> **Sign-In and Security** → **App-Specific Passwords** → **+** → name it
> `NetRelish CI` → copy the password (format `abcd-efgh-ijkl-mnop`).
>
> Paste it here and I'll set the secret, or run this yourself so it never
> touches the chat:
>
> ```bash
> gh secret set APPLE_PASSWORD --repo Shepdesign/NetRelish
> ```
>
> That command prompts for the value, so it stays out of shell history.

- [ ] **Step 4: Set the secret**

Only if Ryan supplied the value rather than running it themselves:

```bash
gh secret set APPLE_PASSWORD --repo Shepdesign/NetRelish --body '<value>'
```

- [ ] **Step 5: Re-run the release**

Tag events trigger unpredictably on this repo — use `workflow_dispatch`:

```bash
gh workflow run release.yml --ref main
```

Then watch: `gh run watch $(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')`

Expected: the run reaches and passes the notarize + staple steps.

- [ ] **Step 6: Verify the artifact is genuinely notarized**

Download the `.dmg` from the draft release, mount it, and check the app:

```bash
spctl -a -vvv -t install /Volumes/NetRelish/NetRelish.app
```

Expected: `accepted`, `source=Notarized Developer ID`.

Also confirm the ticket is stapled (works with no network):

```bash
xcrun stapler validate /Volumes/NetRelish/NetRelish.app
```

Expected: `The validate action worked!`

- [ ] **Step 7: Mark it proven in RELEASING.md**

Replace the block beginning `**⚠️ Notarization is NOT yet proven.` and ending
at the line before `Signing material backed up in iCloud Drive` with:

```markdown
**Notarization is proven.** Verified <DATE>: the CI run notarized and
stapled, and the shipped `.app` passes `spctl -a -t install` as
"Notarized Developer ID" with a stapled ticket that validates offline.

The earlier 401 was `APPLE_PASSWORD` holding a normal Apple ID password
rather than an app-specific one. Two lessons worth keeping: a secret
existing is not a secret working, and notarization authenticates over a
*different* credential path from signing — a build can sign perfectly and
still be refused. The Apple ID is `ryanshepherd93@gmail.com`.
```

Replace `<DATE>` with the actual date of the successful run.

- [ ] **Step 8: Commit**

```bash
git add docs/RELEASING.md
git commit -m "$(cat <<'MSG'
docs(releasing): notarization proven — the app ships

A fresh app-specific password cleared the 401. The stapled .app passes
spctl as Notarized Developer ID and validates offline.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

## Carried forward — not P0's job

Found during the Tasks 1–3 review, real, and deliberately out of scope here:

- **`site/index.html` still promises "Everything is local. Everything." /
  "No account · No cloud · No telemetry."** This is not false *today* — the
  shipped v0.1.0 genuinely has no account and no cloud — but it becomes false
  the moment P2 or P4 ships. Rewriting live marketing copy is a brand decision
  and Ryan's call, not a side effect of a constitution task. **Must be settled
  before P2 ships.**
- **§8 says the engine has "Four layers, all on-device".** P5 adds a fifth
  that is hosted. §8 gains that layer when P5 starts, not before.
- **Path convention in CLAUDE.md.** §5 and §9 use bare `src-tauri/`; §14 uses
  `apps/desktop/src-tauri/`. Task 4's move makes §14 correct; §5 and §9 are
  scoped by the note added under §5's Storage subsection. Revisit only if that
  note proves too subtle.

---

## Done when

- [ ] CLAUDE.md contains no sentence asserting that nothing leaves the machine, and §4a bounds what does.
- [ ] `grep -rn "no account\|no server\|no sync\|No cloud" README.md docs/ROADMAP.md` returns only deliberate historical references.
- [ ] `npm run typecheck` passes from the repo root.
- [ ] `npm run app:build` produces `apps/desktop/src-tauri/target/release/bundle/macos/NetRelish.app`, and the app launches and loads a page.
- [ ] `git status --porcelain` is empty after a full build.
- [ ] A CI run passes notarize + staple, and the shipped `.app` reports `source=Notarized Developer ID`.
