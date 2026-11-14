# ADR 0032 — The sandbox and privacy review: what the App Store build declares, and why

**Status:** proposed (for Ryan) · **Date:** 2026-11-13 · **PR:** feat(p5): sandbox and privacy review

P5's first item (`docs/NetRelish_Plan_and_Roadmap.md`, P5): the entitlements audit and the privacy manifest. Everything the app touches was mapped against what it declares: files, network, Contacts, Keychain, the App Group, and what a web page can ask a browser for. The full map is `docs/reference/privacy-and-sandbox.md`.

**The audit found no sandbox violation.** Every file the app writes is in its own container or one the person picked in a save panel. The network is page loads, StoreKit, the timestamp authority and (Direct only) the license relay. Contacts is read once, when asked. The entitlements stay as they are: sandbox, outgoing network, files the person picks, the Contacts card, and the App Group.

## What this PR decides

| # | Decision | Why |
|---|---|---|
| 1 | **Three privacy manifests**: the app (`Resources/`), the Share extension, and the Pantry framework (also shipped by the PantryKit package for Duo). Each says no tracking, no tracking domains, nothing collected, and gives a reason for UserDefaults: `CA92.1` (the app's own defaults) and `1C8F.1` (the App Group suite the Share extension leaves pages in). | Apple asks every bundle with code for one. On iOS (Duo) a missing reason is an upload rejection; on the Mac it's expected. No other required-reason API is used: no file dates, boot time, disk space or keyboards. `scripts/tests/test_privacy_manifests.py` sweeps the code so a new use can't slip past the manifest. |
| 2 | **The App Store label is "Data Not Collected."** | Apple counts what a developer keeps. Page loads are the person browsing the open web, which Apple exempts. StoreKit's data is Apple's. The timestamp request carries only a fingerprint of the saved copy, and nothing comes back to us. |
| 3 | **The Direct build ships the same manifest.** It has no App Store label, so its one extra call (the license relay: the key and a random name for this Mac, ADR 0027) is disclosed in the privacy policy on netrelish.com instead. | One manifest keeps both builds' Resources the same. A second, Direct-only manifest would need a per-build file swap nobody can test without a Mac. |
| 4 | **Web content is out of App Transport Security** (`NSAllowsArbitraryLoadsInWebContent`). The timestamp and license calls stay under it. | NetRelish is a browser, and some sites are http only. Text for App Review: *"NetRelish is a general-purpose web browser. People type or follow links to any site, some of which are served over http only. The exception covers web views only; the app's own network calls (StoreKit, an RFC 3161 timestamp authority) use https except the one timestamp host listed."* |
| 5 | **Camera and microphone: refused in 1.0.** A page that asks gets a refusal, and macOS is never asked. No entitlement, no purpose string. Location has no entitlement either, so pages asking for it are refused. Screen sharing has no hook an app can answer, so what a page gets is checked on a Mac (the PR's demo). | Per-site, per-jar permission is a feature with its own UI. Answering the request in the app means macOS is never asked, and macOS ends an app that asks for the camera without a purpose string. Proposed for 1.1. |
| 6 | **Local network: a purpose string.** "A page you opened in NetRelish wants to reach a device on your network, like your router or printer." | macOS asks before an app reaches the local network. A router or printer page in a tab triggers it, and without a line the prompt can't say why. |
| 7 | **Export compliance answered** (`ITSAppUsesNonExemptEncryption = NO`). | The app uses system TLS and hashing only. Without the key, App Store Connect asks on every upload. |
| 8 | **The App Store build carries no license address.** `Config/AppStore.xcconfig` empties `NR_LICENSE_ACTIVATION_URL`; CI fails a build where it isn't empty. | App Review 2.4.5: an App Store app asks for no license key. The code never used it there; now the shipped Info.plist doesn't name the relay either. |
| 9 | **Help → Privacy Policy**, for everyone. | App Review 5.1.1(i): the policy must be easy to reach inside the app. It was only in the Pro window. |

## Open for Ryan

1. **Passkeys.** Signing in with a passkey or security key on GitHub, Google or Apple doesn't work in a jar until Apple grants the browser passkey entitlement (`com.apple.developer.web-browser.public-key-credential`). Only the Account Holder can ask, at developer.apple.com/contact/request/macos-browsers-passkeys/, and approval has taken weeks. Apple's criteria include being able to be the default browser, which is a follow-up below. Ask now, or say passkeys are 1.1?
2. **Safe Browsing.** WebKit's fraudulent-site warning is on by default and keeps its lists current through Apple's service. That's a network call the system makes, not one NetRelish makes, and it goes to Apple, not to us. Proposed: keep it on, and add it to non-negotiable 5's list ("…and Apple's Safe Browsing lists, through WebKit") the next time `CLAUDE.md` changes. Or turn it off.
3. **Shortcuts.** A Shortcut the person builds can send Pantry data anywhere they tell it to. Proposed: the privacy policy says so in one line; nothing changes in the app.
4. **The privacy page** on netrelish.com should name DigiCert as the timestamp authority and describe the Direct build's license call (decision 3).

## Found, and left for their own pull requests

These are browser features a reviewer may try, not sandbox or privacy declarations:

- **Browser basics:** web page file uploads (no picker opens), downloads (they go nowhere; saving to Downloads also needs `com.apple.security.files.downloads.read-write`), JavaScript alert/confirm/prompt, printing (needs `com.apple.security.print` and a Print command), sign-in prompts for sites behind basic auth, and video fullscreen.
- **Being the default browser:** `http`/`https` URL types and opening links from other apps. Needed for the passkey request too.
- **The App Store archive:** nothing signs, archives or validates the App Store build yet, and its provisioning profiles don't exist. That is P6's submission work and needs Ryan's App Store Connect setup.
- **KeyboardShortcuts** is linked but never used. Removing it takes the package out of the shipped app.

**Rule check.** NN5: no new endpoint. The App Store build loses the license address it never used. NN6: untouched. NN4: refusing capture reads nothing from the page.
