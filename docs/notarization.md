# Signing & Notarization

For the **Developer ID direct build** (`DIRECT_BUILD`). The App Store build
signs and is reviewed through App Store Connect and none of this applies to
it.

Do this before the first direct build ships. Every project that defers it
loses a week later to entitlement errors and stapler failures.

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

## 4. Updates

**Not yet decided for the Swift app.** The App Store build updates through
the App Store. The direct build needs its own mechanism and does not have one
in the tree — no Sparkle, no appcast, nothing.

The retired Tauri app had a minisign keypair for this, and `v0.2.1` on GitHub
Releases is still signed by it. That key is not used by anything being built
now; it is kept only so the published release stays verifiable. Whatever the
direct build eventually uses, the rule that killed the old one still applies:
lose the signing key and you can never update an installed copy.

## 5. GitHub secrets checklist

These are the secrets a signing CI job needs. There is no release workflow on
`main` today — only `ci.yml` — so nothing consumes them yet.


| Secret | Source |
| :-- | :-- |
| `APPLE_CERTIFICATE` | base64 of the `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | password set during export |
| `APPLE_SIGNING_IDENTITY` | `security find-identity` output |
| `APPLE_ID` | your Apple ID email |
| `APPLE_PASSWORD` | app-specific password |
| `APPLE_TEAM_ID` | the code in parentheses in the identity string |

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
| `The executable does not have the hardened runtime enabled` | Hardened Runtime off in the target's Signing & Capabilities |
| App launches then dies instantly | JIT entitlement missing — WKWebView cannot start |
| `Team ID mismatch` | certificate belongs to a different team than `APPLE_TEAM_ID` |
