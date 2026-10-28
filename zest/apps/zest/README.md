# Zest — the studio

The flagship (ZEST-SPEC §7.3): build the brand once as real tokens, and every
Zest tool inherits them. Lemon in the fruit family; per §8 the studio is the
home page at `zest.netrelish.com`, with the store pages beside it.

## What the free core does

- **Color** — OKLCH engine with sRGB gamut mapping; four role swatches
  (`primary · ink · paper · dark`) per palette with locks; `muted`, `sheet`
  and `line` derived with Zest MD's custom-skin formulas (hand-editable, and
  pinned when a brand file carries explicit values); six harmonies; an
  11-step primary ramp; 12 presets; light and dark palettes with one-click
  dark derivation.
- **Type** — 19 curated pairings from 38 Google Fonts; heading/body/mono
  pickers; modular scale (base × ratio) with a live specimen.
- **Your fonts** — `.woff2/.woff/.ttf/.otf` upload via the FontFace API,
  stored in IndexedDB, this browser only (the cloud library is Pro).
- **Spacing, radius, buttons** — unit + density scale, radius token, button
  size and shape, all live in the preview.
- **Contrast audit** — WCAG 2.1 ratios for both palettes, recomputed as you
  edit.
- **Exports** — `zest-brand.json` (the §7.3 interchange, byte-for-byte shape),
  CSS variables (light + dark + ramp), Tailwind config, `@font-face` CSS,
  and a URL-hash share link that carries the whole brand (minus logo bytes).
- **Import** — the same `zest-brand.json` comes back in through the Import
  button (keyboard-reachable) or by dropping the file anywhere on the page.
- **Send to** — ZestImage (tokens + logo), ZestMail (light palette, body
  font, radius) and Zest MD (both palettes as a custom skin): all three
  import the same file today, by button or by dropping it on the page.
- **Logo** — SVG/PNG/JPEG, validated and embedded base64 in the brand file
  so ZestImage can compose with it. Never uploaded anywhere.

Pro rows are visible and greyed per §4.3 — cloud brand systems, the cloud
font library, Figma/Bricks/theme.json exports, the client-facing brand
sheet, and model-assisted pairings.

## Run locally

```bash
cd zest/apps/zest && npx serve .
```

The only network calls are Google Fonts. Brands live in `localStorage`
(`zeststudio:` keys), custom fonts in IndexedDB; the service worker
(`zstudio-` cache, scoped lookups) keeps the shell offline after first load.
