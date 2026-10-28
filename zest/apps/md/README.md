# Zest MD

A local-first Markdown reader and HTML exporter. Nothing is uploaded. Installable, works offline.

## Brand import

A `zest-brand.json` exported from the Zest studio becomes the custom skin
(ZEST-SPEC §7.3): both palettes land explicitly (light and dark), the fonts
map to the nearest families in the typeface picker, and the radius carries
over. Import it from Settings → Custom skin → "Import zest-brand.json", or
drop the file anywhere on the page. Hand-editing one of the four custom
colours releases the explicit palettes back to derivation.

## Deploy

```bash
npx vercel --prod
```

Static site — no build step. `index.html` is the whole app; `sw.js` handles offline; `manifest.webmanifest` handles install and file handling.

## Bump the cache

Change `VERSION` in `sw.js` on every release. Users get a "Zest MD updated — Reload" toast on next visit.
