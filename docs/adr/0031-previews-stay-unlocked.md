# ADR 0031 — Previews leave Pro unlocked until license keys are on sale

**Status:** accepted (Ryan, Nov 13) · **Date:** 2026-11-13 · **PR:** release: 0.5.0 notes and a preview that leaves Pro unlocked

Ryan, Nov 13, asked whether 0.5.0 should ship with license keys or keep Pro unlocked like 0.4.x: "Keep Pro unlocked."

**Decision:** a preview released before the Creem store issues keys is built with no license address, so Pro is unlocked in it, as ADR 0027 already says a build without one is. `main` keeps the address in `Config/Base.xcconfig`; nothing about the license code changes.

**How.** The Release workflow, started by hand, has a switch: **Leave Pro unlocked**. With it on, that one build gets an empty `NR_LICENSE_ACTIVATION_URL`. The workflow then reads the built app and fails the release if the app does not match the switch: unlocked only when asked for, and otherwise a real https address to activate against. A release from a pushed tag can't turn it on.

**When it stops.** The first release after ADR 0027's list is done (Pro products in Creem with license keys on, `CREEM_API_KEY` in Vercel, the checkout link for the Buy button) is started with the switch off. Its notes say Pro now needs a key, as the 0.5.0 notes promise.

**Rule check.** NN5: an unlocked build has no license address, so it never makes the license call at all.
