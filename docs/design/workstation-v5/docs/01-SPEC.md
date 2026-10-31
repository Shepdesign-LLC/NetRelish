---
title: NetRelish Workstation — UI/UX master spec
version: 3.0
updated: 2026-10-28
audience: Claude Code / implementation
status: ready to build
supersedes: NETRELISH-UI-SPEC.md v2.0 (2026-09-23)
---

# NetRelish Workstation — UI/UX master spec

The build sheet for the workstation shell. Matches `prototype/netrelish-workstation.html` (v5) exactly. Open the prototype alongside this document. Where the two disagree, **this document wins** — but check the prototype first, because it is usually right.

---

## 0. The one-paragraph model

NetRelish is a browser whose unit of organization is a **jar**. A jar is a project: it holds **tabs** and **notes**, it has a name, a color and a capacity, and it fills with relish as you put things in it. Open a jar and its tabs come back. **Dev mode** is a switch that turns the right panel into a workbench for local WordPress copies; with it off, NetRelish is a normal browser. **Zest** is a line of small tools docked in the shelf that read from the same brand.

Everything the user can see, they can rearrange. Nothing requires a terminal.

---

## 1. Vocabulary

Use these words in code, in the UI, and in support docs. Never mix in synonyms. Variable names, CSS classes and component names use the left column.

| Term | Means | Never call it |
|---|---|---|
| **Jar** | A project. Holds tabs and notes. | Folder, space, workspace, collection |
| **Note** | User-written text inside a jar. | Doc, memo, card |
| **Tab** | An open website. | Page, link, site |
| **Keep** | Put the current tab into the active jar. | Bookmark, save |
| **Seal** | Finish a jar; preserve it as-is. | Close, archive, lock |
| **Brine** | The tray of tabs that aged out. | Trash, history |
| **Fill** | How full a jar is (items ÷ capacity). | Progress, usage |
| **Dev** | The switch that turns the right panel into the workbench. | Developer tools, inspector, console |
| **Local copy** | A WordPress site running on this Mac. | Local site, instance, container |
| **Vault** | Keychain-backed store for keys, licenses, passwords. | Secrets, credentials manager |
| **Bench** | The main content area. | Canvas, viewport, content |
| **Shelf** | The left sidebar. Always open. | Sidebar, nav, drawer |
| **Panel** | The right column. | Inspector, sidebar |
| **Guide** | An explainer page that opens in the bench. | Help, docs, tooltip |

---

## 2. Data model

```ts
type ColorKey = 'relish' | 'amber' | 'sky' | 'rose' | 'violet' | 'teal';

interface Jar {
  id: string;
  name: string;
  color: ColorKey;
  cap: number;             // 4–60, default 12
  order: number;           // shelf position
  sealed?: boolean;        // sealed jars are read-only until reopened
  sealedAt?: number;
  notes: Note[];
  tabs: Tab[];
}

interface Note {
  id: string;
  title: string;
  body: string;            // plain text, \n separated
  at: number;              // epoch ms, updated on every edit
  order: number;
  archivedAt?: number;
}

interface Tab {
  id: string;
  jarId: string;
  group?: string;          // optional label, e.g. a client name
  title: string;
  url: string;
  host: string;
  fav: string;             // single character fallback
  icon?: IconKey;          // user-chosen glyph, overrides fav (see 6.2)
  kind: 'live' | 'host' | 'local';
  pinned: boolean;
  locked: boolean;         // cannot be closed while true
  order: number;
  lastSeen: number;
}

type IconKey =
  | 'globe' | 'cart' | 'mail' | 'image' | 'code'
  | 'doc'   | 'chart'| 'play' | 'wrench';

interface LocalSite {        // only surfaced in Dev
  id: string;
  jarId?: string;
  name: string;
  domain: string;            // *.local
  running: boolean;
  php: string;
  wp: string;
  webServer: 'Apache' | 'nginx';
  sslTrusted: boolean;
  path: string;              // on disk
  plugins: Plugin[];
}

interface Plugin {
  id: string;
  name: string;
  slug: string;              // shown in mono under the name
  version: string;
  active: boolean;
}

interface VaultItem {
  id: string;
  label: string;             // "Bento API key"
  jarId?: string;
  masked: string;            // what renders until revealed: "•••• 4f2a"
  // the value itself NEVER lives in app state — see 6.7
}

interface Profile {
  id: string;
  name: string;
  sub: string;               // email
  av: string;                // 1–2 initials
  avatarUrl?: string;        // user-uploaded, replaces initials
  appleId?: string;          // from the signed-in system account
  jarIds: string[];          // profiles do not share jars
}
```

