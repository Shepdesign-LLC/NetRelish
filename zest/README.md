# Zest

Zest is a brand system you build once and every tool inherits. The flagship at
`zest.netrelish.com` is the brand studio itself — palette, type, tokens, and the
store; the tools take the tokens and make things with them. The core of each
tool stays free and local; what a license buys is everything the local file
can't do on its own — cloud brands and designs, image hosting, publishing to a
link, test sends, metered model assistance, the native macOS shell. The full
product and licensing spec is `docs/ZEST-SPEC.md`; the tenets every tool
follows are `docs/PRESS-TOOLS.md` §1.

## The lineup

| Tool | Fruit / hardware | Where |
|---|---|---|
| **Zest** (studio) | Lemon / dial | `apps/zest` — free core built; the home page at zest.netrelish.com when deployed (spec §8 and §11, decision 5) |
| **ZestMail** | Orange / envelope | `apps/mail` |
| **Zest MD** | Lime / page | `apps/md` |
| **ZestImage** | Grapefruit / frame | `apps/image` — free local core built; Pro greyed until accounts |

## This directory

```
zest/
  docs/
    ZEST-SPEC.md      product, licensing, and launch spec — the source of truth
    PRESS-TOOLS.md    tenets and the tool reference (MD Press / Mail Press era)
    MAIL-PRESS.md     ZestMail's full reference
  apps/
    zest/             Zest, the studio: index.html, sw.js, manifest.webmanifest, zest.json, icons
    mail/             ZestMail: index.html, /api/claude proxy, zest.json, icons
    md/               Zest MD: index.html, sw.js, manifest.webmanifest, zest.json, icons
    image/            ZestImage: index.html, zest.json, icons — free core built
    store/            landing-page draft (index.html); the §10 pricing/terms/account pages are not built
  icons/              the four app icons: svg/, layers/, png/, mono/, fruits.json —
                      and showcase.html, which renders the family in a browser
  vendor/             DOMPurify, KaTeX, Mermaid and the tools' fonts, pinned from npm;
                      VENDOR.lock.json records each file (generated: scripts/vendor.mjs)
  scripts/
    vendor.mjs        fetches vendor/ from npm, writes the lock; --check for CI
    vendor.config.json  what vendor.mjs fetches: each library and font family, pinned
    offline-scan.mjs  offline gate 1: static scan of the app bundle
    offline-allowlist.json  its exceptions (each with a reason) and the size budget
  build.sh            dist/ for the web; --app writes ../Resources/Zest for NetRelish.app
  tests/              Playwright suites, contrast sweeps, and offline.js (offline gate 2)
  infra/
    supabase/0001_init.sql   the Supabase schema from spec §5.1 (written, not deployed)
    fixtures/sample.sql.gz   MySQL dump for import testing — not part of the Zest
                             stack (Supabase is Postgres); header says safe to drop
```

## Run locally

Each tool is a single HTML file, but it loads its fonts and libraries from
the shared `vendor/` folder (`vendor/` from the studio at `/`, `../vendor/`
from the others), so serve the assembled topology, not one app's folder.
Served on its own, a tool finds no `vendor/`: it falls back to system type,
and Zest MD runs without its sanitizer, math and diagrams. Serve over http;
`file://` has a null origin, which breaks the service worker and any API call.

- **All four tools** — `cd zest && bash build.sh && npx serve dist`: the
  studio at `/`, then `/mail`, `/md` and `/image`.
- **ZestMail with the drafting proxy** — `bash build.sh`, then `npx vercel dev`
  from `zest/` (below). Without the proxy, use your own key in the app's
  Direct route.
- **The whole topology** (§8/§11.5: studio at `/`, tools at `/mail` `/md`
  `/image`, store at `/pricing`, API at `/api`) — `cd zest && bash build.sh
  && npx serve dist`. For the API too, run `bash build.sh` first and then
  `npx vercel dev` from `zest/` (`vercel dev` serves functions and the
  built `dist/`, but does not run the build itself). The Vercel project
  points at `zest/`; `vercel.json` carries the build and headers.

