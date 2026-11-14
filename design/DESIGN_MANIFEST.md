# NetRelish Design Manifest — v2.0

The single source of truth for the brand and UI across macOS, iOS, and the marketing site. Brand Lock v1.1 is folded in here. Every screen is built from this document, `tokens.css`, and `symbols.svg`. Nothing drifts without a version bump and a changelog line at the bottom.

If an earlier `DESIGN_MANIFEST.md` or `tokens.css` is recovered from the repo or the Sept 15 session, it wins on any token *value* — this consolidated copy is the rules; values were re-derived from the lock.

---

## 1 · Principles

1. **The product is the hero.** Neutral surfaces, system type, hairlines. The brand lives in the mark and the objects, not in color washes.
2. **One accent, and the jar's own color.** Relish appears only in the placements in §4. A jar's color is the user's data and appears only where §4 lists it. Everywhere else is a bug.
3. **Objects, not decoration.** Jars are drawn things you can pick out at a glance. Relish "touches" are small and functional (a tab lip, a badge), never a background.
4. **Apple-friendly, not Apple-generic.** Reads as native at arm's length; unmistakably NetRelish up close.
5. **Fun for hours.** Depth comes from hairlines, layering, and motion — not from glass or noise. The only gradients are inside a jar: the drawn jar and its fill bar.
6. **Locked.** The mark, the vocabulary, and this document are final. Propose changes as a versioned PR.

## 2 · The mark

| Asset | Use | Rules |
|---|---|---|
| `logo.svg` — steel gear drowned in relish on a dark-green squircle (superellipse n=5) | App icon, titlebar, About | Never redrawn, recolored, cropped, or stroked. No wordmark needed beside it. |
| `logo-cog.svg` — gear + relish only, squircle removed | Site, onboarding, empty states, About window | Shown larger than the full mark would be. Same rules. |

Clear space: ½ the mark's width on all sides. Minimum size: 16pt (icon), 40pt (cog). The squircle green and gear steel (`--nr-squircle`, `--nr-steel`) exist in tokens **only** so the mark renders from tokens; they are never UI colors.

## 3 · Color

- **Base**: `--nr-bg`, `--nr-surface`, `--nr-surface-2`, `--nr-hairline`, `--nr-fg` ×3. Light is white/near-black; dark is near-black/off-white. No tinted neutrals.
- **Accent**: `--relish-500` (`#93E413`). `--relish-100` for tints, `--relish-300` for hover, `--relish-700` when relish must sit on white and pass contrast, `--relish-ink` for text on relish.
- **Semantic**: `--nr-danger`, `--nr-warn` (shelf-life warning only), `--nr-focus` (= relish).
- **Jar colors**: six to pick from, the Workstation v5 set — Relish `oklch(83.4% 0.224 130.9)`, Amber `oklch(74.9% 0.148 78.2)`, Sky `oklch(62.3% 0.188 259.8)`, Rose `oklch(65.7% 0.193 20)`, Violet `oklch(70.9% 0.159 293.5)`, Teal `oklch(78.5% 0.133 181.9)`. A jar with no color is Relish. Any other color is still allowed in Edit Jar…. The darker shade a jar's fill runs down to is the same color at 78% of its lightness.
- **Killed**: dark-green glass surfaces, relish backgrounds, gradient fills outside a jar and its fill bar, any second accent.

## 4 · Relish placements — the exhaustive list

Relish may appear in exactly these places. Adding one is a manifest change.

| # | Placement | Token |
|---|---|---|
| 1 | Primary button fill (one per view max) | `--relish-500` / text `--relish-ink` |
| 2 | *(retired in v2.0: the tab in front takes its jar's color, below)* | |
| 3 | Active row tint on the Shelf, for a smart jar row. A jar's own row takes a wash of the jar's color, below. | `--relish-100` |
| 4 | Seal glyph (`#nr-seal`) and the Seal animation | `--relish-500` |
| 5 | Shelf-life bars (remaining life); switches to `--nr-warn` under 20% | `--relish-500` |
| 6 | Count badges (e.g. "412 preserved") | bg `--relish-100`, text `--relish-700` |
| 7 | Focus ring | `--nr-focus` |
| 8 | Site: hero CTA and the cog mark | `--relish-500` |
| 9 | Drop mark — a `--lip-h` bar on the leading edge of the jar row or tab a drag would land on, **only while something is dragged over it** | `--relish-500` |
| 10 | The address row's top line, 2pt, the full width of the window | `--relish-500` |
| 11 | The address field's leading glyph, and the Zest tools' glyphs on the Shelf | `--relish-700` |
| 12 | Section-label tiles on the Shelf (Jars, Pantry, Zest): an 18pt tile holding the section's glyph | `--relish-500` / glyph `--relish-ink` |
| 13 | The Brine pill in the bottom bar, **only while something has sunk**: border, tint and its count | `--relish-500` / `--relish-100` / text `--relish-700` |

**The jar's own color** (its data, ADR 0005; Relish until it's given one) appears in exactly these places: the drawn jar; a wash of it at 16% on the jar's active row on the Shelf and at 20% on the jar's chip in the tab strip; the border and the 2pt bottom bar of the tab in front; the board's one filled button; the fill bar; the border of a board card under the pointer; the dot on a kept card.

