# netrelish-site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and ship `Shepdesign-LLC/netrelish-site` — the one-page NetRelish marketing site that collects beta leads into Bento — on Vercel at netrelish.com.

**Architecture:** Astro static site with plain CSS on `tokens.css`; one server route (`/api/join`) runs as a Vercel function and forwards the email to Bento's API. Every section is one component; the app mock-ups are CSS objects built from the design-kit components. CI enforces the design files match the NetRelish repo, that the built site makes no third-party requests, and that relish appears only where the manifest allows.

**Tech Stack:** Astro 7.3, `@astrojs/vercel` 11, Vitest 5, TypeScript, `@fontsource-variable/bricolage-grotesque` (self-hosted OFL font), `sharp` (dev only, OG image). Node 22.

**Spec:** `docs/superpowers/specs/2026-09-16-netrelish-site-design.md` (in the NetRelish repo). Design of record: `netrelish/design/DESIGN_MANIFEST.md` and `tokens.css`.

## Global Constraints

- The visitor's browser requests only `netrelish.com` origins. No CDN fonts, no analytics, no embeds, no `bento.js`.
- `design/` in the site repo is a byte-for-byte copy of `netrelish/design/{tokens.css,logo.svg,logo-cog.svg,symbols.svg}` at the commit in `design/SOURCE`. Never edited in the site repo.
- Type: `--font-hero` (Bricolage Grotesque wght 800 / wdth 100 / opsz 96) on the H1 only. Everything else `--font-ui`, weights 400/500/600.
- Relish (`--relish-*`) only on: hero primary button, cog fill, and inside mock windows the active tab lip, active jar tint, seal glyph, Seal drip, shelf-life bars, Sealed badge. Never on bullets, card borders, secondary buttons, headings, links.
- Links: `--nr-fg` underlined. Focus ring: `--nr-focus`. No blur, no glass, no gradients, no shadows except the one on the Seal card.
- One primary (relish) button on the page: "Join the beta" in the hero.
- Copy says Mac / macOS 27 or later / Mac App Store. Never Windows, Linux, iPhone, web.
- Vocabulary: Pantry · Jar · Brine · Seal · Recipe · Shelf · Bench · Inspector · Ask the Pantry · Pickle. No pantry puns in headings.
- Secrets `BENTO_PUBLISHABLE_KEY`, `BENTO_SECRET_KEY`, `BENTO_SITE_UUID` come from env only. Never committed.
- Commits: conventional, end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Ryan does not run commands. Everything below is run by the implementer.

---

## File map

| Path | Responsibility |
|---|---|
| `astro.config.mjs` | static output, Vercel adapter, site URL |
| `package.json` | scripts: dev, build, check, test, ci |
| `design/` + `design/SOURCE` | the four design files and the NetRelish commit they came from |
| `scripts/check-design.sh` | fails if `design/` drifts from NetRelish at `SOURCE` |
| `scripts/check-network.mjs` | fails if `dist/` references a foreign host |
| `scripts/check-relish.mjs` | fails if built CSS uses `--relish-*` outside the allowlist |
| `scripts/gen-og.mjs` | renders `public/og.png` from the cog and the H1 |
| `src/styles/site.css` | reset, type scale, theme, buttons, hairlines, layout primitives |
| `src/layouts/Base.astro` | `<head>`, meta/OG, font import, tokens, Nav, Footer slot |
| `src/components/Nav.astro` | sticky nav |
| `src/components/Hero.astro` | cog, H1, sub, JoinForm, requirement line, SealStage |
| `src/components/JoinForm.astro` | the form + progressive-enhancement script |
| `src/components/SealStage.astro` | the animated mock window |
| `src/components/Row.astro` | eyebrow / H2 / copy / mock, alternating |
| `src/components/mocks/*.astro` | Tray, Shelf, Inspector, PantryResults, Recipe |
| `src/components/Intelligence.astro`, `Pickle.astro`, `Pro.astro`, `Questions.astro`, `Footer.astro` | one section each |
| `src/lib/join.ts` | `handleJoin(request, deps)` — all endpoint logic, testable |
| `src/pages/api/join.ts` | Astro route: adapts `handleJoin` to `APIRoute` |
| `src/pages/index.astro`, `thanks.astro`, `privacy.astro` | the three pages |
| `test/join.test.ts` | Vitest for `handleJoin` |
| `.github/workflows/ci.yml` | check-design, test, build, check-network, check-relish |

---

### Task 1: Repo scaffold that builds

**Files:**
- Create: `package.json`, `astro.config.mjs`, `tsconfig.json`, `.gitignore`, `.nvmrc`, `README.md`, `LICENSE`, `src/pages/index.astro`, `src/env.d.ts`

**Interfaces:**
- Produces: a repo at `~/Projects/netrelish-site` with `npm run build` green and `dist/index.html` present. `npm run ci` runs everything later tasks add.

- [ ] **Step 1: Create the GitHub repo and local clone**

```bash
gh repo create Shepdesign-LLC/netrelish-site --public --description "The NetRelish site. Astro, plain CSS, one page." --clone
cd ~/Projects/netrelish-site
```

- [ ] **Step 2: Write package.json**

```json
{
  "name": "netrelish-site",
  "private": true,
  "type": "module",
  "engines": { "node": ">=22" },
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "check": "astro check",
    "test": "vitest run",
    "check:design": "bash scripts/check-design.sh",
    "check:network": "node scripts/check-network.mjs",
    "check:relish": "node scripts/check-relish.mjs",
    "og": "node scripts/gen-og.mjs",
    "ci": "npm run check:design && npm run check && npm run test && npm run build && npm run check:network && npm run check:relish"
  },
  "dependencies": {
    "@astrojs/vercel": "^11.0.10",
    "@fontsource-variable/bricolage-grotesque": "^5.3.0",
    "astro": "^7.3.3"
  },
  "devDependencies": {
    "@astrojs/check": "^0.9.10",
    "sharp": "^0.35.4",
    "typescript": "^7.0.2",
    "vitest": "^5.0.1"
  }
}
```

- [ ] **Step 3: Write astro.config.mjs, tsconfig.json, env.d.ts, .gitignore, .nvmrc**

`astro.config.mjs`:
```js
import { defineConfig } from 'astro/config';
import vercel from '@astrojs/vercel';

export default defineConfig({
  site: 'https://netrelish.com',
  output: 'static',
  adapter: vercel(),
  build: { inlineStylesheets: 'never' },
});
```

`tsconfig.json`:
```json
{ "extends": "astro/tsconfigs/strict", "include": [".astro/types.d.ts", "src/**/*", "test/**/*", "scripts/**/*"] }
```

`src/env.d.ts`:
```ts
/// <reference types="astro/client" />
```

`.gitignore`:
```
node_modules/
dist/
.vercel/
.astro/
.env
.env.*
!.env.example
.DS_Store
```

`.nvmrc`: `22`

- [ ] **Step 4: Write the first index page and README, LICENSE**

`src/pages/index.astro`:
```astro
---
---
<html lang="en"><head><meta charset="utf-8"><title>NetRelish</title></head><body><h1>NetRelish</h1></body></html>
```

`README.md`:
```markdown
# netrelish-site

The site for NetRelish, a Mac browser with a pantry. One page, Astro, plain CSS on the design tokens from the app repo. Deployed to netrelish.com on Vercel.

- `design/` is a byte-for-byte copy of `Shepdesign-LLC/NetRelish/design` at the commit in `design/SOURCE`. Never edit it here; bump `SOURCE` and copy.
- `npm run ci` is what CI runs: design drift, type check, tests, build, network rule, relish audit.
- The one server route, `/api/join`, forwards a beta signup to Bento. It needs `BENTO_PUBLISHABLE_KEY`, `BENTO_SECRET_KEY`, `BENTO_SITE_UUID` in the environment.

Code is MIT. The NetRelish name, `logo.svg`, and `logo-cog.svg` are all rights reserved and excluded from the license.
```

`LICENSE`: the MIT text with copyright "2026 Shepdesign LLC", followed by:
```
Exclusions: the NetRelish name and the files design/logo.svg and design/logo-cog.svg
are not licensed under these terms. All rights reserved.
```

- [ ] **Step 5: Install and build**

Run: `npm install && npm run build`
Expected: build succeeds; `ls dist/index.html` exists (Vercel adapter emits `.vercel/output` too).

- [ ] **Step 6: Commit and push**

```bash
git add -A && git commit -m "chore: astro scaffold that builds

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" && git push -u origin main
```

---

### Task 2: Design files, pinned to the NetRelish repo

**Files:**
- Create: `design/tokens.css`, `design/logo.svg`, `design/logo-cog.svg`, `design/symbols.svg`, `design/SOURCE`, `scripts/check-design.sh`

**Interfaces:**
- Produces: `design/tokens.css` importable from CSS; `design/logo-cog.svg`, `design/logo.svg`, `design/symbols.svg` readable at build time via `fs`. `npm run check:design` exits 0 when they match NetRelish at `SOURCE`.

- [ ] **Step 1: Copy the files and record the source commit**

```bash
SRC=~/Projects/netrelish
mkdir -p design
for f in tokens.css logo.svg logo-cog.svg symbols.svg; do cp "$SRC/design/$f" design/; done
git -C "$SRC" rev-parse HEAD > design/SOURCE
```

