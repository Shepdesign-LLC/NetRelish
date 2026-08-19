# P4 — Mac sync

**Status:** design approved (shape and stage split), ready for a plan
**Date:** 2026-08-19
**Parent:** `docs/superpowers/specs/2026-08-18-netrelish-master-plan-design.md` §4a
**Depends on:** P1 (merged as `5478494`)

Make the Mac app's local SQLite Pantry and the Supabase Pantry one thing.

---

## 1. What P4 actually is

Not "wire up `sync_push`". Measured against the shipped app:

| Fact | Consequence |
| :-- | :-- |
| The local schema has **no sync columns** — no `updated_at`, `deleted_at` or `field_ts` on any of its 8 tables | Field-level merge is meaningless until every write stamps them |
| **29 TypeScript write paths**, **4 Rust ones** | All must stamp `field_ts`, or merges silently pick the wrong winner |
| **5 hard `DELETE`s** | A hard delete cannot propagate. The row vanishes locally and returns on the next pull, because absence is indistinguishable from never-having-known |
| **28 `SELECT`s** | Tombstones change reads too — every query needs `deleted_at IS NULL`. This is the half of the tombstone cost that gets forgotten |

Most of P4 is invisible plumbing in the *existing* app. Only stage E is
visible to a user.

## 2. Decisions

| Decision | Choice | Why |
| :-- | :-- | :-- |
| Engine location | **TypeScript, beside `db.ts`** | Reuses the schema knowledge already there, and matches precedent — the hourly seal sweep already runs in the frontend |
| Note key | **Random key, password-wrapped, stored server-side** | Works on every device including P13's iPhone. Password change re-wraps the key; it never re-encrypts notes |
| Encryption boundary | **Plaintext on disk, ciphertext on the wire and at rest** | See §5 — storing ciphertext locally would break `⌘K` |
| Stage order | **A→E, sequential, only E visible** | Sync that half-works is worse than sync that does not exist |

---

## 3. Stage A — make local writes syncable

Local migration `004_sync_columns.sql`: add `updated_at INTEGER`,
`deleted_at INTEGER`, `field_ts TEXT` (JSON) to `jars`, `items`, `tabs`,
`labels`, `recipes` and `suggestion_feedback`.

Two tables are deliberately different:

- **`item_labels`** gets `updated_at` and `deleted_at` but **no `field_ts`** —
  a pure join table where presence is the only fact.
- **`embeddings` gets nothing and does not sync.** Local vectors are MiniLM;
  the server's are Voyage at a different dimension. They are not comparable,
  so syncing them would move bytes that no client could use. Local embeddings
  stay local; the server computes its own in P5.

Local timestamps stay epoch milliseconds (§ the existing convention); the sync
layer converts to `timestamptz` at the boundary and nowhere else.

### The stamp helper is the whole point of this stage

Do **not** edit 29 write paths to each hand-roll `field_ts`. Add one helper
that every write goes through:

```ts
/** Every local write goes through this. Field timestamps must be correct by
 *  construction — if they depend on 29 call sites remembering, they will be
 *  wrong within a month. */
function stamped(fields: Record<string, unknown>, now = Date.now())
```

It returns the column list, the values, and the merged `field_ts` JSON. A
write path that does not use it is a bug, and the plan should include a grep
that proves none remain.

### Deletes become tombstones

The five `DELETE FROM` sites — jars, tabs, sweep purge, recipes, item_labels —
become `UPDATE … SET deleted_at = ?`. Two follow-on requirements:

1. Every `SELECT` filters `deleted_at IS NULL`.
2. The **FTS triggers** fire on `UPDATE`, not `DELETE`, so a tombstoned item
   stays in the FTS index and `⌘K` keeps finding deleted things. The triggers
   need a matching change, or deleting an item appears to do nothing.

That second point is a real trap: FTS5 external-content tables are already the
subject of a warning in CLAUDE.md §6, and this adds a fourth way to desync them.

### Local purge

Tombstones are removed locally only after the row has been confirmed synced
and is older than the retention window. Until §9's open question is settled,
they are kept indefinitely — keeping too many is harmless, purging too early
resurrects data.

## 4. Stage B — extend `sync_push` beyond items

P1 shipped `sync_push` for `items` only. Jars, tabs, labels, recipes and
suggestion_feedback need the same field-level treatment.

`item_labels` is different and must not be forced into the same shape: with no
fields to merge, the rule is last-writer-wins on the row's *existence*. The
newer of "labelled" and "unlabelled" holds.

Prefer **one function per table over a single generic one.** A generic
row-shape-agnostic merge in plpgsql is possible and would be clever; it would
also be the least readable code in the project, and this is the code that
silently corrupts data when it is wrong.

## 5. Stage C — the sync engine

Lives in `apps/desktop/src/lib/sync.ts`. `db.ts` stays the only module that
writes local SQL; `sync.ts` calls it rather than issuing its own.

**Pull** — per table, `updated_at > last_synced_at`, ordered by `updated_at`.
Tombstones arrive as ordinary rows with `deleted_at` set.

**Push** — local rows where `updated_at > last_synced_at`, batched to
`sync_push(payload, client_synced_at)`. `client_synced_at` is load-bearing:
without it the server cannot distinguish a real prose conflict from a client
that simply has not pulled yet (this bug shipped once in P1 and was fixed in
migration 0006 — do not reintroduce it).

**There is no separate outbox.** The set of pending changes is derivable from
`updated_at > last_synced_at`, so there is no second structure to keep
consistent with the first.

