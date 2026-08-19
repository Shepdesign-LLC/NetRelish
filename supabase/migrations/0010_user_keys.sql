-- P4 Stage D. Where the wrapped note key lives.
--
-- Everything here is either ciphertext or a public KDF parameter. Salts and
-- iteration counts are NOT secrets — they exist to make a stolen database
-- expensive to attack, and they must be readable to derive the key at all.
-- What is never here, in any form: the password, the key derived from it, or
-- the note key itself.
--
-- Why WRAP a random key instead of deriving the note key from the password
-- directly: a password change then re-wraps one small key instead of
-- re-encrypting every note the user has ever written. Proven in the client
-- tests — notes written before a password change still decrypt after it.
--
-- recovery_* is a second wrapping under a code shown once at signup. Without
-- it a forgotten password means permanently lost notes, for the user and for
-- us. It is friction at exactly the wrong moment and it ships anyway.
--
-- OAuth accounts have NO ROW HERE, and that is the design. The wrapping key
-- comes from a password and GitHub sign-in has none, so those accounts store
-- notes as plaintext and the UI says so plainly (CLAUDE.md §4a). Absence of a
-- row is how a client knows which tier it is on.

create table user_keys (
  user_id              uuid primary key references auth.users(id) on delete cascade,
  wrapped_key          text not null,
  wrap_nonce           text not null,
  kdf                  text not null default 'PBKDF2-SHA256',
  kdf_salt             text not null,
  kdf_iterations       integer not null,
  recovery_wrapped_key text,
  recovery_nonce       text,
  recovery_salt        text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

alter table user_keys enable row level security;

-- `with check` as well as `using`, or a user could reassign the row to
-- someone else's user_id.
create policy owner_all on user_keys
  for all
  using      (user_id = auth.uid())
  with check (user_id = auth.uid());