- [ ] **Step 2: Write scripts/check-design.sh**

```bash
#!/usr/bin/env bash
# design/ must equal Shepdesign-LLC/NetRelish/design at the commit in design/SOURCE.
set -euo pipefail
cd "$(dirname "$0")/.."
sha=$(tr -d '[:space:]' < design/SOURCE)
fail=0
for f in tokens.css logo.svg logo-cog.svg symbols.svg; do
  url="https://raw.githubusercontent.com/Shepdesign-LLC/NetRelish/$sha/design/$f"
  if ! curl -fsSL "$url" | cmp -s - "design/$f"; then
    echo "drift: design/$f differs from NetRelish@$sha"; fail=1
  fi
done
[ $fail -eq 0 ] && echo "design/ matches NetRelish@$sha"
exit $fail
```

- [ ] **Step 3: Run it**

Run: `chmod +x scripts/check-design.sh && npm run check:design`
Expected: `design/ matches NetRelish@<sha>`

- [ ] **Step 4: Prove it catches drift**

Run: `echo x >> design/tokens.css && npm run check:design; git checkout design/tokens.css`
Expected: `drift: design/tokens.css differs …` and exit 1; file restored after.

- [ ] **Step 5: Commit**

```bash
git add design scripts/check-design.sh && git commit -m "design: tokens, mark, cog, symbols pinned to NetRelish

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Base layout, site.css, Nav, Footer

**Files:**
- Create: `src/styles/site.css`, `src/layouts/Base.astro`, `src/components/Nav.astro`, `src/components/Footer.astro`, `src/lib/svg.ts`
- Modify: `src/pages/index.astro`

**Interfaces:**
- Produces: `Base.astro` props `{ title: string; description: string; canonical?: string }` with a default slot. CSS classes: `.wrap` (max 1080px), `.btn`, `.btn--primary`, `.btn--secondary`, `.eyebrow`, `.hairline-top`, `.section`. `src/lib/svg.ts` exports `readDesignSvg(name: 'logo' | 'logo-cog' | 'symbols'): string` returning the file contents for inlining.

- [ ] **Step 1: Write src/lib/svg.ts**

```ts
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const files = { logo: 'logo.svg', 'logo-cog': 'logo-cog.svg', symbols: 'symbols.svg' } as const;

/** Inline a design SVG byte-for-byte. Build-time only. */
export function readDesignSvg(name: keyof typeof files): string {
  return readFileSync(fileURLToPath(new URL(`../../design/${files[name]}`, import.meta.url)), 'utf8');
}
```

- [ ] **Step 2: Write src/styles/site.css**

```css
@import '../../design/tokens.css';
@import '@fontsource-variable/bricolage-grotesque/standard.css';

*, *::before, *::after { box-sizing: border-box; }
html { scroll-behavior: smooth; }
@media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
body {
  margin: 0; background: var(--nr-bg); color: var(--nr-fg);
  font-family: var(--font-ui); font-size: var(--fs-lg); line-height: var(--lh-body);
  -webkit-font-smoothing: antialiased;
}
h1, h2, h3, p { margin: 0; }
h2 { font-size: var(--fs-2xl); font-weight: 600; line-height: var(--lh-tight); letter-spacing: -0.01em; }
h3 { font-size: var(--fs-xl); font-weight: 600; line-height: var(--lh-ui); }
a { color: var(--nr-fg); text-decoration: underline; text-underline-offset: 2px; }
a:hover { text-decoration-thickness: 2px; }
:focus-visible { outline: 2px solid var(--nr-focus); outline-offset: 3px; border-radius: var(--r-1); }
kbd {
  font-family: var(--font-mono); font-size: 0.85em; padding: 1px 6px; border-radius: var(--r-1);
  border: var(--hairline) solid var(--nr-hairline); border-bottom-width: 2px; background: var(--nr-surface-2);
}
svg { display: block; }

.wrap { max-width: 1080px; margin: 0 auto; padding: 0 var(--sp-6); }
.section { padding: var(--sp-12) 0; border-top: var(--hairline) solid var(--nr-hairline); }
.hairline-top { border-top: var(--hairline) solid var(--nr-hairline); }
.muted { color: var(--nr-fg-2); }
.quiet { color: var(--nr-fg-3); }
.eyebrow {
  font-family: var(--font-mono); font-size: var(--fs-sm); letter-spacing: 0.06em;
  text-transform: uppercase; color: var(--nr-fg-3); margin-bottom: var(--sp-3);
}
.tnum { font-variant-numeric: tabular-nums; }

.btn {
  display: inline-flex; align-items: center; gap: var(--sp-2); height: 40px; padding: 0 var(--sp-4);
  border-radius: var(--r-1); font: 600 var(--fs-lg) / 1 var(--font-ui); text-decoration: none; cursor: pointer;
  border: var(--hairline) solid var(--nr-hairline); background: transparent; color: var(--nr-fg);
  transition: background var(--t-fast) var(--ease-out);
}
.btn--secondary:hover { background: var(--nr-surface-2); }
.btn--primary { background: var(--relish-500); color: var(--relish-ink); border-color: transparent; }
.btn--primary:hover { background: var(--relish-300); }
.btn:active { transform: translateY(1px); }

.badge {
  display: inline-block; padding: 2px var(--sp-2); border-radius: var(--r-1);
  background: var(--relish-100); color: var(--relish-700); font-size: var(--fs-sm); font-variant-numeric: tabular-nums;
}
```

`.badge` is the manifest's badge (placement #6) and is used only inside the mock windows.

- [ ] **Step 3: Write Nav.astro and Footer.astro**

`src/components/Nav.astro`:
```astro
---
import { readDesignSvg } from '../lib/svg';
const cog = readDesignSvg('logo-cog');
---
<nav class="nav">
  <div class="wrap nav__row">
    <a class="nav__brand" href="/" aria-label="NetRelish home">
      <span class="nav__mark" set:html={cog} />
      <span>NetRelish</span>
    </a>
    <a class="nav__link" href="#how">How it works</a>
    <a class="nav__link" href="#intelligence">Intelligence</a>
    <a class="nav__link" href="#pro">Pro</a>
    <a class="nav__link" href="#questions">Questions</a>
    <a class="btn btn--secondary" href="#join">Join the beta</a>
  </div>
</nav>
<style>
  .nav { position: sticky; top: 0; z-index: 10; background: var(--nr-bg); border-bottom: var(--hairline) solid var(--nr-hairline); }
  .nav__row { display: flex; align-items: center; gap: var(--sp-6); height: 60px; }
  .nav__brand { display: flex; align-items: center; gap: var(--sp-3); font-weight: 600; text-decoration: none; margin-right: auto; }
  .nav__mark { width: 30px; height: 30px; }
  .nav__mark :global(svg) { width: 100%; height: 100%; }
  .nav__link { font-size: var(--fs-md); color: var(--nr-fg-2); text-decoration: none; }
  .nav__link:hover { color: var(--nr-fg); }
  @media (max-width: 820px) { .nav__link { display: none; } }
</style>
```

`src/components/Footer.astro`:
```astro
---
import { readDesignSvg } from '../lib/svg';
const logo = readDesignSvg('logo');
---
<footer class="footer">
  <div class="wrap footer__row">
    <span class="footer__mark" set:html={logo} />
    <span>© 2026 Shepdesign LLC</span>
    <a href="https://github.com/Shepdesign-LLC/NetRelish">GitHub</a>
    <a href="/privacy">Privacy</a>
    <span class="footer__tag">Built on WebKit. Nothing leaves your Mac.</span>
  </div>
</footer>
<style>
  .footer { padding: var(--sp-12) 0; border-top: var(--hairline) solid var(--nr-hairline); color: var(--nr-fg-3); font-size: var(--fs-md); }
  .footer__row { display: flex; align-items: center; gap: var(--sp-6); flex-wrap: wrap; }
  .footer__mark { width: 24px; height: 24px; }
  .footer__mark :global(svg) { width: 100%; height: 100%; }
  .footer__tag { margin-left: auto; }
  .footer a { color: var(--nr-fg-2); }
</style>
```

- [ ] **Step 4: Write Base.astro**

```astro
---
import '../styles/site.css';
import Nav from '../components/Nav.astro';
import Footer from '../components/Footer.astro';
interface Props { title: string; description: string; canonical?: string }
const { title, description, canonical = Astro.url.pathname } = Astro.props;
const url = new URL(canonical, Astro.site).href;
---
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <meta name="description" content={description} />
  <link rel="canonical" href={url} />
  <meta property="og:type" content="website" />
  <meta property="og:title" content={title} />
  <meta property="og:description" content={description} />
  <meta property="og:url" content={url} />
  <meta property="og:image" content={new URL('/og.png', Astro.site).href} />
  <meta name="twitter:card" content="summary_large_image" />
  <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
  <meta name="color-scheme" content="light dark" />
</head>
<body>
  <Nav />
  <slot />
  <Footer />
</body>
</html>
```

Copy `design/logo.svg` to `public/favicon.svg` (a byte-for-byte copy is allowed; it is the mark, unchanged).

- [ ] **Step 5: Wire index.astro to the layout**

```astro
---
import Base from '../layouts/Base.astro';
---
<Base title="NetRelish — Keep the pages that matter" description="NetRelish is a Mac browser with a pantry. Save any page with one key, sort it into jars, and seal the ones you'll need again — searchable, summarized on your Mac, offline.">
  <main><div class="wrap"><h1>NetRelish</h1></div></main>
