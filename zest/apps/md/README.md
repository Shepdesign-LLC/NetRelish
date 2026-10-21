# Zest MD

A local-first Markdown reader and HTML exporter. Nothing is uploaded. Installable, works offline.

## Deploy

```bash
npx vercel --prod
```

Static site — no build step. `index.html` is the whole app; `sw.js` handles offline; `manifest.webmanifest` handles install and file handling.

## Bump the cache

Change `VERSION` in `sw.js` on every release. Users get a "Zest MD updated — Reload" toast on next visit.
