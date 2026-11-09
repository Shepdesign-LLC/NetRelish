# ADR 0024 — What the release workflow trusts, and when it can write

**Status:** accepted (a security fix) · **Date:** 2026-11-09 · **PR:** fix(release): notes from git objects; write access only in publish

**The problem.** The release workflow published `docs/releases/<tag>.md` by reading it through the checkout. A committed symlink would have published whatever it pointed at on the runner, and `docs/` or `docs/releases/` committed as a link would have done the same. One target was checkout's saved credential file, which held the job's write token, because checkout keeps it in `.git/config` by default. That token could write for the whole job, while the job ran Xcode, SwiftPM, a PyPI package and the repository's scripts.

**What changed:**

- **Notes are read as git objects of the released commit, never as files.** `scripts/release_notes.py` walks the path through the commit's trees. Every directory on the way must be a real tree, and the notes a regular-file blob. A symlink or submodule anywhere on the path is refused. Its tests run on every PR, in CI's "CodeQL gate self-test" job.
- **The build job is read-only.** It has `contents: read`, and checkout doesn't keep its token (`persist-credentials: false`). Everything that runs outside code (Xcode, SwiftPM, PyPI's `dmgbuild`, our scripts) runs here. It passes on only the disk image and its checksum.
- **Only the publish job can write** (`contents: write`). It runs on Ubuntu with no checkout and nothing from the repository or PyPI. It verifies the disk image's checksum, then reads the notes again through GitHub's git API, by exact path and file mode, so nothing the build ran can change what's published. Then it tags and publishes.
- **The release checks itself once more before publishing.** The commit must be on main, both before signing and again before tagging. The tag must still point at the commit that was built. Re-running a failed publish keeps a tag it already made.
- **`regen-project` is split the same way.** A read-only job runs Homebrew's XcodeGen and outputs a patch. The push job runs nothing from the branch or Homebrew. It applies the patch only if it touches the project, plist and entitlements files and adds no symlinks or submodules, then commits and pushes. The token reaches only that `git push`.
- **No workflow keeps checkout's token, and test-only workflows can only read.**

**Still to set in GitHub (Ryan).** A workflow can't protect itself from someone who can push a `v*` tag: the tag runs whatever `release.yml` that commit holds. Three settings close that:
1. A tag ruleset on `refs/tags/v*` that lets only release maintainers create, move or delete them.
2. An environment called `release`, with required reviewers and a deployment rule that allows only `main` and `v*` tags.
3. The Apple secrets moved from repository secrets into that environment, with `environment: release` added to both release jobs.

**What it doesn't change.** The build job still holds the Apple signing secrets while it runs third-party build code, as any signing build does. A compromised build dependency could still sign something bad. What it can no longer do is write to the repository, move a tag, or publish runner files as release notes.
