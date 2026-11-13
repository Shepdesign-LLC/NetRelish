# ADR 0030 — Canning, and jars that show when they've been tampered with

**Status:** the check on open is built in this PR; Canning is proposed and waits on Ryan and one System Designer round · **Date:** 2026-11-13 · **PR:** feat(shelf): right-click menus and drag for jars and tabs

Ryan, Nov 13: "introduce Canning, which would be after sealing. It could be a security type feature. And also tamper-resistant jars by making them tamper-evident."

## The idea, in kitchen terms

You seal a jar's lid, then you can it, and the button on the lid goes down. If anyone opens it, the button pops and stays popped. Nothing stops them opening it. You just can't miss that it happened.

That maps onto what NetRelish already has:

| Kitchen | NetRelish | State today |
|---|---|---|
| Seal the lid | **Seal** one page: freeze its `.webarchive`, stamp `sealedAt` | Shipped |
| The lid's button | The page's **fingerprint** (SHA-256 of the saved copy) | Shipped (ADR 0022) |
| Check the button | Re-take the fingerprint and compare | **Built in this PR**, on open |
| Can the jar | **Can** a whole jar: sign a record of everything sealed in it | Proposed below |
| A popped button | The jar or page shows that it no longer matches | Page: this PR. Jar: proposed |

**Can is the word ADR 0010 row 5 left open:** "finishing a whole jar gets its own word". Seal stays per page (non-negotiable 3). Canning is what you do to a jar after its pages are sealed.

## Built in this PR: a saved copy that has changed says so

Every time a sealed page's saved copy is opened, its bytes are fingerprinted again and compared with the fingerprint kept in the Pantry (`Provenance.integrity(of:against:)`, `SealIntegrity`).

- **Matches:** the header adds "Unchanged since sealed".
- **Doesn't match:** a line under the header says "This saved copy has changed since it was sealed. It no longer matches its fingerprint." The copy is still shown. Nothing is repaired, hidden or rewritten.
- **No fingerprint yet** (sealed a moment ago): nothing is claimed either way.

No model change, no new network call, no Pro gate: fingerprints are local and free (ADR 0022). Export Proof already refused a copy that didn't match; now the reader finds out without exporting.

**What this does and doesn't prove.** It catches a saved copy that was edited, swapped or damaged on disk. It does not catch someone who changes the copy *and* the fingerprint in the Pantry database, because both live on the same Mac under the same account. Closing that gap is what Canning is for.

## Proposed: Canning (1.1)

**Can This Jar** does four things, in order:

1. **Seals what's still open.** Each open tab in the jar gets a normal Seal, or is closed, as the user chooses.
2. **Writes the jar's record:** every sealed page's id, fingerprint and `sealedAt`, in order, plus the jar's name and the date. Its SHA-256 is the jar's fingerprint.
3. **Signs the record** with a key made in this Mac's Secure Enclave. The key can't be copied off the Mac or read by NetRelish, and using it asks for Touch ID.
4. **Locks the jar.** A canned jar takes no new tabs or items and gives none up. Its saved copies are marked read-only on disk.

**Opening a canned jar** asks for Touch ID and is written into the record with its date. The jar is an ordinary jar again and can be canned again, which makes a new record. You can always open it. You can't open it quietly.

**Checking.** When a canned jar is shown, and once at launch, NetRelish re-checks every saved copy against the record and the record against its signature. If everything matches, the jar shows as canned. If anything doesn't, the jar shows a popped lid in `--nr-danger` and names what changed: a page edited, a page missing, a page added, or the record itself altered.

### Why this is stronger than the fingerprint alone

| Someone with the Mac unlocked… | Fingerprint only | Canned |
|---|---|---|
| edits a saved copy on disk | Caught | Caught |
| edits the copy and its fingerprint in the database | Missed | Caught: the signed record no longer matches |
| removes a page from the jar, or slips one in | Missed | Caught |
| forges a new record | — | Can't: the key never leaves the Secure Enclave and needs Touch ID |
| deletes the record entirely | — | The jar reads as never canned. Caught only if a timestamp or an exported proof exists (below) |

