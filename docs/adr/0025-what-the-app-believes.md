# ADR 0025 — What the app believes, and from whom

**Status:** proposed (security hardening) · **Date:** 2026-11-11 · **PR:** fix(security): close the code scanning alerts; check timestamps properly; Fill from Me only where you can see

A security review of the Mac app, started from the four open code scanning alerts. The rule it applies everywhere: anything that arrives from outside the app (a page, the network, a file another program could write, a name out of the database) is checked before it's believed.

**Code scanning.**

- **Files are read by path, never by URL.** `Data(contentsOf:)` and `String(contentsOf:)` read whatever a URL points at, and an https URL makes that a network request. The two places that used them (the saved copy, and the bundled Defuddle script) now use `NSData(contentsOfFile:)` and `String(contentsOfFile:)`, which can only read a file. That closes both "URL read that may be remote" alerts in code, and the rule's baseline is now zero: any new hit is a new alert on the pull request that adds it.
- **A saved copy's name is checked.** A snapshot is one file directly inside the Snapshots folder. A name with a folder in it, `..`, or an absolute path is refused for reading, writing and removing.
- **The two "Outbound network call" alerts are the timestamp request**, the one call rule 5 allows and ADR 0022 approved. They carry the `NETRELISH-ALLOW-ENDPOINT: adr-0022` comment and the build gate passes them. Code scanning has no way to read that comment, so they stay listed in GitHub's Security tab until they're dismissed there by hand. Dismissing them changes nothing about the gate, which only reads the repository.

**The timestamp reply is a stranger's until it proves otherwise.** This changes ADR 0022's "When" paragraph. The request goes out over plain http, so anyone on the network between can answer it.

- **Real timestamps now check out. Before this, none did.** Apple's decoder only hashes a message's content by itself when that content is plain data. A timestamp token's content is a TSTInfo, so asked as-is the decoder answers "needs the content" for every real token, never "valid", and the app took anything but "valid" as a bad signature. The tests didn't catch it because they used stand-in authorities, and their recorded reply came from a throwaway authority no Mac trusts. The decoder is now handed the content: the very bytes the Pantry read the fingerprint, the nonce and the time from. So the timestamp that's verified and the timestamp that's read can't be two different things. A reply recorded from DigiCert on Nov 11 is in the tests, with a one-bit-changed copy that must fail.
- **The signer must hold a time-stamping certificate.** The check used the basic certificate policy, which accepts any certificate this Mac trusts for anything. It now uses Apple's time-stamping policy, which also requires the certificate to be issued for time stamping. Measured against the real reply: valid under that policy, and refused when asked as a web-server, mail or code-signing certificate.
- **No redirects.** The fingerprint goes to the authority that was asked and the answer comes from it.
- **A reply is read up to 64 KB and no further**, and the whole exchange has 60 seconds. A real reply is about 6 KB.
- **Nothing that arrives can be held against a page.** A refusal, a reply for another request and a bad signature can all be sent by anyone on the network, so each one is the same as no reply: the page waits for the next try. ADR 0022 counted the last two toward "failed" after three; they no longer count.
- **Pages the old check marked failed get another try.** A one-time data migration (V3) puts them back to waiting. No schema change.
- **The request says less.** `User-Agent: NetRelish` with no build or system version, and a fixed language. The comment that said no stamp can be linked to another was wrong and now says what's true: no cookies and no cache, but the authority and the network still see this Mac's address and the time.

**Fill from Me fills only what you can see, where you are.**

- **It runs in its own JavaScript world**, as Seal's extraction already does. The page can't see the script or the card, and can't swap out the browser functions the script calls to collect what passes through them.
- **A field that isn't drawn is left alone**: `display:none`, hidden, fully transparent, a pixel wide, parked off the page, or marked `aria-hidden`. A page can't show one box and take the rest of the card through fields nobody saw.
- **With the cursor in a form, only that form is filled.** With the cursor nowhere, the whole page, as before.
- These are a best effort. A page can still disguise a field it really draws.

**Smaller things.**

- **The Share inbox is bounded.** It's a file other software on this Mac could write to. Only entries named the way the extension names them are read; one bigger than 16 KB is dropped; 200 are taken at a time; a title is cut to the extension's own 300 characters; an address over 8 KB is skipped; and a date is kept between a year ago and now, so one bad date can't stop Brine from opening.
- **Error logs keep what the error said private.** An error's words can carry a page's address or text. A log line now gives the kind of error in the clear and the rest as private.
- **Compare is limited by the two seals added, not multiplied.** Its cost grows with the square of the sum, so a short seal against an enormous one got through the old limit.
- **Only a debug build can be told it's hosting the tests.** In a build that ships, that environment variable no longer unlocks Pro or turns off the Share inbox, summaries and timestamps.

**Proposed follow-ups, each Ryan's call:**

- Trust only DigiCert's own roots for timestamps, rather than any time-stamping certificate this Mac trusts. Stricter, but a change of roots at DigiCert would stop new stamps until an app update.
- Fill from Me on https pages only, and a short "fill these fields on this site?" step before anything beyond the form in focus.
- A Try Again button beside a timestamp that couldn't be fetched.
- Dismiss the two approved timestamp alerts in GitHub's Security tab, citing this ADR and 0022.
