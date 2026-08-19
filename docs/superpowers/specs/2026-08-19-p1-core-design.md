# P1 — The Core

**Status:** design approved, ready for an implementation plan
**Date:** 2026-08-19
**Parent:** `docs/superpowers/specs/2026-08-18-netrelish-master-plan-design.md`
**Depends on:** P0 (merged to main as `8421d92`)

The backend everything else attaches to: Postgres schema, auth, row-level
security, and a written sync protocol. No sync implementation, no LLM
calls, no UI.

---

## 1. Decisions

Taken 2026-08-19. Each was a real fork; recording them so P4 does not
relitigate.

| Decision | Choice | Why |
| :-- | :-- | :-- |
| Conflict resolution | **Field-level LWW, plus conflict copies for prose** | Different-field edits merge. Same-`body` edits keep both. |
| Auth | **Email/password + GitHub OAuth** | GitHub covers the primary market (§5 designers and developers). |
| Embeddings | **Server re-embeds with a stronger model** | Web and extension cannot run a 90MB ONNX model. |
| Embedding vendor | **Voyage `voyage-3`, 1024-dim** | Anthropic's recommended partner; Anthropic has no embeddings endpoint. |
| Project | **Created** — `netrelish`, ref `qiyqlbaggqthcuxslwyk`, us-east-1 | $10/month on the Pro org. |

### The constraint that shapes everything

There are **three clients**. Any rule implemented in a client is a rule
implemented three times, and three implementations of a merge rule will
drift and then corrupt each other. Therefore: **the database arbitrates.**
Clients submit changes; they do not decide who wins.

---

## 2. Schema

Postgres-native types. The *structure* mirrors CLAUDE.md §6 exactly — one
`items` table with a `kind` discriminator — but ids become `uuid` and
timestamps become `timestamptz`.

This costs nothing at the boundary: local ids are already UUIDv4 stored as
TEXT, and local timestamps are epoch milliseconds. Both cast mechanically.
There is no id-mapping table, now or ever.

### Sync columns

Every syncable table carries these four (with one exception, `item_labels`,
noted under Tables below):

```sql
user_id     uuid not null references auth.users(id) on delete cascade,
updated_at  timestamptz not null default now(),
deleted_at  timestamptz,                    -- tombstone; never hard-delete
field_ts    jsonb not null default '{}'::jsonb
```

`field_ts` maps column name → ISO timestamp of that column's last write:
`{"title": "2026-08-19T09:00:00Z", "body": "2026-08-19T09:04:00Z"}`. It is
what makes field-level merging possible, and it is maintained by the merge
function, never by clients directly.

`deleted_at` is not optional politeness. A delete that does not replicate
is a resurrection: the row comes back from whichever client had not heard
about it. Tombstones are purged only after every registered client has
acknowledged a sync past them, or after 90 days, whichever is later.

### Tables

```sql
create table jars (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  hue         smallint not null check (hue between 1 and 6),
  created_at  timestamptz not null default now(),
  sealed_at   timestamptz,
  shelf_life_hours integer,               -- null = 72h default (migration 002)
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  field_ts    jsonb not null default '{}'::jsonb
);

create table items (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  jar_id      uuid references jars(id) on delete set null,   -- null = Brine
  kind        text not null check (kind in
                ('page','note','task','file','message')),
  url         text,
  title       text not null,
  body        text,
  meta        jsonb,
  created_at  timestamptz not null default now(),
  touched_at  timestamptz not null default now(),
  sealed_at   timestamptz,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  field_ts    jsonb not null default '{}'::jsonb,
  fts         tsvector generated always as (
                to_tsvector('english', coalesce(title,'') || ' ' || coalesce(body,''))
              ) stored
);

create index idx_items_user_jar  on items (user_id, jar_id, touched_at desc);
create index idx_items_user_kind on items (user_id, kind, touched_at desc);
create index idx_items_sync      on items (user_id, updated_at);
create index idx_items_fts       on items using gin (fts);

-- §6's unique URL index becomes per-user: two accounts may hold the same page.
create unique index idx_items_user_url on items (user_id, url)
  where url is not null and deleted_at is null;
```

`tabs`, `labels`, `recipes` and `suggestion_feedback` follow the same
pattern: `user_id`, the four sync columns, and `on delete cascade` from
their parents. Their full DDL belongs in the implementation plan — they
carry no design decision the tables above have not already settled.

**`item_labels` is the exception, and it needs stating.** It is a pure join
table: `(item_id, label_id)` with no other columns. There are no fields to
merge, so `field_ts` is meaningless on it — the only facts are *present* and
*absent*. It therefore carries `user_id`, `updated_at` and `deleted_at` but
**no `field_ts`**, and merging is simply last-writer-wins on the row's
existence: the newer of "labelled" and "unlabelled" holds.

The tombstone matters more here than anywhere else. Without it, removing a
label on one device and syncing from another re-applies it, because absence
is indistinguishable from never-having-known. A join row is deleted by
setting `deleted_at`, never by `delete`.

### Vectors

```sql
create extension if not exists vector;

create table embeddings (
  item_id    uuid primary key references items(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  vector     vector(1024) not null,        -- voyage-3
  model      text not null,                -- e.g. 'voyage-3'
  created_at timestamptz not null default now()
);

create index on embeddings using hnsw (vector vector_cosine_ops);
```

The `model` column exists so a future model change is detectable per row and
backfillable incrementally. **Dimension is pinned at 1024**; changing model
families means a migration, not a config edit. That is deliberate — silent
dimension drift produces a table where old and new vectors are not
comparable and nothing errors.

The local Mac keeps its own MiniLM vectors in SQLite via `sqlite-vec`. The
two vector stores are **not** synced to each other and are not expected to
agree. Local answers fast and offline; the server answers better. §8's
"four layers, all on-device" needs amending when P5 lands.

