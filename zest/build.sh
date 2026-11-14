#!/usr/bin/env bash
# Assemble the one-origin deploy (ZEST-SPEC §8 / §11.5): the studio is the home
# page; the tools live beside it under their paths; the store pages sit at
# /pricing. Vercel runs this as the buildCommand and serves ./dist.
#
# bash build.sh --app assembles the copy NetRelish.app bundles instead (ADR 0015):
# ../Resources/Zest, generated and committed, never edited by hand. ZEST_APP_OUT=<dir>
# builds it somewhere else (CI builds into a temp folder and diffs it against the
# committed copy, so the gates test the bytes that ship).
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "--app" ]; then
  # The free tools, offline: the studio at the root, the three tools beside it, the
  # vendored libraries and fonts, and the third-party notices. No store, no pricing,
  # no API, and none of the files only the web uses: the install manifest, the
  # service worker, the registry manifest (zest.json), Vercel config, READMEs, and
  # the icon sizes only the install manifest names. Only files git tracks are copied
  # (a .DS_Store or a scratch file in apps/ never reaches the app). Same input, same
  # bytes out.
  OUT=${ZEST_APP_OUT:-../Resources/Zest}
  case "$OUT" in ''|/|.|..|../|./) echo "build.sh --app: refusing to build into '$OUT'" >&2; exit 1;; esac
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "build.sh --app: run it inside the git checkout (it copies the files git tracks)" >&2; exit 1; }
  [ -f vendor/VENDOR.lock.json ] || { echo "build.sh --app: vendor/ is missing; run node scripts/vendor.mjs" >&2; exit 1; }
  [ -f ../NOTICE ] || { echo "build.sh --app: the root NOTICE is missing" >&2; exit 1; }
  WEB_ONLY=(manifest.webmanifest sw.js zest.json vercel.json README.md package.json api
            icons/icon-192.png icons/icon-512.png icons/icon-512-maskable.png)
  copy_tracked() {   # the files git tracks under $1 (as they are in the working tree), into $2
    local src=$1 dest=$2 f rel n=0
    mkdir -p "$dest"
    while IFS= read -r -d '' f; do
      [ -f "$f" ] || continue          # tracked but deleted in the working tree
      rel=${f#"$src"/}
      mkdir -p "$dest/$(dirname "$rel")"
      cp "$f" "$dest/$rel"
      n=$((n + 1))
    done < <(git ls-files -z --cached -- "$src")
    [ "$n" -gt 0 ] || { echo "build.sh --app: git tracks no files under zest/$src" >&2; exit 1; }
  }
  copy_tool() {
    copy_tracked "$1" "$2"
    for f in "${WEB_ONLY[@]}"; do rm -rf "${2:?}/$f"; done
  }
  rm -rf "$OUT"
  copy_tool apps/zest "$OUT"
  for app in mail md image; do copy_tool "apps/$app" "$OUT/$app"; done
  copy_tracked vendor "$OUT/vendor"
  rm -f "$OUT/vendor/VENDOR.lock.json"      # build metadata; the licenses travel as NOTICE and the LICENSE files
  cp ../NOTICE "$OUT/NOTICE"
  # Parts only the web has (pricing, Pro prompts, drafting with a model, the service worker, the install
  # manifest) sit between web:start and web:end marks in the tools: <!-- web:start --> … <!-- web:end --> in
  # HTML, /* web:start */ … /* web:end */ in script and style. They leave the app's copy here, so the bytes
  # that ship never hold them; the IN_APP switch in each tool covers the same parts at run time.
  for f in "$OUT/index.html" "$OUT/mail/index.html" "$OUT/md/index.html" "$OUT/image/index.html"; do
    perl -0pi -e 's{<!-- web:start -->.*?<!-- web:end -->}{}gs; s{/\* web:start \*/.*?/\* web:end \*/}{}gs' "$f"
    if grep -n 'web:start\|web:end' "$f" >&2; then echo "build.sh --app: an unmatched web:start or web:end mark in ${f#"$OUT"/}" >&2; exit 1; fi
  done
  cat > "$OUT/README.md" <<'README'
# Resources/Zest — generated, never hand-edited

The four free Zest tools as NetRelish.app ships them: Studio at the root (`index.html`), then
`mail/`, `md/` and `image/`, each with its own `index.html`, the fonts and libraries they use
in `vendor/`, and the third-party notices in `NOTICE`, which Help › Acknowledgments shows. The
Zest window (Window › Zest) serves this folder read-only on `zest://app/` (`Sources/Zest/`).

`bash zest/build.sh --app` writes it from the tools under `zest/apps/` and the pinned files
under `zest/vendor/`, leaving out everything only the web has (the store, pricing, Pro
prompts, drafting with a model, the service workers and install manifests). Change the tools
there and rebuild; don't edit these files by hand. CI rebuilds it and fails when the
committed copy differs, scans it for any network address in a load position and for pricing
or Upgrade text, and runs every tool with the network blocked.

`project.yml` adds this folder to the app as a folder reference, not a flat group, so the
four `index.html` files keep their folders in the bundle instead of colliding at the top of
`Contents/Resources`. This README ships in the bundle; it is plain text and nothing loads it.

Decisions: `docs/adr/0015-zest-inside-netrelish.md`, `docs/adr/0033-zest-ships-in-1-0.md`.
How the host works and where it bites: `docs/subsystems/zest-window.md`.
README
  find "$OUT" -type d -exec chmod 755 {} +
  find "$OUT" -type f -exec chmod 644 {} +

  bytes() { find "$1" -type f -print0 | xargs -0 cat | wc -c | tr -d ' '; }
  mb() { awk -v b="$1" 'BEGIN {printf "%.2f MB", b/1048576}'; }
  total=$(bytes "$OUT")
  echo "$([ "$OUT" = ../Resources/Zest ] && echo Resources/Zest || echo "$OUT") assembled: / (studio) · /mail · /md · /image · /vendor — $(find "$OUT" -type f | wc -l | tr -d ' ') files, $(mb "$total")"
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

# /vendor — the pinned fonts and libraries every page loads from this origin (ADR 0015: no font host or CDN on
# any surface). The lock is build metadata; the license texts travel beside each family and library.
mkdir -p dist/vendor
cp -R vendor/. dist/vendor/
rm -f dist/vendor/VENDOR.lock.json

# /pricing — the store page beside the studio (§8: pricing, account, changelog live here as they're built)
mkdir -p dist/pricing
cp apps/store/index.html dist/pricing/index.html
cp -r apps/store/icons dist/pricing/icons

echo "dist/ assembled: / (studio) · /mail · /md · /image · /vendor · /pricing"