## The app bundle (NetRelish.app)

The free tools ship inside NetRelish.app, offline, in their own window
(ADR 0015, moved into 1.0 on Nov 13). The app gets its own copy, generated and
committed at the repo root:

```
cd zest
bash build.sh --app                 # writes ../Resources/Zest (ZEST_APP_OUT=<dir> to build elsewhere)
node scripts/vendor.mjs --check     # vendor/ and Resources/Zest/vendor/ match the lock and npm
node scripts/offline-scan.mjs       # gate 1: no network address in a load position, no pricing or Upgrade
cd tests && ZEST_CHROMIUM=… node offline.js   # gate 2: each tool with every outside request blocked
```

- **What `--app` copies.** The studio at `Resources/Zest/index.html`, the
  tools at `mail/`, `md/` and `image/`, `vendor/` and the root `NOTICE`. It
  leaves out the store, pricing, `api/`, and every file only the web uses:
  `manifest.webmanifest`, `sw.js`, `zest.json`, `vercel.json`, READMEs,
  `package.json`, and the icon sizes only the install manifest names. It
  copies only the files git tracks, so a `.DS_Store` or a scratch file in
  `apps/` never reaches the app (a new file must be `git add`ed before it
  ships). It strips the parts only the web has, which the tools mark
  `<!-- web:start -->` … `<!-- web:end -->` in HTML and `/* web:start */` …
  `/* web:end */` in script and style (pricing, Pro prompts, drafting with a
  model, the service worker, the install manifest), and writes
  `Resources/Zest/README.md`. Same input, same bytes. Never edit
  `Resources/Zest` by hand; rebuild it and commit it with the change that
  caused it. `bash build.sh` with no argument builds `dist/` for the web,
  with `vendor/` copied to `dist/vendor/` (the lock stays out).
- **One switch in each tool.** `IN_APP` is true on `zest:` or under the
  host's `window.netrelish` stub (`host: 'app'`); it sets `html.in-app`. In the
  app the tools register no service worker and ZestMail has no drafting tab.
  The web's plan is not in the app at all: the studio's and ZestImage's Pro
  sections (rows, badges, the account line) sit between web marks, ZestImage
  keeps no cap on saved brands, and the studio has no Share link (a `zest://`
  link opens nowhere else). An image at a web address shows as a placeholder
  that says why, in ZestMail and Zest MD, and their exports keep the real
  `<img>`. Zest MD's PDF is File › Print (⌘P) in the app. The first-run
  defaults are placeholders (`Your brand`, `Your name · your-site.example`).
  `.web-only` hides what the build did not strip; `.app-only` shows only in
  the app.
- **Not in the app target yet.** `project.yml` excludes `Resources/Zest` from
  the flat Resources group. The Zest window adds it as one folder reference.
- **Vendored, pinned, on every surface.** Every page loads its fonts and
  libraries from `vendor/` on its own origin, on the web and in the app: no
  font host, no CDN. `vendor/` holds DOMPurify 3.4.17, KaTeX 0.16.11 and
  Mermaid 11.17.2 (each file's sha384 equals the integrity hash in
  `apps/md/index.html`), and 38 font families as
  latin-subset woff2 from `@fontsource` / `@fontsource-variable`, only the
  weights and styles the tools ask for, with `fonts/fonts.css` and
  `fonts/fonts.json`. To bump one, change `scripts/vendor.config.json`, run
  `node scripts/vendor.mjs`, update the tag or hash in `apps/md/index.html`
  (and `tests/package.json` for DOMPurify), update `NOTICE`, rebuild with
  `--app`, and commit all of it. `--check` fails if `vendor/`, the lock and
  npm disagree, if `Resources/Zest/vendor/` differs from the lock, if
  `Resources/Zest/NOTICE` differs from `NOTICE`, if `NOTICE` misses a
  release, if Zest MD's tag, hashes or the tests' DOMPurify pin disagree
  with the lock, or if Zest MD's inline renderer no longer hashes to its pin
  (`inline` in `vendor.config.json`). It does not compare the tools' HTML in `Resources/Zest` with
  `apps/`; CI does that by rebuilding into a temp folder and diffing.