---

## 3. Sync protocol

Specified here, implemented in P4.

### Pull

```
select * from <table>
where user_id = auth.uid() and updated_at > $last_synced_at
order by updated_at
```

Clients store `last_synced_at` per table. Tombstones arrive as ordinary rows
with `deleted_at` set — the client applies the delete locally.

### Push

Clients call one function with a batch:

```sql
sync_push(payload jsonb, client_synced_at timestamptz) returns jsonb
```

`client_synced_at` is not decoration: without it the function cannot tell a
genuine prose conflict from a client that simply has not pulled yet. It is
the timestamp the pushing client last successfully pulled through, and it
defines "since we last agreed".

`payload` is an array of rows, each carrying its `field_ts`. The function,
for each row, for each field:

1. If the row does not exist locally on the server, insert it.
2. Otherwise, for each field in the incoming `field_ts`: if the incoming
   timestamp is **strictly newer** than the stored one, take the incoming
   value and its timestamp. Ties keep the stored value — arbitrary but
   deterministic, and determinism is what matters.
3. `updated_at` is set to `now()` by the function, never by the client. A
   client clock that is wrong must not be able to win forever, and must not
   be able to hide a row from another client's `updated_at >` pull.

The function returns the merged rows, so the pushing client immediately
learns what actually won rather than assuming it did.

### Conflict copies

Triggered when `body` is present in the incoming `field_ts`, differs from
stored, and **both** timestamps are newer than `client_synced_at`:

- `stored_ts > client_synced_at` — the server's copy changed after the
  pushing client last saw it, and
- `incoming_ts > client_synced_at` — the client wrote too.

**Both halves are required, and the second one is easy to forget.** An
earlier draft of this spec checked only the first, which forks an item
whenever a client re-sends an unchanged snapshot after any server-side
edit — and full-snapshot push is the obvious way to write a client, so all
three would have done it. Verified against the live database: with one
clause an unedited client produced a conflict copy of its own stale text;
with both, it does not, while a genuinely-edited client still forks.

Then the incoming version is inserted as a new item with:

```
meta.conflict_of  = <original item id>
meta.conflict_at  = <now>
```

Both survive. The UI surfaces it as an ordinary item in the same jar; no
modal, no blocking resolution step.

**Only `body` forks.** Title, `jar_id`, labels, `meta` and the rest take
plain field-level LWW. Losing a retag is a small annoyance; losing written
prose violates §4.3, which is a non-negotiable. This asymmetry is the whole
point of the design and should not be "simplified" later.

### What the protocol deliberately does not do

No operational transform, no CRDT, no vector clocks. NetRelish is
overwhelmingly a single user on two or three devices; conflicts are rare,
and the cost of being wrong is bounded by conflict copies. Reach for a CRDT
if and when P10's teams make genuinely concurrent multi-user editing real.

---

## 4. Row-level security

Every table: enable RLS, then

```sql
create policy owner_all on <table>
  for all
  using      (user_id = auth.uid())
  with check (user_id = auth.uid());
```

`using` governs read and the pre-image of writes; `with check` governs the
post-image. Both are required — `using` alone permits a user to *move* a row
to another user's `user_id`.

**P1's done-when is a test, not a policy.** An automated test creates two
accounts, seeds a jar and an item under account A, and asserts that account B
receives zero rows from select, and zero rows affected from update and delete.
A policy that exists is not a policy that works; §4a's guarantees are only as
good as this test.

---

## 5. Auth

Supabase Auth. Email/password plus GitHub OAuth.

`auth.users` is the identity source; every table's `user_id` references it
with `on delete cascade`, so account deletion removes the account's data
without an application-level sweep.

Note for §4a: signing in transmits an account credential. §4a's "Saved
website credentials never leave" is about the Keychain vault and remains
true — the two are different things, and the wording already distinguishes
them.

---

## 6. A governance change this forces

§4a currently says "The model is a **third party** — this text leaves
NetRelish's infrastructure too", singular. With Voyage for embeddings and
Anthropic for prose there are **two** third parties, with different data
flowing to each:

- **Anthropic** — item text sent for summaries, gap analysis, reports (P5).
- **Voyage** — item title and body sent for embedding (P1 onward).

§4a needs one line naming both. This is a P1 deliverable, not a P5 one,
because Voyage starts receiving text as soon as embeddings backfill.

---

## 7. Out of scope

- **Sync implementation** — P4. This spec is the contract P4 builds against.
- **LLM calls** — P5. The `embeddings` table is populated in P1; nothing
  reads it for intelligence yet.
- **Billing, plan gates, metering** — P6.
- **Any UI** — P2 and P3.
- **Realtime subscriptions.** Polling on `updated_at` is sufficient and far
  simpler. Revisit when a user-visible feature needs push.

---

## 8. Done when

- A signed-in client creates a jar, adds an item, and finds it by a phrase
  from its body via full-text search.
- A second account provably cannot read, update, or delete the first
  account's rows — proven by an automated test, not by inspection.
- `sync_push` merges two divergent versions of one item field-by-field, and
  produces a conflict copy when both edited `body`. Proven by a test.
- Every table has RLS enabled; a query as an anonymous role returns nothing.
- `packages/core` exports typed row shapes and a typed client, generated
  from the live schema rather than hand-written.

---

## 9. Open questions

- **Tombstone purge policy.** 90 days is asserted above, not reasoned. It
  needs a number that accounts for a Mac left closed over a long holiday.
- **Rate limiting `sync_push`.** A looping client could hammer it. Probably
  a P4 concern, but the function should be cheap enough to survive being
  called wrongly.
- **A public jar still needs a name.** §2 forbids "workspace" and
  "collection". Blocks P7, not P1.
