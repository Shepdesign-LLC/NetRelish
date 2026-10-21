# ZestImage

Not built yet. This is the build brief, distilled from `../../docs/ZEST-SPEC.md`
§7.4; where they differ, the spec wins.

Branded featured images — blog hero, OG card, social tile — composed from the
brand system, not generated. The image is typography, colour, the logo, and
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

## Ratios and targets (one click renders all)

| Target | Size | Notes |
|---|---|---|
| Open Graph / Twitter large | 1200×630 | Safe zone drawn on the canvas |
| Blog featured | 1600×900 | Also 1200×675 |
| Square | 1080×1080 | Instagram, LinkedIn |
| Portrait | 1080×1350 | Instagram portrait |
| Story / Reel | 1080×1920 | |
| Pinterest | 1000×1500 | |
| Custom | any | |

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
