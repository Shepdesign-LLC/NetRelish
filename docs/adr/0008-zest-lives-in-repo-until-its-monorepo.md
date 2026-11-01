# ADR 0008 — Zest lives in this repo until its monorepo exists

**Status:** superseded in part by ADR 0015 (Zest's free tools move into the app in 1.1) · **Date:** 2026-10-21 · **PR:** docs: Zest lineup index

The Zest ecosystem — a web product line on the Vercel / Supabase / Stripe stack
per `zest/docs/ZEST-SPEC.md` §8 — is staged in this repo under `/zest` until
its own monorepo exists. It is not part of the macOS app target; no Xcode
target references anything under `/zest`; and the browser's non-negotiables are
unaffected — §5 included, because Zest's endpoints belong to Zest's web apps,
not to NetRelish.app. The eventual home is the `zest/` monorepo layout in spec
§8 (apps, api, packages, presskit, infra); when it exists, this directory moves
out wholesale and this ADR is superseded.
