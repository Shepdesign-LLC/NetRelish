# netrelish-site — design

**Date:** 2026-09-16 (rev 2, after Ryan's Sept 12 draft) · **Status:** approved for build (Ryan, this session) · **Repo:** `Shepdesign-LLC/netrelish-site` (new)

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
    components/           Nav, Hero, SealStage, Row, Intelligence, Pickle, Pro, Questions, JoinForm, Footer — one file each
    components/mocks/     the CSS mock objects for §4.3 (Tray, Shelf, Inspector, PantryResults, Recipe)
    styles/site.css       everything the page needs beyond tokens.css
  astro.config.mjs, package.json, .github/workflows/ci.yml, README.md, LICENSE (MIT; mark excluded)
```

`design/` is never edited in this repo. `check-design.sh` fetches the four files from `Shepdesign-LLC/NetRelish` at the commit recorded in `design/SOURCE` and diffs them. Updating the design means bumping `SOURCE` and copying, in one commit.

## 4 · The page

One route, `/`. Structure follows Ryan's Sept 12 draft (`netrelish-site.html`), rebuilt on manifest v1.1.1: current tokens, `symbols.svg`, system type below the hero, relish only where §6 says. Every section is a component with one job. Where the draft used placeholder screenshots there is no app to screenshot yet, so those slots are CSS mock objects built from the design-kit components (tab strip, shelf, inspector) — real screenshots replace them when P1 lands.

### 4.0 Nav

Sticky, `--nr-bg` solid (no blur, no glass — manifest §6), hairline bottom. Left: `logo-cog.svg` at 30px + "NetRelish" in `--font-ui` 600. Right: text links *How it works · Intelligence · Pro · Questions*, then a secondary button **Join the beta** that scrolls to the hero form. At launch the button becomes *Download*.

### 4.1 Hero

- `logo-cog.svg` at 132px beside the copy (clear space ½ width). No drop shadow — the manifest allows none on the mark.
- H1 in `--font-hero`, wght 800 / wdth 100 / opsz 96: **"Keep the pages that matter."**
- Sub, `--font-ui` `--fs-xl` in `--nr-fg-2`: *"NetRelish is a Mac browser with a pantry. Save any page with one key, sort it into jars, and seal the ones you'll need again — searchable, summarized on your Mac, offline."*
- The join form inline (§5): email field + primary button **"Join the beta"** — the page's one relish button. Beside it a secondary button *See how it works* → `#how`.
- Requirement line, `--fs-sm` in `--nr-fg-3`: *"macOS 27 or later · Apple silicon · Free, with a Pro upgrade · Beta invites go out in waves."*

### 4.2 The Seal stage (in the hero)

The draft's centerpiece, kept: a mock browser window in a `--nr-surface-2` stage with `--r-3` corners. Window bar with three tabs (active tab carries `#nr-lip`, others carry shelf-life bars), a `--shelf-w` shelf with three `#nr-jar`, a page of hairline placeholder lines. On a 4.4s loop: a page card lifts, shrinks toward the active jar (`--relish-100` tint), the lid caps, **one drip runs** (`#nr-drip`, relish — this is the Seal's drip and the only one on the page), the active tab collapses so the count visibly drops, a badge toast *Sealed to Reference* (`--relish-100` bg, `--relish-700` text). Plays only while in view (IntersectionObserver); `prefers-reduced-motion` freezes it on the final frame. Caption under it: *Press ⌘S. The page is preserved, the tab closes, the jar keeps it.*

The card gets the one floating-sheet shadow the manifest allows; nothing else on the page has a shadow.

### 4.3 How it works — five rows, alternating

Each row: mono eyebrow in `--nr-fg-3`, H2 in `--font-ui` 600 `--fs-2xl`, one or two paragraphs in `--nr-fg-2`, and a mock object opposite.

| Eyebrow | H2 | Copy | Mock |
|---|---|---|---|
| Capture | One key to save anything. | Press ⌘D on any page, or share from any app. It lands in Brine, right where you can see it. Nothing gets lost in a bookmarks folder again. | Brine tray with three items |
| Sort | Jars, not folders. | Drag a saved page onto a jar on the Shelf. Jars are where your projects live — clients, research, reading, whatever you're working on this month. Every jar is its own profile: its own cookies, its own logins. Switch with ⌘1–9. | Shelf with four jars, one active |
| Seal | Seal it, and it's yours. | Sealing saves a complete snapshot, closes the tab, and runs the jar's Recipe. The page is preserved exactly as you saw it and never changes. The tab count goes down. That's the point. | Inspector after a seal |
| Search | Search what you kept, not the whole internet. | Every sealed page is indexed in full. Find it from Ask the Pantry or straight from Spotlight. | Ask the Pantry result rows with `#nr-jar` provenance chips |
| Recipes | Workflows that run on save. | A Recipe is a short list of steps: label it, move it, summarize it, export it. Attach one to a jar and it runs on every seal. Every Recipe is a Shortcut, so Siri and the rest of your Mac can run it too. | Recipe row beside a Shortcuts tile |