**Fill** = `(jar.notes.length + jar.tabs.length) / jar.cap`, clamped 0–1.
**Capacity is a soft limit.** Exceeding it never blocks anything; it shows the jar as full and offers the seal.

**Persistence.** Local-first. SQLite (or Core Data) on the Mac; nothing leaves the machine unless the user signs into sync. Notes autosave on every keystroke, debounced 300ms. Vault values go to Keychain, never to the app database.

---

## 3. Design tokens

**`design/tokens.css` is the source of truth.** It carries the full ramp, both themes, the six jar pairs, the duration ladder, the reduced-motion block and the focus ring. Import it first; do not restate values in component CSS.

The one rule worth repeating here: **`--jc`** is the active jar's face color, set on `:root` whenever the jar changes. Every accent in the window derives from it with `color-mix(in oklch, var(--jc) N%, transparent)`. One variable re-skins the app. Hard-coding a jar color anywhere is a bug.

### 3.1 Type scale

Display `Bricolage Grotesque` 500/600/700 — headings only.
Body `-apple-system / SF Pro Text` — everything else.
Mono `SF Mono` — plugin slugs, vault values, domains in dev cards. Nowhere else.

| Role | Size / line | Weight |
|---|---|---|
| Board title | 30 / 1.1, `-.025em` | 600 display |
| Guide title | 34 / 1.1, `-.025em` | 600 display |
| Note page title | 32, `-.025em` | 600 display |
| Note title | 15.5 / 1.3 | 600 body |
| Section head | 15 | 600 body, `--ink-2` |
| Section label (shelf) | 12.5, `.02em` | 600 body, `--ink-2` |
| Body | 15 / 1.5 | 400 |
| Note page body | 16.5 / 1.75 | 400 |
| Guide body | 16 / 1.7, max `66ch` | 400, `--ink-2` |
| Caption, timestamp | 12–12.5 | 400, `--ink-3` |

### 3.2 Metrics

Radii `9 / 11 / 12 / 18 / 24 / 999`.

| Thing | Size |
|---|---|
| Titlebar row | **48** |
| Search row | **46** |
| Bottom bar | **44** |
| Shelf | **238** |
| Right panel | **322** |
| Shelf rows | 44 |
| Section-label buttons | 36 |
| Tabs | 34 tall × **176** wide, pinned 46 |
| Controls (buttons, omnibox) | 30–36 |
| Window | min 1120 × 640; `min(1580px, 100%)` × `min(980px, 100dvh − 48px)` |

---

## 4. The jar, drawn

The jar is rendered live as SVG, never a static asset, because the fill level is data. **The same code renders the jars on the beta page** — keep one implementation.

**Geometry** — viewBox `0 0 22 26`:

```
body  M4.6 7.6 C4.6 6.3 5.7 5.2 7 5.2 h8 C16.3 5.2 17.4 6.3 17.4 7.6
      v11.6 a3.4 3.4 0 0 1 -3.4 3.4 h-6 a3.4 3.4 0 0 1 -3.4 -3.4 z
lid   rect x=5.4 y=1.5 w=11.2 h=3.6 rx=1.3   fill currentColor @ .75
```

**Layer order, bottom to top. All six, in this order:**

