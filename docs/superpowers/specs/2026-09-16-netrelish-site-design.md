# netrelish-site — design

**Date:** 2026-09-16 · **Status:** approved for build (Ryan, this session) · **Repo:** `Shepdesign-LLC/netrelish-site` (new)

The marketing site for NetRelish. One page, launch-ready today, collecting beta leads into Bento. Governed by `netrelish/design/DESIGN_MANIFEST.md` §10 (Site) and `tokens.css`; this document adds only what the manifest leaves to the site.

## 1 · Job

Between now and the Dec 14, 2026 Mac App Store launch, the site does one thing: turn a visitor into a beta lead. At launch the CTA flips to the App Store link with no rebuild of the page structure.

The promise made to a lead is **beta access, invited in waves**. Ryan chooses who gets a build and when, from Bento. The site never says "download now" until there is something to download.

**Apple-only.** NetRelish runs on macOS 27 or later, from the Mac App Store. The site says "Mac" everywhere, states the requirement plainly, and never hints at Windows, Linux, iPhone, or web. (iPhone Duo is post-1.0 and does not appear.)

## 2 · Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | Astro 5, `output: 'static'`, `@astrojs/vercel` adapter | Locked in CLAUDE.md. Static pages; the adapter exists only for the one endpoint. |
| CSS | Plain CSS, `tokens.css` imported unchanged | Locked. No Tailwind, no preprocessor. |
| Fonts | Bricolage Grotesque variable (OFL) self-hosted in `/public/fonts`, used only in the hero. Everything else `--font-ui`. | Manifest §5. Self-hosted so the page makes zero third-party requests. |
| Hosting | Vercel project `netrelish` (existing, currently paused) re-linked to the new repo | Keeps the project, its history, and the team. |
| Domain | `netrelish.com` (Ryan owns it) | Canonical URLs and OG tags built for it. |
| Lead capture | `POST /api/join` → Bento API | §5. |
| Analytics | None. No Vercel Web Analytics, no Speed Insights, no tracking script. | A product whose rule is "browsing data never leaves the device" does not ship a tracker on its own site. |

**Network rule for the browser:** a visitor's browser makes requests only to `netrelish.com`. No CDN fonts, no analytics, no embeds. This is checked in CI (§8).

## 3 · Repo layout

```
netrelish-site/
  design/                 tokens.css, logo-cog.svg, logo.svg, symbols.svg — byte-for-byte copies
  scripts/check-design.sh verifies design/ matches netrelish/design at a pinned commit; CI fails on drift
  public/fonts/           BricolageGrotesque[opsz,wdth,wght].woff2 + OFL.txt
  public/og.png           1200×630, generated (§7)
  src/
    layouts/Base.astro    <head>, tokens.css, theme, footer
    pages/index.astro     the page
    pages/thanks.astro    post-signup
    pages/privacy.astro   what the form does with an email
    pages/api/join.ts     the one server route (prerender = false)
    components/           Hero, Section, Pricing, JoinForm, Footer — one file each
    styles/site.css       everything the page needs beyond tokens.css
  astro.config.mjs, package.json, .github/workflows/ci.yml, README.md, LICENSE (MIT; mark excluded)
```

`design/` is never edited in this repo. `check-design.sh` fetches the four files from `Shepdesign-LLC/NetRelish` at the commit recorded in `design/SOURCE` and diffs them. Updating the design means bumping `SOURCE` and copying, in one commit.

## 4 · The page

One route, `/`, sections in this order. Every section is a component with one job.

### 4.1 Hero

- `logo-cog.svg` at 64px (manifest: shown larger than the full mark would be; clear space ½ width).
- H1 in `--font-hero`, wght 800 / wdth 100 / opsz 96: **"The browser that preserves your work."**
- One paragraph in `--font-ui`, `--fs-lg`: what it is, in product words. Draft: *"NetRelish is a Mac browser with a pantry. Idle tabs sink into brine. The ones worth keeping you seal into jars — searchable, private, and never leaving your Mac."*
- The join form inline (§5): email field + primary button **"Join the beta"**. This is relish placement #8 and the page's only primary button.
- Requirement line under the form, `--fs-sm` in `--nr-fg-2`: *"macOS 27 or later · Mac App Store · Beta invites go out in waves."*

