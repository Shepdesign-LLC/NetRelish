# Releasing NetRelish

The pipeline is wired end to end. Two human steps stand between here and a
public build — both need Ryan, neither needs a terminal beyond copy-paste.

## One-time setup

1. **Apple Developer Program** — enroll at developer.apple.com ($99/yr,
   24–48h approval). Every signing step waits on this (CLAUDE.md §13).
2. **Create a Developer ID Application certificate** in the Apple portal,
   export it as a `.p12` with a password.
3. **Add GitHub repository secrets** (github.com/Shepdesign-LLC/NetRelish →
   Settings → Secrets and variables → Actions):
   - `APPLE_CERTIFICATE` — the .p12, base64-encoded
   - `APPLE_CERTIFICATE_PASSWORD`
   - `APPLE_SIGNING_IDENTITY` — e.g. `Developer ID Application: Ryan …`
   - `APPLE_ID`, `APPLE_PASSWORD` (app-specific password), `APPLE_TEAM_ID`
     — for notarization
   - `TAURI_SIGNING_PRIVATE_KEY` — contents of `~/.tauri/netrelish.key`
   - `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — leave this secret **unset**.
     The key has no password, GitHub refuses empty-string secrets, and an
     absent secret reaches the workflow as empty — which is correct.

Status 2026-08-19: enrolment done (Individual, Team ID `D9QDJ44773`) and
the certificate is issued.

**Correction — the repo moved to an organization.** NetRelish now lives at
**`Shepdesign-LLC/NetRelish`**; `Shepdesign` is Ryan's personal account and
is no longer the owner. Transferring a repository to an org creates a new
repository record, and **secrets do not transfer** — neither does workflow
run history. That is why this repo showed 0 secrets, 0 runs and 0 releases
while the git history came across intact.

GitHub 301-redirects the old path, so `Shepdesign/NetRelish` keeps working
in `gh` commands and in a browser. Convenient, and misleading: it hid the
ownership change for a full day. Prefer the canonical path everywhere, and
never rely on the redirect for anything baked into a shipped binary.

So the long-standing story here — "`APPLE_PASSWORD` is present but
invalid, notarization fails 401" — was never true of *this* repo. The
secrets were simply absent. Two lessons survive the correction, and both
are worth keeping:

- A secret existing is not the same as a secret working. (And a secret
  you remember setting is not the same as a secret that is there.)
- Notarization authenticates to Apple over the network with `APPLE_ID` +
  `APPLE_PASSWORD` + `APPLE_TEAM_ID` — a *different* credential path from
  signing. A build can sign perfectly and still be refused. A 401 is
  nearly always `APPLE_PASSWORD` holding a normal Apple ID password
  where the notary service requires an **app-specific** one.

Ryan re-added all seven secrets on 2026-08-19: six piped from the local
key material in `~/.tauri/`, plus a fresh app-specific password from
appleid.apple.com. The Apple ID is **ryanshepherd93@gmail.com**, not
ryan@shepdesign.com — an earlier attempt failed with "account does not
exist" on exactly that.

**Notarization is proven — 2026-08-19.** Run 32229611836 built, signed,
notarized and stapled from the new `apps/desktop` layout. Verified on the
artifact itself rather than on a green checkmark:

```
$ spctl -a -vvv -t install /Volumes/.../NetRelish.app
accepted
source=Notarized Developer ID
origin=Developer ID Application: Ryan Shepherd (D9QDJ44773)

$ xcrun stapler validate /Volumes/.../NetRelish.app
The validate action worked!
```

The stapled ticket is what makes it work offline — Gatekeeper does not
need to reach Apple on first launch.

A note for next time: the CI log shows **no** "Notarizing" or "Stapling"
line. What it does show is `Signing …/NetRelish.zip` followed by a ~53s
gap before the DMG is signed — that gap *is* the notary submission. Do not
read the missing log line as a skipped step, and equally, do not read a
green step as proof. Check the artifact.

Signing material backed up in iCloud Drive → NetRelish (the Developer ID
`.p12`/`.key`, and the updater key — see below).

Note the *local* machine has no codesigning identity in its login
keychain (`security find-identity -p codesigning` returns none), so a
local `npm run app:build` produces an **ad-hoc signed** app: fine to run
here, refused by Gatekeeper anywhere else. Real signing happens in CI,
which imports the `.p12` from the secrets above.

## The updater private key — backed up

`~/.tauri/netrelish.key` signs every future update. Lose it and no
installed copy can ever update again — there is no recovery path (§13),
and a fresh key cannot sign for apps already out there, because the
matching public key is baked into `tauri.conf.json` at build time.

**Verified 2026-08-16.** Three copies exist:

| Where | Retrievable? | For |
| :-- | :-- | :-- |
| `~/.tauri/netrelish.key` | yes | local `npm run app:build` |
| **iCloud Drive → NetRelish/netrelish.key** | **yes** | disaster recovery |
| GitHub secret `TAURI_SIGNING_PRIVATE_KEY` | no — write-only | CI signing |

The iCloud copy is the one that matters: it is byte-identical to
`~/.tauri/netrelish.key`, fully downloaded rather than an evicted
`.icloud` stub, and it is the only off-machine copy you can actually get
*back*. A GitHub secret can be overwritten but never read, so it protects
CI's ability to ship — not your ability to restore a new Mac.

Checked by comparing hashes, never contents; and the key on disk is
confirmed to be the right one — its public half matches the `pubkey` in
`tauri.conf.json`.

The key has no passphrase (see `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`
above), so anyone holding the file can sign updates as NetRelish. Treat
the iCloud folder accordingly.

To make a local build produce the signed updater artifacts too:

```bash
export TAURI_SIGNING_PRIVATE_KEY="$(cat ~/.tauri/netrelish.key)"
```

Without it, `npm run app:build` still produces `.app` and `.dmg`, then
fails at the last step with *"A public key has been found, but no private
key"* — the bundles are fine, only `NetRelish.app.tar.gz` goes unsigned.

## Each release

1. Bump `version` in `apps/desktop/src-tauri/tauri.conf.json` and
   `apps/desktop/package.json`. The **root** `package.json` carries a version
   too, but it is the workspace root, not the app — the shipped version is the
   one in `tauri.conf.json`, and the two under `apps/desktop/` should agree.
2. Commit, then tag: `git tag v0.1.0 && git push origin v0.1.0`.
3. CI (`.github/workflows/release.yml`) builds, signs, notarizes, staples,
   and drafts a GitHub Release with the .dmg + updater artifacts.
4. Publish the draft. Installed copies see the update at the endpoint in
   `tauri.conf.json` (`netrelish.com/releases/...` — point it at the GitHub
   release asset URLs, or move the manifest to Vercel later, §10).

## Local sanity build

`npm run app:build` — unsigned, for your own Mac only.
