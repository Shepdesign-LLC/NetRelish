# ADR 0027 — The Direct build's license key: Creem, through a relay on netrelish.com

**Status:** accepted (Ryan, 2026-11-12) · **Date:** 2026-11-12 · **PR:** feat(pro): the Direct build's license key

**The store.** The Direct build is sold through Creem, a merchant of record (Ryan, Nov 12). This settles ADR 0016's open question 1, Freemius or Paddle or Lemon Squeezy. CLAUDE.md's billing row now names Creem. The App Store build keeps StoreKit 2 (ADR 0023).

**Why a relay.** Creem's license API needs the store's secret API key on every call, including activation. A key inside the app can be pulled out of it, and it opens the whole store's API, customers included. So the app never calls Creem. It calls `POST https://netrelish.com/api/license`, a small endpoint in the `netrelish-site` repo that holds the key as a Vercel environment variable and forwards the call. It takes an action (activate, validate, deactivate), the license key, and a random name for this Mac or the id Creem gave it. It answers with the status, the activation id and when the license runs out, nothing else.

**What leaves the Mac, and when (non-negotiable 5).** This is the one license call rule 5 allows. It sends the license key and a random name like `NetRelish-3f9a01c2`, never the Mac's own name and never anything about browsing. It goes out only when the person presses Activate, Check Again or Deactivate This Mac. Never at launch, never on a timer. The relay sees the Mac's address and the time, as any web server does.

**On the Mac.**

- The answer is kept in the login Keychain, never synchronized, as the Me card is (ADR 0006).
- Pro is unlocked while the license is active and, for a yearly one, until the day it runs out. A year that runs out locks Pro without asking anyone. Check Again is how a renewal is found.
- Deactivate This Mac gives the activation back so the key works on another Mac. Offline, nothing changes, so going offline never costs anyone an activation.
- The call is https only, follows no redirect, reads at most 8 KB and gives up after 30 seconds. It carries `NETRELISH-ALLOW-ENDPOINT: adr-0027` and is listed in `.github/codeql/approved-endpoints.txt`.
- A Direct build with no relay address set (`NR_LICENSE_ACTIVATION_URL` empty) stays unlocked, as previews were. The App Store build never reads that setting.

**What it costs.**

- A refund or cancellation reaches a Mac only when someone presses Check Again there. Checking at launch would catch it, and is exactly the polling rule 5 rules out.
- The license lives on a Mac its owner controls. This keeps honest people honest; it doesn't stop a determined one, and nothing in a Direct build can.
- The relay is a server to keep running. It is stateless, stores nothing and logs no keys, but if it goes down nobody can activate until it's back.
- **At the WordPress cutover (week of Jan 4, 2027, ADR 0016) the endpoint must move with the site, at the same address.** Shipped apps have it compiled in.

**Before the first Direct release that uses it (Ryan):** create the Pro products in Creem with license keys turned on, put the store's API key in Vercel as `CREEM_API_KEY`, and send me the checkout link for the Pro window's Buy button (today it goes to netrelish.com).
