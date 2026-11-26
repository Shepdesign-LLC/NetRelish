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

sha256_of() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

LOCK=scripts/xcodegen-version.txt
WANT=$(awk '$1 == "version" { print $2; exit }' "$LOCK")
SHA=$(awk '$1 == "sha256" { print $2; exit }' "$LOCK")
if [ -z "$WANT" ] || [ -z "$SHA" ]; then
    echo "::error file=$LOCK::$LOCK must carry a 'version' line and a 'sha256' line" >&2
    exit 1
fi

# Both fields are about to become path components and one of them a URL, so neither may be a
# path or anything but what it claims to be.
case $WANT in ''|*[!0-9.]*|*..*) echo "::error file=$LOCK::version '$WANT' is not a version" >&2; exit 1 ;; esac
case $SHA in ''|*[!0-9a-f]*) echo "::error file=$LOCK::sha256 '$SHA' is not a lowercase hex digest" >&2; exit 1 ;; esac

# One directory per pinned ARCHIVE — the version AND the hash — so that changing either field
# fetches afresh. Keying on the version alone was a bug: the download and the hash comparison
# both sit inside the cache-miss branch below, so a hash-only change (upstream re-tags a
# release, which is the very case the mismatch error is written for) would miss nothing, reuse
# the old binary, and still print "(pinned)". With the hash in the path, anything already here
# was put here by a verified extraction of exactly these bytes.
#
# The root is per-user, never a world-writable /tmp: a predictable path under a shared root can
# be pre-created by another local user, and `mkdir -p` succeeds on an existing directory
# whatever its owner, so a mode set afterwards would never apply.
: "${HOME:?HOME must be set}"
DEST="${XCODEGEN_HOME:-$HOME/.cache}/netrelish-xcodegen/$WANT-$SHA"
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
    GOT=$(sha256_of "$ZIP")
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

# A sanity check, not the integrity gate: the hash in $DEST is what establishes the bytes. This
# only confirms the archive holds the tool it says it does, and costs nothing.
HAVE=$("$BIN" --version 2>/dev/null | tr -d '\r' | awk '{print $NF}')
if [ "$HAVE" != "$WANT" ]; then
    echo "::error file=$LOCK::the archive pinned as XcodeGen $WANT reports itself as $HAVE" >&2
    exit 1
fi

echo "XcodeGen $HAVE (pinned)" >&2
echo "$BIN"
