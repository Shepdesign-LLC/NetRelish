# ZestImage

The free local core is built: `index.html` is the whole app. Open it over
http and everything below marked Free works — eight layouts, every target,
PNG/WebP at 1× and 2×, the filename pattern, required alt text, the OG
snippet and the `zest-image.json` manifest. Pro features are visible and
greyed per ZEST-SPEC §4.3; they arrive with Zest accounts.

## Run locally

```bash
npx serve .          # any http server works; file:// blocks font loading
```

Brand fonts load from Google Fonts and degrade to system type offline.
Photos, logos and brands stay in this browser — nothing is uploaded.

---

The build brief below is distilled from `../../docs/ZEST-SPEC.md` §7.4;
where they differ, the spec wins.

Branded featured images — blog hero, OG card, social tile — composed from the
brand system, not generated. The image is typography, color, the logo, and
structure. No stock, no diffusion. Pricing-page one-liner: *Featured images
that look like your brand, not like a prompt.*

## Inputs

- A `zest-brand.json`, or a brand chosen from the cloud
- A title; optional kicker and byline
- An optional photo the user supplies — their own, cropped and tinted to the
  palette, never invented

## Layouts (v1, eight)

Title card · Kicker + title · Split (text left, photo right) · Photo with
gradient scrim and title · Stat card (one big number) · Quote card · Numbered
series (Part 3 of 7) · Logo lockup only.

Each layout is a small template function over the tokens, the same way ZestMail
blocks are. A new layout is one function.

The eight share one grid and one set of parts, so a set of cards reads as one
series:

- **Grid.** Margins come from both sides of the canvas, and each layout picks a
  wide, square or tall composition from the ratio, so a 3:1 banner and a story
  are both composed, not stretched.
- **Color.** The brand's 11-step `ramp` (derived from the primary the way the
  studio does when a file has none) gives the tints, deep tones and the ladder
  of steps where a color field meets the page. The primary is always the
  brand's literal value. Every line of type is set in the color that reads on
  what it sits on: 4.5:1, or 3:1 for big bold type.
- **Type.** Every line is measured before it is set. A word never breaks
  across lines; a headline steps down in size, then the picture or field gives
  it room, before anything is cut. Bylines and labels never go under 0.042 of
  the short side, about 11px when a 1200px card shows in a feed.
- **Parts.** A footer rail (brand mark and byline), a kicker chip with the
  brand's radius, the brand initial set tone-on-tone, and the logo placed by
  its measured shape, inside the safe zone like type.
- **Logo color.** Under the logo, **Color: Auto · Original · One color**. Auto
  keeps the logo's own colors and sets it in one color only where it would not
  read: a dark wordmark on a Dark card or a deep field. A logo that fills its
  box (a badge) keeps its colors. On Logo lockup a wide wordmark is the lockup
  itself; a square mark sits on a white tile beside the name.

The layout picker shows each one live, in the current brand, mode and target.
`tests/cards.js` checks all eight across every target, both modes and both
sample brands.

## Ratios and targets (one click renders all)

| Target | Size | Safe zone (kept clear of type) |
|---|---|---|
| Open Graph / Twitter large | 1200×630 | 40px top and bottom, 84px sides: some apps round or trim link cards |
| Blog featured | 1600×900 | none. Also 1200×675 |
| Square | 1080×1080 | none. Instagram, LinkedIn |
| Portrait | 1080×1350 | 34px sides: the profile grid shows the middle 3:4 |
| Story / Reel | 1080×1920 | 250px top, 340px bottom, 60px sides: the top bar and reply bar |
| Pinterest | 1000×1500 | 150px top and bottom, 60px sides: the hover buttons |
| Custom | any | none |

One function, `safeInsets(target, W, H)`, gives these numbers. The stage draws
the dashed Safe zone from it, and every layout takes the same insets as its
minimum margins, so type never sits where the platform covers it. The toggle
only shows on targets that have a zone. `tests/cards.js` checks that every
card's type sits inside the drawn zone.

## The stage

On a desktop the workspace is the window: the preview fits the stage in both
directions, centered, and never grows past real size. **Fit · 100%** in the
stage bar switches between that and real pixels (the stage scrolls), with the
live scale beside it. The side panels scroll on their own. If brand fonts
can't load, a quiet "Brand fonts offline" line sits in the stage bar instead
of a message over the card.

On a phone the preview docks at the top on a solid bar, with the whole
filename readable. Tap it for a full-screen preview you can pinch; close it
with its button or Esc. In landscape, tall targets such as Story stay large.

## Rendering

SVG composed in the browser, rasterised with `canvas` to PNG/WebP at 1× and 2×.
The SVG is itself an export (Pro), so the same image stays editable in
Illustrator or Figma. Fonts come from the brand: Google Fonts embedded as
`@font-face` in the SVG, custom fonts from the Zest font library.

## Metadata

- **Filename** from a pattern: `{brand}-{slug}-{target}.{ext}` →
  `shepdesign-zest-launch-og.png`. Lowercase, hyphens, no dates unless asked.
- **Alt text** required before export, pre-filled from title + kicker,
  editable. Exported alongside as `alt.txt` and in the manifest.
- **XMP/EXIF written into the file** (Pro): title, description, creator,
  copyright, keywords, `dc:source` = the brand id. Client-side: PNG gets an
  `iTXt` chunk, WebP an `XMP ` chunk, JPEG APP1.
- **OG snippet** copied with the image: `og:image`, `og:image:width/height`,
  `og:image:alt`, `twitter:card`.
- **Manifest** `zest-image.json` per export batch: every file, its target,
  dimensions, alt text, and the brand version it was made from — so a rebrand
  can regenerate the whole set.

## Free / Pro

| Feature | Free | Pro |
|---|---|---|
| All layouts, all ratios, PNG and WebP at 2× | ✓ | ✓ |
| Brands | 3 | unlimited, cloud |
| Batch: one title → every target | — | ✓ |
| SVG export | — | ✓ |
| XMP/EXIF metadata writer | filename + alt.txt | ✓ embedded |
| Upload to S3 → CloudFront URL | — | ✓ pasteable into ZestMail and Zest MD |
| Regenerate from brand version | — | ✓ |
| Series mode: one design, twelve titles from a list | — | ✓ |

## Ties to the other tools

ZestMail's Image and Hero blocks get a "Make with ZestImage" button that opens
ZestImage with the brand and block title prefilled and returns the CloudFront
URL. Zest MD's Publish uses ZestImage to make the OG card for a published
document automatically — that second one is the demo.