**Cadence** — on launch, on window focus, after any local write (debounced
~2s), and hourly. The existing seal sweep already establishes launch+hourly.

**Offline** is a normal state, not an error. Failures leave `last_synced_at`
untouched and retry; nothing is lost because nothing was acknowledged.

## 6. Stage D — note encryption

### Where encryption applies

**Plaintext on disk. Ciphertext on the wire and at rest on the server.**

Storing ciphertext locally would break `⌘K`: local FTS5 indexes `body`, so
encrypted note bodies would index as ciphertext and `⌘K` would stop finding
note content — a shipped week-8 feature broken by a privacy decision. The
threat model §4a states is "no server-side feature may read them", not "the
local disk is encrypted", which FileVault already handles.

**The honest cost:** the server's `tsvector` indexes ciphertext for notes, so
server-side search cannot match note bodies. Every client decrypts and searches
notes locally. Fine for Mac and iPhone, which hold the whole Pantry. A real
constraint for P2's web app, and it must be designed for there, not discovered.

### Key handling

- At signup, generate a random 256-bit `noteKey` (CSPRNG).
- Derive `wrapKey` from the password with Argon2id and a random salt.
- Store server-side: `AES-256-GCM(noteKey, wrapKey)`, the salt, and the KDF
  parameters. The server holds ciphertext and never the key.
- Sign-in unwraps `noteKey` into memory and the macOS Keychain.
- **A password change re-wraps `noteKey`. It never re-encrypts notes.** This is
  the entire reason for wrapping rather than deriving the note key directly.
- Note and task bodies: AES-256-GCM, fresh nonce per write.

### The recovery code

Generated at signup, shown **once**, and used to wrap `noteKey` a second time.
Without it, a forgotten password means permanently lost notes — for the user
and for us. It is friction at exactly the wrong moment and it ships anyway,
because the alternative is a support story with no good ending.

### The problem this design has, stated plainly

**Supabase Auth receives the raw password.** If `wrapKey` were derived from
that same password, a compromised or malicious server could derive it too, and
"we can't read your notes" would be marketing rather than architecture.

The fix is to split the password client-side before anything leaves:

```
authSecret = HKDF(password, info="netrelish-auth")   → sent to Supabase Auth
wrapKey    = Argon2id(password, salt, info="wrap")   → never leaves the device
```

Supabase only ever sees `authSecret`, which cannot be reversed to `password`.

**This breaks GitHub OAuth users**, who have no password to derive from. See
§9 — it is an open question, and it blocks stage D but nothing before it.

## 7. Stage E — sign-in and sync status

Sign-in in the Mac app (email/password and GitHub). The mock's `SYNCED` chip
in the titlebar, with real states: synced, syncing, offline, error. Conflict
copies appear as ordinary items in their jar, tagged, with no modal and no
blocking resolution step — per the P1 spec.

---

## 8. Safeguards — not optional

Ryan's `netrelish.db` is 90 items and 4 jars of real work and is the only copy.

1. **A hash-verified backup before sync writes to it once.** Copy the file,
   compare hashes, record both. Not "remember to back up".
2. **Stages A–D are developed against a throwaway account and a copied
   database.** The real Pantry is what stage E touches, not stage A.
3. The comfort, which is real but is not a substitute for 1 and 2: P1's
   conflict design fails toward duplication, not loss.

## 9. Out of scope

- **The web app and iPhone** — P2 and P13. P4 makes one client sync.
- **Realtime.** Polling on `updated_at` is enough. Revisit when a feature needs push.
- **Sharing and roles** — P7 and P10.
- **Recipes and tabs on other clients.** They sync as data; only the Mac acts on them.

## 10. Done when

- A jar created on the Mac appears in Supabase, and one created via SQL appears on the Mac.
- An edit made offline survives reconnection.
- A delete on either side stays deleted and does not resurrect.
- Editing different fields of one item on two clients keeps both edits.
- Editing the same note body on two clients produces a conflict copy, and both survive.
- `⌘K` still finds note bodies locally after encryption ships.
- A note read back on a second device decrypts correctly.
- The server, queried directly, shows ciphertext for note bodies and plaintext for pages.
- No `SELECT` in `db.ts` returns tombstoned rows; a grep proves it.

## 11. Open questions

- ~~**OAuth users and the note key.**~~ **Decided 2026-08-19: notes are
  unencrypted on OAuth accounts, and the UI says so plainly.** A separate
  encryption passphrase was rejected — a second secret to remember undermines
  the reason GitHub sign-in exists. Stage D is unblocked.

  What this obliges stage D to build: account settings that name the tier in
  plain words, and copy that never says "private, even from us" to an OAuth
  user. CLAUDE.md §4a now carries both rules.

  Still to design when stage D starts: what happens if an OAuth user later
  adds a password. The honest options are to encrypt from that point forward
  only, or to re-encrypt the backlog — the second is correct and slower, and
  it is a stage D detail, not a blocker.
- **Tombstone retention.** How long before a confirmed-synced tombstone is
  purged locally. Must exceed the longest plausible time a device stays
  offline — a Mac closed over a long holiday is the case that decides it.
- **Backfilling the server's vectors.** `embeddings` does not sync (§3), so
  the server has none until P5 computes them. Whether that backfill runs on
  first sync or lazily on first AI use is a P5 decision, not a P4 one — noted
  here so P5 does not assume P4 left it vectors.
