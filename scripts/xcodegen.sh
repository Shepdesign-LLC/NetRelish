#!/bin/sh
# Puts the pinned XcodeGen on the PATH, and refuses to carry on with any other version.
#
# Why this exists. `brew install xcodegen` is not deterministic on a GitHub runner: if an
# older XcodeGen is already in the image's Homebrew cache, `install` says "already installed"
# and does nothing, so two runners can hold two versions. The versions do not agree about
# what a project looks like — 2.48.0 writes `buildArchitectures = "Automatic"` into every
# .xcscheme and earlier ones do not — and "Generated files match their sources" compares the
# committed project against whatever the runner generates.
#
# On 2026-11-26 that check passed on PR #115 and failed on PR #118 three minutes apart with a
# byte-identical project.yml and NetRelish.xcodeproj. Nothing was stale; the two runners were
# holding different tools.
#
# So: upgrade to whatever Homebrew serves, then assert it is the version this repository's
# committed project was generated with. A mismatch is loud and says what to do, instead of
# surfacing later as a confusing "NetRelish.xcodeproj is stale" on a PR that changed nothing.
#
# To move to a new XcodeGen: edit scripts/xcodegen-version.txt, run scripts/gen-project.sh,
# and commit the project it writes in the same commit. The two must always travel together.
set -eu
cd "$(dirname "$0")/.."
WANT=$(tr -d '[:space:]' < scripts/xcodegen-version.txt)

if ! command -v xcodegen >/dev/null 2>&1; then
    brew install xcodegen >/dev/null
else
    # `install` is a no-op when any version is present, so ask for the upgrade explicitly.
    brew upgrade xcodegen >/dev/null 2>&1 || brew install xcodegen >/dev/null 2>&1 || true
fi

HAVE=$(xcodegen --version 2>/dev/null | tr -d '\r' | awk '{print $NF}')
if [ "$HAVE" != "$WANT" ]; then
    echo "::error file=scripts/xcodegen-version.txt::XcodeGen $HAVE is installed, but NetRelish.xcodeproj was generated with $WANT. Either pin Homebrew to $WANT, or edit scripts/xcodegen-version.txt to $HAVE, run scripts/gen-project.sh and commit the project with it."
    exit 1
fi
echo "XcodeGen $HAVE (pinned)"
