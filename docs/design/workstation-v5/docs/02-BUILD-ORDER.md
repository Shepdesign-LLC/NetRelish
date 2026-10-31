# Build order

Six phases. Each one ends in something you can open and use. Do not start a phase before the one above it works.

The target is a **macOS app wrapping WKWebView** — Swift shell, web UI. The prototype is the UI, not a mockup of it; most of its CSS is the real CSS.

---

## Phase 1 — The shell

Window chrome, the four-row grid, tab strip, bottom bar. Materials and tokens. No data yet.

- [ ] `design/tokens.css` imported first, before any component CSS
- [ ] `.win` grid: `48px 46px 1fr 44px`, `--shadow`, 18px radius, `isolation: isolate`
- [ ] `.win::before` specular top line
- [ ] Traffic lights gray at rest, colored on `.win:hover`
- [ ] Cog mark inlined from `assets/netrelish-mark.svg`, 32px, no plate, gradient IDs kept namespaced `nr-*`
- [ ] Tab strip with bordered tabs at 176px — a tab must be visible against the chrome with no data in it
- [ ] Search row with the 2px relish top border and the gradient wash
- [ ] Body grid `238px 1fr 322px`, right panel collapsing via `[data-panel="off"]`
- [ ] Bottom bar frost with the Brine pill and the clock

**Done when:** it looks like the prototype with placeholder text and nothing is clickable yet.

---

## Phase 2 — Jars and notes

This is the product. Everything after this is addition.

- [ ] Data model and persistence (SQLite / Core Data)
- [ ] **Jar SVG renderer** — all six layers, fill driven by data. One implementation, shared with the marketing page.
- [ ] `--jc` set on `:root` on every jar change; no hard-coded jar colors anywhere
- [ ] Shelf: section-label buttons with glyph tiles and info buttons, jar rows with live fill and counts
- [ ] Jar board: header, fill bar, notes grid, tab groups
- [ ] Note page with autosave (300ms debounce)
- [ ] Quick note in the right panel
- [ ] Guide pages for Jars and Zest, opened by the section-label info buttons

**Done when:** you can create a jar, put notes in it, watch it fill, and the app is worth using.

---

## Phase 3 — Manipulation

Everything the user can see, they can rearrange.

- [ ] Context menus for jar, tab and note — including the 6-swatch color row and the 9-icon tab picker
- [ ] Archive with a 6-second Undo toast. **Archive, never delete.**
- [ ] Drag and drop in all five directions (spec §7.2), every drop inside `startViewTransition`
- [ ] Jar settings in the right panel: name, capacity, color
- [ ] The Seal — 900ms, one curve, with the reduced-motion collapse

**Done when:** nothing in the UI is fixed in place.

---

## Phase 4 — Dev

The switch and the workbench. Scope creep lives here; resist it.

- [ ] Dev switch replaces the right panel contents. **No drawer. No layout reflow.**
- [ ] Dev head with plain-language status
- [ ] Site card with Start / Stop
- [ ] 6-cell action gallery
- [ ] Plugin list with ZIP export
- [ ] **Vault** — Keychain-backed, Touch ID on every reveal, value never enters app state or the database, clears on blur

**Then the plain-language pass.** Have someone non-technical read every string in this panel out loud. Any sentence they stumble on gets rewritten. No terminal, no WP-CLI, no SQL, no log tails, no *webhook / endpoint / CLI / stdout*.

**Done when:** a non-developer can start a local site, back it up and find an API key without being told how.

---

## Phase 5 — Zest

- [ ] Shelf entries and tool surfaces
- [ ] Brand handoff format (`zest-brand.json`) read by every tool
- [ ] Note → Zest MD
- [ ] Jar → ZestMail
- [ ] Image → ZestImage

**Done when:** a note becomes a formatted document without leaving the jar.

---

## Phase 6 — Polish

- [ ] Onboarding sheet
- [ ] Profiles, including avatar upload and inline name/email editing
- [ ] Command palette (⌘K)
- [ ] Full keyboard map, with the `isContentEditable` bail-out
- [ ] Reduced-motion audit
- [ ] VoiceOver pass — every icon-only control has `title` and `aria-label`

---

## Known traps

Things that already went wrong once.

| Trap | What happens | Fix |
|---|---|---|
| Unprefixed SVG gradient IDs | The mark renders flat gray — its gradients collide with the jar's | Keep `nr-g`, `nr-gGloss`, `nr-gGearSteel`, `nr-gHoleSteel`, `nr-gGoop` |
| Inline SVG with no size rule | Glyphs render as huge filled paths | Every icon context needs an explicit `width/height/fill:none/stroke-width` rule |
| Three-class selectors beating two-class ones | `.empty-state .actions .btn` outranks `.btn.primary` → white-on-white buttons | Specificity, not `!important` |
| `overflow-wrap: anywhere` inherited into tables | Headers break mid-word ("Chro/me") | `overflow-wrap:normal; word-break:normal; min-width:6ch` on cells, `white-space:nowrap` on `th` |
| A theme toggle that cycles auto→light→dark | The first click is invisible on a matching OS theme | Two-way toggle plus a separate Auto/Light/Dark segment |
| `setInterval` clock in a headless test | The DOM never settles; the test hangs to timeout | `process.exit(0)` at the end of every headless test |
| British spellings | Not the house style | **US English only**: color, behavior, organize, recognize, optimize, license, centered, gray, while, among, catalog, canceled |
