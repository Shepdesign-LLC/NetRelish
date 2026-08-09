# Roadmap

Eight weeks to a browser worth using daily. Each week has a **demo** — the one
thing you can show someone at the end of it. If the demo doesn't work, the
week isn't done, regardless of what's committed.

Build weeks in order. Later weeks read from schema decisions made in earlier
ones; skipping ahead means migrations.

---

## Week 1 — Shell ✅

**Demo:** a signed, notarized NetRelish.app opens google.com in a native pane.

- [x] Tauri v2 + Vite + React + TypeScript
- [x] macOS window: overlay titlebar, hidden title, 13.0 minimum
- [x] Hardened runtime entitlements (JIT, network client, user-selected files)
- [x] Native child WKWebView via `Window::add_child`
- [x] `ResizeObserver` → `preview_set_bounds` hole tracking
- [x] Shelf rail with superellipse tiles
- [x] GitHub Actions: build → sign → notarize → staple → draft release

**Do first, outside the repo:** enrol in the Apple Developer Program. $99/yr,
24–48h approval, and every signing step is blocked behind it.

---

## Week 2 — Brine

**Demo:** browse for ten minutes, then find any page you visited by typing a
phrase from its body text. Offline.

- [ ] `tauri-plugin-sql` wired, database at the app support path
- [ ] Migration `001_init.sql` — full schema from `CLAUDE.md`
- [ ] `src/lib/db.ts` — the only module that writes SQL
- [ ] Content script injection on preview navigation
- [ ] Readability extraction → `items` with `kind='page'`, `jar_id = NULL`
- [ ] `items_fts` triggers on insert/update/delete
- [ ] Deny list (user-editable) for URLs never extracted
- [ ] Brine surface: reverse-chronological list, title + domain + snippet
- [ ] Click a Brine row → reopens in the preview pane

**Acceptance**

- Extraction under 50ms p95, never blocks paint
- 1,000 items → FTS query under 10ms
- Quit mid-navigation, relaunch, nothing corrupt or missing
- Nothing leaves the machine — verify with Little Snitch or `lsof -i`

**Watch for:** FTS5 external-content tables need all three triggers or the
index silently drifts out of sync with `items`.

---

## Week 3 — Jars

**Demo:** create a jar, browse into it, `⌘J` a page from Brine into it, switch
jars and watch the window change.

- [ ] Jar CRUD, hue assigned round-robin from `--nr-jar-1..6`
- [ ] Shelf rail renders real jars with live item counts
- [ ] Active-jar state — new pages extract with that `jar_id`
- [ ] `⌘J` — jar the current page
- [ ] `⌘J` on a Brine selection — multi-select, jar as a **Batch**
- [ ] Jar view: items grouped by kind, newest first
- [ ] Move an item between jars; move back to Brine
- [ ] Jar chip in the titlebar shows the active jar

**Acceptance**

- Jar switch under 100ms with 5,000 items
- Deleting a jar sends its items to Brine, never deletes them
- Every action reachable by keyboard

---

## Week 4 — Ask the Pantry

**Demo:** `⌘K`, type a half-remembered phrase, land on the exact page — and
see the web fallback sitting below it, not above.

- [ ] `⌘K` palette over the stage (sibling of `.nr-stage`, not a child)
- [ ] Results ranked: active jar → other jars → Brine → web
- [ ] Results as you type, debounced 80ms
- [ ] Filters: `jar:name`, `kind:page`, `is:sealed`, `since:7d`
- [ ] Snippet highlighting from FTS5 `snippet()`
- [ ] Enter opens; `⌘Enter` opens without leaving the palette
- [ ] Empty state explains the syntax rather than apologizing

**Acceptance**

- First keystroke to first result under 50ms at 10,000 items
- Web results never rank above a local match
- Escape always closes and never loses typed input on reopen

---

## Week 5 — Sealing

**Demo:** leave tabs open for three days. They preserve themselves and close.
Reopen one from its jar exactly as it was.