</Base>
```

- [ ] **Step 6: Build, then check the font is same-origin**

Run: `npm run build && grep -o 'url([^)]*woff2[^)]*)' dist/_astro/*.css | head -3`
Expected: build green; woff2 URLs are relative `/_astro/...`, no `fonts.gstatic.com`.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: base layout, site.css on tokens, nav and footer

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: The join endpoint, test-first

**Files:**
- Create: `src/lib/join.ts`, `src/pages/api/join.ts`, `test/join.test.ts`, `vitest.config.ts`, `.env.example`

**Interfaces:**
- Produces: `handleJoin(request: Request, deps: JoinDeps): Promise<Response>` where
  ```ts
  interface JoinDeps { fetch: typeof fetch; env: { BENTO_PUBLISHABLE_KEY: string; BENTO_SECRET_KEY: string; BENTO_SITE_UUID: string }; allowedHosts: string[] }
  ```
  Behavior (spec §5): bad origin → 403; honeypot → 200/303 as success without calling Bento; invalid email → 400 JSON `{ ok:false, error }` or 303 to `/?join=invalid#join`; Bento non-2xx or throw → 502; success → 303 `/thanks` for form posts, `{ ok:true }` for JSON posts.
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write vitest.config.ts and .env.example**

`vitest.config.ts`:
```ts
import { defineConfig } from 'vitest/config';
export default defineConfig({ test: { include: ['test/**/*.test.ts'] } });
```

`.env.example`:
```
BENTO_PUBLISHABLE_KEY=
BENTO_SECRET_KEY=
BENTO_SITE_UUID=
```

- [ ] **Step 2: Write the failing tests**

`test/join.test.ts`:
```ts
import { describe, it, expect, vi } from 'vitest';
import { handleJoin, type JoinDeps } from '../src/lib/join';

const env = { BENTO_PUBLISHABLE_KEY: 'pk', BENTO_SECRET_KEY: 'sk', BENTO_SITE_UUID: 'uuid' };

function deps(fetchImpl: JoinDeps['fetch'] = vi.fn(async () => new Response('{"results":1}', { status: 200 }))): JoinDeps {
  return { fetch: fetchImpl, env, allowedHosts: ['netrelish.com', 'localhost'] };
}

function formPost(fields: Record<string, string>, origin = 'https://netrelish.com') {
  const body = new URLSearchParams(fields);
  return new Request('https://netrelish.com/api/join', {
    method: 'POST', body,
    headers: { 'content-type': 'application/x-www-form-urlencoded', origin },
  });
}

function jsonPost(fields: Record<string, string>, origin = 'https://netrelish.com') {
  return new Request('https://netrelish.com/api/join', {
    method: 'POST', body: JSON.stringify(fields),
    headers: { 'content-type': 'application/json', origin },
  });
}

describe('handleJoin', () => {
  it('rejects a foreign origin', async () => {
    const res = await handleJoin(formPost({ email: 'a@b.co' }, 'https://evil.example'), deps());
    expect(res.status).toBe(403);
  });

  it('treats a filled honeypot as success without calling Bento', async () => {
    const f = vi.fn();
    const res = await handleJoin(formPost({ email: 'a@b.co', website: 'spam' }), deps(f as any));
    expect(res.status).toBe(303);
    expect(res.headers.get('location')).toBe('/thanks');
    expect(f).not.toHaveBeenCalled();
  });

  it('rejects a bad email with 400 for JSON', async () => {
    const res = await handleJoin(jsonPost({ email: 'nope' }), deps());
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ ok: false });
  });

  it('redirects a bad email back to the form for form posts', async () => {
    const res = await handleJoin(formPost({ email: 'nope' }), deps());
    expect(res.status).toBe(303);
    expect(res.headers.get('location')).toBe('/?join=invalid#join');
  });

  it('subscribes with the beta tag and source, then emits the join event', async () => {
    const f = vi.fn(async () => new Response('{"results":1}', { status: 200 }));
    const res = await handleJoin(jsonPost({ email: 'Ryan@Example.com' }), deps(f as any));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(f).toHaveBeenCalledTimes(2);
    const [subUrl, subInit] = f.mock.calls[0] as [string, RequestInit];
    expect(subUrl).toBe('https://app.bentonow.com/api/v1/batch/subscribers?site_uuid=uuid');
    expect((subInit.headers as Record<string, string>)['User-Agent']).toBe('netrelish-site/1.0');
    expect((subInit.headers as Record<string, string>)['Authorization']).toBe('Basic ' + btoa('pk:sk'));
    expect(JSON.parse(subInit.body as string)).toEqual({
      subscribers: [{ email: 'ryan@example.com', tags: 'netrelish-beta,lead', signup_source: 'netrelish.com' }],
    });
    const [evUrl, evInit] = f.mock.calls[1] as [string, RequestInit];
    expect(evUrl).toBe('https://app.bentonow.com/api/v1/batch/events?site_uuid=uuid');
    expect(JSON.parse(evInit.body as string)).toEqual({ events: [{ type: '$netrelish_beta_join', email: 'ryan@example.com' }] });
  });

  it('returns 502 when Bento fails, never a silent success', async () => {
    const f = vi.fn(async () => new Response('nope', { status: 500 }));
    const res = await handleJoin(jsonPost({ email: 'a@b.co' }), deps(f as any));
    expect(res.status).toBe(502);
    expect(await res.json()).toMatchObject({ ok: false, error: expect.stringContaining('list') });
  });

  it('returns 502 when Bento is unreachable', async () => {
    const f = vi.fn(async () => { throw new Error('ECONNRESET'); });
    const res = await handleJoin(formPost({ email: 'a@b.co' }), deps(f as any));
    expect(res.status).toBe(502);
  });

  it('303s to /thanks on a successful form post', async () => {
    const res = await handleJoin(formPost({ email: 'a@b.co' }), deps());
    expect(res.status).toBe(303);
    expect(res.headers.get('location')).toBe('/thanks');
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `npm test`
Expected: FAIL — cannot find module `../src/lib/join`.

- [ ] **Step 4: Write src/lib/join.ts**

```ts
/** /api/join — forwards a beta signup to Bento. All logic lives here so it can be tested without Astro. */

export interface JoinEnv { BENTO_PUBLISHABLE_KEY: string; BENTO_SECRET_KEY: string; BENTO_SITE_UUID: string }
export interface JoinDeps { fetch: typeof fetch; env: JoinEnv; allowedHosts: string[] }

const BENTO = 'https://app.bentonow.com/api/v1';
const TAGS = 'netrelish-beta,lead';
const SOURCE = 'netrelish.com';
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function wantsJson(req: Request): boolean {
  return (req.headers.get('content-type') ?? '').includes('application/json');
}

function originHost(req: Request): string | null {
  const o = req.headers.get('origin') ?? req.headers.get('referer');
  if (!o) return null;
  try { return new URL(o).hostname; } catch { return null; }
}

function hostAllowed(host: string | null, allowed: string[]): boolean {
  if (!host) return false;
  return allowed.some((a) => host === a || host.endsWith('.' + a));
}

async function readFields(req: Request): Promise<Record<string, string>> {
  if (wantsJson(req)) {
    const j = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    return Object.fromEntries(Object.entries(j).map(([k, v]) => [k, String(v ?? '')]));
  }
  const form = await req.formData().catch(() => new FormData());
  return Object.fromEntries([...form.entries()].map(([k, v]) => [k, String(v)]));
}

function reply(req: Request, ok: boolean, status: number, error?: string, redirect?: string): Response {
  if (wantsJson(req)) {
    return new Response(JSON.stringify(ok ? { ok } : { ok, error }), { status, headers: { 'content-type': 'application/json' } });
  }
  return new Response(null, { status: 303, headers: { location: redirect ?? (ok ? '/thanks' : '/?join=error#join') } });
}

export async function handleJoin(req: Request, deps: JoinDeps): Promise<Response> {
  if (!hostAllowed(originHost(req), deps.allowedHosts)) {
    return new Response('forbidden', { status: 403 });
  }
  const fields = await readFields(req);
  if (fields.website) return reply(req, true, 200); // honeypot: pretend, record nothing

  const email = (fields.email ?? '').trim().toLowerCase();
  if (!EMAIL.test(email)) return reply(req, false, 400, 'That email doesn’t look right.', '/?join=invalid#join');

  const { BENTO_PUBLISHABLE_KEY: pk, BENTO_SECRET_KEY: sk, BENTO_SITE_UUID: site } = deps.env;
  const headers = {
    'Authorization': 'Basic ' + btoa(`${pk}:${sk}`),
    'User-Agent': 'netrelish-site/1.0',
    'Content-Type': 'application/json',
  };
  const post = (path: string, body: unknown) =>
    deps.fetch(`${BENTO}/${path}?site_uuid=${encodeURIComponent(site)}`, { method: 'POST', headers, body: JSON.stringify(body) });

  try {
    const sub = await post('batch/subscribers', { subscribers: [{ email, tags: TAGS, signup_source: SOURCE }] });
    if (!sub.ok) throw new Error(`bento subscribers ${sub.status}`);
    const ev = await post('batch/events', { events: [{ type: '$netrelish_beta_join', email }] });
    if (!ev.ok) throw new Error(`bento events ${ev.status}`);
  } catch (e) {
    console.error('join: bento failed', e instanceof Error ? e.message : e);
    return reply(req, false, 502, 'Couldn’t reach the list — try again in a minute.');
  }
  return reply(req, true, 200);
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `npm test`
Expected: 8 passed.

- [ ] **Step 6: Write the Astro route**

`src/pages/api/join.ts`:
```ts
import type { APIRoute } from 'astro';
import { handleJoin } from '../../lib/join';

export const prerender = false;

const allowedHosts = ['netrelish.com', 'localhost', 'vercel.app'];

export const POST: APIRoute = async ({ request }) => {
  const env = {
    BENTO_PUBLISHABLE_KEY: import.meta.env.BENTO_PUBLISHABLE_KEY ?? process.env.BENTO_PUBLISHABLE_KEY ?? '',
    BENTO_SECRET_KEY: import.meta.env.BENTO_SECRET_KEY ?? process.env.BENTO_SECRET_KEY ?? '',
    BENTO_SITE_UUID: import.meta.env.BENTO_SITE_UUID ?? process.env.BENTO_SITE_UUID ?? '',
  };
  if (!env.BENTO_SECRET_KEY) {
    console.error('join: BENTO_* env not set');
    return new Response(JSON.stringify({ ok: false, error: 'The list isn’t configured yet.' }), { status: 503, headers: { 'content-type': 'application/json' } });
  }
  return handleJoin(request, { fetch, env, allowedHosts });
};
```

- [ ] **Step 7: Build and confirm the route is a function**

Run: `npm run build && ls .vercel/output/functions`
Expected: a `_render.func` (or similar) directory exists — the adapter emitted a function for the one non-prerendered route. `npm run check` clean.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(join): /api/join forwards a beta signup to Bento, tested

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Hero with the join form

**Files:**
- Create: `src/components/JoinForm.astro`, `src/components/Hero.astro`
- Modify: `src/pages/index.astro`

**Interfaces:**
- Consumes: `.btn--primary`, `.wrap` from Task 3; `/api/join` behavior from Task 4 (JSON success `{ok:true}`, errors `{ok:false,error}`).
- Produces: `<JoinForm />` (renders `<form id="join">`); `<Hero />` renders cog + H1 + sub + JoinForm + requirement line and a `<slot />` where Task 6 mounts SealStage.

- [ ] **Step 1: Write JoinForm.astro**

```astro
---
---
<form id="join" class="join" method="post" action="/api/join" novalidate>
  <label class="join__label" for="join-email">Email</label>
  <div class="join__row">
    <input id="join-email" class="join__input" type="email" name="email" placeholder="you@example.com" autocomplete="email" required inputmode="email" />
    <button class="btn btn--primary" type="submit">Join the beta</button>
  </div>
  <div class="join__hp" aria-hidden="true"><label>Website<input type="text" name="website" tabindex="-1" autocomplete="off" /></label></div>
  <p class="join__msg" role="status" aria-live="polite"></p>
</form>
<style>
  .join { margin-top: var(--sp-8); max-width: 520px; }
  .join__label { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
  .join__row { display: flex; gap: var(--sp-3); flex-wrap: wrap; }
  .join__input {
    flex: 1 1 240px; height: 40px; padding: 0 var(--sp-3); font: 400 var(--fs-lg) var(--font-ui);
    color: var(--nr-fg); background: var(--nr-surface); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-1);
  }
  .join__input::placeholder { color: var(--nr-fg-3); }
  .join__hp { position: absolute; left: -10000px; top: auto; width: 1px; height: 1px; overflow: hidden; }
  .join__msg { min-height: 1.5em; margin-top: var(--sp-2); font-size: var(--fs-md); color: var(--nr-fg-2); }
  .join__msg[data-tone="error"] { color: var(--nr-danger); }
</style>
<script>
  const form = document.getElementById('join') as HTMLFormElement;
  const msg = form.querySelector('.join__msg') as HTMLParagraphElement;
  const params = new URLSearchParams(location.search);
  if (params.get('join') === 'invalid') { msg.dataset.tone = 'error'; msg.textContent = 'That email doesn’t look right.'; }
  if (params.get('join') === 'error') { msg.dataset.tone = 'error'; msg.textContent = 'Couldn’t reach the list — try again in a minute.'; }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('button') as HTMLButtonElement;
    const data = Object.fromEntries(new FormData(form).entries());
    btn.disabled = true; msg.dataset.tone = ''; msg.textContent = 'Adding you…';
    try {
      const res = await fetch(form.action, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(data) });
      const j = await res.json().catch(() => ({ ok: false }));
      if (j.ok) {
        form.querySelector('.join__row')!.replaceWith(Object.assign(document.createElement('p'), { className: 'join__done', textContent: 'You’re on the list. Beta invites go out in waves; you’ll hear from us.' }));
        msg.textContent = '';
      } else {
        msg.dataset.tone = 'error'; msg.textContent = j.error ?? 'Something went wrong.'; btn.disabled = false;
      }
    } catch {
      msg.dataset.tone = 'error'; msg.textContent = 'Couldn’t reach the list — try again in a minute.'; btn.disabled = false;
    }
  });
