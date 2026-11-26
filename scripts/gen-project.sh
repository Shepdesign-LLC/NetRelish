#!/bin/sh
# Regenerates NetRelish.xcodeproj from project.yml with the XcodeGen pinned in
# scripts/xcodegen-version.txt — by version and by hash, because two XcodeGens do not write the
# same project and the committed one has to match what CI regenerates. See scripts/xcodegen.sh.
# Commit the result: CI regenerates and fails if the committed project differs.
set -eu
cd "$(dirname "$0")/.."
XCODEGEN=$(scripts/xcodegen.sh)
"$XCODEGEN" generate --quiet
echo "regenerated NetRelish.xcodeproj"
