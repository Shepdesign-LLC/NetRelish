# ZestMail

ZestMail (formerly Mail Press) is an HTML email generator. Static page + one serverless function that proxies Claude so the API key stays on the server.

## Brand import

A `zest-brand.json` exported from the Zest studio creates or updates a brand
here (ZEST-SPEC §7.3): its light palette, body font (as an email-safe stack)
and corner radius land in the brand's token fields; identity fields (company,
links, ESP tags) stay yours. Import it from the Brand tab's button, the
Export → Import design menu, or by dropping the file anywhere on the page.

## The canvas

On a desktop the email draws at a readable size: **Fit · 100% · 125% · 150%**
in the canvas pane head (Fit fills the pane, up to 125%, or 150% on a pane
wider than 1500px). The choice is
remembered, the previews use the same zoom, and the exported HTML never
changes with it. On a phone the canvas is the email at phone width, 1:1, with
columns stacked; tap text to type, tap a block's edge or **Properties** for
its settings. Merge tags show as chips on the canvas and export as the exact
tag. `docs/MAIL-PRESS.md` §2.1 has the details.

## Run locally

```bash
npx vercel dev        # serves index.html and /api/claude on http://localhost:3000
```

or run the whole Zest topology from `zest/`: `bash build.sh`, then
`npx vercel dev` there serves this app at `/mail` with the shared
`/api/claude` — the production shape (`vercel dev` does not run the
build itself).

or, without the proxy (use your key in the app's Direct route):

```bash
npx serve .           # any http server works; file:// does not
```

## Deploy

```bash
npx vercel --prod
```

Then in Vercel → Project → Settings → Environment Variables:

- `ANTHROPIC_API_KEY` — your key
- `MAILPRESS_TOKEN` — any long random string (**required** — the proxy fails closed without it, so an unset token can't become an open proxy on your API key); enter the same value in the app under Claude → Proxy token. `MAILPRESS_TOKEN` and the `x-mailpress-token` request header are internal names kept verbatim per ZEST-SPEC §2 — the ZestMail rename does not touch them.

In the app, leave the API key field empty and Route on Auto: hosted pages use the proxy automatically.

## Why the CORS error happens

Browsers only allow cross-origin API calls from an `http(s)` origin. `file://` pages have origin `null` and get blocked before the request is sent. Serve the page over http and it works; or use the proxy and never put a key in the browser at all.
