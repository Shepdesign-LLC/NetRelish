# NetRelish Design Manifest — v2.1

The single source of truth for the brand and UI across macOS, iOS, and the marketing site. Brand Lock v1.1 is folded in here. Every screen is built from this document, `tokens.css`, and `symbols.svg`. Nothing drifts without a version bump and a changelog line at the bottom.

If an earlier `DESIGN_MANIFEST.md` or `tokens.css` is recovered from the repo or the Sept 15 session, it wins on any token *value* — this consolidated copy is the rules; values were re-derived from the lock.

---

## 1 · Principles

1. **The product is the hero.** Neutral surfaces, system type, hairlines. The brand lives in the mark and the objects, not in color washes.
2. **One accent, and the jar's own color.** Relish appears only in the placements in §4. A jar's color is the user's data and appears only where §4 lists it. Everywhere else is a bug.
3. **Objects, not decoration.** Jars are drawn things you can pick out at a glance. Relish "touches" are small and functional (the Seal glyph, the Sealed pill), never a background.
4. **Apple-friendly, not Apple-generic.** Reads as native at arm's length; unmistakably NetRelish up close.
5. **Fun for hours.** Depth comes from hairlines, layering, and motion — not from glass or noise. No gradients in the product: the jar is drawn flat.
6. **Locked.** The mark, the vocabulary, and this document are final. Propose changes as a versioned PR.

## 2 · The mark

| Asset | Use | Rules |
|---|---|---|
| `logo.svg` — steel gear drowned in relish on a dark-green squircle (superellipse n=5) | App icon, titlebar, About | Never redrawn, recolored, cropped, or stroked. No wordmark needed beside it. |
| `logo-cog.svg` — gear + relish only, squircle removed | Site, onboarding, empty states, About window | Shown larger than the full mark would be. Same rules. |

Clear space: ½ the mark's width on all sides. Minimum size: 16pt (icon), 40pt (cog). The squircle green and gear steel (`--nr-squircle`, `--nr-steel`) exist in tokens **only** so the mark renders from tokens; they are never UI colors.

## 3 · Color

