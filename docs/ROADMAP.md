# Roadmap & positioning

Where NetRelish is going and why, in one page. Kept current with the plan.

**What wins when this page disagrees:** `CLAUDE.md` (the contract), then the accepted
ADRs in `docs/adr/`, then `docs/NetRelish_Plan_and_Roadmap.md` (the 12-week plan to the
Mac App Store). This page summarizes them. It never overrides them.

Ryan's business plan (v1.0, Aug 2026) stays out of this repo, which is public. Strategy
stays off the public record.

*Last updated Nov 5, 2026.*

---

## Positioning

NetRelish is a native Mac browser with a Pantry. It sits **between research and
execution**, and answers one question:

> "I found all this stuff. Now what?"

Bookmark managers own saving, Notion owns documents, read-later apps own reading, and AI
browsers own answering. Nobody owns the gap between *found it* and *used it*. That gap
is the product.

- **Tagline:** "Savor the web. Get more done."
- **Approved for marketing copy:** "Don't just save the web. Use it."
- **The wedge:** NetRelish's intelligence reads only what you sealed. It never sees a
  live tab, never clicks, never acts inside a signed-in session. That closes the attack
  surface every AI browser on Chromium is exposed to. It's a consequence of how
  NetRelish is built, not a slogan, so it's a proof point, listed third, not the
  headline.

In NetRelish the **Pantry is what you've kept**, not the internet. The web is the market
you shop in; the Pantry is home.

## Who it's for

1. **Web designers and developers.** They research constantly, repeat the same workflows
   across clients, and fight tab chaos daily. This is Ryan; the first user is the
   persona.
2. **Marketers.** Competitor, SEO and campaign research. Jars are client files.
3. **Business professionals.** Market research, vendor comparisons, planning.
4. **Researchers, lawyers, consultants.** People whose job is to keep receipts on the
   web.

Sell to the first group first. They have the problem every day, and their public work
brings in the rest.

## Business-plan words, and what the product calls them

| The business plan says | The product says | Status |
| :-- | :-- | :-- |
| Workspace | **Jar** (a project, and its own browsing profile) | Shipped |
| Ingredient | item (`page · note · task · file · message`) | Shipped |
| "Relish This" / save in seconds | **Capture** (⌘D) into Brine, or Share → NetRelish from any app | Shipped |
| Preserve a page | **Seal** (⌘S): a saved copy, full-text searchable | Shipped |
| Repeatable workflow | **Recipe**, each one a Shortcut | Built-in Seal & Summarize: 1.0. Record one and replay it with ⌘R: 1.1 |
| AI summaries | Seal & Summarize, on-device with Apple Intelligence | 1.0 |
| AI categorization, related items | Semantic search, on-device | 1.1 |
| Web clipper | Page-level capture | Shipped. Highlights and notes (Notebook): 1.1 |
| Proof of what a page said | Reseal & diff, and provenance export | 1.0, Pro |
| Sharing a collection | Jar bundles over AirDrop, no account either end | 1.1, Pro |
| Website analysis ("Relish Report") | Not on the native roadmap | Ryan's call if it returns |
| "What am I missing?" gap analysis | Not on the native roadmap: it needed hosted intelligence | Ruled out by non-negotiable 5 |
| Knowledge graph | Not on the native roadmap | Ryan's call if it returns |
| Public collections, marketplace, teams | Not on the native roadmap: they need a server | Ruled out by non-negotiable 5 |

## Roadmap

### The 12 weeks to the Mac App Store

Launch target: **Dec 14, 2026**. On Nov 1 Ryan held the date and cut the scope
(ADR 0012).

