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
| `test.js` (98) | Studio: roles, OKLCH harmony, locks, shuffle, type palettes, font upload/replacement, brand export/import round-trips, logo handling, share links, ZestImage brand import, the folds (four closed on every load and Pro open on every load, all worked by keyboard, their controls still reach the preview, the export and the next visit), the one Light/Dark switch, Send to, no uncaught exceptions |
| `handoff2.js` (89) | Brand handoff studio → Mail and MD: token import, font mapping, serif stacks, name whitelisting, JSON routing, persistence, the DOMPurify XSS fix in MD (sanitized path *and* fail-closed path with the CDN blocked). Untrusted input: Mail's design import, reload and tampered storage (nothing runs, an honest design re-imports byte-identical, a design never changes a brand that is already there, link-valued merge tags are checked as links); MD's Contents list built from hostile heading ids (dropped file and `?text=` link), its saved reader settings, the integrity hashes on the sanitizer tag and on every on-demand file, and Mermaid always configured `strict` |
| `topology.js` (38) | The assembled `dist/`: studio at `/`, tools at `/mail` `/md` `/image`, store at `/pricing`, scope-relative service workers and manifests, tools-row links, cross-app brand download |
| `mobile.js` (38) | Every surface at 390×844 with touch (plus a landscape-phone case): no layout-viewport blowout, panels reachable, and each core flow works by tap — Mail's drawer/bottom-sheet/scaled canvas, MD's wrapped bar + Contents drawer + clamped popovers, the studio's capped preview + jump nav, Image's docked preview, the store's menu and stacked comparison table |
| `sound.js` (135) | The sound kit and its mute toggle in all four tools: the kit block is present and the four copies are byte-identical; nothing plays, and no audio context is made, before the first real click or key press; each wired interaction asks for its sound and stays quiet and short; the Sound toggle has a name and `aria-pressed`, works by keyboard, and its choice survives a reload under the one shared key `zest.sound`; muted means no oscillator starts; nothing throws without Web Audio or without `localStorage`; no request goes to a new host |
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
