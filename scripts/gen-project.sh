#!/bin/sh
# Regenerates NetRelish.xcodeproj from project.yml. Requires XcodeGen (brew install xcodegen).
# Commit the result: CI regenerates and fails if the committed project differs.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
echo "regenerated NetRelish.xcodeproj"