- [ ] `tabs` table tracking `touched_at` and `seal_after`
- [ ] Per-jar shelf life; default 3 days, pinned tabs never seal
- [ ] Background sweep on launch and hourly
- [ ] Seal = ensure extracted → set `sealed_at` → close the tab
- [ ] Reopen from jar restores URL and scroll position
- [ ] **Batch** view — everything sealed in one sweep, undoable for 24h
- [ ] Toast: "Sealed 12 tabs into Meridian Rebuild" → Undo

**Acceptance**

- No tab ever closes without its content being in `items` first
- Undo restores every tab in the batch, open, in order
- Sweeping 200 tabs never freezes the UI

**This is the feature that gets screenshotted.** Make the animation good and
make Undo genuinely reliable.

---

## Week 6 — The engine

**Demo:** open a jar. It says *"9 things in Brine look like they belong here."*
It's right about most of them.

- [ ] ONNX embedding model bundled, `ort` crate, Apple Silicon
- [ ] `sqlite-vec` extension loaded
- [ ] Embed on extraction, backfill existing items in the background
- [ ] Session detection — time window + referrer chains
- [ ] Entity extraction — domains, `[A-Z]{2,6}-\d+`, repo paths
- [ ] Suggestion surface in the jar header, one key to accept all
- [ ] Rejections weighted into future scoring
- [ ] Semantic results merged into `⌘K` behind exact matches

**Acceptance**

- Embedding under 200ms per item, off the UI thread
- Backfill is resumable and survives quit
- Suggestions are never applied without approval
- Model adds no more than ~120MB to the bundle

---

## Week 7 — Recipes

**Demo:** run a saved recipe. Four tabs open in the right layout, it walks you
through three steps, output lands back in the jar.

- [ ] `recipes` table, JSON steps
- [ ] Recorder — work normally, "Save as Recipe", steps reconstructed
- [ ] Step kinds: `open`, `split`, `task`, `note`, `collect`, `seal`
- [ ] Runner UI — current step, skip, back, finish
- [ ] `{{date}}`, `{{jar}}`, `{{url}}` interpolation
- [ ] `⌘R` — run a recipe in the active jar
- [ ] Split layout with synced scroll (needed by `split`)

**Acceptance**

- A recorded recipe replays to the same end state
- Cancelling mid-run leaves no orphan tabs or half-written items
- Recipe JSON is readable and hand-editable

---

## Week 8 — Notes, tasks, polish

**Demo:** a jar holding tabs, notes, tasks and files, all searchable together,
on a machine that has never been online.

- [ ] In-jar notes, markdown, `kind='note'`
- [ ] Tasks with due dates, `kind='task'`
- [ ] Drag a local file into a jar → `kind='file'`, path watched
- [ ] Labels: create, assign, filter
- [ ] Full keyboard map + shortcut sheet
- [ ] Light theme parity pass
- [ ] Updater live, first public build

---

## Not in v1

Deliberately cut. Each is a week or more, none is on the critical path.

| | Why not now |
| :-- | :-- |
| Email (`kind='message'`) | Schema already supports it. Gmail API needs Google's security review — money and a month of calendar. Start with IMAP, after launch. |
| Cloud sync | Needs an account system and a server. Kills the local-only promise if done carelessly. |
| iOS | App Store only, and Guideline 2.5.6 forces WKWebView. Ship a PWA companion instead, after Mac lands. |
| Sharing / teams | Different product. Revisit at 1,000 users. |
| Billing | Free during beta. Gate after there's something worth paying for. |
| Extensions | Enormous surface area. Never, probably. |
| Windows / Linux | Different webview, different signing, different bugs. Not until Mac is loved. |

---

## Order-of-operations warnings

- **Apple Developer enrolment blocks everything.** Start it today.
- **Back up the updater private key.** Lose it and you can never push an
  update to an installed copy. There is no recovery.
- **Week 2's schema is load-bearing.** Weeks 3–8 all read from `items`.
  Changing `kind` or the FTS setup later means a migration on real user data.
- **Never seal before extracting.** A sealed tab whose content didn't make it
  into `items` is exactly the data loss the whole product promises to prevent.
