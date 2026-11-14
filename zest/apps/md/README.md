# Zest MD

A local-first Markdown reader and HTML exporter. Nothing is uploaded. Installable, works offline.

## Brand import

A `zest-brand.json` exported from the Zest studio becomes the custom skin
(ZEST-SPEC §7.3): both palettes land explicitly (light and dark), the fonts
map to the nearest families in the typeface picker, and the radius carries
over. Import it from Settings → Custom skin → "Import zest-brand.json", or
drop the file anywhere on the page. Hand-editing one of the four custom
colors releases the explicit palettes back to derivation.

## Run and deploy

Zest MD loads its sanitizer (DOMPurify), math (KaTeX), diagrams (Mermaid) and
fonts from `../vendor/`, the folder `zest/build.sh` puts beside it. Served on
its own from this folder, none of those load. Run it the way it ships:
`cd zest && bash build.sh && npx serve dist`, then open `/md/`. It deploys as
part of the Zest project, from `zest/` (see `zest/README.md`), not from here.
`index.html` is the whole app; `sw.js` handles offline; `manifest.webmanifest`
handles install and file handling.

## Bump the cache

Change `VERSION` in `sw.js` on every release. Users get a "Zest MD updated — Reload" toast on next visit.