</script>
```

- [ ] **Step 2: Write Hero.astro**

```astro
---
import { readDesignSvg } from '../lib/svg';
import JoinForm from './JoinForm.astro';
const cog = readDesignSvg('logo-cog');
---
<header class="hero">
  <div class="wrap">
    <div class="hero__copy">
      <span class="hero__mark" set:html={cog} />
      <div>
        <h1 class="hero__h1">Keep the pages that matter.</h1>
        <p class="hero__sub">NetRelish is a Mac browser with a pantry. Save any page with one key, sort it into jars, and seal the ones you’ll need again — searchable, summarized on your Mac, offline.</p>
        <JoinForm />
        <p class="hero__cta"><a class="btn btn--secondary" href="#how">See how it works</a></p>
        <p class="hero__req quiet">macOS 27 or later · Apple silicon · Free, with a Pro upgrade · Beta invites go out in waves.</p>
      </div>
    </div>
    <slot />
  </div>
</header>
<style>
  .hero { padding: 88px 0 var(--sp-10); }
  .hero__copy { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: var(--sp-8); align-items: start; max-width: 820px; }
  .hero__mark { width: 132px; height: 132px; margin: -14px 66px 0 0; /* clear space = ½ width */ }
  .hero__mark :global(svg) { width: 100%; height: 100%; }
  .hero__h1 {
    font-family: var(--font-hero); font-weight: 800; font-stretch: 100%; font-optical-sizing: auto; font-variation-settings: 'opsz' 96;
    font-size: clamp(40px, 6vw, 68px); line-height: 1.02; letter-spacing: -0.02em; text-wrap: balance;
  }
  .hero__sub { margin-top: var(--sp-5); font-size: var(--fs-xl); color: var(--nr-fg-2); max-width: 34em; }
  .hero__cta { margin-top: var(--sp-4); }
  .hero__req { margin-top: var(--sp-4); font-size: var(--fs-sm); }
  @media (max-width: 820px) { .hero { padding-top: var(--sp-12); } .hero__copy { grid-template-columns: 1fr; } .hero__mark { margin: 0; width: 96px; height: 96px; } }
</style>
```

- [ ] **Step 3: Mount in index.astro**

Replace the `<main>` with:
```astro
<main>
  <Hero />
</main>
```
and import `Hero` at the top.

- [ ] **Step 4: Run dev and check the form end to end without keys**

Run: `npm run dev` then in the built-in browser open `http://localhost:4321/`, submit `test@example.com`.
Expected: message "The list isn’t configured yet." (503 path — proves the wiring; keys arrive in Task 11). Disable JS (or `curl -X POST -H 'origin: http://localhost:4321' -d email=nope localhost:4321/api/join -i`) → 303 to `/?join=invalid#join`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(hero): cog, headline, join form with progressive enhancement

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: The Seal stage

**Files:**
- Create: `src/components/SealStage.astro`
- Modify: `src/components/Hero.astro` (already has the slot), `src/pages/index.astro`

**Interfaces:**
- Consumes: `readDesignSvg('symbols')` (Task 3) — inlined once so `<use href="#nr-jar">` etc. resolve. `.badge` from site.css.
- Produces: `<SealStage />` which also inlines `symbols.svg` (hidden) for every later `<use>` on the page. Later mocks rely on the symbols being present exactly once: SealStage owns that.

- [ ] **Step 1: Write SealStage.astro**