- **Size.** 6.91 MB (7,250,832 bytes, 143 files) on 2026-11-14, 86% of
  the 8 MB budget in `scripts/offline-allowlist.json` (the scan fails above
  it): Mermaid 3.41 MB, fonts 2.00 MB, KaTeX 0.54 MB, Zest MD 0.43 MB, the
  studio with NOTICE and the README 0.18 MB, ZestMail 0.17 MB, ZestImage
  0.16 MB.
- **Exports carry their own type.** The studio's `@font-face` export and Zest
  MD's HTML export embed the faces they name as `data:` URIs read from
  `vendor/`, so a saved file loads nothing; ZestImage embeds the brand faces
  in its SVG the same way. The brand file's `googleFontsUrl` stays in the
  format, empty.
- **The gates pass, and they block.** CI's `app-bundle` job in
  `.github/workflows/zest-tests.yml` reads the committed `Resources/Zest`
  (never a rebuild of it). The vendor check, the rebuild-and-diff, the static
  scan and `offline.js` all fail the PR (`ZEST_OFFLINE_ENFORCE: 'true'`).
  `npm test` in `tests/` runs `offline.js` and `inapp.js` too, on a fresh
  build in a temp folder.

## Sound

Every tool plays a short sound when you copy, save, add or remove something,
switch a tab or mode, or hit something it will not do. The sounds are
synthesized in the browser (Web Audio): no audio files, no requests. One kit,
`window.ZestSound = { play(name), muted, setMuted(bool) }` with five sounds
(`tap`, `pop`, `drop`, `done`, `nope`), is inlined in each tool between
`/* zest-sound:start v1 */` and `/* zest-sound:end */`. Each tool has one
**Sound** toggle; the choice is stored under one `localStorage` key,
`zest.sound` (`on` or `off`, on by default), shared by every tool on the same
origin. Nothing plays before the first click or key press. `tests/sound.js`
covers it; `tests/README.md` says how to change the kit.

## Status against ZEST-SPEC §10, Milestone 1

In hand:

- Renames done in UI strings (Mail Press → ZestMail, MD Press → Zest MD);
  internal identifiers kept verbatim per spec §2
- `zest.json` manifests done for mail and md
- New marks done for md and mail (all four icons exist under `icons/`)
- Supabase schema written (`infra/supabase/0001_init.sql`) — written is not deployed
- The studio's free core (`apps/zest`): OKLCH palettes with locks, pairings,
  custom fonts, exports, share links, WCAG audit
- `zest-brand.json` schema (§7.3) and the full handoff: export from the
  studio; import in ZestImage, ZestMail (Import…, in the Export menu or on the Brand tab) and Zest MD (custom skin)
- The one-origin deploy topology in-repo (`build.sh` + `vercel.json` +
  shared `api/`): studio at `/` with the §11.5 tools row, tools at their
  paths, store at `/pricing`

Not done:

- Vercel project + subdomain CNAME (console steps — the repo side is ready)
- Supabase deploy
- Stripe products, Checkout, webhook provisioning, portal
- Magic-link auth via Resend
- `can()` gating with upgrade prompts
- Pricing page, terms, privacy, refund policy, changelog
- Account page with Export everything
- Pro features across all four tools wait on accounts

## Not the browser

Zest is a separate product line from the NetRelish browser — a web stack
(Vercel, Supabase, Stripe; spec §8) staged in this repo until its own monorepo
exists (`docs/adr/0008` in the repo root's `/docs`). Its free tools also ship
inside NetRelish.app, offline (ADR 0015; see "The app bundle" above): the app
is to bundle the generated `Resources/Zest`, never this directory, and no Xcode
target references `zest/`. The browser's
privacy rule — CLAUDE.md non-negotiable 5, browsing data never leaves the
device — is untouched by anything in it: Zest's endpoints belong to Zest's web
apps, not to NetRelish.app.
