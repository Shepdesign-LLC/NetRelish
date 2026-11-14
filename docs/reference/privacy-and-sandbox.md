---
title: Privacy and sandbox — what each bundle declares
type: reference
created: 2026-11-13
updated: 2026-11-13
sources:
  - code: Resources/PrivacyInfo.xcprivacy
  - code: Sources/ShareExtension/PrivacyInfo.xcprivacy
  - code: Sources/Pantry/PrivacyInfo.xcprivacy
  - code: project.yml
  - code: Config/AppStore.xcconfig
  - code: Sources/Bench/WebView.swift
  - code: Sources/App/NetRelishApp.swift
  - code: scripts/tests/test_privacy_manifests.py
  - code: .github/workflows/ci.yml
verified_at: a7941bc
---

# Privacy and sandbox

What the shipped bundles declare to macOS and to App Store Connect, and the code each line
answers for. The decisions are ADR 0032 (`docs/adr/0032-sandbox-and-privacy-review.md`).
How the files get into the bundles is [[building-without-a-mac]].

## Privacy manifests

| Bundle | Manifest | UserDefaults reasons | Why |
|---|---|---|---|
| NetRelish.app | `Resources/PrivacyInfo.xcprivacy` | `CA92.1`, `1C8F.1` | Tab icons and the Panel (`Sources/App/Workbench.swift:1162`), the Direct build's revoked activations (`Sources/App/License.swift:102`); the App Group suite through Pantry |
| NetRelishShare.appex | `Sources/ShareExtension/PrivacyInfo.xcprivacy` | `1C8F.1` | Leaves shared pages in the App Group suite (`Sources/Pantry/Store/ShareInbox.swift:33`) |
| Pantry.framework, PantryKit | `Sources/Pantry/PrivacyInfo.xcprivacy` | `1C8F.1` | ShareInbox, compiled into the framework; the package lists it as a resource (`Package.swift`) |

All three: no tracking, no tracking domains, nothing collected. No other required-reason API
is used. `scripts/tests/test_privacy_manifests.py` sweeps each bundle's Swift for them.

> ⚠️ **A new required-reason API fails the tests until the manifest says why.** File dates
> (`contentModificationDate`, `attributesOfItem`, `stat`), `systemUptime`, disk space and
> active keyboards each need a reason code in the manifest of every bundle whose code calls
> it. Pick the reason that honestly fits from Apple's list; the test only knows which codes
> exist (`scripts/tests/test_privacy_manifests.py:46`).

> ⚠️ **Declaring collected data changes the App Store page.** The tests hold
> `NSPrivacyCollectedDataTypes` empty on purpose. Adding a type needs an ADR and the same
> answer in App Store Connect's privacy section.

## Entitlements (app)

| Entitlement | What uses it |
|---|---|
| `app-sandbox` | Everything. The Pantry, saved copies and each jar's website data live in the container |
| `network.client` | Page loads, StoreKit, the timestamp authority, the Direct build's license relay |
| `files.user-selected.read-write` | Export Proof's save panel (`Sources/App/Workbench.swift:370`) |
| `print` | File › Print… for the Zest tool in front: Zest MD's Print and Save as PDF (ADR 0033) |
| `personal-information.addressbook` | Import from my card, once (ADR 0006); paired with `NSContactsUsageDescription` |
| `application-groups` | The Share extension's hand-off (ShareInbox) |

The Share extension has the sandbox and the App Group only. Both builds use the same files.

## Info.plist keys that answer a question

| Key | Value | Answers |
|---|---|---|
| `NSAppTransportSecurity` → `NSAllowsArbitraryLoadsInWebContent` | YES | http-only sites in a tab. URLSession stays under ATS; only `timestamp.digicert.com` is excepted |
| `NSLocalNetworkUsageDescription` | one line | macOS's prompt when a page reaches a router or printer |
| `NSContactsUsageDescription` | one line | Import from my card |
| `ITSAppUsesNonExemptEncryption` | NO | Export compliance, on every upload |
| `NRLicenseActivationURL` | empty in the App Store build | App Review 2.4.5; `Config/AppStore.xcconfig` empties it, CI checks the built app |

## What a page can ask for

| Request | 1.0 |
|---|---|
| Camera, microphone | Refused in the app before macOS is asked (`Sources/Bench/WebView.swift:205`) |
| Location | Refused: no entitlement |
| Passkeys, security keys | Fail until Apple grants the browser passkey entitlement (ADR 0032, open item 1) |
| Local network devices | macOS asks, with the line above |

> ⚠️ **Camera, microphone and location come in pairs.** An entitlement without its purpose
> string can get the app ended the first time it's used; a string without the entitlement
> promises something the app can't do. The tests fail on either half alone
> (`scripts/tests/test_privacy_manifests.py:214`). Adding them also means a per-jar
> permission prompt, which is 1.1.
