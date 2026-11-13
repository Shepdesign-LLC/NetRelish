---
title: Releasing a preview — the Direct build as a disk image
type: operation
created: 2026-11-13
updated: 2026-11-13
sources:
  - code: .github/workflows/release.yml
  - code: scripts/release_notes.py
  - code: Config/Base.xcconfig
  - code: Sources/App/License.swift
  - code: Sources/App/NetRelishApp.swift
verified_at: 2c4c510
---

# Releasing a preview

A preview is the Direct build, signed with the Developer ID, notarized, packed into a disk
image and published as a GitHub pre-release. One workflow does all of it:
`.github/workflows/release.yml`. Previews 0.4.0, 0.4.1 and 0.4.2 were all cut by starting
it by hand on `main`. How the session compiles anything at all is [[building-without-a-mac]].

## The order

1. **Notes first.** `docs/releases/<tag>.md` must be on `main` before the run starts. It
   becomes the public body of the release, word for word, so it follows `docs/voice/`.
2. **Start the workflow on `main`** with the version (`v0.5.0`). It builds, signs,
   notarizes, makes the disk image, notarizes that, and checks both with Gatekeeper.
3. **Only then** does a second job tag `main` and publish. A run that fails leaves no tag
   and no release behind, so the same version can be tried again from a fixed `main`.

The build job can read the repository and nothing else. The publish job holds the only
write token, checks nothing out and runs nothing from the repository
(`.github/workflows/release.yml:23`).

## Pro in a preview

Whether a Direct build locks Pro is decided by one build setting,
`NR_LICENSE_ACTIVATION_URL` (`Config/Base.xcconfig`), read from the app's Info.plist at
launch (`Sources/App/License.swift:153`, `Sources/App/NetRelishApp.swift:34`):

| The address in the built app | Pro |
|---|---|
| empty | unlocked for everyone, as previews before license keys |
| an https address | locked until a license key is activated (ADR 0027) |
| anything else | locked, with no way to unlock |

The workflow's **Leave Pro unlocked** switch builds that one release with an empty address
(ADR 0031). It then reads the built app and fails the run if the app does not match the
switch.

> ⚠️ **`main` has the license address set.** A release started without the switch locks
> Pro for everyone who installs it. Until the Creem store issues keys (ADR 0027's last
> paragraph), nobody could unlock it, the owner included. Ask before releasing which one
> is wanted.

> ⚠️ **An address that is set but wrong locks Pro; it does not unlock it.** That includes
> the unexpanded text `$(NR_LICENSE_ACTIVATION_URL)`. To unlock a build, the setting has to
> reach the app as an empty string, which is what the switch does. Deleting the line from
> the xcconfig without checking the built Info.plist is how a preview ships locked.

> ⚠️ **The notes are read from the commit, twice, never from the checkout**
> (`scripts/release_notes.py`). A notes file that exists only on a branch, or is a symlink,
> stops the run before anything is signed. Changing the notes after the run has started
> changes nothing: the run publishes the commit it was started on.

> ⚠️ **A green run is not a shippable release.** `docs/RELEASING.md` records two green runs
> that produced something wrong. Open the published release and check its name, its notes
> and that the disk image and its checksum are both attached.

## What this page does not cover

The Apple account, the certificate and the notarization secrets are in `docs/RELEASING.md`
and `docs/notarization.md`. Those two describe the account, not this workflow, and
`docs/RELEASING.md` still says the release process is unwritten; the workflow file is the
record of what runs.
