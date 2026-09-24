# Releasing NetRelish

**The pipeline described here until 2026-09-16 no longer exists.** `ad0bdff`
retired Tauri and deleted the release workflow with it; `main` carries only
`ci.yml`. Everything about tags, `tauri.conf.json` versions, `tauri-action`
and the updater manifest went with it, and is preserved on the legacy branch
at `324762e`.

What follows is what survived the change: the Apple facts, which are about
the account rather than the toolchain, and the one rule that has been earned
three times.

## The release process is not written yet

Two builds ship from one codebase (`#if DIRECT_BUILD`):

| Build | Signs with | Distributed by | Updates by |
| :-- | :-- | :-- | :-- |
| App Store | Apple Distribution | App Store Connect | the App Store |
| Direct | Developer ID | *undecided* | email — by design, see ADR 0006 |

The direct build has **no updater, deliberately**: no Sparkle, no appcast,
nothing that polls. A new version is announced by email to the address that
bought the licence, and About links to the download page. Decided by Ryan on
2026-09-23; the reasoning, and what would overturn it, are in
`docs/adr/0007-direct-build-updates.md`.

The constraint that drove it is CLAUDE.md §5, which lists every call the app
may make and ends "Add an endpoint and you've broken this rule." An appcast
polled on a schedule is such an endpoint. Adding one later is possible, but it
amends a non-negotiable and must be written as such, in the same commit.

Write this section when the first build of either kind actually ships. Do not
write it from intention; that is how the file you are reading became wrong.

## Apple account — still true

Enrolment is done: **Individual, Team ID `D9QDJ44773`**, Developer ID
Application certificate issued.

The Apple ID is **ryanshepherd93@gmail.com**, not ryan@shepdesign.com. An
earlier attempt failed with "account does not exist" on exactly that
mistake. Notarization needs an **app-specific** password from
appleid.apple.com, never the account password — a normal password there
produces a 401 that looks like a broken credential rather than a wrong kind
of credential.

`docs/notarization.md` has the certificate, secrets and verification detail.

**The local machine has no codesigning identity** in its login keychain
(`security find-identity -p codesigning` returns none), so a local build is
ad-hoc signed: fine to run here, refused by Gatekeeper anywhere else.

## The repository moved, and secrets did not

NetRelish lives at **`Shepdesign-LLC/NetRelish`**. Transferring to an org
creates a new repository record: **secrets do not transfer, and neither does
workflow run history.** An empty secret list after a move means "moved", not
"never set". GitHub 301-redirects the old path, which is why the move went
unnoticed for a day.

Two lessons survive the toolchain:

- A secret existing is not the same as a secret working, and a secret you
  remember setting is not the same as a secret that is there.
- Never let a redirect carry anything baked into a shipped binary.

## Check the artifact, not the checkmark

```bash
spctl -a -vvv -t install "NetRelish.app"   # expect: accepted, Notarized Developer ID
xcrun stapler validate "NetRelish.app"     # expect: The validate action worked
```

The stapled ticket is what makes it work offline — Gatekeeper does not need
to reach Apple on first launch.

The release workflow ran four times in its life, and every run was green.
**Half of them produced something that should not ship:**

| Run | Trigger | Outcome |
| :-- | :-- | :-- |
| 32229611836 | dispatch | Fine — the notarization proof, checked on the artifact |
| 34007890136 | tag `v0.2.0` | Updater endpoint named the wrong GitHub owner |
| 34030599628 | dispatch on `main` | Release named after the branch, not a version |
| 34032765839 | tag `v0.2.1` | Fine — shipped |

Green means the job finished. It does not mean the thing it produced is
shippable. The two that were fine are the two that were checked.

## v0.2.1 — the last Tauri release

Published 2026-09-06, signed and notarized, still downloadable. Its updater
manifest resolves correctly and is signed by the retired minisign key.

It is a historical artifact and receives no further updates. The Swift app's
floor is macOS 27, so nothing installed from it can upgrade into the new app
even if a bridge existed. Leave it published; it is verifiable and harms
nothing.
