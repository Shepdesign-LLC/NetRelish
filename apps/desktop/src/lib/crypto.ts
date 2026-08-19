/**
 * P4 Stage D — note encryption.
 *
 * CLAUDE.md §4a: note and task bodies are encrypted client-side on a password
 * account, and no server-side feature may read them. Page text stays readable,
 * because a note is something you wrote and a page is a copy of something
 * already public.
 *
 * WHERE ENCRYPTION APPLIES — this is the part that is easy to get wrong.
 * Plaintext on disk; ciphertext on the wire and at rest on the server. Local
 * FTS5 indexes `body`, so storing ciphertext locally would break ⌘K for notes —
 * a shipped feature broken by a privacy decision. The threat model §4a states
 * is "no server-side feature may read them", not "the local disk is
 * encrypted", which FileVault already handles.
 *
 * The honest cost: the server's tsvector indexes ciphertext for notes, so
 * server-side search cannot match note bodies. Every client decrypts and
 * searches notes locally.
 *
 * TWO TIERS. OAuth accounts have no password, so nothing to derive a wrapping
 * key from, so notes are stored plaintext and the UI must say so (§4a). A
 * client detects its tier by whether a `user_keys` row exists — see
 * `loadKeyring`.
 *
 * PRIMITIVES. PBKDF2-SHA256 and AES-256-GCM, both native to WebCrypto. Argon2id
 * would be stronger against GPU attack but needs a WASM dependency inside the
 * webview; PBKDF2 at OWASP's iteration count is the honest trade for shipping
 * without one. `KDF_ITERATIONS` is stored per row, so raising it later is a
 * re-wrap of one key, not a migration of every note.
 */

const KDF = "PBKDF2-SHA256";
const KDF_ITERATIONS = 600_000; // OWASP 2023 for PBKDF2-SHA256
const KEY_BITS = 256;
const NONCE_BYTES = 12; // AES-GCM standard

const enc = new TextEncoder();
const dec = new TextDecoder();

const b64 = (b: ArrayBuffer | Uint8Array): string =>
  btoa(String.fromCharCode(...new Uint8Array(b)));

const unb64 = (s: string): Uint8Array =>
  Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

const randomBytes = (n: number): Uint8Array =>
  crypto.getRandomValues(new Uint8Array(n));

/** Derive a wrapping key from a secret (password or recovery code). */
async function deriveWrapKey(
  secret: string,
  salt: Uint8Array,
  iterations: number,
): Promise<CryptoKey> {
  const base = await crypto.subtle.importKey(
    "raw", enc.encode(secret), "PBKDF2", false, ["deriveKey"],
  );
  return crypto.subtle.deriveKey(
    { name: "PBKDF2", salt: salt as BufferSource, iterations, hash: "SHA-256" },
    base,
    { name: "AES-GCM", length: KEY_BITS },
    false,
    ["encrypt", "decrypt"],
  );
}

/**
 * The value sent to Supabase Auth as the account password.
 *
 * Supabase receives this, never the real password — so a compromised auth
 * service cannot derive the wrapping key from what it sees. It is a one-way
 * derivation with a different context string from the wrapping key, so the two
 * cannot be computed from each other.
 *
 * CONSEQUENCE, and it is not small: a password reset performed anywhere other
 * than this app sets a raw password and breaks sign-in. The reset flow must go
 * through the app, which derives the new authSecret and re-wraps the note key.
 * And because a reset means the old password is forgotten, the note key can
 * only be recovered with the recovery code — which is exactly why one exists.
 */
export async function authSecret(password: string, email: string): Promise<string> {
  const base = await crypto.subtle.importKey(
    "raw", enc.encode(password), "PBKDF2", false, ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      // Email as salt: deterministic (no round-trip to fetch a salt before
      // sign-in) while still differing per account.
      salt: enc.encode(`netrelish-auth:${email.toLowerCase()}`) as BufferSource,
      iterations: KDF_ITERATIONS,
      hash: "SHA-256",
    },
    base,
    256,
  );
  return b64(bits);
}

async function wrap(noteKey: Uint8Array, wrapKey: CryptoKey) {
  const nonce = randomBytes(NONCE_BYTES);
  const ct = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce as BufferSource }, wrapKey, noteKey as BufferSource,
  );
  return { wrapped: b64(ct), nonce: b64(nonce) };
}

async function unwrap(
  wrapped: string, nonce: string, wrapKey: CryptoKey,
): Promise<Uint8Array> {
  const raw = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: unb64(nonce) as BufferSource }, wrapKey, unb64(wrapped) as BufferSource,
  );
  return new Uint8Array(raw);
}

export interface KeyRecord {
  wrapped_key: string;
  wrap_nonce: string;
  kdf: string;
  kdf_salt: string;
  kdf_iterations: number;
  recovery_wrapped_key: string | null;
  recovery_nonce: string | null;
  recovery_salt: string | null;
}

