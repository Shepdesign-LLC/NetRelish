#!/bin/sh
# Regenerates NetRelish.xcodeproj from project.yml with the XcodeGen named in
# scripts/xcodegen-version.txt, and refuses any other version — two XcodeGens do not write the
# same project, and the committed one has to match what CI regenerates. See scripts/xcodegen.sh.
# Commit the result: CI regenerates and fails if the committed project differs.
set -eu
cd "$(dirname "$0")/.."
scripts/xcodegen.sh
xcodegen generate --quiet
echo "regenerated NetRelish.xcodeproj"