1. Body path, `currentColor` at 8% — the empty glass.
2. Relish fill, clipped to the body. A rect from `y = 22.6 − (17.4 × fill)` to the bottom, filled with a vertical gradient face→base. An ellipse at the surface (`rx 6.5, ry .9`, face at 85%) gives it a meniscus.
3. At fill ≥ 1, two small white circles at 30% and 22% — bubbles. Only when full.
4. Specular pass: the body path filled with a horizontal gradient, white .42 → transparent at 35% → transparent at 85% → white .16. **This is what gives the jar depth. Do not skip it.**
5. Body path stroked in `currentColor` at 55%, 1.15 width.
6. Lid, plus a small white rounded rect at 28% for the lid's own highlight.

`currentColor` is the jar's **base** color, so glass, outline and lid tint together.

Sizes in use: **19** (tab-strip chip), **24** (shelf row), **40** (page header), **54** (board header). Below 19, drop to the plain outline glyph.

Every jar SVG carries `filter: drop-shadow(0 1px 2px oklch(0 0 0/.2))`.

---

## 5. Layout

Four rows. The shelf is **locked open** — there is no shelf toggle, and the cog mark sits where the toggle used to be.

```
┌─────────────────────────────────────────────────────────────────┐
│ 48  ◉◉◉  ‹  ⚙mark │ [jar chip][tab][tab][tab][+]                │  glass
├─────────────────────────────────────────────────────────────────┤
│ 46  [⌕ ───────────── omnibox, full width ─────────────] Dev◉ ☼ (RS) │  2px relish top border
├──────────┬────────────────────────────────┬─────────────────────┤
│ shelf    │ bench                          │ panel 322           │
│ 238      │ container-type: inline-size    │                     │
│          │                                │ Dev OFF → context:  │
│ ▣ JARS ⓘ │ jar board / note page /        │   actions, settings,│
│   rows   │ guide page / zest tool         │   quick note, recent│
│ ▣ ZEST ⓘ │                                │ Dev ON  → workbench │
│   rows   │                                │   (6.7)             │
├──────────┴────────────────────────────────┴─────────────────────┤
│ 44  [🫙 Brine 3]                                   ⌘  2:14 AM   │  frost
└─────────────────────────────────────────────────────────────────┘
```

```css
.win  { grid-template-rows: 48px 46px 1fr 44px }
.body { grid-template-columns: 238px 1fr 322px }
.win[data-panel="off"] .body { grid-template-columns: 238px 1fr 0 }
```

The right panel is the only collapsible column. Below 1100px it auto-hides.

A 1px specular line runs the top edge of the window (`.win::before`). Keep it; it is what makes the window read as a physical object rather than a div.

---

## 6. Components

### 6.1 Titlebar (row 1)

Traffic lights → back → **cog mark** → tab strip. That is the whole row. No address bar here (it moved to row 2), no shelf toggle (the shelf never closes).

- **Traffic lights** are gray at rest and only take their colors on `.win:hover`. This is the macOS behavior and it matters.
- **The cog mark** is the real NetRelish logo, inlined from `assets/netrelish-mark.svg`, 32px, transparent, **no plate or rounded square behind it**. Hover scales 1.08 and adds `--line-2`. It is a button: clicking it opens the Jars guide.
  - The SVG's gradient IDs are namespaced `nr-g`, `nr-gGloss`, `nr-gGearSteel`, `nr-gHoleSteel`, `nr-gGoop`. **Keep the namespace** — unprefixed IDs collide with the jar gradients and the mark renders as flat gray.
- Glass: `backdrop-filter: blur(34px) saturate(190%)`. The saturate is mandatory — without it, translucency reads as gray mud.

### 6.2 Tab strip

Tabs must **always be visible against the chrome**. Never let them blend in.

