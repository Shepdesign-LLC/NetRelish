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
| **Zest** (studio) | Lemon / dial | Not yet in this repo. Lives at zest.netrelish.com when built — the studio is the home page (spec §8 and §11, decision 5) |
| **ZestMail** | Orange / envelope | `apps/mail` |
| **Zest MD** | Lime / page | `apps/md` |
| **ZestImage** | Grapefruit / frame | Spec §7.4 only. Stub at `apps/image` — its README is the build brief |

## This directory

```
zest/
  docs/
    ZEST-SPEC.md      product, licensing, and launch spec — the source of truth
    PRESS-TOOLS.md    tenets and the tool reference (MD Press / Mail Press era)
    MAIL-PRESS.md     ZestMail's full reference
  apps/
    mail/             ZestMail: index.html, /api/claude proxy, zest.json, icons
    md/               Zest MD: index.html, sw.js, manifest.webmanifest, zest.json, icons
    image/            ZestImage: README (build brief) only — no app yet
    store/            landing-page draft (index.html); the §10 pricing/terms/account pages are not built
  icons/              the four app icons: svg/, layers/, png/, mono/, fruits.json —
                      and showcase.html, which renders the family in a browser
  infra/
    supabase/0001_init.sql   the Supabase schema from spec §5.1 (written, not deployed)
    fixtures/sample.sql.gz   MySQL dump for import testing — not part of the Zest
                             stack (Supabase is Postgres); header says safe to drop
```

## Run locally

Both shipped apps are single HTML files. Serve them over http; `file://` has a
null origin, which breaks the service worker and any API call.

- **ZestMail** — `cd apps/mail && npx vercel dev` serves the app and
  `/api/claude` on `http://localhost:3000`. Without the proxy:
  `npx serve .` and use your own key via the app's Direct route.
- **Zest MD** — `cd apps/md && npx serve .`. Static, no build step.
- **Zest (studio), ZestImage** — nothing to run yet.

## Status against ZEST-SPEC §10, Milestone 1

In hand:

- Renames done in UI strings (Mail Press → ZestMail, MD Press → Zest MD);
  internal identifiers kept verbatim per spec §2
- `zest.json` manifests done for mail and md
- New marks done for md and mail (all four icons exist under `icons/`)
- Supabase schema written (`infra/supabase/0001_init.sql`) — written is not deployed

Not done:

- Monorepo, Vercel project, subdomain CNAME
- Supabase deploy
- Stripe products, Checkout, webhook provisioning, portal
- Magic-link auth via Resend
- `zest-brand.json` schema and the Zest → tool handoff (blocked on the studio)
- `can()` gating with upgrade prompts
- Pricing page, terms, privacy, refund policy, changelog
- Account page with Export everything
- The studio and ZestImage apps do not exist yet

## Not the browser

Zest is a separate product line from the NetRelish browser — a web stack
(Vercel, Supabase, Stripe; spec §8) staged in this repo until its own monorepo
exists (`docs/adr/0008` in the repo root's `/docs`). Nothing here runs inside
the browser app, and no Xcode target references this directory. The browser's
privacy rule — CLAUDE.md non-negotiable 5, browsing data never leaves the
device — is untouched by anything in it: Zest's endpoints belong to Zest's web
apps, not to NetRelish.app.
