#!/usr/bin/env bash
# Assemble the one-origin deploy (ZEST-SPEC §8 / §11.5): the studio is the home
# page; the tools live beside it under their paths; the store pages sit at
# /pricing. Vercel runs this as the buildCommand and serves ./dist.
#
# bash build.sh --app assembles the copy NetRelish.app bundles instead (ADR 0015):
# ../Resources/Zest, generated and committed, never edited by hand.
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "--app" ]; then
  # The free tools, offline: the studio at the root, the three tools beside it, the
  # vendored libraries and fonts, and the third-party notices. No store, no pricing,
  # no API, and none of the files only the web uses: the install manifest, the
  # service worker, the registry manifest (zest.json), Vercel config, READMEs, and
  # the icon sizes only the install manifest names. Same input, same bytes out.
  OUT=../Resources/Zest
  [ -f vendor/VENDOR.lock.json ] || { echo "build.sh --app: vendor/ is missing; run node scripts/vendor.mjs" >&2; exit 1; }
  [ -f ../NOTICE ] || { echo "build.sh --app: the root NOTICE is missing" >&2; exit 1; }
  WEB_ONLY=(manifest.webmanifest sw.js zest.json vercel.json README.md package.json api
            icons/icon-192.png icons/icon-512.png icons/icon-512-maskable.png)
  copy_tool() {
    mkdir -p "$2"
    cp -R "$1/." "$2/"
    for f in "${WEB_ONLY[@]}"; do rm -rf "${2:?}/$f"; done
  }
  rm -rf "$OUT"
  copy_tool apps/zest "$OUT"
  for app in mail md image; do copy_tool "apps/$app" "$OUT/$app"; done
  mkdir -p "$OUT/vendor"
  cp -R vendor/. "$OUT/vendor/"
  rm -f "$OUT/vendor/VENDOR.lock.json"      # build metadata; the licenses travel as NOTICE and the LICENSE files
  cp ../NOTICE "$OUT/NOTICE"
  find "$OUT" -type d -exec chmod 755 {} +
  find "$OUT" -type f -exec chmod 644 {} +

  bytes() { find "$1" -type f -print0 | xargs -0 cat | wc -c | tr -d ' '; }
  mb() { awk -v b="$1" 'BEGIN {printf "%.2f MB", b/1048576}'; }
  total=$(bytes "$OUT")
  echo "Resources/Zest assembled: / (studio) · /mail · /md · /image · /vendor — $(find "$OUT" -type f | wc -l | tr -d ' ') files, $(mb "$total")"
  for part in mail md image vendor/fonts vendor/katex vendor/mermaid vendor/dompurify; do
    printf '  %-16s %s\n' "$part" "$(mb "$(bytes "$OUT/$part")")"
  done
  exit 0
fi

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
cp -r apps/store/icons dist/pricing/icons

echo "dist/ assembled: / (studio) · /mail · /md · /image · /pricing"
