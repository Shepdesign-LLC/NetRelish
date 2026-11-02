#!/bin/bash
# make-dmg.sh — builds the NetRelish disk image: the app, a link to Applications, and a
# Finder window laid out to the brand (gen-dmg-background.swift, layout.json). Unsigned;
# the release job signs, notarizes and staples it after.
#
#   scripts/dmg/make-dmg.sh <NetRelish.app> <out.dmg> [--preview <dir>]
#
# --preview also writes preview.png and preview@2x.png to <dir>: the window as it will look.
set -euo pipefail

APP="$1"
OUT="$2"
PREVIEW_DIR=""
if [ "${3:-}" = "--preview" ]; then PREVIEW_DIR="$4"; fi

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -d "$APP" ] || { echo "make-dmg: no app at $APP" >&2; exit 1; }
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || { echo "make-dmg: $APP has no AppIcon.icns" >&2; exit 1; }

if [ -n "$PREVIEW_DIR" ]; then
  swift "$HERE/gen-dmg-background.swift" "$HERE/layout.json" "$WORK/art" --preview "$APP"
  mkdir -p "$PREVIEW_DIR"
  cp "$WORK/art/preview.png" "$WORK/art/preview@2x.png" "$PREVIEW_DIR/"
else
  swift "$HERE/gen-dmg-background.swift" "$HERE/layout.json" "$WORK/art"
fi

# dmgbuild needs Python 3.10 or later; the one Xcode ships is older, so take the newest found.
PYTHON=""
for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$candidate" > /dev/null && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
    PYTHON="$candidate"; break
  fi
done
[ -n "$PYTHON" ] || { echo "make-dmg: needs Python 3.10 or later (brew install python)" >&2; exit 1; }
"$PYTHON" -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet --disable-pip-version-check --no-deps --require-hashes -r "$HERE/requirements.txt"

rm -f "$OUT"
"$WORK/venv/bin/dmgbuild" -s "$HERE/settings.py" \
  -D app="$APP" -D layout="$HERE/layout.json" -D background="$WORK/art/background.png" \
  "NetRelish" "$OUT"

# What a person sees when they open it: the app, Applications, the window art, the disk icon.
MOUNT="$WORK/mnt"
mkdir -p "$MOUNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$OUT" > /dev/null
check() { [ -e "$MOUNT/$1" ] || { hdiutil detach "$MOUNT" -quiet; echo "make-dmg: the image has no $1" >&2; exit 1; }; }
check "NetRelish.app"
check "Applications"
check ".background.tiff"
check ".DS_Store"
check ".VolumeIcon.icns"
if [ "${MAKE_DMG_UNSIGNED:-}" != 1 ] && ! codesign --verify --deep --strict --verbose=2 "$MOUNT/NetRelish.app"; then
  xattr -l "$MOUNT/NetRelish.app" >&2 || true
  hdiutil detach "$MOUNT" -quiet
  echo "make-dmg: the app's signature didn't survive the copy (codesign says why, above)" >&2
  exit 1
fi
hdiutil detach "$MOUNT" -quiet
echo "wrote $OUT"
