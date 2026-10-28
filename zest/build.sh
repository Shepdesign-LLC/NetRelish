#!/usr/bin/env bash
# Assemble the one-origin deploy (ZEST-SPEC §8 / §11.5): the studio is the home
# page; the tools live beside it under their paths; the store pages sit at
# /pricing. Vercel runs this as the buildCommand and serves ./dist.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf dist
mkdir -p dist

# / — the studio IS the home page
cp -R apps/zest/. dist/
rm -f dist/vercel.json dist/README.md

# /mail /md /image — the tools, exactly as they ship standalone
for app in mail md image; do
  mkdir -p "dist/$app"
  cp -R "apps/$app/." "dist/$app/"
  rm -rf "dist/$app/vercel.json" "dist/$app/README.md" "dist/$app/package.json" "dist/$app/api"
done

# /pricing — the store page beside the studio (§8: pricing, account, changelog live here as they're built)
mkdir -p dist/pricing
cp apps/store/index.html dist/pricing/index.html

echo "dist/ assembled: / (studio) · /mail · /md · /image · /pricing"
