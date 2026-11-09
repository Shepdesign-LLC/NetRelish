# ADR 0024 — What the release workflow trusts, and when it can write

**Status:** accepted (a security fix) · **Date:** 2026-11-09 · **PR:** fix(release): notes from git objects; write access only in publish

**The problem.** The release workflow published `docs/releases/<tag>.md` by reading it through the checkout. A committed symlink would have published whatever it pointed at on the runner, and `docs/` or `docs/releases/` committed as a link would have done the same. One target was checkout's saved credential file, which held the job's write token, because checkout keeps it in `.git/config` by default. That token could write for the whole job, while the job ran Xcode, SwiftPM, a PyPI package and the repository's scripts.

**What changed:**

- **Notes are read as git objects of the released commit, never as files.** `scripts/release_notes.py` walks the path through the commit's trees. Every directory on the way must be a real tree, and the notes a regular-file blob. A symlink or submodule anywhere on the path is refused. Its tests run on every PR, in CI's "CodeQL gate self-test" job.
- **The build job is read-only.** It has `contents: read`, and checkout doesn't keep its token (`persist-credentials: false`). Everything that runs outside code (Xcode, SwiftPM, PyPI's `dmgbuild`, our scripts) runs here. It passes on only the disk image and its checksum.
- **Only the publish job can write** (`contents: write`). It runs on Ubuntu with no checkout and nothing from the repository or PyPI. It verifies the disk image's checksum, then reads the notes again through GitHub's git API, by exact path and file mode, so nothing the build ran can change what's published. Then it tags and publishes.
- **No other workflow keeps checkout's token.** `regen-project` still has to push its commit, so it hands its token to that one `git push`, through the environment.

**What it doesn't change.** The build job still holds the Apple signing secrets while it runs third-party build code, as any signing build does. A compromised build dependency could still sign something bad. What it can no longer do is write to the repository, move a tag, or publish runner files as release notes.
