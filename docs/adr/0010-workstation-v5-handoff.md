# ADR 0010 — Workstation v5 handoff: what it overrides, and what it doesn't

**Status:** accepted · **Date:** 2026-10-31 · **Accepted:** 2026-11-01 · **PR:** docs(design): land the Workstation v5 handoff

The Workstation v5 handoff (`docs/design/workstation-v5/`) is the design target
for the workstation shell: the four-row layout, shelf, jar board, notes, the
right panel and Dev workbench, context menus, drag, Brine, onboarding,
keyboard, and the voice guide. It was written as if for an empty repo, so it
conflicts with locked rules in `CLAUDE.md` and `DESIGN_MANIFEST.md` v1.2.

**Decision:** adopt v5's **experience** (layout, interactions, copy). Keep the
repo's **architecture**. Where the two conflict, the repo stands unless a row
below is marked *Ryan decides* and he decides otherwise. Nothing in `/design`
changes until a manifest version bump.

| # | v5 says | Repo rule | Proposed default |
|---|---|---|---|
| 1 | Swift shell, web UI in WKWebView; lift the prototype CSS | SwiftUI; `Tokens.swift` generated from `/design` (Stack) | **Repo stands.** Rebuild v5 in SwiftUI; the prototype CSS is a spec for metrics and behavior, not code to ship. |
| 2 | Separate `Jar` / `Note` / `Tab` / `LocalSite` models | One `Item` table, discriminated by `kind` (non-negotiable 1) | **Repo stands.** Note and tab are `Item` kinds. `cap`, `color`, `order` and `sealedAt` belong on `Jar`. A local copy is Pickle data (row 7). |
| 3 | Glass and frost on chrome (`blur` + `saturate`), specular lines, gradient fills, chrome shadows | Manifest §6: no blur, no glass, no chrome shadows; §3: no gradients in the product | **Decided (Ryan, 2026-11-01): v1.2 holds.** v5's layout is built on hairlines and flat surfaces. No glass, no manifest v2.0. |
| 4 | Relish on the search row, Dev switch, guide tiles and Brine glow; Bricolage for in-app headings | Relish only in the 8 placements in manifest §4; Bricolage only in the site hero | **Decided (Ryan, 2026-11-01): v1.2 holds.** Relish stays in the 8 manifest §4 placements; Bricolage stays in the site hero. |
| 5 | **Seal** = finish a whole jar (read-only until reopened) | Seal = per item: stamp `sealedAt`, freeze the `.webarchive`, close the tab, run the Recipe (non-negotiable 3) | **Decided (Ryan, 2026-11-01): Seal stays per item.** Finishing a whole jar gets its own word, chosen in the PR that builds it, so "Seal" keeps one meaning. |
| 6 | Profiles hold many jars; profiles don't share jars | Every jar is a profile: one `WKWebsiteDataStore` per jar (non-negotiable 6) | **Repo stands.** v5's profiles become an account-level layer *above* jars. Each jar still gets its own data store. Multi-profile stays uncosted (see `docs/design/README.md`). |
| 7 | Dev = local WordPress copies (Start/Stop, plugins, backup, Copy to live) in 1.0 | That is Pickle: direct build only, deferred to 1.2 | **Decided (Ryan, 2026-11-01): 1.2, direct build only.** Dev is Pickle's user-facing name. Running local servers fights the App Store sandbox. |
| 8 | Vault (Keychain, Touch ID on every reveal) | `Sources/Vault` already holds the Me card in Keychain (ADR 0006) | **Merge.** One Vault: v5's reveal rules (Touch ID on every reveal, clears on blur, never in app state) apply to all of it. |
| 9 | Bans "inspector" and "sidebar"; adds Keep, Note, Panel, Guide, Local copy | `CLAUDE.md` vocabulary includes Inspector | **Merge.** Adopt v5's added words. Panel replaces Inspector in UI copy; code renames follow in the PR that builds the panel. |
| 10 | Brine expires after 14 days, the last 3 shown in amber | Brine is a query; jar shelf life drives sinking | **Repo stands** on mechanics. v5's 14-day / amber-at-3 display applies to items already in Brine. |
| 11 | Nothing leaves the Mac unless the user signs into sync | Browsing data never leaves the device (non-negotiable 5) | **Repo stands.** There is no sync of browsing data. Only Notes sync could be discussed, and that needs its own ADR. |
| 12 | `assets/netrelish-mark.svg` is "the real mark" | `/design/logo.svg` and `logo-cog.svg` are the locked marks | **Decided (Ryan, 2026-11-01): the locked marks stand.** The v5 file is kept as a reference for its `nr-` gradient namespacing. |
| 13 | (absent) jar-fill drip; notes in plain text | 2026-10-21: drip on add (Brand Lock v1.2), Markdown notes | **Repo stands.** Both stay. v5 dropped them silently, and the earlier prototype keeps the reference implementation. |

Agreements worth stating, because v5 and the repo already match: the jar is
the unit; Brine; the shelf is always open; archive instead of delete, with Undo;
no terminal in the product; US English; `prefers-reduced-motion`; the relish
focus ring.

Ryan settled rows 3, 4, 5, 7 and 12 on 2026-11-01, all on the proposed default,
so this ADR is **accepted**. No row changes a manifest rule, so `/design` and
manifest v1.2 stay as they are.