| Phase | What | Dates | Status |
| :-- | :-- | :-- | :-- |
| P0 Pivot | Swift foundation; the data model generated from System Designer | Sep 14–18 | Done |
| P1 Bench + Shelf + Brine | Tabs, the jar rail, jars as profiles, Brine, ⌘K, ⌘D | Sep 21 – Oct 2 | Done |
| P2 Seal | Saved copies, search, Reader view, Smart Jars, the Panel | Oct 5–16 | Done |
| P3 Recipes + Shortcuts + Share | Share menu, Shortcuts, Seal & Summarize | Oct 19–30 | Built. Seal & Summarize merged Nov 5 |
| P4 Pro | Reseal & diff, provenance export, buying Pro | Nov 2–13 | In progress: Reseal & diff and provenance export shipped; buying Pro built (App Store build; the Direct build stays unlocked until its license key) |
| P5 App Store prep | Sandbox and privacy review, StoreKit 2, accessibility, onboarding | Nov 16–25 | Not started |
| P6 TestFlight + launch | Testers, App Store listing, submission | Nov 30 – Dec 11 | Not started |

Previews 0.4.0–0.4.2 ship the finished phases as a signed direct download
(`docs/releases/`).

### What 1.0 includes (ADR 0012)

- **Browsing:** the Shelf, jars as profiles, Brine, links that open new windows become
  tabs.
- **Keeping:** Capture, Seal, search that opens the saved copy, Smart Jars (Brine, Today,
  Sealed, Sinking soon), Reader view, the Panel, the Share menu, Shortcuts.
- **Recipes:** a few built-in ones, one per jar, run on Seal and listed in Shortcuts.
  "Seal & Summarize" uses on-device Foundation Models.
- **Pro:** reseal & diff, provenance export, buying and restoring Pro (StoreKit 2), and a
  license key for the direct build.
- **App Store prep:** everything in P5.

Free and Pro: Free, and Pro at $39/yr or $99 lifetime ("Buy once, use forever."). Pro
launches with two features at those prices.

### 1.1 (January 2027)

- Moved from 1.0 by ADR 0012: Ask the Pantry, content blocker, split view, Jar bundles,
  semantic search, unlimited Recipes, recording a Recipe and replaying it with ⌘R.
- Notebook: highlights and notes on saved pages.
- Zest: the free Zest tools inside the app, offline, in their own window (ADR 0015).
- Proposed, not decided: Panel notes, which need a model change in System Designer first.

### After 1.1

- **Duo companion (iOS):** capture and Brine on the phone. Post-1.0, no date (Ryan,
  Nov 5). The Pantry core is already a Swift package for it (ADR 0009).
- **1.2:** Pickle, a jar with a local dev environment (direct build only); voice notes;
  opt-in larger on-device models (MLX).
- **1.3:** Pickle with Docker; a visionOS "Pantry as a room" demo.

### The site

netrelish.com moves from Astro to WordPress the week of Jan 4, 2027 (ADR 0016). It
lives in its own repo, `netrelish-site`. Its roadmap page and changelog must match this
page before they go live.

## Retired

These came from the August Tauri plan and were dropped with the September pivot to a
native Mac app (`docs/NetRelish_Plan_and_Roadmap.md`, and `CLAUDE.md` § Retired). They are
listed so the change stays visible.

- **Accounts, a cloud backend, sync through a server, and a hosted LLM.** Browsing data
  never leaves the Mac (non-negotiable 5). The only network calls are page loads,
  StoreKit, provenance timestamps and the direct build's license activation. Sync for
  Duo, when it comes, goes through the person's own iCloud Drive.
- **A Chrome/Edge extension and a web app.** NetRelish is the browser, on the Mac.
- **The Tauri app's features** (the suggestion strip, `⌘J` "Jar it", the password vault)
  are not being carried over. The native app's Me card (Keychain, ⌘⇧F) covers form
  filling.

## Metrics that matter

- **Seals per active user per week:** the one number that says the Pantry is being used.
- **Free → Pro conversion, and Pro refunds.**
- **Recipes created per Pro user.**
- **Crash-free sessions.**
- **App Store rating.**

Targets are in the plan, §8. NetRelish has no analytics: these numbers come from App
Store Connect and StoreKit, and from feedback people choose to send. Nothing more is
collected unless it's written down first.