### 4.2 What it does

Four items, nouns from the vocabulary, one line each, `#nr-jar` / `#nr-seal` / `#nr-sink` from `symbols.svg` where a jar, seal, or sinking is meant. No other icons.

| Noun | Line |
|---|---|
| Jars | Every project is a jar. Every jar is a profile — its own cookies, its own logins. Nothing crosses. |
| Brine | Tabs you stop using sink instead of piling up. Pinned tabs never sink. |
| Seal | ⌘S freezes the page as a `.webarchive`, closes the tab, and files it. Sealed pages don't change. |
| Recipes | Record what you do in a jar; replay it with ⌘R. Every Recipe is a Shortcut. |

Symbols render in `--nr-fg`; `#nr-seal` is the exception and renders in `--relish-500` (placement #4).

### 4.3 On your Mac, on device

The four §11 claims, substance locked, one short line each:

1. **Ask the Pantry runs on-device.** It answers over what you've sealed. Nothing leaves the Mac.
2. **Recipes are Shortcuts.** Siri and Shortcuts can run any Recipe.
3. **Seal sorts for you.** Kind, labels, and a suggested jar are proposed from the sealed snapshot.
4. **Writing Tools in your notes.** Notes on sealed pages get system Writing Tools.

Followed by the privacy line, stated exactly as the non-negotiable allows: *"NetRelish makes no network calls except the pages you load, the App Store, and — on Pro — a signed timestamp for your sealed pages."*

### 4.4 Pricing

Two columns, hairline-separated, secondary-button styling only (no second relish fill on the page).

- **Free** — the browser: jars, brine, seal, Ask the Pantry, Recipes.
- **Pro** — **$39/yr or $99 lifetime.** Line items: *Provenance — every sealed page carries a signed RFC 3161 timestamp.* Further Pro items are added when P4 decides them; the component takes a list.
- Block ends with the sentence **"Buy once, use forever."** (manifest §10, verbatim).
- Both columns' action is the same text link, `--nr-fg` underlined: *"In beta — join the list"* → scrolls to the hero form. At launch this becomes the App Store badge.

### 4.5 Footer

Open-core line: *"NetRelish is open source under MIT. The name, the mark, and the App Store listing are reserved."* Links: GitHub, Privacy, `hello@` (Ryan supplies the address or the link is omitted). Mark at 16px is `logo.svg`, not the cog.

### 4.6 `/thanks`

Cog at 40px, one line — *"You're on the list. Beta invites go out in waves; you'll hear from us."* — and a text link back. Empty-state pattern from manifest §8.

### 4.7 `/privacy`

Plain words, `--font-ui`: the email goes to Bento (the mailing tool), is tagged for the NetRelish beta, is used only for beta invites and launch news, and is deleted on request. The page sets no cookies and loads nothing from third parties.

## 5 · Lead capture

### Browser side

A plain `<form method="post" action="/api/join">` with:
- `email` (type email, required, autocomplete email)
- `website` — honeypot, visually hidden, must be empty
- no JavaScript required. With JS available, the form submits via `fetch` and swaps in the thanks line without leaving the page; without it, the server redirects to `/thanks`.

### Server side — `src/pages/api/join.ts`

`export const prerender = false`. Runs as a Vercel function. Steps:

1. Reject unless `Content-Type` is form or JSON and `Origin`/`Referer` is `netrelish.com` (or the Vercel preview host).
2. Honeypot filled → respond as success, record nothing.
3. Validate the email shape. Fail → 400 with a one-line message the form shows.
4. `POST https://app.bentonow.com/api/v1/batch/subscribers?site_uuid=…` (base URL confirmed with a real call before the PR opens) with Basic auth (`BENTO_PUBLISHABLE_KEY:BENTO_SECRET_KEY`), `User-Agent: netrelish-site/1.0`, body `{ subscribers: [{ email, tags: "netrelish-beta,lead", signup_source: "netrelish.com" }] }`. Bento creates the `netrelish-beta` tag on first use.
5. `POST …/v1/batch/events` with one event `{ type: "$netrelish_beta_join", email }` so a Bento Flow can send a welcome email. (The subscribers import alone does not trigger Flows.)
6. Bento unreachable or non-2xx → 502 with *"Couldn't reach the list — try again in a minute."* Never a silent success.
7. Success → 303 to `/thanks` (form post) or `{ ok: true }` (fetch).

Secrets: `BENTO_PUBLISHABLE_KEY`, `BENTO_SECRET_KEY`, `BENTO_SITE_UUID` as Vercel environment variables, set by Ryan in the dashboard. Never in the repo, never in `.env.example` with real values. Locally the endpoint reads the same names from `.env` (gitignored).

Why the `netrelish-beta` tag matters: Ryan's Bento site is shared with other businesses (`care-*`, `seo-*` tags exist). The tag is the only thing separating NetRelish leads.

## 6 · Theme

Light and dark from `tokens.css` via `prefers-color-scheme`; no toggle in v1 (the manifest's `data-theme` hook stays available). Body background is explicit. Relish appears in exactly three places: the hero primary button (placement #8), the cog's own fill (#8), and the `#nr-seal` glyph in §4.2 (#4, under "below the hero follows product rules"). Links are `--nr-fg` underlined. Focus ring is `--nr-focus`.

## 7 · OG image

`public/og.png`, 1200×630: `logo-cog.svg` on `--nr-bg` with the H1 in the system stack. Produced once by `scripts/gen-og.mjs` (sharp, dev dependency) and committed; regenerated only when the copy changes. Meta: `og:title`, `og:description`, `og:image`, `twitter:card=summary_large_image`, canonical `https://netrelish.com/`.

## 8 · Testing and CI

- **Unit:** `join.ts` handler — honeypot, bad email, Bento 500, Bento success — with Bento mocked. Vitest.
- **Build:** `astro build` must succeed; `astro check` clean.
- **Design drift:** `scripts/check-design.sh` — the four files match the pinned NetRelish commit.
- **Network rule:** after build, grep `dist/` for `https?://` and fail on any host other than `netrelish.com`, `github.com`, and `apps.apple.com`.
- **Relish audit:** grep the built CSS for `--relish-500` usages; fail if any selector other than the three in §6 uses it.
- **Accessibility:** form has a visible label, contrast is from the token pairs the manifest already passes, `prefers-reduced-motion` respected (the only motion is the button hover).

## 9 · Vercel and DNS (Ryan's clicks, in order — I write the exact steps in the PR)

1. Un-pause the `netrelish` project.
2. Settings → Git: disconnect `NetRelish`, connect `netrelish-site`. Root Directory: blank. Framework: Astro.
3. Settings → Environment Variables: the three Bento values, Production + Preview.
4. Settings → Domains: add `netrelish.com` and `www` → redirect to apex. Add the A/CNAME records Vercel shows at the registrar.
5. Push to `main` deploys.

## 10 · Demo (in the PR)

1. Open the preview URL Vercel posts on the PR. Light and dark both render.
2. Submit your own email in the hero form → `/thanks`.
3. In Bento, the subscriber exists with tag `netrelish-beta` and `signup_source = netrelish.com`. (I verify this through the Bento connector and paste the result in the PR.)
4. Turn JavaScript off, repeat step 2 — same result.

## 11 · Out of scope

Blog, docs, changelog, press kit, a second language, an App Store badge before there is a listing, any numbers on the page ("412 preserved") until there are real ones, a dark/light toggle, cookie banner (nothing to consent to).

## 12 · Decisions recorded here

- **Lead capture goes through a server route, not Bento's script.** Chosen by Ryan this session over `bento.js` and the hosted embed, for the network rule.
- **Beta promise is "invited in waves."** Chosen by Ryan.
- **Pro line items:** only provenance timestamps are documented. Others are P4's call; the site does not guess.