```astro
---
import { readDesignSvg } from '../lib/svg';
const symbols = readDesignSvg('symbols');
---
<div class="symbols" aria-hidden="true" set:html={symbols} />
<div class="stage" id="seal-stage" aria-label="Sealing a page into a jar">
  <div class="win">
    <div class="win__bar">
      <span class="dot"></span><span class="dot"></span><span class="dot"></span>
      <div class="tabs">
        <span class="tab">developer.apple.com — App Intents<span class="life"><i style="width:62%"></i></span></span>
        <span class="tab tab--live"><svg class="lip"><use href="#nr-lip" /></svg>designfirst.io — System Designer</span>
        <span class="tab">github.com/Shepdesign-LLC<span class="life"><i style="width:18%"></i></span></span>
      </div>
    </div>
    <div class="win__body">
      <div class="shelf">
        <span class="jar jar--target"><svg><use href="#nr-jar" /></svg><i class="jdrip"><svg><use href="#nr-drip" /></svg></i></span>
        <span class="jar"><svg><use href="#nr-jar" /></svg></span>
        <span class="jar"><svg><use href="#nr-jar" /></svg></span>
      </div>
      <div class="page">
        <div class="ln ln--t"></div><div class="ln" style="width:92%"></div><div class="ln" style="width:86%"></div><div class="ln" style="width:70%"></div>
        <div class="ln ln--block"></div><div class="ln" style="width:88%"></div><div class="ln" style="width:64%"></div>
      </div>
    </div>
    <div class="card" aria-hidden="true"><svg class="card__seal"><use href="#nr-seal" /></svg>System Designer — Design First</div>
    <div class="toast badge" aria-hidden="true">Sealed to Reference</div>
  </div>
</div>
<p class="caption quiet">Press <kbd>⌘</kbd><kbd>S</kbd>. The page is preserved, the tab closes, the jar keeps it.</p>
<style>
  .symbols { position: absolute; width: 0; height: 0; overflow: hidden; }
  .stage { margin-top: var(--sp-12); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-3); background: var(--nr-surface-2); padding: var(--sp-6); position: relative; overflow: hidden; }
  .win { background: var(--nr-surface); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-2); overflow: hidden; position: relative; }
  .win__bar { display: flex; align-items: center; gap: var(--sp-2); padding: var(--sp-3); border-bottom: var(--hairline) solid var(--nr-hairline); }
  .dot { width: 11px; height: 11px; border-radius: 50%; background: var(--nr-hairline); }
  .tabs { display: flex; gap: 6px; margin-left: var(--sp-3); flex: 1; min-width: 0; }
  .tab { position: relative; height: var(--tab-h); display: flex; align-items: center; font-size: var(--fs-sm); color: var(--nr-fg-2); padding: 0 var(--sp-3); border-radius: var(--r-2) var(--r-2) 0 0; background: transparent; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 220px; }
  .tab--live { color: var(--nr-fg); background: var(--nr-surface); border: var(--hairline) solid var(--nr-hairline); border-bottom: 0; }
  .lip { position: absolute; top: 0; left: 0; right: 0; height: var(--lip-h); width: 100%; }
  .life { position: absolute; left: var(--sp-3); right: var(--sp-3); bottom: 0; height: 2px; background: var(--nr-hairline); }
  .life i { display: block; height: 100%; background: var(--relish-500); }
  .win__body { display: grid; grid-template-columns: var(--shelf-w) 1fr; min-height: 300px; }
  .shelf { background: var(--nr-surface-2); border-right: var(--hairline) solid var(--nr-hairline); padding: var(--sp-3) 0; display: flex; flex-direction: column; align-items: center; gap: var(--sp-3); }
  .jar { width: 40px; height: 40px; border-radius: var(--r-2); display: grid; place-items: center; position: relative; color: var(--nr-fg); }
  .jar svg { width: 24px; height: 29px; }
  .jar--target { background: var(--relish-100); }
  .jdrip { position: absolute; top: 12px; left: 50%; width: 10px; height: 0; margin-left: -5px; overflow: hidden; color: var(--relish-500); }
  .jdrip svg { width: 10px; height: 12px; }
  .page { padding: var(--sp-6) var(--sp-8); display: flex; flex-direction: column; gap: var(--sp-3); }
  .ln { height: 9px; border-radius: var(--r-1); background: var(--nr-hairline); opacity: .6; }
  .ln--t { height: 14px; width: 55%; opacity: 1; }
  .ln--block { height: 70px; width: 100%; margin-top: 6px; }
  .card { position: absolute; left: 84px; top: 74px; width: 240px; display: flex; gap: var(--sp-2); align-items: center; padding: var(--sp-3); background: var(--nr-surface); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-2); font-size: var(--fs-sm); color: var(--nr-fg-2); transform-origin: center; box-shadow: 0 1px 2px rgb(0 0 0 / .08); }
  .card__seal { width: 16px; height: 16px; color: var(--relish-500); flex: none; }
  .toast { position: absolute; right: var(--sp-6); bottom: var(--sp-6); opacity: 0; }
  .caption { margin-top: var(--sp-4); font-size: var(--fs-md); text-align: center; }

  @keyframes seal { 0% { opacity: 0; transform: none } 12%, 52% { opacity: 1; transform: none } 74% { opacity: 1; transform: translate(-56px, -42px) scale(.16) } 78%, 100% { opacity: 0; transform: translate(-56px, -42px) scale(.08) } }
  @keyframes tabgone { 0%, 58% { opacity: 1; max-width: 220px } 76%, 100% { opacity: 0; max-width: 0; padding: 0; border-width: 0 } }
  @keyframes jdrip { 0%, 82% { height: 0 } 92%, 100% { height: 12px } }
  @keyframes toast { 0%, 78% { opacity: 0; transform: translateY(4px) } 85%, 96% { opacity: 1; transform: none } 100% { opacity: 0 } }
  .stage.is-playing .card { animation: seal 4.4s var(--ease-jar) infinite; }
  .stage.is-playing .tab--live { animation: tabgone 4.4s var(--ease-out) infinite; }
  .stage.is-playing .jdrip { animation: jdrip 4.4s var(--ease-out) infinite; }
  .stage.is-playing .toast { animation: toast 4.4s var(--ease-out) infinite; }
  @media (prefers-reduced-motion: reduce) {
    .stage.is-playing .card, .stage.is-playing .tab--live, .stage.is-playing .jdrip, .stage.is-playing .toast { animation: none; }
    .stage .card { opacity: 0; } .stage .toast { opacity: 1; } .stage .tab--live { display: none; } .stage .jdrip { height: 12px; }
  }
  @media (max-width: 820px) { .card { left: 68px; top: 64px; width: 190px; } }
</style>
<script>
  const st = document.getElementById('seal-stage')!;
  new IntersectionObserver(([e]) => st.classList.toggle('is-playing', e.isIntersecting), { threshold: 0.4 }).observe(st);
</script>
```

Note on the drip: `#nr-drip` is the manifest's drip (§7), colored by `currentColor` = `--relish-500`. It is the only drip on the page.

- [ ] **Step 2: Mount inside Hero in index.astro**

```astro
<Hero><SealStage /></Hero>
```

- [ ] **Step 3: Verify in the browser**

Run: `npm run dev`, open `/` in the built-in browser. Expected: the loop plays (card → jar, tab collapses, drip appears, toast). With macOS Reduce Motion on (System Settings → Accessibility → Display) the final frame is static. Confirm `symbols.svg` ids resolve (jars render, not empty boxes). Take a screenshot for the PR.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(hero): the Seal stage — one drip, the tab count drops

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: How-it-works rows and the mock objects

**Files:**
- Create: `src/components/Row.astro`, `src/components/mocks/Tray.astro`, `Shelf.astro`, `Inspector.astro`, `PantryResults.astro`, `Recipe.astro`
- Modify: `src/pages/index.astro`

**Interfaces:**
- Consumes: symbols inlined by SealStage (Task 6); `.badge`, `.eyebrow`, `.section`, `.wrap` (Task 3).
- Produces: `<Row eyebrow h2 flip?>` with a default slot for the copy and a `mock` named slot.

- [ ] **Step 1: Write Row.astro**

```astro
---
interface Props { eyebrow: string; h2: string; flip?: boolean; id?: string }
const { eyebrow, h2, flip = false, id } = Astro.props;
---
<section class="section" id={id}>
  <div class:list={['wrap', 'row', { 'row--flip': flip }]}>
    <div class="row__copy">
      <p class="eyebrow">{eyebrow}</p>
      <h2>{h2}</h2>
      <div class="row__text muted"><slot /></div>
    </div>
    <div class="row__mock"><slot name="mock" /></div>
  </div>
</section>
<style>
  .row { display: grid; grid-template-columns: minmax(0, 5fr) minmax(0, 7fr); gap: var(--sp-12); align-items: center; }
  .row--flip { grid-template-columns: minmax(0, 7fr) minmax(0, 5fr); }
  .row--flip .row__copy { order: 2; }
  .row__copy h2 { margin-bottom: var(--sp-4); }
  .row__text :global(p + p) { margin-top: var(--sp-3); }
  .row__mock { border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-3); background: var(--nr-surface-2); aspect-ratio: 16 / 10; display: grid; place-items: center; padding: var(--sp-6); overflow: hidden; }
  @media (max-width: 820px) { .row, .row--flip { grid-template-columns: 1fr; gap: var(--sp-8); } .row--flip .row__copy { order: 0; } }
</style>
```

- [ ] **Step 2: Write the five mocks**

