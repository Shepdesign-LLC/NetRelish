# Releasing NetRelish

The pipeline is wired end to end. Two human steps stand between here and a
public build — both need Ryan, neither needs a terminal beyond copy-paste.

## One-time setup

1. **Apple Developer Program** — enroll at developer.apple.com ($99/yr,
   24–48h approval). Every signing step waits on this (CLAUDE.md §13).
2. **Create a Developer ID Application certificate** in the Apple portal,
   export it as a `.p12` with a password.
3. **Add GitHub repository secrets** (github.com/Shepdesign/NetRelish →
   Settings → Secrets and variables → Actions):
   - `APPLE_CERTIFICATE` — the .p12, base64-encoded
   - `APPLE_CERTIFICATE_PASSWORD`
   - `APPLE_SIGNING_IDENTITY` — e.g. `Developer ID Application: Ryan …`
   - `APPLE_ID`, `APPLE_PASSWORD` (app-specific password), `APPLE_TEAM_ID`
     — for notarization
   - `TAURI_SIGNING_PRIVATE_KEY` — contents of `~/.tauri/netrelish.key`
   - `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — empty (key has no password)

## ⚠️ The updater private key

`~/.tauri/netrelish.key` signs every future update. **Back it up now**
(password manager, printed copy, anywhere safe). Lose it and no installed
copy can ever update again — there is no recovery path (§13). The matching
public key is already baked into `tauri.conf.json`.

## Each release

1. Bump `version` in `src-tauri/tauri.conf.json` and `package.json`.
2. Commit, then tag: `git tag v0.1.0 && git push origin v0.1.0`.
3. CI (`.github/workflows/release.yml`) builds, signs, notarizes, staples,
   and drafts a GitHub Release with the .dmg + updater artifacts.
4. Publish the draft. Installed copies see the update at the endpoint in
   `tauri.conf.json` (`netrelish.com/releases/...` — point it at the GitHub
   release asset URLs, or move the manifest to Vercel later, §10).

## Local sanity build

`npm run app:build` — unsigned, for your own Mac only.
