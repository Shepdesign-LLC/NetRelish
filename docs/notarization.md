# Signing & Notarization

Do this in week 1. Every project that defers it loses a week later to
entitlement errors and stapler failures.

## 1. Apple Developer Program

$99/year. Enrolment can take 24–48 hours, so start it before anything else.

## 2. Certificate

In Xcode: **Settings → Accounts → Manage Certificates → + → Developer ID
Application**. This is the one for distribution outside the App Store. A
"Development" certificate will build but will never notarize.

Export it as `.p12` with a password, then:

```bash
base64 -i certificate.p12 | pbcopy   # → GitHub secret APPLE_CERTIFICATE
```

Find your identity string:

```bash
security find-identity -v -p codesigning
# "Developer ID Application: Your Name (ABCDE12345)"
```

## 3. App-specific password

appleid.apple.com → Sign-In and Security → App-Specific Passwords.
This is **not** your Apple ID password. → GitHub secret `APPLE_PASSWORD`.

## 4. Updater keypair

```bash
npm run tauri signer generate -- -w ~/.netrelish/updater.key
```

Public key → `plugins.updater.pubkey` in `tauri.conf.json` (committed).
Private key → GitHub secret `TAURI_SIGNING_PRIVATE_KEY` (never committed).

Lose the private key and you cannot ship updates to installed copies. Back it
up somewhere you will still have in three years.

## 5. GitHub secrets checklist

| Secret | Source |
| :-- | :-- |
| `APPLE_CERTIFICATE` | base64 of the `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | password set during export |
| `APPLE_SIGNING_IDENTITY` | `security find-identity` output |
| `APPLE_ID` | your Apple ID email |
| `APPLE_PASSWORD` | app-specific password |
| `APPLE_TEAM_ID` | the code in parentheses in the identity string |
| `TAURI_SIGNING_PRIVATE_KEY` | contents of `updater.key` |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | password set during generate |

## 6. Verify a build

```bash
codesign -dv --verbose=4 "NetRelish.app"      # expect Developer ID + runtime flag
spctl -a -vvv -t install "NetRelish.app"      # expect: accepted, Notarized Developer ID
xcrun stapler validate "NetRelish.app"        # expect: The validate action worked
```

If `spctl` says *rejected*, notarization did not complete. Pull the log:

```bash
xcrun notarytool log <submission-id> \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_PASSWORD"
```

## Common failures

| Symptom | Cause |
| :-- | :-- |
| `The signature does not include a secure timestamp` | built offline; signing needs network |
| `The executable does not have the hardened runtime enabled` | `hardenedRuntime: true` missing from `tauri.conf.json` |
| App launches then dies instantly | JIT entitlement missing — WKWebView cannot start |
| `Team ID mismatch` | certificate belongs to a different team than `APPLE_TEAM_ID` |
