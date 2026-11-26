#!/bin/sh
# Prints the absolute path of the pinned XcodeGen on stdout, fetching it first if it is not
# already here. Diagnostics go to stderr, so callers can do:
#
#     XCODEGEN=$(scripts/xcodegen.sh)
#     "$XCODEGEN" generate --quiet
#
# Why this does not use Homebrew. Two XcodeGens do not write the same project: 2.48.0 writes
# `buildArchitectures = "Automatic"` into every .xcscheme and 2.46.0 does not. CI's "Generated
# files match their sources" job compares the committed project against a fresh generation, so
# the version that generates it decides whether a pull request is green.
#
# `brew install xcodegen` cannot hold a version still. It is a no-op when ANY version is
# already in the runner image's cache, so two runners can hold two tools. On 2026-11-26 that
# check passed on PR #115 and failed on PR #118 three minutes apart, with a byte-identical
# project.yml and NetRelish.xcodeproj: nothing was stale, the two runners were holding
# different XcodeGens. `brew upgrade` is no better — it pins to Homebrew's formula HEAD, which
# moves on its own schedule, so the next upstream bump turns a green pull request red for a
# change it never made.
#
# So the version comes from upstream's own release archive, checked against a recorded hash.
# That is reproducible on any runner, on any image generation, in any month.
set -eu
cd "$(dirname "$0")/.."

LOCK=scripts/xcodegen-version.txt
WANT=$(awk '$1 == "version" { print $2; exit }' "$LOCK")
SHA=$(awk '$1 == "sha256" { print $2; exit }' "$LOCK")
if [ -z "$WANT" ] || [ -z "$SHA" ]; then
    echo "::error file=$LOCK::$LOCK must carry a 'version' line and a 'sha256' line" >&2
    exit 1
fi

# One directory per version, so a changed pin fetches afresh instead of reusing the old tool.
DEST="${XCODEGEN_HOME:-${TMPDIR:-/tmp}}/netrelish-xcodegen/$WANT"
BIN="$DEST/xcodegen/bin/xcodegen"

if [ ! -x "$BIN" ]; then
    URL="https://github.com/yonaskolb/XcodeGen/releases/download/$WANT/xcodegen.zip"
    ZIP="$DEST/xcodegen.zip"
    rm -rf "$DEST"
    mkdir -p "$DEST"
    echo "fetching XcodeGen $WANT" >&2
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$ZIP" "$URL"; then
        echo "::error file=$LOCK::could not download XcodeGen $WANT from $URL" >&2
        exit 1
    fi
    if command -v shasum >/dev/null 2>&1; then
        GOT=$(shasum -a 256 "$ZIP" | awk '{print $1}')
    else
        GOT=$(sha256sum "$ZIP" | awk '{print $1}')
    fi
    if [ "$GOT" != "$SHA" ]; then
        rm -rf "$DEST"
        echo "::error file=$LOCK::XcodeGen $WANT downloaded as $GOT, but $LOCK records $SHA. The release was re-tagged or the download was altered; nothing was installed." >&2
        exit 1
    fi
    # The archive holds xcodegen/bin/xcodegen and the xcodegen/share/xcodegen/SettingPresets it
    # resolves beside itself, so the whole tree is kept, not just the binary.
    ( cd "$DEST" && unzip -oq xcodegen.zip )
    rm -f "$ZIP"
fi

# The archive is what the hash covers, but ask the tool itself too: a re-tagged release with a
# matching hash is impossible, and this costs nothing.
HAVE=$("$BIN" --version 2>/dev/null | tr -d '\r' | awk '{print $NF}')
if [ "$HAVE" != "$WANT" ]; then
    echo "::error file=$LOCK::the archive pinned as XcodeGen $WANT reports itself as $HAVE" >&2
    exit 1
fi

echo "XcodeGen $HAVE (pinned)" >&2
echo "$BIN"
