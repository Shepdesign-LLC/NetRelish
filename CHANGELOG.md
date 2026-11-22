# Changelog

Notable changes to NetRelish. Release notes for each preview are in `docs/releases/`. Numbers are pull requests.

## Unreleased

### Added
- The welcome sheet: three cards on jars, Brine and Seal, shown once at the first launch and again from Help › Welcome to NetRelish (ADR 0038).

## 0.6.0 — 2026-11-21

### Added
- Accessibility: VoiceOver says what capture, Seal, sinking, restore and a move did; keys and menu items for what needed the pointer (⌘L, ⌃Tab, ⌘[ and ⌘], Tab › Move Tab to Jar, Jars › Show Board); Reduce Motion, Reduce Transparency, Increase Contrast and Differentiate Without Color followed live (#103, ADR 0036).
- The workbench facelift: attached tabs, the Shelf as a rail of jars, a two-phase Seal, the floating ⌘K (#102, ADR 0035).
- The Workstation v5 window, with a board for each jar (#95, ADR 0034).
- The Zest tools inside NetRelish.app, offline, under Window › Zest (#93, ADR 0033).
- Sandbox and privacy review: privacy manifests, Help › Privacy Policy, camera and microphone refused, a reason for the local network prompt (#91, ADR 0032).
- ZestMail canvas at full size and 1:1 on phones; ZestImage stage fits the window; the eight Zest cards redesigned (#92).

### Changed
- CI no longer pays for abandoned runs or for commits that can't change what it builds (#104, ADR 0037).
- 0.6.0 notes and the changelog cut (#105).

### Fixed
- Security: during Seal, the address row and the selected tab follow the page in front, not the tab being sealed (#107).
- `main` builds again after #107, and the capture → jar → seal UI test passes for the first time (#109).
- Image: malformed SVG brand logos no longer freeze the app (#99).
- Mail: merge-tag scanning, image-placeholder scans and image-like comments no longer hang the native preview (#96, #97, #98).

## 0.5.0 — 2026-11-13

### Added
- Seal & Summarize: an on-device summary of every sealed page (#72).
- Reseal & diff (Pro): seal a page again and compare the two copies side by side (#74).
- Provenance (Pro): fingerprint, RFC 3161 timestamp, and Export Proof (#75).
- Buying Pro with StoreKit 2 (#76).
- The Direct build's license key (#88, ADR 0027).
- Right-click and drag, the Mason Jar, and a seal that shows when it's broken (#89).
- Simpler Zest tools, with sound (#89).

### Changed
- ROADMAP.md describes the native plan (#73).
- Swift CodeQL runs on supported Xcode 26 (#71).
- 0.5.0 notes, and a preview that leaves Pro unlocked (#90, ADR 0031).
- The CodeQL gate decides what code scanning sees; approved endpoints aren't alerts (#86).

### Fixed
- Security: Fill from Me no longer discloses through clipping, mixed direction, or unsupported writing-mode geometry (#84, #85).
- Security: Zest tools check what they're given; the pipeline pins what it runs (#82).
- Security: code scanning alerts closed; timestamps that check out; Fill from Me only where you can see (#81, #83).
- Repaired the CodeQL gate and Fill from Me script after the #83 merge (#87).
- CI: release notes come from git objects, and write access is limited to publish jobs (#78).

## 0.4.2 — 2026-11-02

### Added
- Shortcuts: Capture, a full Seal, Open a Jar, and Search (#67).
- A branded disk image (#67).

### Fixed
- The app's signature stays intact in the disk image (#70).

## 0.4.1 — 2026-11-01

### Added
- Capture from Safari or any app's Share menu (#65).

### Fixed
- Notarizable build; tag only after Gatekeeper passes (#64).

## 0.4.0 — 2026-11-01

### Added
- Reader view, ⌘⇧R (#57).
- The Panel: kind, source, sealed date and labels, ⌘⌥I (#59, #60).
- Smart jars: Today, Sealed and Sinking soon join Brine, on ⌃⌘1–4 (#55).
- Links that open new windows become tabs; sealed results open the saved copy (#53).

### Fixed
- The saved copy stays frozen, and commands act on the visible tab (#54).

## 0.3.0 — 2026-10-21

### Added
- The first native build: the Shelf, tabs and Brine, the Me card, ⌘K and ⌘D, and Seal with freeze, extract and index (#12–#19).
- The Pantry generated from MSON, with Swift token bridge (#5, #9, #10).
- CodeQL with a non-negotiable 5 query (#21, #22, #23).

### Removed
- Tauri (#7).

## 0.2.1 — 2026-09-06

### Fixed
- The version that carries the updater fix (#2).

## 0.2.0 — 2026-09-05

Early Tauri-era preview, since retired.

## 0.1.0 — 2026-08-16

Initial Tauri-era preview, since retired.
