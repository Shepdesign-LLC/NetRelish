# Zest tests

Playwright suites and WCAG contrast sweeps for the Zest web tools. One command
runs everything: it assembles `dist/` via `build.sh`, serves the apps on local
ports, and fails red if any stage does.

```
cd zest/tests
npm ci
npx playwright install chromium
npm test
```

CI runs the same thing on every PR that touches `zest/**`
(`.github/workflows/zest-tests.yml`).

## What runs

| Stage | Covers |
|---|---|
| `test.js` (136) | Studio: roles, OKLCH harmony, locks, shuffle, type palettes, font upload/replacement, brand export/import round-trips, logo handling, share links, ZestImage brand import (5- and 7-digit hex fall back to valid colors), ZestImage's stage (at 1280×720, 1440×900 and 1920×1080 every target's preview is whole, centered and as large as fits, never past real size; the panels scroll on their own; Fit · 100% and the live scale, shown only under Fit; each target's own safe zone, its toggle hidden where there is none; toasts and the fonts-offline line never over the card), the folds (four closed on every load and Pro open on every load, all worked by keyboard, their controls still reach the preview, the export and the next visit), the one Light/Dark switch, Send to, no uncaught exceptions |
| `handoff2.js` (171) | Brand handoff studio → Mail and MD: token import, font mapping, serif stacks, name whitelisting, JSON routing, persistence, the DOMPurify XSS fix in MD (sanitized path *and* fail-closed path with the vendored file refused). Untrusted input: Mail's design import, reload and tampered storage (nothing runs, an honest design re-imports byte-identical, a design never changes a brand that is already there, link-valued merge tags are checked as links); MD's Contents list built from hostile heading ids (dropped file and `?text=` link), its saved reader settings, the integrity hashes on the sanitizer tag and on every on-demand file, and Mermaid always configured `strict` |
| `topology.js` (45) | The assembled `dist/`: studio at `/`, tools at `/mail` `/md` `/image`, the pinned fonts and libraries at `/vendor` (the lock not published), store at `/pricing`, scope-relative service workers and manifests, tools-row links, cross-app brand download |
| `mobile.js` (112) | Every surface at 390×844 with touch (plus landscape-phone, tablet, 375×667 and 1024×768 iPad cases): no layout-viewport blowout, panels reachable, and each core flow works by tap — Mail's 1:1 phone canvas (text at phone size, columns stacked), caret-only text taps with the B · I · Link bar, merge-tag chips that read back exactly (a tap puts the caret beside a chip; the next key no longer replaces it), focus kept through a resize, the content-height sheet (opens from a block or Properties, the block scrolled above it, closes by X, swipe or a tap on text, toast above it), the block's actions as the sheet's top row while it is open and a toast that clears the block bar while it is closed, 16px/44px fields and menu rows, the drawer below the toolbar, Source → Build back to the canvas with the drawer closed, canvas text ≥ 15px with the sheet open at every size (the landscape sheet used to drop it to 70%), at least 200px of block in sight above the sheet at 375×667, and a 1024px iPad toolbar that wraps with Export on screen; MD's wrapped bar + Contents drawer + clamped popovers, the studio's capped preview + jump nav, Image's docked preview (opaque, the whole filename readable, tap for a full-screen preview that closes by button or Esc, safe-zone toggle only where a target has one and its label never on the card, toasts clear of the frame, tall targets large in landscape), the store's menu and stacked comparison table. The old "canvas scales to fit" check (zoom < 1) is now "canvas text reads at ≥ 15px": the 55% canvas was the bug |
| `desktop.js` (51) | Mail at 1280×800, 1920×1080 and 2560×1440: the email never draws below 100% on a laptop and Fit grows it on wide screens (up to 125%, or 150% on a stage wider than 1500px; the 2560 check moved from 125% to 150% on purpose), the canvas header spans its pane, the zoom control (Fit · 100% · 125% · 150%) scales the email but not the block tools and survives a reload (and works with storage blocked), a zoomed email wider than the stage starts centered with every block tool on screen, the readout shows only under Fit, a resize keeps the preview's scroll, a 1366×480 window's zoom buttons work, a custom platform's `*|FNAME|*` tag is a chip that reads back and exports as typed, Desktop and Outlook previews show the 600px desktop email at the canvas's zoom in frames as tall as the email, and the exported HTML is identical at every zoom and window size |
| `sound.js` (139) | The sound kit and its mute toggle in all four tools: the kit block is present and the four copies are byte-identical; nothing plays, and no audio context is made, before the first real click or key press; each wired interaction asks for its sound and stays quiet and short; the Sound toggle has a name and `aria-pressed`, works by keyboard, and its choice survives a reload under the one shared key `zest.sound`; muted means no oscillator starts; nothing throws without Web Audio or without `localStorage`; no request leaves the machine |
| `cards.js` (19, run twice) | ZestImage's eight featured-image layouts, judged card by card through the live stage, once in the brand's own faces from `vendor/` (what people see) and once in the system fallback (`CARDS_FONTS=system`; CI's Ubuntu runner falls back to DejaVu Sans): 8 layouts × 6 targets (OG, Square, Story, Pinterest, a 1500×500 banner, an 800×1200 custom) × Light/Dark × both sample brands × a short and a 14-word title (384 cards), then again with a 4:1 logo and a white-sky, black-ground photo on three targets (192). Every line of type: its ink inside the canvas and the layout's safe rect, no word split across lines, nothing cut short with an ellipsis, at least 0.042 of the short side, and 4.5:1 against the color it names in `data-bg` (3:1 for bold type at 0.06 of the short side). Decorative glyphs (`data-deco`) may bleed. The card's safe rect sits inside the Safe zone the stage draws, for every layout on OG, Portrait, Story and Pinterest (Story's type runs exactly 250–1580), so the overlay and the layouts use the same numbers. Every logo inside the safe rect too, and on square and tall targets a short headline at 0.1 of the short side or more (the panel gives way first). Also: logos placed by their measured aspect and flush to the margin, a dark wordmark set in one color that reads 3:1 on Dark cards (Auto, with Original and One color to choose), a 400-only head face that still loads, from vendor/, when the role's weights are not in the family, a live thumbnail of every layout in the picker that follows brand, mode and target and repaints once after typing stops (never for a format or scale change), and titles and bylines drawn as text, never markup |
| `inapp.js` (108) | The tools as NetRelish.app runs them: the app's copy (`build.sh --app`, built by `run.js` into a temp folder) on a free local port with the host's frozen `window.netrelish` stub in the main frame, every file served with the host's own headers (the Content-Security-Policy, nosniff and the content types, read from `Sources/Zest/ZestFiles.swift`). It first checks the host has a type for every extension shipped. Per tool: the in-app switch is on; nothing sells (no pricing link or text, no Upgrade, no Pro badge, no drafting with a model, and none of it left in the shipped page); no service worker is registered; no Pro row, `data-pro` or account line is in the app at all; no visible control links or copies a `zest:` URL; the defaults are placeholders, not the maker's details; the studio has its three columns at the Zest window's 1180-wide default and no Share link; ZestImage's byline is a placeholder and its saved brands have no cap; ZestMail's first brand is a placeholder, an image at a web address is a placeholder with a line saying why on the canvas and in the Desktop preview, and its exported email keeps the real `<img>`; ZestMail has no drafting tab; Zest MD's sample diagram has one frame and one Copy, its web image is a placeholder and its export keeps the real `<img>` and embeds KaTeX_SansSerif for sans-serif math; the UI faces, the studio's preview frame and ZestImage's brand face load from `vendor/` on that origin; Zest MD's sanitizer, KaTeX and Mermaid load from there and render; the studio's `@font-face` export and Zest MD's HTML export embed their faces and load nothing; the host's policy refuses nothing in any frame (srcdoc previews included); no request leaves 127.0.0.1; no page error. Then the web sources (ports 8771-8774) with the same stub: the run-time switch alone hides the same parts, the Pro sections and the Share link included; without the stub the web keeps its pricing link and drafting tab. `--shots <dir>` saves 1180×820 screenshots |
| `offline.js` | Offline gate 2 for the app's copy (`run.js` builds it into a temp folder; CI runs it on the committed `Resources/Zest`): serves it on a free local port with the host's stub, opens each tool with every request to another host aborted and recorded, works the first flows (studio pairings and exports, a ZestMail block and copy, Zest MD's sample with math and a diagram, a ZestImage export), and fails on any attempted request outside 127.0.0.1 (resource hints included: a `preconnect` or `dns-prefetch` link to another host counts, static or added by script, since it opens a connection the router never sees) or any step that did not run |
| `contrast-audit.js` | Full-page WCAG text-contrast sweep (alpha compositing, gradient detection) on Mail, MD (dark **and** light scheme — its reader skins react to `prefers-color-scheme`), and the studio — any failure fails the run. Mail and the studio ship one fixed dark chrome, so a single sweep covers them |

## The offline gates (app bundle)

ADR 0015 holds the app's copy of the tools to no network in three layers: a
static scan (`../scripts/offline-scan.mjs`), `offline.js` here, and the app's
content rule list. Both run in `npm test`, and both pass with no exception: no tool loads
anything from another host, in the app or on the web, and the shipped copy
holds no pricing or Upgrade text.

```
cd zest && bash build.sh --app && node scripts/offline-scan.mjs
cd tests && node offline.js [--json report.json]
```

`offline.js` and `inapp.js` take their own free port, so they can run beside
the fixed-port suites. `run.js` builds the app's copy into a temp folder
(`ZEST_APP_OUT`) next to `dist/` and points both at it (`ZEST_APP_ROOT`). CI
also runs both gates in the `app-bundle` job of
`.github/workflows/zest-tests.yml`, on the committed `Resources/Zest` (it
rebuilds into a temp folder only to diff it against the committed copy), and
every step there fails the PR (`ZEST_OFFLINE_ENFORCE: 'true'`).

The scan's exceptions live in `../scripts/offline-allowlist.json`, each
narrowed to the files and exact links in use. A URL in a load position
(including every `srcset` candidate, `srcdoc`, `image-set()`, a JSON-escaped
`https:\/\/` and a protocol-relative `//host`) always fails, and no entry
passes a URL whose path ends in `.png`, `.js`, `.css`, `.woff2` and the like
unless it names that one URL exactly. A library bump that brings a URL on a
new host fails the scan until someone adds a reviewed entry.

## Notes

- **The sound kit is one block, pasted four times.** Each tool is a single
  file, so the kit lives inline between `/* zest-sound:start v1 */` and
  `/* zest-sound:end */` in `apps/zest`, `apps/mail`, `apps/md` and
  `apps/image`. To change it, edit one copy, paste it over the other three and
  bump the version in the marker; `sound.js` fails if the copies differ.
  `sound.js` swaps Web Audio for a counting stand-in, so it checks what the
  kit asks for, not how it sounds — listen in a browser after changing a sound.
- **ZestImage is excluded from the contrast sweep.** Its body background is a
  gradient, which the auditor cannot composite — it falls back to white and
  flags the whole page. Pre-existing harness limitation, not a product issue;
  ZestImage's chrome values are verified by hand in PR brand checks.
- **Nothing leaves the machine in any suite.** The fonts, DOMPurify, KaTeX
  and Mermaid are vendored and load from `/vendor/` on the page's own origin
  (`dist/vendor` on the web; `run.js` serves `zest/vendor` at `/vendor/` on
  each tool's own port, so `vendor/` and `../vendor/` resolve the same way).
  Every page context aborts any address that is not localhost or 127.0.0.1,
  so a run never depends on egress, and `sound.js` fails on any request that
  leaves the machine. `handoff2.js` checks that the vendored sanitizer is byte
  for byte the npm release pinned in `package.json` here, so the XSS tests
  exercise the sanitizer the app ships, and tests the fail-closed path by
  refusing `/vendor/dompurify/`. **When one moves, move the other**: a
  Dependabot bump here must be mirrored in `scripts/vendor.config.json`, the
  lock and `apps/md/index.html`, and vice versa.
- **DOMPurify, KaTeX and Mermaid are also vendored** in `../vendor/`, pinned
  by `../scripts/vendor.config.json` and recorded in `VENDOR.lock.json`.
  `node ../scripts/vendor.mjs --check` fails when the tag's version, any
  integrity hash in `apps/md/index.html`, or the `dompurify` pin here differs
  from the vendored files, or when `Resources/Zest/vendor/` or
  `Resources/Zest/NOTICE` differ from the lock and the root `NOTICE`, so a
  bump now also means rerunning `node scripts/vendor.mjs` and
  `bash build.sh --app`.
- **The sanitizer tag carries an `integrity` hash** and a `data-version`.
  A version bump changes `package.json` here, `scripts/vendor.config.json`,
  the vendored file (`node ../scripts/vendor.mjs`), the tag's `data-version`
  and its hash. Compute the hash from the vendored file, never by hand:
  `openssl dgst -sha384 -binary ../vendor/dompurify/purify.min.js | openssl base64 -A`,
  prefixed with `sha384-`. `vendor.mjs --check` and `handoff2.js` both fail
  when they disagree.
- **KaTeX and Mermaid load on demand and are hashed too.** Each file in the
  `VENDOR` table in `apps/md/index.html` is a `../vendor/` path listed with
  its `sha384`, and the loader sets it on the tag. A version bump reruns
  `node ../scripts/vendor.mjs` and updates the hashes, which
  `vendor.mjs --check` compares with the vendored files. `handoff2.js` checks
  that every on-demand file has a hash and that the loader puts it on the
  tag; `inapp.js` renders the sample's math and diagram with the real files.
- **Mermaid is tested with a stand-in.** The real library (3.5 MB) is not a
  test dependency. `handoff2.js` proves two things with a few lines that
  record how the app configures the library. Served at the app's Mermaid
  address, the stand-in is refused because it is not the pinned release, and
  the diagram stays a code block. Defined before the page loads, it shows that
  every `initialize` call asks for `securityLevel: 'strict'`. The suite does
  not render a diagram. Rendering under `strict` was checked by hand against
  Mermaid 11.17.2 on 2026-11-11: a flowchart renders, a `click … href` with a
  script URL becomes a link with no address, `click … call` runs nothing, and
  handler attributes in label markup are removed. Repeat that check when the
  version changes, until the real library is a test dependency.
- `fixtures/` holds two Caladea TTFs (SIL OFL 1.1, license included) for the
  studio's font-upload round-trip — no system font paths, so the suite runs
  on any OS. ZestImage's one-weight head face (`cards.js`) uses the vendored
  DM Serif Display.
- `ZEST_CHROMIUM=/path/to/chromium npm test` launches that binary instead of
  the Playwright-managed browser (for sandboxes with a system Chromium).
- The suites talk to ports 8771 (studio), 8772 (image), 8773 (mail),
  8774 (md), 8780 (dist); `run.js` hosts all five in-process.