### 4.4 Intelligence

Eyebrow *Apple Intelligence*. H2 **Built for Apple Intelligence. Reads only what you've kept.** Four items in a 2×2, the §11 claims in the draft's words, bound by non-negotiable 4:

1. **Summaries, on your Mac.** Every sealed page gets a summary from on-device Foundation Models. No page leaves the machine.
2. **Seal sorts for you.** Kind, labels, and a suggested jar are proposed at seal time, from the snapshot.
3. **Siri and Shortcuts.** Every Recipe is an App Intent. "Seal this into Clients" works from Siri, Shortcuts, the Action button, and Focus.
4. **Nothing to trick.** Intelligence reads sealed snapshots, never a live tab or a logged-in session. There's no agent in your browser for a page to hijack.

(The draft's "Visual Intelligence on capture" is dropped: reading on the way in is not reading a sealed snapshot.)

### 4.5 Pickle

Eyebrow *Pickle · coming in 1.2 · Direct build*. H2 **A jar that runs your site.** One paragraph from the draft: a Pickle is a jar with a local environment inside it — one click starts it on your Mac with OrbStack or Docker, opens it on the Bench, and keeps it in step with a GitHub repo you sign into once. Mock: `#nr-jar-pickle` beside a mono line *localhost:8080 · main · synced*.

### 4.6 Pro

On `--nr-surface-2`. Eyebrow *Pro*. H2 **Pro turns saved pages into evidence.** A four-cell hairline grid — Reseal and diff · Provenance · Jar bundles · Unlimited recipes + semantic search — then two plan cards, hairline-bordered, no relish border, no drip:

- **Free · $0 · forever** — Capture, jars, seal, full-text search · 3 Recipes · Share extension, Spotlight, Shortcuts.
- **Pro · $39 · per year, or $99 once** — Everything in Free · Reseal and diff, provenance export · Jar bundles, unlimited Recipes · Semantic search.

Contents are ADR 0003. List markers are plain (no relish bullets). Each card's action is a secondary button *Join the beta* → hero form; at launch, *Download* / *Get Pro*. Fine print: *"One price. No seats, no tiers, no telemetry. Buy once, use forever."*

### 4.7 Questions

Six `<details>` rows from the draft, hairline-separated, marker in `--nr-fg-2`: Is it a browser? (WebKit, same engine as Safari) · Where's my data? (a database on your Mac; export any time as a jar bundle) · Does it need an account? (No) · Extensions? (No; Recipes and Shortcuts do that job without the security surface) · Windows? (No plans) · Open source? (MIT on GitHub; the name and mark are ours).

### 4.8 Footer

`logo.svg` at 24px, © 2026 Shepdesign LLC, links GitHub · Privacy, and right-aligned *Built on WebKit. Nothing leaves your Mac.* Press and Changelog links from the draft are omitted until those pages exist.

### 4.9 `/thanks`

Cog at 40px, one line — *"You're on the list. Beta invites go out in waves; you'll hear from us."* — and a text link back. Empty-state pattern from manifest §8.

### 4.10 `/privacy`

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

Light and dark from `tokens.css` via `prefers-color-scheme`; no toggle in v1 (the manifest's `data-theme` hook stays available). Body background is explicit. Relish appears only in: the hero primary button (placement #8); the cog's own fill (#8); and, inside the mock windows under "below the hero follows product rules", the active tab lip (#2), the active jar tint (#3), the seal glyph and the Seal animation's one drip (#4), shelf-life bars (#5), and the *Sealed* badge (#6). Not on bullets, card borders, secondary buttons, or headings. Links are `--nr-fg` underlined. Focus ring is `--nr-focus`.

## 7 · OG image

`public/og.png`, 1200×630: `logo-cog.svg` on `--nr-bg` with the H1 in the system stack. Produced once by `scripts/gen-og.mjs` (sharp, dev dependency) and committed; regenerated only when the copy changes. Meta: `og:title`, `og:description`, `og:image`, `twitter:card=summary_large_image`, canonical `https://netrelish.com/`.

## 8 · Testing and CI

- **Unit:** `join.ts` handler — honeypot, bad email, Bento 500, Bento success — with Bento mocked. Vitest.
- **Build:** `astro build` must succeed; `astro check` clean.
- **Design drift:** `scripts/check-design.sh` — the four files match the pinned NetRelish commit.
- **Network rule:** after build, grep `dist/` for `https?://` and fail on any host other than `netrelish.com`, `github.com`, and `apps.apple.com`.
- **Relish audit:** grep the built CSS for `--relish-500` usages; fail if any selector outside the §6 allowlist uses it. The Pro card and list markers are explicitly asserted relish-free.
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
- **Free/Pro contents:** ADR 0003, adopted from Ryan's Sept 12 draft.
- **Headline:** "Keep the pages that matter." (Ryan's draft) over the manifest's voice example.
- **Type below the hero:** system stack per manifest; the draft's Bricolage headings are not carried over.
- **Relish extras in the draft** (bullets, Pro-card border and drip, secondary-button outlines): dropped per manifest v1.1.1.
