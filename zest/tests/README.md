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
| `test.js` (66) | Studio: roles, OKLCH harmony, locks, shuffle, type palettes, font upload/replacement, brand export/import round-trips, logo handling, share links, ZestImage brand import, no uncaught exceptions |
| `handoff2.js` (41) | Brand handoff studio → Mail and MD: token import, font mapping, serif stacks, name whitelisting, JSON routing, persistence, the DOMPurify XSS fix in MD (sanitized path *and* fail-closed path with the CDN blocked) |
| `topology.js` (38) | The assembled `dist/`: studio at `/`, tools at `/mail` `/md` `/image`, store at `/pricing`, scope-relative service workers and manifests, tools-row links, cross-app brand download |
| `contrast-audit.js` | Full-page WCAG text-contrast sweep (alpha compositing, gradient detection) on Mail, MD (dark **and** light scheme — its reader skins react to `prefers-color-scheme`), and the studio — any failure fails the run. Mail and the studio ship one fixed dark chrome, so a single sweep covers them |

## Notes

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
- `fixtures/` holds two Caladea TTFs (SIL OFL 1.1, license included) for the
  studio's font-upload round-trip — no system font paths, so the suite runs
  on any OS.
- `ZEST_CHROMIUM=/path/to/chromium npm test` launches that binary instead of
  the Playwright-managed browser (for sandboxes with a system Chromium).
- The suites talk to ports 8771 (studio), 8772 (image), 8773 (mail),
  8774 (md), 8780 (dist); `run.js` hosts all five in-process.
