# ADR 0016: netrelish.com moves from Astro to WordPress

**Status:** proposed; WordPress, visual layout and WP Engine decided by Ryan (Nov 1) · **Date:** 2026-11-01 · **PR:** docs(adr): netrelish.com on WordPress

Ryan made two decisions on Nov 1. Both overturn locked rules:

- Zest: "Zest tools inside the Mac app" / "Zest is supposed to live in NetRelish." That one gets its own ADR.
- Site: "I want a WordPress site not Astro."

This ADR covers the site only.

## What it overturns

The `CLAUDE.md` stack table, Site row:

> | Site | Separate repo `netrelish-site`, Astro static, plain CSS from `tokens.css`. |

**Replacement line:**

> | Site | Separate repo `netrelish-site`: WordPress on WP Engine, laid out in Bricks, with variables generated from `tokens.css` and brand checks on rendered pages (ADR 0016). |

`DESIGN_MANIFEST.md` §10 changes from "(`netrelish-site`, Astro)" to "(`netrelish-site`, WordPress + Bricks)" in a v1.2.2 changelog line. The rest of §10 stays. After cutover, "Astro for netrelish.com" goes on the Retired list.

## Design

**Ryan lays pages out visually.** Ryan's answer to "why WordPress" is that he wants to design pages in a builder, the way he works on his other WordPress sites. So the site is a **Bricks** build, not a locked block theme. Ryan composes and edits every marketing page himself.

**The brand holds through tokens and checks, not locks.**
- Bricks global variables and classes are generated from `tokens.css` and checked in CI, the same "generated, never hand-edited" rule as `Tokens.swift`.
- Relish is only reachable through named components for the manifest §4 placements: primary button, badge, hero CTA and the cog. It isn't in the color picker.
- Bricolage is offered only in the hero component.

**Two pages stay rendered from data.** Roadmap and Privacy make promises. A small plugin block renders the roadmap from `data/roadmap.json`, and the existing roadmap tests keep it matched to ADR 0012. Privacy is rendered from a reviewed text file. Ryan can place these blocks anywhere, but their words change only through a PR.

**Store and licenses: Freemius (Ryan's leaning, to confirm).** Freemius is a merchant of record: it handles checkout, tax, receipts and license keys. That replaces the Stripe and Bento store the Astro site has today. In the direct build, the app's one license-activation call goes to Freemius, which is the slot non-negotiable 5 already allows. The App Store build keeps StoreKit 2. Before committing, check two things:
- that Freemius licenses a macOS app outside WordPress (its SaaS / desktop licensing API);
- what its checkout loads in a visitor's browser.

If Freemius is confirmed, CLAUDE.md's Billing row changes from "Paddle or Lemon Squeezy" to Freemius.

**Hosting.** WP Engine (Ryan, Nov 1): staging, deploys from GitHub, and nothing of its own injected into pages. `zest.netrelish.com` stays on Vercel.

**CI checks what visitors receive.** On every PR, and nightly against production, CI renders every page on WordPress Playground or staging. It runs these checks on the rendered pages:
- `check:network`, `check:relish` and `check:design`, as today
- `check:cookies` (new)
- one primary button per view (new)
- the banned words from the voice guide

If a check fails, Ryan gets a plain-English email listing the page and the problem, never a log. Edits made in Bricks go live straight away, so the nightly run is the safety net.

**Hardening.** A small plugin turns off the WordPress features that contact other hosts or open an attack surface: emoji, the api.w.org link, oEmbed, Google Fonts in the Font Library, Gravatar, XML-RPC and comments.

**Pickle.** Not used and not a dependency. Once Pickle ships (1.2, direct build only), this site is a natural real-world test for it, and nothing more.

## Before and after Dec 14

| When | Work | Fits ADR 0012? |
|---|---|---|
| Nov 2–8 | Confirm Freemius for the direct build's license and checkout. That has to be settled before `NR_LICENSE_ACTIVATION_URL` is set for a shipped build and before the store opens, while there are no customers. Pull the roadmap out into `data/roadmap.json`, and confirm the Astro site is unchanged. | Yes, about 2 days |
| Nov 9–Dec 4 | WP Engine staging; Bricks variables and components generated from `tokens.css`; the roadmap and privacy blocks; hardening plugin; rendered-page CI. Lower priority than the app's P5 work. Nothing goes public. | Yes, and can slip |
| Nov 27–Jan 3 | Astro serves App Review (around Nov 30) and the launch. Home copy is frozen. No DNS changes. | Yes |
| Week of Jan 4 | Cutover, page by page. Every URL keeps its path. The Astro build stays up as a rollback for 7 days. Cutover waits until staging matches Astro's Lighthouse numbers. | After |
| January | Delete Astro and mark this ADR accepted. Add a News section. | After, with 1.1 |

## Rule check

- **NN5 (browsing data never leaves the device):** it governs the app, and the app's endpoints don't change in kind. The activation URL fills the existing "one-time license activation" slot. The privacy page's paragraph about the app stays word for word.
- **The site's own network rule:** kept. It is now checked on rendered pages. Freemius checkout hosts are added to the allowlist only on the pricing page, once confirmed.
- **NN8 (open-core):** our plugin and generated Bricks styles are MIT, which is compatible with WordPress's GPL. Bricks itself is a commercial theme, licensed separately and not in the repo. `logo.svg`, `logo-cog.svg` and the name stay rights reserved.
- **NN4 (no model calls on live content):** not touched. The site makes no model calls.
- **Every PR has a demo:** for site PRs, the demo is a Playground link or the staging URL.
- **Not touched:** NN1–3, 6 and 7.

## Risks

1. **Bricks edits go live without review.** The roadmap and privacy blocks plus the nightly checks limit the damage, but a bad claim or an off-brand color could stay live for up to a day.
2. **WordPress updates can bring back calls to other hosts.** `check:network` fails if one does.
3. **Larger attack surface than a static site.** No keys or secrets live in WordPress. The worst case is defaced marketing pages.
4. **Speed.** PHP behind a page cache may be slower than static Astro. Measure before claiming.
5. **Launch-month time.** Only the Nov 2–8 Freemius decision is required before launch.
6. **The privacy page must change.** It has to name the new host and any analytics. Rewrite it in the same PR as the analytics switch. If the cookie-free counter (Koko Analytics) stores anything identifying, launch the WordPress site with no analytics.
7. **Freemius fit.** Freemius was built for WordPress plugins and themes. Its fit for a macOS app's license keys and its checkout's third-party loads must be checked before it is chosen; Paddle or Lemon Squeezy (CLAUDE.md's current choices) remain the fallback.

## Ryan decided (Nov 1)

- netrelish.com moves to WordPress, laid out visually by Ryan (Bricks), on WP Engine.
- The current site carries App Review and the Dec 14 launch; WordPress goes live the week of Jan 4.
- Store and licenses: "probably Freemius." Recorded as a leaning, not a decision.

## Ryan decides (still open)

1. Freemius for sure, once it's confirmed it can license a Mac app? Or keep Paddle / Lemon Squeezy as CLAUDE.md says?
2. Is Bricks the builder you want, or another one?
3. Roadmap and Privacy keep their words in a reviewed file, so you ask me to change them, but you can place them anywhere. OK?
4. For visit counts: a cookie-free counter inside WordPress, or no analytics?
5. Do you want a "Store open" switch in the WordPress admin, so you turn on sales yourself?
