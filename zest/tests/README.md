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
| `test.js` (134) | Studio: roles, OKLCH harmony, locks, shuffle, type palettes, font upload/replacement, brand export/import round-trips, logo handling, share links, ZestImage brand import, ZestImage's stage (at 1280×720, 1440×900 and 1920×1080 every target's preview is whole, centered and as large as fits, never past real size; the panels scroll on their own; Fit · 100% and the live scale; each target's own safe zone, its toggle hidden where there is none; toasts and the fonts-offline line never over the card), the folds (four closed on every load and Pro open on every load, all worked by keyboard, their controls still reach the preview, the export and the next visit), the one Light/Dark switch, Send to, no uncaught exceptions |
| `handoff2.js` (169) | Brand handoff studio → Mail and MD: token import, font mapping, serif stacks, name whitelisting, JSON routing, persistence, the DOMPurify XSS fix in MD (sanitized path *and* fail-closed path with the CDN blocked). Untrusted input: Mail's design import, reload and tampered storage (nothing runs, an honest design re-imports byte-identical, a design never changes a brand that is already there, link-valued merge tags are checked as links); MD's Contents list built from hostile heading ids (dropped file and `?text=` link), its saved reader settings, the integrity hashes on the sanitizer tag and on every on-demand file, and Mermaid always configured `strict` |
| `topology.js` (38) | The assembled `dist/`: studio at `/`, tools at `/mail` `/md` `/image`, store at `/pricing`, scope-relative service workers and manifests, tools-row links, cross-app brand download |
| `mobile.js` (93) | Every surface at 390×844 with touch (plus landscape-phone and tablet cases): no layout-viewport blowout, panels reachable, and each core flow works by tap — Mail's 1:1 phone canvas (text at phone size, columns stacked), caret-only text taps with the B · I · Link bar, merge-tag chips that read back exactly, focus kept through a resize, the content-height sheet (opens from a block or Properties, the block scrolled above it, closes by X, swipe or a tap on text, toast above it), the block bar, 16px/44px fields and menu rows, the drawer below the toolbar, Source → Build back to the canvas, and the 768 tablet and 844×390 layouts; MD's wrapped bar + Contents drawer + clamped popovers, the studio's capped preview + jump nav, Image's docked preview (opaque, the whole filename readable, tap for a full-screen preview that closes by button or Esc, safe-zone toggle only where a target has one, toasts clear of the frame, tall targets large in landscape), the store's menu and stacked comparison table. The old "canvas scales to fit" check (zoom < 1) is now "canvas text reads at ≥ 15px": the 55% canvas was the bug |
| `desktop.js` (38) | Mail at 1280×800, 1920×1080 and 2560×1440: the email never draws below 100% on a laptop and Fit grows it on wide screens (capped at 125%), the canvas header spans its pane, the zoom control (Fit · 100% · 125% · 150%) scales the email but not the block tools and survives a reload (and works with storage blocked), Desktop and Outlook previews show the 600px desktop email at the canvas's zoom in frames as tall as the email, and the exported HTML is identical at every zoom and window size |
| `sound.js` (139) | The sound kit and its mute toggle in all four tools: the kit block is present and the four copies are byte-identical; nothing plays, and no audio context is made, before the first real click or key press; each wired interaction asks for its sound and stays quiet and short; the Sound toggle has a name and `aria-pressed`, works by keyboard, and its choice survives a reload under the one shared key `zest.sound`; muted means no oscillator starts; nothing throws without Web Audio or without `localStorage`; no request goes to a new host |
| `cards.js` (11) | ZestImage's eight featured-image layouts, judged card by card through the live stage: 8 layouts × 6 targets (OG, Square, Story, Pinterest, a 1500×500 banner, an 800×1200 custom) × Light/Dark × both sample brands × a short and a 14-word title (384 cards), then again with a 4:1 logo and a white-sky, black-ground photo on three targets (192). Every line of type: its ink inside the canvas and the layout's safe rect, no word split across lines, nothing cut short with an ellipsis, at least 0.042 of the short side, and 4.5:1 against the color it names in `data-bg` (3:1 for bold type at 0.06 of the short side). Decorative glyphs (`data-deco`) may bleed. Also: logos placed by their measured aspect and flush to the margin, a live thumbnail of every layout in the picker that follows brand, mode and target, and titles and bylines drawn as text, never markup |
| `contrast-audit.js` | Full-page WCAG text-contrast sweep (alpha compositing, gradient detection) on Mail, MD (dark **and** light scheme — its reader skins react to `prefers-color-scheme`), and the studio — any failure fails the run. Mail and the studio ship one fixed dark chrome, so a single sweep covers them |

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
- **No live CDN in any suite.** Every page context aborts `cdnjs` and Google
  Fonts, so a run sees the same page state with or without egress and never
  flakes on CDN weather. The one exception is deliberate: `handoff2.js`
  serves `dompurify` from `node_modules` — pinned in `package.json` to the
  exact version Zest MD's cdnjs `<script>` tag loads — so the XSS tests
  exercise the sanitizer the app ships (and the fail-closed path is tested
  with it absent). **When one moves, move the other**: a Dependabot bump
  here must be mirrored in `apps/md/index.html`, and vice versa.
- **The sanitizer tag carries an `integrity` hash**, so a version bump is
  three edits: `package.json` here, the version in the cdnjs URL, and the
  hash. Compute the hash from the installed package, never by hand:
  `openssl dgst -sha384 -binary node_modules/dompurify/dist/purify.min.js | openssl base64 -A`,
  prefixed with `sha384-`. `handoff2.js` serves that same file for the cdnjs
  URL, so a hash that does not match the pinned release fails the suite.
- **KaTeX and Mermaid load on demand and are hashed too.** Each file in the
  `VENDOR` table in `apps/md/index.html` is listed with its `sha384`, and the
  loader sets it on the tag. A version bump is two edits per file: the version
  in the URL and the hash. Take the hash from the published npm package, not
  from the CDN: `npm pack katex@<version>` (or `mermaid@<version>`), unpack it,
  then `openssl dgst -sha384 -binary package/dist/<file> | openssl base64 -A`,
  prefixed with `sha384-`. cdnjs does not carry the script for every Mermaid
  release (11.4.1 has none), so check the address answers before pinning it.
  `handoff2.js` checks that every on-demand file has a hash and that the
  loader puts it on the tag; it does not download the real files.
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
  on any OS.
- `ZEST_CHROMIUM=/path/to/chromium npm test` launches that binary instead of
  the Playwright-managed browser (for sandboxes with a system Chromium).
- The suites talk to ports 8771 (studio), 8772 (image), 8773 (mail),
  8774 (md), 8780 (dist); `run.js` hosts all five in-process.
