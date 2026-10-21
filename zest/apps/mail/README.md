# ZestMail

ZestMail (formerly Mail Press) is an HTML email generator. Static page + one serverless function that proxies Claude so the API key stays on the server.

## Run locally

```bash
npx vercel dev        # serves index.html and /api/claude on http://localhost:3000
```

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
