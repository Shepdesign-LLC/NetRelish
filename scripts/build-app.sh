#!/bin/sh
# Builds the app for local use and prints the .app path.
#
#   scripts/build-app.sh            → Debug-AppStore (default; the Design Kit is in)
#   scripts/build-app.sh direct     → Debug-Direct
#   scripts/build-app.sh release    → Release-AppStore
#
# Then: open "$(scripts/build-app.sh)"
set -eu
cd "$(dirname "$0")/.."
case "${1:-appstore}" in
  appstore) CONFIG=Debug-AppStore;   SCHEME="NetRelish (App Store)" ;;
  direct)   CONFIG=Debug-Direct;     SCHEME="NetRelish (Direct)" ;;
  release)  CONFIG=Release-AppStore; SCHEME="NetRelish (App Store)" ;;
  *) echo "usage: $0 [appstore|direct|release]" >&2; exit 2 ;;
esac
DERIVED=".build/DerivedData"
xcodebuild -project NetRelish.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS' build -quiet
echo "$PWD/$DERIVED/Build/Products/$CONFIG/NetRelish.app"