So the honest claim is **tamper-evident, not tamper-proof**, and it is not encryption: canning doesn't hide a jar's contents. The app and the listing should say exactly that (ADR 0025).

### What Apple gives us for it

- **CryptoKit:** SHA-256 for fingerprints (already used), P-256 signatures for the record.
- **Secure Enclave** (`SecureEnclave.P256.Signing`): a signing key that is created in the chip and never exists outside it. Works in the App Store sandbox.
- **LocalAuthentication:** Touch ID, Apple Watch or the Mac's password to can and to open.
- **Keychain:** holds the reference to that key, and a second copy of each jar's fingerprint, so deleting the record from the database is itself noticed.
- **The immutable file flag:** canned saved copies are marked so an accidental write fails. This is the "tamper-resistant" part; the signature is the "tamper-evident" part.
- **App Intents:** "Can a Jar" and "Check a Jar" in Shortcuts, in the same spirit as non-negotiable 7.
- **RFC 3161 (Pro, already an approved call):** one trusted timestamp on the jar's fingerprint. It sends the hash and nothing else, exactly as page timestamps do. This is the anchor outside the Mac that makes a deleted record provable.

Not used: App Attest and DeviceCheck. Both call Apple's servers, which non-negotiable 5 rules out.

### What it needs from System Designer

Canning needs two fields on `Jar`, so it starts in the diagram (CLAUDE.md), and ADR 0028 asks for one on `Tab`. One round covers all three.

**Schemas tab › Jar** — add these lines:

```json
"cannedAt": "property",
"canning": "property",
"can": "method",
"open": "method",
"onCanned": "event",
"onOpened": "event"
```

**Models tab › Jar** — add these lines:

```json
"cannedAt": { "type": "date",   "readOnly": false, "mandatory": false, "default": "1970-01-01T00:00:00.000Z" },
"canning":  { "type": "object", "readOnly": false, "mandatory": false, "default": {} },
"can":      { "params": [], "result": "Jar" },
"open":     { "params": [], "result": "Jar" },
"onCanned": { "params": [ { "name": "jar", "type": "Jar" } ] },
"onOpened": { "params": [ { "name": "jar", "type": "Jar" } ] }
```

**Schemas tab › Tab** — add `"glyph": "property"`. **Models tab › Tab** — add `"glyph": { "type": "string", "readOnly": false, "mandatory": false, "default": "" }`.

Export to `/design/NetRelish.json` and the Swift is regenerated from it. The behavior bodies for `can` and `open` are written with the feature.

## Rule check

- **NN1:** no new table. The record is a field on `Jar`.
- **NN3:** Canning never changes a sealed snapshot's bytes, `body` or `sealedAt`. Marking the file read-only changes a file flag, not the file. Seal keeps its one meaning.
- **NN4:** unchanged. Intelligence still reads sealed snapshots only.
- **NN5:** no new endpoint. The only call is the RFC 3161 timestamp already on the approved list, and only for Pro.
- **NN6:** unchanged. A canned jar keeps its own data store.
- **NN7:** Can and Check ship as App Intents.

## Ryan decides

1. **Does canning lock the jar, or only stamp it?** Proposed: lock. A can you can keep adding to isn't one.
2. **Touch ID to can and to open?** Proposed: yes for both.
3. **Free or Pro?** Proposed: canning and checking are free, like fingerprints. The trusted timestamp on a jar, and Export Proof for a whole jar, are Pro.
4. **When?** Proposed: 1.1. The check on open in this PR is small enough for Dec 14 if you want it there.
5. **The words.** Proposed: "Can This Jar…", "Open This Jar…", "Canned Nov 13", and for a failed check "This jar's seal is broken". No lid puns in the copy.
6. **The picture.** A canned jar needs its own glyph in `symbols.svg` (a jar with the lid's button down, and one with it popped). That's a drawing for Claude Design, and a manifest line.

## Also noted

- A page's fingerprint is taken a moment after Seal, off the main thread (ADR 0022). Canning should take it inside the Seal itself, so there is no gap between freezing a page and fingerprinting it.
- The roadmap's "Seal a Mason Jar" (export a `.masonjar` bundle) reads better as "Can a Mason Jar" once this lands. Left as it is for now.