`mocks/Tray.astro` (Brine tray — solid, not frosted; manifest §6 forbids glass):
```astro
<div class="tray">
  <div class="tray__label"><svg class="tray__sink"><use href="#nr-sink" /></svg>Brine <span class="badge">3</span></div>
  <div class="item"><span class="fav"></span>swiftpackageindex.com — GRDB</div>
  <div class="item"><span class="fav"></span>github.com/design-first</div>
  <div class="item"><span class="fav"></span>developer.apple.com — WKWebView</div>
</div>
<style>
  .tray { width: 100%; display: flex; align-items: center; gap: var(--sp-3); flex-wrap: wrap; padding: var(--sp-3) var(--sp-4); background: var(--nr-surface); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-2); }
  .tray__label { display: flex; align-items: center; gap: var(--sp-2); font-size: var(--fs-sm); color: var(--nr-fg-2); }
  .tray__sink { width: 18px; height: 18px; color: var(--nr-fg-2); }
  .item { display: flex; align-items: center; gap: var(--sp-2); height: 32px; padding: 0 var(--sp-3); border-radius: var(--r-1); background: var(--nr-bg); border: var(--hairline) solid var(--nr-hairline); font-size: var(--fs-sm); color: var(--nr-fg-2); white-space: nowrap; }
  .fav { width: 11px; height: 11px; border-radius: 3px; background: var(--nr-hairline); }
</style>
```

`mocks/Shelf.astro`:
```astro
<div class="shelf">
  {['Clients', 'Research', 'Reading', 'Tooling'].map((name, i) => (
    <span class:list={['jar', { 'jar--on': i === 1 }]}><svg><use href="#nr-jar" /></svg><span class="jar__name">{name}</span></span>
  ))}
</div>
<style>
  .shelf { display: flex; gap: var(--sp-6); }
  .jar { width: 64px; display: grid; justify-items: center; gap: var(--sp-1); padding: var(--sp-2) 0; border-radius: var(--r-2); color: var(--nr-fg); }
  .jar svg { width: 32px; height: 39px; }
  .jar--on { background: var(--relish-100); }
  .jar__name { font-size: var(--fs-xs); color: var(--nr-fg-2); }
  .jar--on .jar__name { color: var(--nr-fg); }
</style>
```

`mocks/Inspector.astro`:
```astro
<div class="insp">
  <div><div class="insp__title">What is System Designer?</div><div class="quiet insp__meta">designfirst.io · sealed 2 min ago</div></div>
  <div><div class="insp__k">Jar</div><div class="insp__jar"><svg><use href="#nr-jar" /></svg>Reference</div></div>
  <div><div class="insp__k">Snapshot</div><div class="muted insp__v">.webarchive · 1.2 MB · frozen</div></div>
  <div><div class="insp__k">On seal</div><div class="insp__recipe">Summarize and label</div></div>
</div>
<style>
  .insp { width: 280px; display: flex; flex-direction: column; gap: var(--sp-4); padding: var(--sp-4); background: var(--nr-surface-2); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-2); }
  .insp > div + div { border-top: var(--hairline) solid var(--nr-hairline); padding-top: var(--sp-3); }
  .insp__title { font-weight: 500; font-size: var(--fs-md); }
  .insp__meta, .insp__v, .insp__recipe { font-size: var(--fs-sm); }
  .insp__k { font-size: var(--fs-sm); color: var(--nr-fg-2); margin-bottom: var(--sp-1); }
  .insp__jar { display: flex; align-items: center; gap: var(--sp-2); font-size: var(--fs-sm); }
  .insp__jar svg { width: 16px; height: 20px; }
  .insp__recipe { padding: var(--sp-2) var(--sp-3); border-radius: var(--r-1); background: var(--nr-surface); border: var(--hairline) solid var(--nr-hairline); }
</style>
```

`mocks/PantryResults.astro`:
```astro
<div class="pantry">
  <div class="pantry__field">hinge tolerances</div>
  {[['Reference', 'Hinge tolerances for cabinet doors — Blum'], ['Research', 'Why your soft-close hinge slams — a tolerance stack-up'], ['Clients', 'Hartley kitchen — hardware spec']].map(([jar, title]) => (
    <div class="res"><span class="res__jar"><svg><use href="#nr-jar" /></svg>{jar}</span><span>{title}</span></div>
  ))}
</div>
<style>
  .pantry { width: 100%; max-width: 480px; background: var(--nr-surface); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-2); overflow: hidden; }
  .pantry__field { padding: var(--sp-3) var(--sp-4); font-size: var(--fs-md); border-bottom: var(--hairline) solid var(--nr-hairline); }
  .res { display: flex; align-items: center; gap: var(--sp-3); padding: var(--sp-3) var(--sp-4); font-size: var(--fs-sm); color: var(--nr-fg); }
  .res + .res { border-top: var(--hairline) solid var(--nr-hairline); }
  .res__jar { display: inline-flex; align-items: center; gap: var(--sp-1); padding: 2px var(--sp-2); border-radius: var(--r-1); background: var(--nr-surface-2); color: var(--nr-fg-2); font-size: var(--fs-xs); white-space: nowrap; }
  .res__jar svg { width: 12px; height: 15px; }
</style>
```

`mocks/Recipe.astro`:
```astro
<div class="recipe">
  <div class="recipe__card">
    <div class="recipe__name">Summarize and label</div>
    <ol class="recipe__steps"><li>Summarize the page</li><li>Add labels</li><li>Move to Reference</li></ol>
  </div>
  <div class="recipe__arrow" aria-hidden="true">→</div>
  <div class="recipe__card"><div class="recipe__name">Shortcuts</div><div class="muted recipe__sc">“Seal this into Clients”</div><div class="quiet recipe__sc">Siri · Action button · Focus</div></div>
</div>
<style>
  .recipe { display: flex; align-items: center; gap: var(--sp-4); }
  .recipe__card { padding: var(--sp-4); background: var(--nr-surface); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-2); min-width: 200px; }
  .recipe__name { font-weight: 500; font-size: var(--fs-md); margin-bottom: var(--sp-2); }
  .recipe__steps { margin: 0; padding-left: 18px; font-size: var(--fs-sm); color: var(--nr-fg-2); }
  .recipe__sc { font-size: var(--fs-sm); }
  .recipe__arrow { color: var(--nr-fg-3); font-size: var(--fs-xl); }
</style>
```

- [ ] **Step 3: Add the five rows to index.astro**

After `<Hero>…</Hero>`:
```astro
<Row id="how" eyebrow="Capture" h2="One key to save anything.">
  <p>Press <kbd>⌘</kbd><kbd>D</kbd> on any page, or share from any app. It lands in Brine, right where you can see it. Nothing gets lost in a bookmarks folder again.</p>
  <Tray slot="mock" />
</Row>
<Row eyebrow="Sort" h2="Jars, not folders." flip>
  <p>Drag a saved page onto a jar on the Shelf. Jars are where your projects live — clients, research, reading, whatever you’re working on this month. Every jar is its own profile: its own cookies, its own logins.</p>
  <p>Switch with <kbd>⌘</kbd><kbd>1</kbd> through <kbd>⌘</kbd><kbd>9</kbd>.</p>
  <Shelf slot="mock" />
</Row>
<Row eyebrow="Seal" h2="Seal it, and it’s yours.">
  <p>Sealing saves a complete snapshot, closes the tab, and runs the jar’s Recipe. The page is preserved exactly as you saw it and never changes.</p>
  <p>The tab count goes down. That’s the point.</p>
  <Inspector slot="mock" />
</Row>
<Row eyebrow="Search" h2="Search what you kept, not the whole internet." flip>
  <p>Every sealed page is indexed in full. Find it from Ask the Pantry or straight from Spotlight.</p>
  <PantryResults slot="mock" />
</Row>
<Row eyebrow="Recipes" h2="Workflows that run on save.">
  <p>A Recipe is a short list of steps: label it, move it, summarize it, export it. Attach one to a jar and it runs on every seal.</p>
  <p>Every Recipe is a Shortcut, so Siri and the rest of your Mac can run it too.</p>
  <Recipe slot="mock" />
</Row>
```
Import `Row` and the five mocks at the top.

- [ ] **Step 4: Verify and commit**

Run: `npm run build && npm run check`. Open in the browser: five rows alternate, jars render from symbols, nothing relish except the active jar tint and the Brine badge.

```bash
git add -A && git commit -m "feat(how): five rows with mock objects from the design kit

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Intelligence, Pickle, Pro, Questions

**Files:**
- Create: `src/components/Intelligence.astro`, `Pickle.astro`, `Pro.astro`, `Questions.astro`
- Modify: `src/pages/index.astro`

**Interfaces:**
- Consumes: `.section`, `.wrap`, `.eyebrow`, `.btn--secondary`, symbols (`#nr-jar-pickle`).
- Produces: four sections with ids `intelligence`, `pickle`, `pro`, `questions`.

- [ ] **Step 1: Intelligence.astro**

```astro
<section class="section" id="intelligence"><div class="wrap">
  <p class="eyebrow">Apple Intelligence</p>
  <h2 class="ai__h2">Built for Apple Intelligence. Reads only what you’ve kept.</h2>
  <div class="ai">
    <div><h3>Summaries, on your Mac.</h3><p class="muted">Every sealed page gets a summary from on-device Foundation Models. No page leaves the machine.</p></div>
    <div><h3>Seal sorts for you.</h3><p class="muted">Kind, labels, and a suggested jar are proposed at seal time, from the snapshot.</p></div>
    <div><h3>Siri and Shortcuts.</h3><p class="muted">Every Recipe is an App Intent. “Seal this into Clients” works from Siri, Shortcuts, the Action button, and Focus.</p></div>
    <div><h3>Nothing to trick.</h3><p class="muted">Intelligence reads sealed snapshots, never a live tab or a logged-in session. There’s no agent in your browser for a page to hijack.</p></div>
  </div>
</div></section>
<style>
  .ai__h2 { max-width: 18em; }
  .ai { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: var(--sp-8) var(--sp-10); margin-top: var(--sp-8); }
  .ai h3 { margin-bottom: var(--sp-2); }
  .ai p { font-size: var(--fs-lg); }
  @media (max-width: 820px) { .ai { grid-template-columns: 1fr; } }
</style>
```