- **Base**: `--nr-bg`, `--nr-surface`, `--nr-surface-2`, `--nr-hairline`, `--nr-fg` ×3. Light is white/near-black; dark is near-black/off-white. No tinted neutrals. `--nr-fg-3` is `#6C6C65` / `#8F8F88` from v2.1: the old values failed AA as text.
- **Workbench neutrals** (v2.1, the art's backdrop and rails), light / dark:

  | Token | Light | Dark | Where |
  |---|---|---|---|
  | `--nr-canvas` | `#F6F6F3` | `#141413` | the jar board, Brine, the palette's scrim |
  | `--nr-rail` | `#FAFAF8` | `#181817` | the Shelf, the Panel, the bottom bar |
  | `--nr-tab` | `#F3F3F0` | `#262624` | a tab behind, the idle address field, the jar chip, hover rows, the selected palette row, the neutral badge |
  | `--nr-tab-hover` | `#EDEDEA` | `#2C2C2A` | a tab behind, under the pointer |
  | `--nr-float` | `#FFFFFF` | `#232321` | cards, the palette box, a jar's glass, the tile's count badge |
  | `--nr-hairline` | `#E5E5E2` | `#3B3B38` | the window, the front tab's sides, cards |
  | `--nr-hairline-soft` | `#EEEEEB` | `#2A2A28` | under the title strip and the address row, the rail edges, Panel sections |
  | `--nr-jar-line` | `#2A2A2A` | `#DADAD5` | the drawn jar's outline and an active jar's lid |
  | `--nr-jar-lid` | `#CFCFCA` | `#4A4A47` | an idle jar's lid |

  The title strip and the address row are `--nr-surface`. Dark is near-black neutrals, never green: the only dark surface with any green in it is `--relish-100` dark (`#1F3308`), and it appears only in the Sealed pill, the selected smart-jar row and the lit Brine pill (and, in 1.1, Ask's badges).
- **Accent**: `--relish-500` (`#93E413`). `--relish-100` for tints, `--relish-300` for hover, `--relish-700` when relish must sit on white and pass contrast, `--relish-ink` for text on relish.
- **Semantic**: `--nr-danger`, `--nr-warn` (shelf-life warning only), `--nr-focus` (= relish).
- **Jar colors**: six to pick from, the Workstation v5 set — Relish `oklch(83.4% 0.224 130.9)`, Amber `oklch(74.9% 0.148 78.2)`, Sky `oklch(62.3% 0.188 259.8)`, Rose `oklch(65.7% 0.193 20)`, Violet `oklch(70.9% 0.159 293.5)`, Teal `oklch(78.5% 0.133 181.9)`. A jar with no color is Relish. Any other color is still allowed in Edit Jar…. The fill is flat: one color, a meniscus line, no darker shade.
- **Killed**: dark-green glass surfaces, relish backgrounds, gradient fills (the jar is flat from v2.1), any second accent.

## 4 · Relish placements — the exhaustive list

Relish may appear in exactly these places. Adding one is a manifest change.

| # | Placement | Token |
|---|---|---|
| 1 | Primary button fill (one per view max): the empty state's one button. On a jar board the one filled button (New Tab) takes the jar's color instead, so it is relish only for a Relish jar. | `--relish-500` / text `--relish-ink` |
| 2 | *(retired in v2.0, still retired: the front tab's lip is in its JAR's color, below)* | |
| 3 | A selected smart-jar row on the Shelf (Today, Sealed, Sinking soon). The active jar tile takes the jar's color, below. | `--relish-100` |
| 4 | The Seal glyph (`#nr-seal`) and the Seal animation: the band and the drops, their highlight and gloss, the flying chip's check disc. **The Sealed pill** (v2.1): in the address row during Seal, and small on sealed cards. | band, drops, disc `--relish-500`; highlight and gloss `--relish-300`. Pill: fill `--relish-100`, 1pt edge `--relish-300` (dark `--relish-700`), disc `--relish-500`, check `--relish-ink`, the word in `--nr-fg` |
| 5 | Shelf-life bars in the Panel (remaining life); switch to `--nr-warn` under 20% | `--relish-500` |
| 6 | **Narrowed in v2.1:** Ask the Pantry's rank badges and citation markers (1.1, not in 1.0). Count badges are neutral (§8 Badge). | bg `--relish-100`, 1pt edge `--relish-300`, numerals `--relish-ink` |
| 7 | Focus ring, and the caret in the address field and in ⌘K | `--nr-focus` |
| 8 | Site: hero CTA. Everywhere: the cog mark (the empty state's cog is the mark, never redrawn) | `--relish-500` |
| 9 | Drop mark — a `--lip-h` bar on the leading edge of the jar tile or tab a drag would land on, **only while something is dragged over it** | `--relish-500` |
| 10 | *(retired in v2.1: the address row's top line)* | |
| 11 | **Narrowed in v2.1:** the address field's leading lock, and Ask's sparkle (1.1). The Zest glyphs on the Shelf are neutral (`--nr-fg-2`). | lock `--relish-700` (dark `--relish-500`) |
| 12 | *(retired in v2.1: the Shelf's section-label tiles)* | |
| 13 | **Narrowed in v2.1:** the Brine pill in the bottom bar lights **only for what came into Brine since Brine was last opened** — tabs that sank, and captures and Share-extension items, which land in Brine too. Opening Brine puts it out. Otherwise it is neutral with its count. | tint `--relish-100`, 1pt edge `--relish-300`, count `--nr-fg` |

**The jar's own color** (its data, ADR 0005; Relish until it's given one) appears in exactly these places:

1. the drawn jar (its fill and the jar-fill drip's drop);
2. the active jar's tile on the Shelf: a wash of it (the 100 step) and a 1pt edge of it (the 300 step). Dark: a `--nr-float` tile with the 1pt edge, never a dark-green panel;
3. the front tab's 5pt top lip (`#nr-lip`, `--lip-h`);
4. the board's one filled button (New Tab);
5. the border of a board card under the pointer;
6. the edge of the tile's count badge (the badge is `--nr-float` with ink numerals);
7. the jar-fill drip.

**Its shades** come from `JarPaint` (`Sources/UI/JarGlyph.swift`), from the jar's one stored color (its 500 step, the face), in OKLCH at the jar's hue `h`:

| Step | Light | Dark |
|---|---|---|
| wash (100) | L .964, C min(c, .022–.04) | L .29–.30 |
| edge (300) | L .86, C .075 | L .52–.55 |
| text (700) | L .52, C ≤ .17 | — |

Relish is pinned to the token values, so a Relish tile is exactly `--relish-100` with a `--relish-300` edge (dark: `--nr-float` with a `--relish-700` edge). The dark wash exists for completeness; no dark surface uses it in 1.0. Contrast for any color is checked through `JarPaint.inkContrast` (ink on the 500 step).

**Removed in v2.1**: the wash on the jar's chip (the chip is `--nr-tab`; its drawn jar carries the color), the wash on a jar row, the front tab's border and 2pt bottom bar, the board's fill bar (the drawn jar shows the level), the dot on a kept card.

Not relish: links (use `--nr-fg` underlined), selection (system), toolbar icons, sidebar text, scrollbars, toasts, count badges, the jar chip, the Zest glyphs.

## 5 · Type

- **Product**: system stack (`--font-ui`). Weights 400/500/600 only. Sizes from `--fs-*`. Line heights from `--lh-*`. Tabular numerals for counts and timers.
- **Code / URLs / Mason Jar console**: `--font-mono`.
- **Site hero only**: Bricolage Grotesque, wght 800 / wdth 100 / opsz 96, HarfBuzz kerning. Nowhere in the app.
- **Voice**: headlines say what the product does ("The browser that preserves your work"). Pantry vocabulary is used as *nouns in the UI*, never as puns in headlines. Proof lines are numbers: "412 things preserved, none of them lost."

## 6 · Shape, space, depth

- 4pt grid (`--sp-*`). Radii `--r-1/2/3`; jars use `--r-jar` with superellipse shoulders (n=5). Tabs use 8 (top corners only), cards `--r-2` (10), floating boxes 12.
- Depth = hairlines + one level of surface (`--nr-surface` for the title strip and address row, `--nr-canvas` behind boards, `--nr-rail` for rails, `--nr-float` for cards). Chrome rows stay flat: no shadow on the title strip, the address row, the Shelf, the Panel or the bottom bar.
- **One float shadow**, on floating things only (the ⌘K palette, menus, sheets; Ask in 1.1): light `0 4 20` black 8% plus `0 1 3` black 4%, over a `--nr-float` fill and a 1pt `--nr-hairline` stroke. Dark has no shadow: the hairline does that job. It is code (`Sources/UI/FloatShadow.swift`), not a token.
- No blur, no glass, no noise textures.

## 7 · Symbols (`symbols.svg`)

| id | Meaning | Rules |
|---|---|---|
| `#nr-jar` | A jar (project) | Wherever a jar is meant. Filled body, hairline shoulder. Variants: `#nr-jar-smart` (adds filter glyph), `#nr-jar-mason` (adds `</>`). |
| `#nr-seal` | Seal action | Relish. |
| `#nr-lip` | The front tab's lip (back in v2.1) | On the front tab's top edge, in its **jar's** color, `--lip-h` tall. Also the drop mark's bar (relish, §4 #9). |
| `#nr-drip` | The drip | Two placements: the Seal animation (relish), and the jar fill when something lands in a jar (the jar's tint). Nowhere else. |
| `#nr-sink` | Sinking / sunk state | Neutral. |
| Everything else | SF Symbols, line weight matching system | No emoji. No custom icons beyond this table. |

## 8 · Components

| Component | Spec |
|---|---|
| **Shelf** | A `--shelf-w` (120pt) rail, leading edge, full height under the title strip, `--nr-rail`, `--nr-hairline-soft` on its trailing edge, always open. A column of big jars: each tile is 100 × 88, the jar drawn at 58pt, its name under it at 12/500 (12/600 when active), one line, truncated. The active tile takes the jar's wash and a 1pt edge in the jar's color (§4). New Jar is a "+" under the jars. Then a hairline, then **Today**, **Sealed**, **Sinking soon** as 28pt rows with `#nr-jar-smart` at 16pt (the selected one `--relish-100`, §4 #3), and **Zest** at the bottom (its tools' glyphs in `--nr-fg-2`; a row opens the Zest window on that tool). Every behavior stays: clicking a jar opens its board; ⌘1–9 / ⌃⌘1–4 (smart jars; ⌘⇧3/4 are macOS screenshot keys, ADR 0014); a jar reorders by dragging among the jars, and Move Up / Move Down in its menu do the same; a tab or a Brine row dragged onto a jar lands in that jar and the tile shows the drop mark; right-click a jar: new tab, edit, color, move. |
| **The jar, drawn** | Never an image, because its fill is data. Line art, as in the beta art: a `--nr-jar-line` outline, a separate neck, a lid (`--nr-jar-line` when the jar is active, `--nr-jar-lid` when idle), `--nr-float` glass, a flat fill in the jar's color with a meniscus line, one highlight. No gradients. Its size is its drawn height; its width is height × 33/47. Fill is the jar's count over 12, held at full; nothing stops at 12. Sizes: 14 (palette), 18 (chip, Brine rows), 22 (Panel), 46 (board), 58 (Shelf tile). An idle jar keeps its own color. |
| **Title strip** | 44pt, `--nr-surface`, the whole width of the window, `--nr-hairline-soft` under it. The system title bar is hidden; its three buttons stay, centered at y 22, 18pt from the leading edge. Then the cog mark at 28pt (x 80), which opens the jar's board. Then the tabs, from x 120 (the Shelf's width). Its empty stretches move the window, and a double-click there zooms or minimizes, as the Mac is set. |
| **Tabs** | Attached to the Bench. **The tab in front** is `--nr-surface`, 38pt tall, with `--nr-hairline` on its sides and top and **no line under it** (it covers the strip's hairline, so it joins the address row), and a 5pt lip in its jar's color on its top edge (`#nr-lip`). It grows to fit its title up to 260pt before the others shrink. **A tab behind** is `--nr-tab` (`--nr-tab-hover` under the pointer), 33pt, unbordered. Corners 8, top only; 4pt apart. Widths 116 to 224; pinned 44 (icon only, with a pin mark). A tab's close button shows on hover. "+" sits after the last tab; the strip scrolls sideways when the tabs don't fit, with flat 1pt hairlines at a clipped edge. A tab's icon is the one picked for it (an SF Symbol), or its site's first letter on a tile (in ink on the front tab). No favicons. Pinned tabs never sink. Sinking tabs fade to `--nr-fg-3` over the last 10% of shelf life. Right-click a tab: pin, icon (a palette of SF Symbols), copy link, move to a jar, close. A tab dragged onto another takes its place and the target shows the drop mark; dragged onto a jar on the Shelf, it moves there. |
| **Address row** | 44pt, `--nr-surface`, only as wide as the Bench (it sits over the Bench, right of the Shelf), `--nr-hairline-soft` under it. In order: the jar's chip (the jar drawn at 18pt and its name, on `--nr-tab`; it opens the board), back, forward, then one field, 28pt, on `--nr-tab`: with a page in front it shows that page's address behind a leading lock (§4 #11); otherwise what you type opens in a new tab in the jar you're in. Capture, Reader and Reload sit inside it while a page is in front. Then the Seal slot (where the Sealed pill lands), and the Panel's switch on the trailing edge. |
| **Bench** | The web panes. Chrome is `--nr-surface`, hairline-separated. Nothing brand-colored touches the page. A real page draws its own colors, so it stays light in dark mode when the site is light. |
| **Jar board** | What the Bench shows for a jar when no page is in front, or when the jar, its chip or the mark is clicked. On `--nr-canvas`: the jar drawn at 46pt, its name at 30pt/600, "3 tabs · 12 kept", Edit Jar… and one filled button in the jar's color (New Tab). No fill bar: the drawn jar shows the level. Then its open tabs as tiles and what it keeps as cards, on `--nr-float`, `--r-2`, hairline borders (the jar's color under the pointer), in a grid of 252pt-minimum columns. A sealed card carries the small Sealed pill. A tile opens its page; a kept card opens the item (a sealed one, its saved copy). A query: the board moves nothing. |
| **Brine** | On `--nr-canvas`; rows carry the jar drawn at 18pt. |
| **Inspector** (the Panel) | `--inspector-w`, trailing edge, `--nr-rail`. **Closed at launch** (a person who opened it before keeps their choice). It slides over the Bench's trailing edge; the web view resizes once, when the slide ends. Sections separated by `--nr-hairline-soft`, `--fs-sm` labels in `--nr-fg-2`. For a jar it carries the six color swatches and the jar drawn at 22pt. |
| **Bottom bar** | 32pt, `--nr-rail`, the whole width of the window, hairline on top. Brine is a pill on the leading edge: the `#nr-sink` glyph, the word, and a count; neutral, lit only per §4 #13; it opens Brine on the Bench. Trailing: the Pantry's item count and "Search the Pantry ⌘K". |
| **Primary button** | Relish fill, `--relish-ink` text, `--r-1`, 600 weight. One per view. Hover `--relish-300`. |
| **Secondary button** | Hairline border, `--nr-fg` text, no fill. |
| **Badge** | Neutral (v2.1): `--nr-tab` bg, `--nr-fg-2` text, `--r-1`, tabular numerals. The Shelf tile's count badge is `--nr-float` with a 1pt edge in the jar's color and ink numerals. |
| **Shelf-life bar** | 2pt, `--relish-500` → `--nr-warn` under 20%, `--nr-hairline` track. In the Panel. |
| **Command palette** | ⌘K. A floating box 560pt wide over a `--nr-canvas` scrim, `--nr-float`, corners 12, the float shadow (§6). A pill field, then rows grouped **Pantry**, **Open tabs**, **Commands**; a jar shows drawn at 14pt; the selected row is `--nr-tab`. Return opens it, Esc closes. In 1.0, ⌘K is the palette (Ask the Pantry is 1.1). |
| **Seal** | ⌘S in a tab. Two phases, below (§8.1). The longest animation in the app. |
| **Jar fill (add)** | Something lands in a jar: a `#nr-drip` in the jar's tint falls inside the drawn jar (300ms, `--ease-drip`, scaleY .7 → 1.15); at 240ms the level rises (420ms, `--ease-jar`, so it overshoots and settles); the tile bumps 1 → 1.05 → 1 (420ms, `--ease-jar`); the count badge shows for 2.4s. 660ms in all, shorter than Seal. On Seal the jar's count doesn't change (one tab closes, one item is kept), so the level rises from one step below. |
| **Ask the Pantry** | 1.1, not in 1.0 (ADR 0012). Its answer is Foundation Models over sealed snapshots only (non-negotiable 4). System search field, `--nr-surface`, results as plain rows with `#nr-jar` provenance chips. No chat bubbles. |
| **Empty states** | `logo-cog.svg` at 56pt, one line of copy, one primary button. |

### 8.1 · Seal, in two phases

The app can't keep a fixed clock: the Workbench closes the tab only after extraction, the web archive and the Pantry write return, and the write can fail. So the Workbench's Seal phase (started → frozen or failed) drives the second phase, never a sleep.

**A, on ⌘S:**
- t0 — the glyph pulses 1 → 1.18 → 1 (200ms, `--ease-out`).
- t60 — the lip rises to the window's top edge (120ms).
- t120 — a 14pt capsule band runs out of the lip, both ways (260ms, `--ease-out`). It starts at the tab strip's leading edge, never over the window buttons.
- t200 — drops form, 40ms apart outward from the tab: a short nub on the lip about 68% across (centered on a pinned tab), small drops on the seams between tabs, and the big ones (with gloss) in the open strip after "+". No drop crosses a tab's title; one drop may pass the strip and stops above the field. Large 480ms (`--t-seal`), small 340ms; scaleY on `--ease-drip`, settle on `--ease-jar`.
- …the drops hang while the write runs.

**B, when the write returns, and never earlier than about 700ms after A started:**
- +0 — the page blinks once (ink 7%, 160ms): the copy is frozen.
- +20 — the Sealed pill pops in at the trailing end of the address row, and its check draws.
- +280 — drain: the highlight leaves, the drops retract (240ms), the band shrinks to the lip's own width and fades in its last 80ms, the lip lowers.
- +640 — a chip of the tab (its title and a check disc) flies to its jar on the Shelf: 560ms, y on `--ease-out` first so it never crosses the window buttons, x ease-in-out, shrinking late. It lands as the jar-fill drip, and the jar's count badge ticks.
- About 2.5s in all on a fast page. A second ⌘S lands the running Seal at once (close and fill) and seals the next tab: nothing ever ignores the key.

**The tab closes when the write returns**, as it always has: the motion is presentation only and never changes when or whether Seal stamps `sealedAt`, freezes the web archive, closes the tab, fires `onSeal` or runs the jar's Recipe (non-negotiable 3). The Bench moves to the next tab's page then. The tab strip keeps drawing a copy of the sealed tab, which can't be clicked, until its chip leaves (at most 4s). On a write faster than 700ms the page switches during phase A.

**Failure:** at B the drops drain, no pill, the tab stays open, and the address field shows the shipped status line ("Couldn’t seal this page") for 2.5s.

**Where it draws:** one Seal overlay over the whole window (title strip, address row and page), which takes no clicks. Not inside the tab, which closes. The window's three buttons stay drawn above it. It plays only in the window in front; Seal from Shortcuts with no window plays nothing.

**Reduce Motion:** Seal becomes a fade (the Sealed pill fades in and out; no band, drops or flying chip); the jar fill becomes a plain level change.

## 9 · Motion

`--t-fast` for hover/focus, `--t-base` for layout, `--t-seal` for Seal only. `--ease-out` default; `--ease-jar` for anything a jar does (drop into shelf, settle, switch); `--ease-drip` (v2.1) for things that fall (Seal's drops, the jar-fill drop).

- **Tabs**: the lip slides and resizes (200ms, `--ease-out`); fills cross-fade (120ms); height 33 ↔ 38 (200ms); a new tab opens from width 0 (200ms, `--ease-out`); a closing tab goes to width 0 (200ms) and fades (160ms).
- **Jar switch**: the tile's wash and edge (120ms), the lid's ink (120ms), a tile bump (320ms, `--ease-jar`), the tabs cross-fade out (120ms) and in (200ms, a 6pt slide), the lip's color (200ms), the Bench cross-fades (200ms).
- **The Panel** slides over the Bench's trailing edge (200ms, `--ease-out`). The web view resizes once, when the slide ends; never a per-frame width change on a real page. For those 200ms the Panel overlaps the page's edge, by design.
- **⌘K** fades in (200ms) and its field scales .98 → 1.
- **Reduce Motion**: Seal becomes a fade; the jar-fill drip becomes a plain level change; slides become cross-fades.

## 10 · Platforms

- **macOS** (v1.0): the title strip (44) across the whole window; under it the Shelf (120) at full height, then a column of the address row (44, only over the Bench) above the Bench, with the Panel sliding over the Bench's trailing edge; the bottom bar (32) across the whole window. The window is at least 960 × 600. The Panel starts closed. The title bar is hidden; the window's title still carries the active jar's name for the Window menu and Mission Control. The mark in the title strip is the cog at 28pt, right after the window buttons.
- **iOS Duo** (post-1.0): Shelf becomes a bottom jar bar, Inspector a sheet. Same tokens, same symbols, no new colors.
- **Site** (`netrelish-site`, Astro): same `tokens.css`. Hero uses `--font-hero` and the cog. Everything below the hero follows product rules. Pricing block ends with "Buy once, use forever."

## 11 · Apple Intelligence — day-one positioning

Four claims, all bound by non-negotiable 4 (sealed snapshots only). Confirm wording against the Sept 15 copy doc if it's recovered; the substance is locked:

1. **Ask the Pantry runs on-device.** Foundation Models answers over what you've sealed. Nothing leaves the Mac.
2. **Recipes are Shortcuts.** Every Recipe is an App Intent — Siri and Shortcuts can run them.
3. **Seal sorts for you.** Kind, labels, and a suggested jar are proposed at seal time from the snapshot.
4. **Writing Tools in your notes.** Notes on sealed pages get system Writing Tools for free.

## 12 · Do-not list

Dark-green glass · gradient text in the product · relish backgrounds · a second accent · emoji in UI · custom icons outside §7 · pantry puns in headlines · altering the mark · shadows on chrome · nested folders · streaks/rewards.

---

## Changelog
- **v2.1 (Nov 18 2026)** — the workbench facelift (ADR 0035). Ryan, Nov 18, on the comp (`docs/design/workbench-facelift/index.html`): "all yes, build it"; Nov 17: "put our icon on the top left". Attached tabs: the front tab is `--nr-surface`, joined to the Bench, with a 5pt lip in its jar's color on its top edge (`#nr-lip` is back, `--lip-h` 3 → 5); tabs behind are `--nr-tab`, unbordered; the 2pt bottom bar goes. Relish leaves the chrome: placements 10 (the address row's line) and 12 (the Shelf's section tiles) retire; 6, 11 and 13 narrow (count badges go neutral, Zest glyphs go `--nr-fg-2`, the Brine pill lights only for what is new since Brine was last opened); 4 gains the Sealed pill. The Shelf is a 120pt rail of big jars (`--shelf-w` 238 → 120); an idle jar keeps its own color; the jar is redrawn as flat line art with a lid, and the fill bar, the chip wash and the kept-card dot go. Seal plays in two phases, the second driven by the write returning, with the tab still closing at write return. One float shadow, on floating things only; chrome rows stay flat. Rows: title strip 44, address row 44 (field 28), bottom bar 32; the window is at least 960 × 600; the Panel starts closed. The cog mark sits at 28pt after the window buttons. ⌘K is restyled as a floating palette; Ask the Pantry stays 1.1. New tokens: `--nr-canvas`, `--nr-rail`, `--nr-tab`, `--nr-tab-hover`, `--nr-float`, `--nr-hairline-soft`, `--nr-jar-line`, `--nr-jar-lid`, `--ease-drip`; `--nr-hairline` `#E5E5E2`; `--nr-fg-3` `#6C6C65` / `#8F8F88`. Proposed in its PR; merging it is the decision.
- **v2.0 (Nov 14 2026)** — the Workstation v5 shell (ADR 0034). Ryan, Nov 14, with screenshots of the v5 prototype in dark and light: "Should look like this." Four rows; the wide, always-open Shelf with section labels; tabs in the title row behind the jar's chip; the address row under a line of relish; the jar board; the bottom bar with the Brine pill; the jar drawn filled in its own color. Relish placement 2 retires and 10–13 arrive; the jar's own color gets its own list in §4; the six jar colors are the v5 set. `--shelf-w` 56 → 238, `--inspector-w` 320 → 322. Still out: glass, blur, shadows on chrome, Bricolage in the app. Proposed in its PR; merging it is the decision.
- **v1.3 (Nov 13 2026)** — relish placement 9, the drop mark: a `--lip-h` relish bar on whatever a drag would land on, shown only during the drag. Right-click menus and drag come to the Shelf and the tab strip (ADR 0028). Ryan asked for more relish on Nov 13; this is the one placement that work needs, proposed in its PR, and merging it is the decision. Pickle is now Mason Jar (ADR 0029): `#nr-jar-pickle` becomes `#nr-jar-mason`, and the drawing is unchanged.
- **v1.2.1 (Nov 1 2026)** — smart jars move from ⌘⇧1–4 to ⌃⌘1–4: ⌘⇧3 and ⌘⇧4 are macOS's screenshot keys and never reach the app. Decided by Ryan (ADR 0014).
- **v1.2 (Oct 21 2026)** — second drip approved: the jar fill plays a `#nr-drip` in the jar's tint when something lands in a jar; Seal keeps the relish drip. Decided by Ryan in the workstation prototype review (`docs/design/netrelish-workstation.html` implements it).
- **v1.1.2 (Sept 21 2026)** — relish-100/300/700/ink take the Sept 15 Design Kit values, per the v1.1 note that the earlier file wins on values. relish-500 unchanged.
- **v1.1.1 (Sept 16 2026)** — `tokens.css` OKLCH values re-derived exactly from their hex fallbacks; the v1.1 numbers were approximations that rendered darker (relish-500 came out `#9CE700`). Hexes unchanged. Decided by Ryan, ADR 0001.
- **v1.1 (consolidated, Sept 16 2026)** — merged Brand Lock v1.1 + Design Manifest v1.1 into one file. Token values re-derived; original file wins on values if recovered.
- **v1.1 (Sept 15 2026)** — neutral base locked; relish placement list made exhaustive; cog variant approved; dark-green world retired.
- **v1.0** — mark, vocabulary, OKLCH system, superellipse n=5 carried over from the Shepdesign toolkit era.