export interface NewKeyring {
  record: KeyRecord;
  /** Shown to the user ONCE. Never stored, never sent. */
  recoveryCode: string;
}

/** A recovery code the user can actually write down: 4 groups of 5. */
function makeRecoveryCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1
  const bytes = randomBytes(20);
  const chars = Array.from(bytes, (b) => alphabet[b % alphabet.length]);
  return [0, 5, 10, 15].map((i) => chars.slice(i, i + 5).join("")).join("-");
}

/**
 * Create a keyring at signup. Returns what to store server-side and the
 * recovery code to show once.
 */
export async function createKeyring(password: string): Promise<NewKeyring> {
  const noteKey = randomBytes(32);

  const salt = randomBytes(16);
  const wrapKey = await deriveWrapKey(password, salt, KDF_ITERATIONS);
  const primary = await wrap(noteKey, wrapKey);

  const recoveryCode = makeRecoveryCode();
  const rSalt = randomBytes(16);
  const rKey = await deriveWrapKey(recoveryCode, rSalt, KDF_ITERATIONS);
  const recovery = await wrap(noteKey, rKey);

  return {
    recoveryCode,
    record: {
      wrapped_key: primary.wrapped,
      wrap_nonce: primary.nonce,
      kdf: KDF,
      kdf_salt: b64(salt),
      kdf_iterations: KDF_ITERATIONS,
      recovery_wrapped_key: recovery.wrapped,
      recovery_nonce: recovery.nonce,
      recovery_salt: b64(rSalt),
    },
  };
}

/** Recover the note key from the password, or from the recovery code. */
export async function openKeyring(
  rec: KeyRecord,
  secret: string,
  via: "password" | "recovery" = "password",
): Promise<Uint8Array> {
  if (via === "recovery") {
    if (!rec.recovery_wrapped_key || !rec.recovery_nonce || !rec.recovery_salt) {
      throw new Error("This account has no recovery code on file.");
    }
    const k = await deriveWrapKey(secret, unb64(rec.recovery_salt), rec.kdf_iterations);
    return unwrap(rec.recovery_wrapped_key, rec.recovery_nonce, k);
  }
  const k = await deriveWrapKey(secret, unb64(rec.kdf_salt), rec.kdf_iterations);
  return unwrap(rec.wrapped_key, rec.wrap_nonce, k);
}

/**
 * Re-wrap the note key under a new password. Notes are NOT re-encrypted —
 * that is the whole point of wrapping a random key rather than deriving from
 * the password.
 */
export async function rewrap(
  noteKey: Uint8Array, newPassword: string,
): Promise<Pick<KeyRecord, "wrapped_key" | "wrap_nonce" | "kdf_salt" | "kdf_iterations" | "kdf">> {
  const salt = randomBytes(16);
  const k = await deriveWrapKey(newPassword, salt, KDF_ITERATIONS);
  const w = await wrap(noteKey, k);
  return {
    wrapped_key: w.wrapped, wrap_nonce: w.nonce,
    kdf: KDF, kdf_salt: b64(salt), kdf_iterations: KDF_ITERATIONS,
  };
}

// --- body encryption ------------------------------------------------------

/** Marks a body as ciphertext so a plaintext one is never mistaken for it. */
const PREFIX = "nrenc1:";

export function isEncrypted(body: string | null | undefined): boolean {
  return typeof body === "string" && body.startsWith(PREFIX);
}

/** Encrypt a note or task body for transit. A fresh nonce per write. */
export async function encryptBody(plain: string, noteKey: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", noteKey as BufferSource, "AES-GCM", false, ["encrypt"],
  );
  const nonce = randomBytes(NONCE_BYTES);
  const ct = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce as BufferSource }, key, enc.encode(plain) as BufferSource,
  );
  return `${PREFIX}${b64(nonce)}.${b64(ct)}`;
}

/**
 * Decrypt a body. Returns it unchanged if it is not ciphertext, so a Pantry
 * that mixes tiers (an account that was OAuth and later added a password)
 * still reads correctly.
 */
export async function decryptBody(
  stored: string | null, noteKey: Uint8Array | null,
): Promise<string | null> {
  if (stored === null || !isEncrypted(stored)) return stored;
  if (!noteKey) throw new Error("This note is encrypted and the keyring is locked.");
  const [nonce, ct] = stored.slice(PREFIX.length).split(".");
  const key = await crypto.subtle.importKey(
    "raw", noteKey as BufferSource, "AES-GCM", false, ["decrypt"],
  );
  const raw = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: unb64(nonce) as BufferSource }, key, unb64(ct) as BufferSource,
  );
  return dec.decode(raw);
}

/** Kinds whose bodies are the user's own writing, and so are encrypted. */
export const ENCRYPTED_KINDS = new Set(["note", "task"]);