- [ ] **Step 2: Pickle.astro**

```astro
<section class="section" id="pickle"><div class="wrap pk">
  <div>
    <p class="eyebrow">Pickle · coming in 1.2 · Direct build</p>
    <h2>A jar that runs your site.</h2>
    <p class="muted pk__p">A Pickle is a jar with a local environment inside it. One click starts it on your Mac with OrbStack or Docker, opens it on the Bench, and keeps it in step with a GitHub repo you sign into once.</p>
    <p class="muted pk__p">For the people who build sites, not just read them.</p>
  </div>
  <div class="pk__mock"><svg class="pk__jar"><use href="#nr-jar-pickle" /></svg><span class="pk__mono">localhost:8080 · main · synced</span></div>
</div></section>
<style>
  .pk { display: grid; grid-template-columns: minmax(0, 5fr) minmax(0, 7fr); gap: var(--sp-12); align-items: center; }
  .pk h2 { margin-bottom: var(--sp-4); }
  .pk__p + .pk__p { margin-top: var(--sp-3); }
  .pk__mock { border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-3); background: var(--nr-surface-2); aspect-ratio: 16 / 10; display: flex; align-items: center; justify-content: center; gap: var(--sp-6); }
  .pk__jar { width: 48px; height: 58px; color: var(--nr-fg); }
  .pk__mono { font-family: var(--font-mono); font-size: var(--fs-sm); color: var(--nr-fg-2); }
  @media (max-width: 820px) { .pk { grid-template-columns: 1fr; gap: var(--sp-8); } }
</style>
```

- [ ] **Step 3: Pro.astro** (contents = ADR 0003; no relish anywhere in this section)

```astro
<section class="section pro" id="pro"><div class="wrap">
  <p class="eyebrow">Pro</p>
  <h2>Pro turns saved pages into evidence.</h2>
  <div class="pro__grid">
    <div><h3>Reseal and diff</h3><p class="muted">Seal the same page again later and see exactly what changed — prices, terms, copy, anything.</p></div>
    <div><h3>Provenance</h3><p class="muted">Every seal carries a signed timestamp and a fingerprint you can export as proof you saw it, when you saw it.</p></div>
    <div><h3>Jar bundles</h3><p class="muted">Share a whole jar over AirDrop. No account, no server, nothing to sign up for on the other end.</p></div>
    <div><h3>Unlimited Recipes</h3><p class="muted">And semantic search across everything you’ve sealed, so “that thing about hinge tolerances” is findable.</p></div>
  </div>
  <div class="plans">
    <div class="plan">
      <div class="plan__name">Free</div><div class="plan__price tnum">$0</div><div class="quiet plan__per">forever</div>
      <ul class="plan__list"><li>Capture, jars, seal, full-text search</li><li>3 Recipes</li><li>Share extension, Spotlight, Shortcuts</li></ul>
      <a class="btn btn--secondary" href="#join">Join the beta</a>
    </div>
    <div class="plan">
      <div class="plan__name">Pro</div><div class="plan__price tnum">$39</div><div class="quiet plan__per">per year, or $99 once</div>
      <ul class="plan__list"><li>Everything in Free</li><li>Reseal and diff, provenance export</li><li>Jar bundles, unlimited Recipes</li><li>Semantic search</li></ul>
      <a class="btn btn--secondary" href="#join">Join the beta</a>
    </div>
  </div>
  <p class="quiet pro__fine">One price. No seats, no tiers, no telemetry. Buy once, use forever.</p>
</div></section>
<style>
  .pro { background: var(--nr-surface-2); }
  .pro__grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: var(--hairline); background: var(--nr-hairline); border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-3); overflow: hidden; margin-top: var(--sp-8); }
  .pro__grid > div { background: var(--nr-bg); padding: var(--sp-6) var(--sp-8); }
  .pro__grid h3 { margin-bottom: var(--sp-2); }
  .pro__grid p { font-size: var(--fs-lg); }
  .plans { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: var(--sp-5); margin-top: var(--sp-10); max-width: 760px; }
  .plan { border: var(--hairline) solid var(--nr-hairline); border-radius: var(--r-3); padding: var(--sp-6) var(--sp-8); background: var(--nr-bg); }
  .plan__name { font-weight: 600; font-size: var(--fs-xl); }
  .plan__price { font-weight: 600; font-size: var(--fs-3xl); letter-spacing: -0.02em; margin: var(--sp-2) 0 0; line-height: 1; }
  .plan__per { font-size: var(--fs-md); margin-top: var(--sp-1); }
  .plan__list { margin: var(--sp-5) 0 var(--sp-6); padding-left: 18px; color: var(--nr-fg-2); font-size: var(--fs-lg); display: grid; gap: var(--sp-2); }
  .pro__fine { margin-top: var(--sp-5); font-size: var(--fs-md); }
  @media (max-width: 820px) { .pro__grid, .plans { grid-template-columns: 1fr; } }
</style>
```

- [ ] **Step 4: Questions.astro**

```astro
---
const qa = [
  ['Is it a browser?', 'Yes. It uses WebKit, the same engine as Safari, so sites behave. You can make it your default or keep it alongside Safari.'],
  ['Where’s my data?', 'In a database on your Mac. Export it any time as a jar bundle.'],
  ['Does it need an account?', 'No. Pro is a Mac App Store purchase, or a license key from this site for the direct build.'],
  ['Extensions?', 'No browser extensions. Recipes and Shortcuts do that job without the security surface.'],
  ['Windows?', 'No plans. NetRelish is a Mac app.'],
  ['Open source?', 'The code is MIT on GitHub. The name and mark are ours.'],
];
---
<section class="section" id="questions"><div class="wrap q">
  <p class="eyebrow">Questions</p>
  <h2 class="q__h2">Before you join</h2>
  {qa.map(([q, a]) => (<details class="q__item"><summary>{q}</summary><p class="muted">{a}</p></details>))}
</div></section>
<style>
  .q { max-width: 760px; }
  .q__h2 { margin-bottom: var(--sp-6); }
  .q__item { border-top: var(--hairline) solid var(--nr-hairline); padding: var(--sp-4) 0; }
  .q__item:last-of-type { border-bottom: var(--hairline) solid var(--nr-hairline); }
  summary { cursor: pointer; font-weight: 500; list-style: none; display: flex; justify-content: space-between; align-items: center; }
  summary::-webkit-details-marker { display: none; }
  summary::after { content: '+'; color: var(--nr-fg-2); font-size: var(--fs-xl); line-height: 1; }
  details[open] summary::after { content: '–'; }
  .q__item p { margin-top: var(--sp-3); max-width: 60ch; }
</style>
```

- [ ] **Step 5: Mount the four in index.astro after the rows; build; commit**

```bash
npm run build && npm run check
git add -A && git commit -m "feat: intelligence, pickle, pro (ADR 0003), questions

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: /thanks, /privacy, OG image

**Files:**
- Create: `src/pages/thanks.astro`, `src/pages/privacy.astro`, `scripts/gen-og.mjs`, `public/og.png`

- [ ] **Step 1: thanks.astro**

```astro
---
import Base from '../layouts/Base.astro';
import { readDesignSvg } from '../lib/svg';
const cog = readDesignSvg('logo-cog');
---
<Base title="You’re on the list — NetRelish" description="Beta invites go out in waves.">
  <main class="empty"><div class="wrap empty__box">
    <span class="empty__mark" set:html={cog} />
    <p class="empty__line">You’re on the list. Beta invites go out in waves; you’ll hear from us.</p>
    <p><a href="/">Back to NetRelish</a></p>
  </div></main>
</Base>
<style>
  .empty { min-height: 60vh; display: grid; place-items: center; padding: var(--sp-12) 0; }
  .empty__box { display: grid; justify-items: center; gap: var(--sp-4); text-align: center; }
  .empty__mark { width: 48px; height: 48px; }
  .empty__mark :global(svg) { width: 100%; height: 100%; }
  .empty__line { font-size: var(--fs-xl); max-width: 32em; }
</style>
```

- [ ] **Step 2: privacy.astro**

```astro
---
import Base from '../layouts/Base.astro';
---
<Base title="Privacy — NetRelish" description="What this site does with your email, and what it doesn’t do.">
  <main class="section"><div class="wrap prose">
    <h2>Privacy</h2>
    <p>This site sets no cookies and loads nothing from third parties. There is no analytics script.</p>
    <p>If you join the beta list, your email goes to Bento, the mailing tool we use, tagged for the NetRelish beta. It is used for beta invites and launch news, nothing else, and is never sold or shared. Every email has an unsubscribe link, and you can ask for your address to be deleted at any time by replying to one.</p>
    <p>The app is a different matter, and a simpler one: NetRelish makes no network calls except the pages you load, the App Store, and — on Pro — a signed timestamp for your sealed pages. Your browsing data never leaves your Mac.</p>
    <p><a href="/">Back to NetRelish</a></p>
  </div></main>
