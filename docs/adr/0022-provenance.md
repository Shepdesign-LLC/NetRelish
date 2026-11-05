# ADR 0022 — How provenance works

**Status:** proposed · **Date:** 2026-11-05 · **PR:** feat(pro): provenance — fingerprint, timestamp, Export Proof

ADR 0003 and ADR 0012 put provenance in Pro for 1.0: "an RFC 3161 timestamp and fingerprint on every seal, exportable". The plan (§P4) says: SHA-256 of the `.webarchive`, an RFC 3161 timestamp, and a PDF export.

- **The fingerprint** is SHA-256 of the saved copy's bytes, worked out on this Mac for every sealed page. Pages sealed before this change get one too.
- **The timestamp** comes from DigiCert's public timestamp authority (Ryan, Nov 5). It needs no account, and DigiCert's stamps are widely trusted, including by Apple's code signing. The request carries the fingerprint and a random number (the nonce), and nothing else: not the page, its address or its title. Non-negotiable 5 already lists RFC 3161 timestamping as an allowed network call, and this is that call.
- **The address is committed** (Ryan, Nov 5). `NR_TIMESTAMP_URL` is set in `Config/Base.xcconfig`, so every build, the released one included, stamps without any setup. It's a public address, not a secret. A local `Config.xcconfig` can still override it. CLAUDE.md's line "endpoints come from `Config.xcconfig`, gitignored" now reads that the public endpoints are committed and secrets still never are.
- **Plain http, for that one host.** `timestamp.digicert.com` answers on http only (an https connection is reset). Info.plist makes an App Transport Security exception for that host alone. That's safe here: what's sent is a fingerprint, and what comes back is signed. Before the app keeps a reply, it checks that the reply answers this request (same fingerprint, same nonce), and that the CMS signature and its certificate chain check out against this Mac's trust settings (Security framework). A reply that was altered, replayed or forged is refused.
- **When:** after Seal, off the main thread, like summaries (ADR 0020). Seal never waits. What's waiting is a question the Pantry answers, so a page sealed while offline is stamped the next time the app seals a page or comes forward. Offline isn't counted against a page; three real failures mark it failed.
- **Where it's stored:** `Item.meta["provenance"]` (the fingerprint, a status, the token in base64, the authority, the attempts). No schema change, so no System Designer round trip for 1.0. The snapshot, `body` and `sealedAt` are never touched (non-negotiable 3).
- **Pro:** stamping and Export Proof sit behind `Pro.isUnlocked` (still true until StoreKit, ADR 0021). Fingerprints are local and cost nothing, so every page gets one.
- **Export Proof** (Ryan, Nov 5: a folder, not a PDF alone) saves one folder. It holds `Proof.pdf` (one page: the page, address, when it was sealed, the jar, the fingerprint, the timestamp and what they prove), `Saved copy.webarchive` (byte for byte), `Timestamp.tst` (the signed token, when there is one) and `How to check.txt` (the `shasum` and `openssl ts` commands). Anyone can check it without NetRelish.
- **The PDF** is drawn from a SwiftUI view in the Light appearance, because it's meant for paper. Neutral tokens only; no relish (manifest §4).
- **Proposed follow-ups:**
  - Add provenance to the System Designer components (the `provenance` meta key, or a real property if it ever needs to be searched or sorted).
  - The Direct build's license activation address goes in `Config/Base.xcconfig` the same way when it exists.
  - A Shortcuts action, "Export Proof", once Ryan wants it.
