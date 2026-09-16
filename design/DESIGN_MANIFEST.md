# NetRelish Design Manifest — v1.1 (consolidated)

The single source of truth for the brand and UI across macOS, iOS, and the marketing site. Brand Lock v1.1 is folded in here. Every screen is built from this document, `tokens.css`, and `symbols.svg`. Nothing drifts without a version bump and a changelog line at the bottom.

If an earlier `DESIGN_MANIFEST.md` or `tokens.css` is recovered from the repo or the Sept 15 session, it wins on any token *value* — this consolidated copy is the rules; values were re-derived from the lock.

---

## 1 · Principles

1. **The product is the hero.** Neutral surfaces, system type, hairlines. The brand lives in the mark and the objects, not in color washes.
2. **One accent.** Relish appears only in the placements in §4. Everywhere else is a bug.
3. **Objects, not decoration.** Jars are drawn things you can pick out at a glance. Relish "touches" are small and functional (a tab lip, a badge), never a background.
4. **Apple-friendly, not Apple-generic.** Reads as native at arm's length; unmistakably NetRelish up close.
5. **Fun for hours.** Depth comes from hairlines, layering, and motion — not from glass, gradients, or noise.
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
- **Killed**: dark-green glass surfaces, relish backgrounds, gradient fills in the product, any second accent.

## 4 · Relish placements — the exhaustive list

Relish may appear in exactly these places. Adding one is a manifest change.

| # | Placement | Token |
|---|---|---|
| 1 | Primary button fill (one per view max) | `--relish-500` / text `--relish-ink` |
| 2 | Active tab lip — a `--lip-h` bar on the top edge of the **active tab only** | `--relish-500` |
| 3 | Active jar row tint on the Shelf | `--relish-100` |
| 4 | Seal glyph (`#nr-seal`) and the Seal animation | `--relish-500` |
| 5 | Shelf-life bars (remaining life); switches to `--nr-warn` under 20% | `--relish-500` |
| 6 | Count badges (e.g. "412 preserved") | bg `--relish-100`, text `--relish-700` |
| 7 | Focus ring | `--nr-focus` |
| 8 | Site: hero CTA and the cog mark | `--relish-500` |

Not relish: links (use `--nr-fg` underlined), selection (system), toolbar icons, sidebar text, scrollbars, toasts.

## 5 · Type

- **Product**: system stack (`--font-ui`). Weights 400/500/600 only. Sizes from `--fs-*`. Line heights from `--lh-*`. Tabular numerals for counts and timers.
- **Code / URLs / Pickle console**: `--font-mono`.
- **Site hero only**: Bricolage Grotesque, wght 800 / wdth 100 / opsz 96, HarfBuzz kerning. Nowhere in the app.
- **Voice**: headlines say what the product does ("The browser that preserves your work"). Pantry vocabulary is used as *nouns in the UI*, never as puns in headlines. Proof lines are numbers: "412 things preserved, none of them lost."

## 6 · Shape, space, depth

- 4pt grid (`--sp-*`). Radii `--r-1/2/3`; jars use `--r-jar` with superellipse shoulders (n=5).
- Depth = hairlines + one level of surface (`--nr-surface` on `--nr-bg`, `--nr-surface-2` for rails). No drop shadows on chrome; a single 0/1/2 shadow on floating sheets only.
- No blur, no glass, no noise textures.

## 7 · Symbols (`symbols.svg`)

| id | Meaning | Rules |
|---|---|---|
| `#nr-jar` | A jar (project) | Wherever a jar is meant. Filled body, hairline shoulder. Variants: `#nr-jar-smart` (adds filter glyph), `#nr-jar-pickle` (adds `</>`). |
| `#nr-seal` | Seal action | Relish. |
| `#nr-lip` | Active tab lip | Relish, `--lip-h` tall. |
| `#nr-drip` | The one drip | Seal animation only. |
| `#nr-sink` | Sinking / sunk state | Neutral. |
| Everything else | SF Symbols, line weight matching system | No emoji. No custom icons beyond this table. |

## 8 · Components

| Component | Spec |
|---|---|
| **Shelf** (jar rail) | `--shelf-w` wide, leading edge, `--nr-surface-2`. One `#nr-jar` per row, 40pt hit target, label under icon at `--fs-xs`. Active row: `--relish-100` tint + `--nr-fg` label. Smart jars at the bottom under a hairline. New Jar button last. ⌘1–9 / ⌘⇧1–4. |
| **Tabs** | `--tab-h`, `--r-2` top corners, `--nr-surface` active / transparent inactive. Active tab carries `#nr-lip`. Pinned tabs show a pin glyph and never sink. Sinking tabs fade to `--nr-fg-3` over the last 10% of shelf life. |
| **Bench** | The web panes. Chrome is `--nr-surface`, hairline-separated. Nothing brand-colored touches the page. |
| **Inspector** | `--inspector-w`, trailing edge, `--nr-surface-2`. Sections separated by hairlines, `--fs-sm` labels in `--nr-fg-2`. |
| **Primary button** | Relish fill, `--relish-ink` text, `--r-1`, 600 weight. One per view. Hover `--relish-300`. |
| **Secondary button** | Hairline border, `--nr-fg` text, no fill. |
| **Badge** | `--relish-100` bg, `--relish-700` text, `--r-1`, tabular numerals. |
| **Shelf-life bar** | 2pt, `--relish-500` → `--nr-warn` under 20%, `--nr-hairline` track. |
| **Seal** | ⌘S in a tab. Glyph pulses once, the drip falls (`--t-seal`, `--ease-jar`), tab closes, jar count badge increments. The only animation longer than `--t-base`. |
| **Ask the Pantry** | System search field, `--nr-surface`, results as plain rows with `#nr-jar` provenance chips. No chat bubbles. |
| **Empty states** | `logo-cog.svg` at 40–64pt, one line of copy, one primary button. |

## 9 · Motion

`--t-fast` for hover/focus, `--t-base` for layout, `--t-seal` for Seal only. `--ease-out` default; `--ease-jar` for anything a jar does (drop into shelf, settle, switch). Respect Reduce Motion: Seal becomes a fade.

## 10 · Platforms

- **macOS** (v1.0): Shelf · Bench · Inspector three-column. Window title carries the active jar name. Titlebar mark at 16pt.
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
- **v1.1.1 (Sept 16 2026)** — `tokens.css` OKLCH values re-derived exactly from their hex fallbacks; the v1.1 numbers were approximations that rendered darker (relish-500 came out `#9CE700`). Hexes unchanged. Decided by Ryan, ADR 0001.
- **v1.1 (consolidated, Sept 16 2026)** — merged Brand Lock v1.1 + Design Manifest v1.1 into one file. Token values re-derived; original file wins on values if recovered.
- **v1.1 (Sept 15 2026)** — neutral base locked; relish placement list made exhaustive; cog variant approved; dark-green world retired.
- **v1.0** — mark, vocabulary, OKLCH system, superellipse n=5 carried over from the Shepdesign toolkit era.