Not relish: links (use `--nr-fg` underlined), selection (system), toolbar icons, sidebar text, scrollbars, toasts.

## 5 · Type

- **Product**: system stack (`--font-ui`). Weights 400/500/600 only. Sizes from `--fs-*`. Line heights from `--lh-*`. Tabular numerals for counts and timers.
- **Code / URLs / Mason Jar console**: `--font-mono`.
- **Site hero only**: Bricolage Grotesque, wght 800 / wdth 100 / opsz 96, HarfBuzz kerning. Nowhere in the app.
- **Voice**: headlines say what the product does ("The browser that preserves your work"). Pantry vocabulary is used as *nouns in the UI*, never as puns in headlines. Proof lines are numbers: "412 things preserved, none of them lost."

## 6 · Shape, space, depth

- 4pt grid (`--sp-*`). Radii `--r-1/2/3`; jars use `--r-jar` with superellipse shoulders (n=5).
- Depth = hairlines + one level of surface (`--nr-surface` on `--nr-bg`, `--nr-surface-2` for rails). No drop shadows on chrome; a single 0/1/2 shadow on floating sheets only.
- No blur, no glass, no noise textures.

## 7 · Symbols (`symbols.svg`)

| id | Meaning | Rules |
|---|---|---|
| `#nr-jar` | A jar (project) | Wherever a jar is meant. Filled body, hairline shoulder. Variants: `#nr-jar-smart` (adds filter glyph), `#nr-jar-mason` (adds `</>`). |
| `#nr-seal` | Seal action | Relish. |
| `#nr-lip` | Active tab lip | Relish, `--lip-h` tall. |
| `#nr-drip` | The drip | Two placements: the Seal animation (relish), and the jar fill when something lands in a jar (the jar's tint). Nowhere else. |
| `#nr-sink` | Sinking / sunk state | Neutral. |
| Everything else | SF Symbols, line weight matching system | No emoji. No custom icons beyond this table. |

## 8 · Components

| Component | Spec |
|---|---|
| **Shelf** | `--shelf-w` wide, leading edge, `--nr-surface-2`, always open. Three sections, each under a 36pt label with a relish tile: **Jars** (its label carries New Jar), **Pantry** (Today, Sealed, Sinking soon), **Zest** (the four tools; a row opens the Zest window on that tool). A jar row is 44pt: the jar drawn filled at 20pt, its name at `--fs-lg`, and a count of its open tabs plus what it keeps. The active jar row takes a wash of the jar's color. Clicking a jar opens its board. ⌘1–9 / ⌃⌘1–4 (smart jars; ⌘⇧3/4 are macOS screenshot keys, ADR 0014). A jar reorders by sliding among the jars, and only there; Move Up and Move Down in its menu do the same. A tab or a Brine row dragged onto a jar lands in that jar, and the row shows the drop mark. Right-click a jar: new tab, edit, color, move. |
| **The jar, drawn** | Never an image, because its fill is data. In a 22 × 26 box: the glass, the fill with its meniscus, two bubbles only when full, the specular pass, the outline, the lid. Fill is the jar's count over 12, held at full; nothing stops at 12. Sizes: 16 (chip), 20 (Shelf), 46 (board). |
| **Title row** | 48pt, `--nr-surface-2`, the top of the window: the title bar is hidden and only its three buttons remain. Back, forward, the cog mark at 28pt (it opens the jar's board), then the tab strip. Its empty stretches move the window. |
| **Tabs** | In the title row. The strip leads with the jar's chip: the jar drawn at 16pt and its name on a wash of the jar's color; it opens the board. Every tab is `--tab-h` tall and 176pt wide (pinned: 46pt, icon only, with a pin mark), `--r-2`, and always has a hairline border, so a tab never blends into the chrome. The tab in front is `--nr-surface` with its border and a 2pt bottom bar in the jar's color. A tab's icon is the one picked for it, or its site's first letter. Pinned tabs never sink. Sinking tabs fade to `--nr-fg-3` over the last 10% of shelf life. Right-click a tab: pin, icon (a palette of SF Symbols), copy link, move to a jar, close. A tab dragged onto another takes its place and the target shows the drop mark; dragged onto a jar on the Shelf, it moves there. |
| **Address row** | 46pt, `--nr-surface`, under a 2pt line of relish. One field the width of the row, 32pt, `--r-2`: with a page in front it shows that page's address; otherwise what you type opens in a new tab in the jar you're in. Capture, Reader and Reload sit inside it while a page is in front. The Panel's switch is on the trailing edge. |
| **Bench** | The web panes. Chrome is `--nr-surface`, hairline-separated. Nothing brand-colored touches the page. |
| **Jar board** | What the Bench shows for a jar when no page is in front, or when the jar, its chip or the mark is clicked. The jar drawn at 46pt, its name at 30pt/600, "3 tabs · 12 kept", Edit Jar… and one filled button in the jar's color (New Tab). The fill bar, 300 × 8. Then its open tabs as tiles and what it keeps as cards, in a grid of 252pt-minimum columns, `--r-3`, hairline borders. A tile opens its page; a kept card opens the item (a sealed one, its saved copy). A query: the board moves nothing. |
| **Inspector** (the Panel) | `--inspector-w`, trailing edge, `--nr-surface-2`. Sections separated by hairlines, `--fs-sm` labels in `--nr-fg-2`. For a jar it carries the six color swatches. |
| **Bottom bar** | 44pt, `--nr-surface-2`, hairline on top. Brine is a pill on the leading edge: the `#nr-sink` glyph, the word, and a count. It lights up (placement 13) only while something has sunk, and opens Brine on the Bench. Trailing: the Pantry's item count and ⌘K. |
| **Primary button** | Relish fill, `--relish-ink` text, `--r-1`, 600 weight. One per view. Hover `--relish-300`. |
| **Secondary button** | Hairline border, `--nr-fg` text, no fill. |
| **Badge** | `--relish-100` bg, `--relish-700` text, `--r-1`, tabular numerals. |
| **Shelf-life bar** | 2pt, `--relish-500` → `--nr-warn` under 20%, `--nr-hairline` track. |
| **Seal** | ⌘S in a tab. Glyph pulses once, the drip falls (`--t-seal`, `--ease-jar`), tab closes, jar count badge increments. The longest animation in the app. |
| **Jar fill (add)** | Something lands in a jar: a `#nr-drip` in the jar's tint falls inside the glyph, then the fill rises to the new level (`--ease-jar`). Shorter than `--t-seal`. |
| **Ask the Pantry** | System search field, `--nr-surface`, results as plain rows with `#nr-jar` provenance chips. No chat bubbles. |
| **Empty states** | `logo-cog.svg` at 40–64pt, one line of copy, one primary button. |

## 9 · Motion

`--t-fast` for hover/focus, `--t-base` for layout, `--t-seal` for Seal only. `--ease-out` default; `--ease-jar` for anything a jar does (drop into shelf, settle, switch). Respect Reduce Motion: Seal becomes a fade; the jar-fill drip becomes a plain level change.

## 10 · Platforms

- **macOS** (v1.0): four rows — title row (48), address row (46), Shelf · Bench · Panel side by side, bottom bar (44). The window is at least 1120 × 640. The title bar is hidden; the window's title still carries the active jar's name for the Window menu and Mission Control. The mark in the title row is the cog at 28pt.
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
- **v2.0 (Nov 14 2026)** — the Workstation v5 shell (ADR 0034). Ryan, Nov 14, with screenshots of the v5 prototype in dark and light: "Should look like this." Four rows; the wide, always-open Shelf with section labels; tabs in the title row behind the jar's chip; the address row under a line of relish; the jar board; the bottom bar with the Brine pill; the jar drawn filled in its own color. Relish placement 2 retires and 10–13 arrive; the jar's own color gets its own list in §4; the six jar colors are the v5 set. `--shelf-w` 56 → 238, `--inspector-w` 320 → 322. Still out: glass, blur, shadows on chrome, Bricolage in the app. Proposed in its PR; merging it is the decision.
- **v1.3 (Nov 13 2026)** — relish placement 9, the drop mark: a `--lip-h` relish bar on whatever a drag would land on, shown only during the drag. Right-click menus and drag come to the Shelf and the tab strip (ADR 0028). Ryan asked for more relish on Nov 13; this is the one placement that work needs, proposed in its PR, and merging it is the decision. Pickle is now Mason Jar (ADR 0029): `#nr-jar-pickle` becomes `#nr-jar-mason`, and the drawing is unchanged.
- **v1.2.1 (Nov 1 2026)** — smart jars move from ⌘⇧1–4 to ⌃⌘1–4: ⌘⇧3 and ⌘⇧4 are macOS's screenshot keys and never reach the app. Decided by Ryan (ADR 0014).
- **v1.2 (Oct 21 2026)** — second drip approved: the jar fill plays a `#nr-drip` in the jar's tint when something lands in a jar; Seal keeps the relish drip. Decided by Ryan in the workstation prototype review (`docs/design/netrelish-workstation.html` implements it).
- **v1.1.2 (Sept 21 2026)** — relish-100/300/700/ink take the Sept 15 Design Kit values, per the v1.1 note that the earlier file wins on values. relish-500 unchanged.
- **v1.1.1 (Sept 16 2026)** — `tokens.css` OKLCH values re-derived exactly from their hex fallbacks; the v1.1 numbers were approximations that rendered darker (relish-500 came out `#9CE700`). Hexes unchanged. Decided by Ryan, ADR 0001.
- **v1.1 (consolidated, Sept 16 2026)** — merged Brand Lock v1.1 + Design Manifest v1.1 into one file. Token values re-derived; original file wins on values if recovered.
- **v1.1 (Sept 15 2026)** — neutral base locked; relish placement list made exhaustive; cog variant approved; dark-green world retired.
- **v1.0** — mark, vocabulary, OKLCH system, superellipse n=5 carried over from the Shepdesign toolkit era.