</Base>
<style>
  .prose { max-width: 640px; display: grid; gap: var(--sp-4); }
</style>
```

- [ ] **Step 3: gen-og.mjs** (dev-only; commits the PNG)

```js
// Renders public/og.png: the cog on --nr-bg with the headline. Run: npm run og
import sharp from 'sharp';
import { readFileSync, writeFileSync } from 'node:fs';

const cog = readFileSync('design/logo-cog.svg');
const W = 1200, H = 630;
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">
  <rect width="${W}" height="${H}" fill="#FCFCFB"/>
  <text x="300" y="300" font-family="-apple-system, Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="700" font-size="64" fill="#1D1D1B">Keep the pages that matter.</text>
  <text x="300" y="360" font-family="-apple-system, Helvetica Neue, Helvetica, Arial, sans-serif" font-size="28" fill="#66665F">A Mac browser with a pantry.</text>
</svg>`;
const cogPng = await sharp(cog).resize(160, 160).png().toBuffer();
const out = await sharp(Buffer.from(svg)).composite([{ input: cogPng, left: 100, top: 235 }]).png().toBuffer();
writeFileSync('public/og.png', out);
console.log('public/og.png', out.length, 'bytes');
```

Hex values are the sRGB fallbacks from `tokens.css` (`--nr-bg #FCFCFB`, `--nr-fg #1D1D1B`, `--nr-fg-2 #66665F`).

- [ ] **Step 4: Generate, build, look, commit**

Run: `npm run og && npm run build`; open `public/og.png`.

```bash
git add -A && git commit -m "feat: thanks and privacy pages, OG image

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: CI — network rule, relish audit, workflow

**Files:**
- Create: `scripts/check-network.mjs`, `scripts/check-relish.mjs`, `.github/workflows/ci.yml`

- [ ] **Step 1: check-network.mjs**

```js
// The built site may reference only these hosts. Anything else is a third-party request and fails.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ALLOWED = new Set(['netrelish.com', 'www.netrelish.com', 'github.com', 'apps.apple.com', 'www.w3.org']);
const root = 'dist';
const hits = [];

function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (/\.(html|css|js|svg|json|txt)$/.test(name)) {
      const src = readFileSync(p, 'utf8');
      for (const m of src.matchAll(/https?:\/\/([a-z0-9.-]+)/gi)) {
        if (!ALLOWED.has(m[1].toLowerCase())) hits.push(`${p}: ${m[0]}`);
      }
    }
  }
}
walk(root);
if (hits.length) { console.error('network rule: foreign hosts referenced:\n' + [...new Set(hits)].join('\n')); process.exit(1); }
console.log('network rule: only allowed hosts referenced');
```

`www.w3.org` is the SVG/xmlns namespace, not a request.

- [ ] **Step 2: check-relish.mjs**

```js
// --relish-* may appear only in selectors on the allowlist. Astro scopes component CSS with data-astro-cid-*,
// so we match on the class names we own.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const ALLOW = [
  /\.btn--primary/,                 // hero primary button (#8)
  /\.badge/,                        // count/status badge (#6) — mock windows only
  /\.jar--target|\.jar--on/,        // active jar tint (#3)
  /\.life i/,                       // shelf-life bar (#5)
  /\.jdrip|\.card__seal/,           // seal glyph + the one drip (#4)
  /--nr-focus/,                     // focus ring (#7) is defined as relish in tokens
  /:root|:focus-visible|@media/,    // token definitions and the focus ring
];
const dir = 'dist/_astro';
const bad = [];
for (const f of readdirSync(dir).filter((n) => n.endsWith('.css'))) {
  const css = readFileSync(join(dir, f), 'utf8');
  // split into rules: selector{body}
  for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const [, sel, body] = m;
    if (!/--relish-/.test(body)) continue;
    if (/^\s*:root/.test(sel) || /prefers-color-scheme/.test(sel)) continue; // tokens.css itself
    if (!ALLOW.some((re) => re.test(sel))) bad.push(`${f}: ${sel.trim()} { ${body.trim()} }`);
  }
}
if (bad.length) { console.error('relish audit: relish outside the allowlist:\n' + bad.join('\n')); process.exit(1); }
console.log('relish audit: clean');
```

- [ ] **Step 3: Run both against the build; fix anything they catch**

Run: `npm run build && npm run check:network && npm run check:relish`
Expected: both print their clean line. If the relish audit flags `.join__input` or `.plan`, that's a real bug — fix the CSS, not the allowlist.

- [ ] **Step 4: ci.yml** (org requires full-SHA action pins — copy the SHAs from `netrelish/.github/workflows/*.yml` for `actions/checkout` and `actions/setup-node`)

```yaml
name: ci
on: { push: { branches: [main] }, pull_request: {} }
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha-from-netrelish-workflows> # v5
      - uses: actions/setup-node@<sha-from-netrelish-workflows> # v5
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npm run ci
```

- [ ] **Step 5: Commit and push; confirm the Actions run is green**

```bash
git add -A && git commit -m "ci: design drift, network rule, relish audit, build and tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" && git push
gh run watch --exit-status
```

---

### Task 11: Vercel, keys, domain — and the demo

**Files:**
- Create: `docs/DEPLOY.md` in the site repo (the click list, so it outlives this chat)

- [ ] **Step 1: Write docs/DEPLOY.md**

```markdown
# Deploying netrelish-site

Vercel project: `netrelish` in team Shepdesign (`shepdesign-projects`). One-time setup, all in the Vercel dashboard:

1. **Un-pause.** Project → Settings → Advanced → Pause Project → Resume.
2. **Re-link Git.** Settings → Git → Disconnect `Shepdesign-LLC/NetRelish` → Connect `Shepdesign-LLC/netrelish-site`, production branch `main`.
3. **Root Directory.** Settings → General → Root Directory: leave **blank**. Framework Preset: Astro. Node: 22.x.
4. **Environment variables.** Settings → Environment Variables, for Production and Preview:
   `BENTO_PUBLISHABLE_KEY`, `BENTO_SECRET_KEY`, `BENTO_SITE_UUID` — from Bento → Settings → API keys. Mark them Sensitive.
5. **Domain.** Settings → Domains → Add `netrelish.com` (and `www.netrelish.com`, redirect to apex). At the registrar add the records Vercel shows: an `A` record `@ → 76.76.21.21` and `CNAME www → cname.vercel-dns.com` (Vercel's page is the source of truth if these change).
6. Push to `main` deploys. PRs get a preview URL.

Nothing else. No analytics, no Speed Insights — leave both off; the site's network rule forbids them.
```

- [ ] **Step 2: Ask Ryan to do steps 1–4** (5 can wait). Give him the list in chat, not a file.

- [ ] **Step 3: When the preview builds, verify the endpoint against real Bento**

Run: `curl -i -X POST -H 'origin: https://netrelish.com' -H 'content-type: application/json' -d '{"email":"ryan@shepdesign.com"}' https://<preview-url>/api/join`
Expected: `200 {"ok":true}`. Then, via the Bento connector: `get_subscriber` for that email shows tag `netrelish-beta` and `signup_source = netrelish.com`. If the base URL `app.bentonow.com/api/v1` turns out wrong, the 502 message names the status — fix `BENTO` in `src/lib/join.ts` and re-run the tests (they pin the URL, so update the two `expect(subUrl)` lines).

- [ ] **Step 4: Open the PR** on `netrelish-site` from a `v1` branch (do Tasks 1–10 on `v1`, not `main`, so there is a PR to review), body with **What / Demo / Rule check / Brand check**, screenshots light and dark, the curl output, and the Bento verification. End with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 5: Update the NetRelish spec** — one line under §2 Stack: "Astro 7.3 (the spec said 5; 7 is current and the API used is identical)"; and §3 fonts line → "`@fontsource-variable/bricolage-grotesque/standard.css`, bundled same-origin by Astro (not `/public/fonts`)". Commit to `netrelish` main as `docs(site): spec follows the build`.

---

## Self-review

- **Spec coverage:** §1 job (Task 5 CTA + copy) · §2 stack (1, 3) · §3 layout (all) · §4.0–4.10 (3, 5, 6, 7, 8, 9) · §5 (4, 5) · §6 theme (3 + audit 10) · §7 OG (9) · §8 tests/CI (4, 10) · §9 Vercel (11) · §10 demo (11) · §11 out of scope honored (no blog/press/changelog/toggle) · §12 decisions (8 Pro, 5 headline, 3 type, 10 audit).
- **Gaps found and fixed:** `favicon.svg` (added in Task 3 Step 4); `vercel.app` in allowed hosts for previews (Task 4 Step 6); Reduce Motion final frame (Task 6 CSS); the `www.w3.org` namespace exemption in the network check (Task 10).
- **Type consistency:** `handleJoin(req, deps: JoinDeps)` and `JoinDeps { fetch, env, allowedHosts }` match between Task 4's tests, lib, and route. `readDesignSvg` names match across Tasks 3, 5, 6, 9. Slot name `mock` matches Task 7 Row and index. CSS classes `.btn--primary/--secondary`, `.badge`, `.eyebrow`, `.section`, `.wrap`, `.muted`, `.quiet`, `.tnum` defined in Task 3 and used as such.