- Leads with the **jar chip**: the jar's filled icon at 19px plus its name, tinted `color-mix(in oklch, var(--jc) 20%, transparent)`. Click returns to the board. Right-click opens the jar menu.
- Tabs are a fixed **176px**, never elastic. Pinned tabs are **46px**, icon only, sorted to the front.
- **Every tab, selected or not, has a 1px border, a `--pane-2` fill, `--tab-sh` shadow, and a 1px gloss line across its top.** This is the "chunky, not terminal" requirement.
- Selected tab: `--win` background, border in `--jc`, a heavier shadow, and a 2px bar in `--jc` along the bottom edge (inset 9px each side).
- Locked tabs show a padlock and **have no close button in the DOM** — not a disabled one, none.
- Close button appears on hover only.
- The **icon chip** is 19px. By default it is the first letter on `--pane-3`. If `tab.icon` is set, it renders that glyph with no background. Users pick from a **9-icon row in the tab context menu**: globe, cart, mail, image, code, doc, chart, play, wrench.

### 6.3 Search row (row 2)

Full width, below the tabs, and visibly relish.

- `border-top: 2px solid var(--relish-500)` plus a 14px relish-tinted gradient wash fading down. This is the "put some relish in the search bar" requirement — the row itself is the brand element, not the input.
- **Omnibox** fills the row: 32px tall, `--win` fill, inset top shadow, a relish link glyph on the left, and action buttons on the right that take `--relish-100` on hover. Focus: relish border + 4px relish glow ring.
- **Dev switch** sits right of the omnibox: a real pill switch with a track and a knob, labeled "Dev". On: `--relish-100` fill, relish border, relish-800 text, knob translated 13px.
- Then the appearance toggle, then the **avatar** (32px circle, initials on `--relish-100`, or the user's uploaded image).

### 6.4 Shelf

Order is fixed: **JARS** → **ZEST**. Jars are always first. Nothing goes above them. Local copies do **not** get a shelf section — they live in the Dev panel.

**Section labels are buttons, not text.** 36px tall, gradient `--pane-2` → `--pane-3`, 1px border, outer shadow plus inset gloss. Each carries:
- an 18px **glyph tile** on the left, filled with that section's color (relish for Jars, relish for Zest) and holding the parent icon in white;
- the label;
- an **info button** on the right that opens that section's **guide page** in the bench.

Hover: border goes relish, the row lifts 1px, the info icon goes relish.

**Jar row:** filled jar icon 24, name, `n/cap` count. Active row gets `color-mix(in oklch, var(--jc) 15%, transparent)`. A full jar gets a pulsing 7px relish dot, top right, 2.2s cycle.

Rows are `draggable` for reorder and are drop targets for tabs.

### 6.5 Jar board (default bench view)

1. **Header** — jar icon 54, name, "N notes · M tabs", **Open all**, **New note**.
2. **Fill bar** — 300px max, gradient `--jc` → 70% mixed with black, inset gloss, with "10 of 14 — 71% full".
3. **Seal banner**, only at fill ≥ 1 — "This jar is full." with a **Seal jar** button and a note that capacity can be raised instead.
4. **Notes** — cards in `repeat(auto-fill, minmax(252px, 1fr))`, draggable to reorder. Under a 700px container, one column.
5. **Tab groups** — one section per `group` value, each with a count. Local tabs are filtered out entirely when Dev is off; a group whose tabs are all local renders nothing.

**Note card:** color dot (jar color, 11px, radius 4, with a shadow and an inset gloss) + title, 120-char body preview, clock icon + relative timestamp. Hover lifts 3px and borders in `--jc`.

**Tab tile:** 34px icon chip, title, host, then pin and lock marks, then a kind tag — "account" for hosts, a running dot for locals.

### 6.6 Right panel — Dev OFF

Contextual. For a jar: actions, **jar settings** (name field, capacity field, six-swatch color row), **quick note**, recent notes with color dots and timestamps, and a **Send to Zest** block pinned to the bottom (`margin-top: auto`).

Quick note is `contenteditable="plaintext-only"` with a `data-ph` placeholder via `:empty::before`. One button commits it; the first line becomes the title.

### 6.7 Right panel — Dev ON (the workbench)

**The Dev switch does not open a drawer.** It replaces the contents of the right panel. Nothing moves, nothing slides up from the bottom, the layout does not reflow.

Top to bottom:

1. **Dev head** — a relish-tinted gradient band: a live status dot, "Local copies", and a line of plain-language status. Example: *"juniperbakery.example is running — WordPress 7.1, PHP 8.4."*
2. **Site card** — name, `domain · WordPress 7.1 · PHP 8.4`, **Start / Stop**, Settings.
3. **Action gallery** — a 2×3 grid of raised cells, each with a relish icon tile, a bold label and a one-line description. Open the site · Open the dashboard · Open the files · Caught mail · Back up · Copy to live.
4. **Plugins** — one row per plugin: icon, name, slug in mono, version, and a **ZIP** button that exports it.
5. **Vault** — amber lock banner first: *"Locked. Touch ID to reveal."* Then rows of `label · masked value · reveal · copy`. Values come from Keychain on demand and are **never held in app state, never logged, never written to the database.** Reveal requires Touch ID every time; the revealed value clears on blur.

**Never ship anywhere in Dev:** a terminal, WP-CLI, SQL, a network waterfall, log tails, or the words *webhook*, *endpoint*, *CLI*, *stdout*. Severity is a word plus a dot, never a dot alone.

### 6.8 Guide pages

Section-label info buttons open full bench pages. Two exist: `GUIDES.jars` and `GUIDES.zest`. They are product education, not tooltips, and they are part of the product — a new user should be able to learn the whole model from them.

Structure: a header with a 52px colored glyph tile, title and subtitle; prose at 16/1.7 capped at 66ch; **is / isn't card pairs** (relish border for "is", rose heading for "isn't"); **numbered step rows** with a relish number tile.

`.gcard h3 svg` must carry `width:16px; height:16px; fill:none; stroke:currentColor; stroke-width:2.4`. Without an explicit size and stroke rule, check and × glyphs render as giant filled paths.

**Jars guide** covers: what a jar is and isn't, the five-step workflow, why the limit exists, what the brine is.
**Zest guide** covers: the tool line-up, and the rule — *Zest composes. It doesn't generate.*

### 6.9 Bottom bar and Brine

44px, frost — the only frost in the app: `blur(40px) saturate(200%)`.

**Brine is a button, not a tray.** Left side: a pill with a jar glyph, the word "Brine", and a count badge. When there are tabs in it, the pill takes `.glow` — relish border, `--relish-100` fill, relish-800 text, and a 2.6s pulsing ring. That glow is the whole notification mechanism.

Clicking opens a **modal** listing each brined tab as a row. Each row is draggable onto a jar in the shelf, and each row also carries **four jar buttons** for a one-click move. Right side of the bar: command hint and the clock.

---

## 7. Interactions

### 7.1 Context menus

Right-click is a first-class input. Every menu is a `popover` with the glass material and a 150ms scale-in from `.96`.

**Jar** — Rename · *color swatch row (6)* · Open all tabs · New note here · Change how much it holds · Seal jar · Duplicate · **Archive jar**

**Tab** — Pin / Unpin · Lock / Unlock · *icon picker row (9)* · Copy link · Write a note about this · Move to *(three other jars)* · **Close tab** *(reads "Locked — unlock first" and does nothing when locked)*

**Note** — Edit · Rename · Duplicate · Move to *(three other jars)* · Send to Zest MD · **Archive note**

Destructive items are last, red on hover, and **archive, never delete**. Every archive shows a toast with **Undo** for 6 seconds.

### 7.2 Drag

| Drag | Onto | Result |
|---|---|---|
| Note | Another note | Reorder within the jar |
| Tab | Jar row in shelf | Move to that jar |
| Tab | Another tab or tile | Reorder |
| Jar row | Another jar row | Reorder the shelf |
| Brine row | Jar row in shelf | Restore into that jar |

Dragged element goes to 40% opacity; the drop target shows a 3px inset bar in relish. All drops run inside `startViewTransition`.

### 7.3 The Seal

900ms, one curve. The source element's ghost lifts, translates and scales to the jar row, fading to 12% and rounding to 60px; the jar row pulses 1 → 1.06 → 1 over 340ms on arrival; a toast confirms. Under `prefers-reduced-motion` the whole thing collapses to 160ms.

### 7.4 Keyboard

| Keys | Does |
|---|---|
| ⌘K | Command palette |
| ⌘L | Focus the omnibox |
| ⌘N | New note in the active jar |
| ⌘1–9 | Jump to jar |
| ⌘⇧D | Dev on/off |
| ⌘⌥I | Right panel |
| ⌘D | Keep this tab in the jar |
| ? | Shortcuts sheet |
| Esc | Close menu, modal or palette |

There is no ⌘\ — the shelf does not close.

Keyboard handlers must bail early when `e.target.isContentEditable || e.target.matches('input')` so typing a note never triggers a shortcut.

### 7.5 Onboarding

One sheet, three cards, shown once and re-openable from the palette. The guide pages (6.8) carry the long version.

1. **A jar is a project** — clients, a build, things to read. Open it and everything comes back.
2. **Write it down** — notes live in the jar. Right-click anything to rename, recolor or move it.
3. **Fill it, then seal it** — jars fill as you add. Full means finished; seal it.

Footer: "You can move anything, anywhere. It's your bench." Button: **Start**.

### 7.6 Profiles

Avatar in the search row. The popover shows, in order:

1. **Signed in with Apple** row, sourced from the system account.
2. **Edit** — name field, email field, and an avatar picker that accepts an image file or falls back to initials. Changes save immediately, no Save button.
3. The profile list.
4. "Add a profile — its own jars and history."

Profiles do not share jars, tabs, notes, or history.

---

## 8. Platform techniques

Load-bearing. Keep them.

| Technique | Where |
|---|---|
| `backdrop-filter` blur + **saturate(190–210%)** | Titlebar, bottom bar, menus, all sheets |
| View Transitions | Every jar switch, recolor, drag drop, view change |
| `popover` + `@starting-style` | Palette, profile, onboarding, brine modal |
| `:has()` | Panel collapse from button state |
| SVG `clipPath` + gradients | The jar fill and its gloss |
| `color-mix()` in oklch | Every tint derived from `--jc` |
| `contenteditable="plaintext-only"` | Notes — takes typing, never foreign formatting |
| Container queries | Bench reflows on its own width |
| `scroll-timeline` | Reading progress bar, off main thread |
| Native drag and drop | All rearranging |
| `text-wrap: balance` | Headings |
| `overscroll-behavior: contain` | Shelf, bench scroll, panel |

**Accessibility.** Focus ring is 2.5px relish at 2px offset, never removed. Menus are `role="menu"` with arrow-key navigation. Every icon-only control has a `title` and `aria-label`. `prefers-reduced-motion` drops transitions to 120ms and animations to 1ms. Color is never the only signal — locked shows a padlock, running shows a dot *and* a word, problems show a severity word alongside the dot.

---

## 9. Open questions

Not blockers. Build the stated default; these are worth a decision before 1.0.

1. **Capacity: soft or set?** Today the user sets it, which makes the fill meaningful but adds a decision. The alternative is a fixed default of 20 with the bar as a sense of weight. **Build the user-set version** — it's in the prototype — but the mechanic may be more charming when nobody configures it.
2. **"Jar" on day one.** Obvious after the guide page, unknown before it. Worth one round of user testing before the word is locked into marketing.
3. **Sealed jars.** Read-only, or read-only-with-a-prompt-to-reopen? **Build: opening a sealed jar asks once, then unseals.**
4. **Brine expiry.** **Build: 14 days**, with the last 3 days shown in amber.
5. **iOS.** Different app, same objects. Jars as the tab bar, panel as a sheet, Dev reduced to problems and caught mail. Design separately rather than shrinking this. Out of scope for this handoff.
