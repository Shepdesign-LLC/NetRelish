/**
 * P4 Stage E — sign-in, and the two privacy tiers.
 *
 * CLAUDE.md §4a: on a password account, note and task bodies are encrypted
 * client-side and the server cannot read them. On an OAuth account there is no
 * password to derive a wrapping key from, so notes sync as plaintext — and the
 * UI must say so plainly, in words, not a padlock icon.
 *
 * This module is where a client learns which tier it is on. `tier()` is the
 * single source of truth; nothing else should infer it.
 */

import {
  createKeyring, openKeyring, type KeyRecord, authSecret,
} from "./crypto";
import { remote, unlockKeyring, usePlaintextNotes, lockKeyring } from "./sync";

export type Tier = "encrypted" | "plaintext" | "locked" | "no-keyring" | "signed-out";

export interface Account {
  id: string;
  email: string | null;
  /** "github" etc. Absent for password accounts. */
  provider: string;
}

let account: Account | null = null;
let currentTier: Tier = "signed-out";

export const tier = (): Tier => currentTier;
export const currentAccount = (): Account | null => account;

/** "github" → "GitHub". Only for the sentence below. */
function providerLabel(p: string | undefined): string {
  if (!p || p === "github") return "GitHub";
  return p.charAt(0).toUpperCase() + p.slice(1);
}

/** In plain words, for the UI. §4a forbids leaving this to an icon. */
export function tierStatement(t: Tier = currentTier, provider = account?.provider): string {
  switch (t) {
    case "encrypted":
      return "Your notes are encrypted on this Mac before they sync. We can't read them.";
    case "plaintext":
      // "plaintext" is reached by more than one path: an OAuth account (no
      // password, so no wrapping key) and a password account with no keyring.
      // Blaming GitHub in the second case is a falsehood told in the one place
      // §4a insists on plain words, so only say it when it is true. An unknown
      // provider keeps the OAuth wording — that is the pre-commit warning
      // shown before signInWithGitHub, when there is no account yet.
      return provider === "email"
        ? "Your notes are not encrypted. This account has no encryption keyring, so notes " +
          "sync the same way pages do — we can read them."
        : `Your notes are not encrypted. Signing in with ${providerLabel(provider)} means ` +
          "there's no password to build an encryption key from, so notes sync the same way " +
          "pages do — we can read them. Sign in with an email and password instead if you'd " +
          "rather we couldn't.";
    case "locked":
      return "Notes are encrypted and locked. Enter your password to read or sync them.";
    case "no-keyring":
      return "Syncing is off. This account has no encryption keyring, so there is no safe " +
        "way to send your notes — and rather than send them readable, nothing syncs at all. " +
        "Everything stays on this Mac.";
    case "signed-out":
      return "Not signed in. Everything stays on this Mac.";
  }
}

/**
 * What a missing `user_keys` row means. It is only evidence of a plaintext
 * account when the account has no password to build a key from; for a password
 * account it means the keyring is MISSING — a sign-up whose insert failed, or
 * an account predating keyrings — which is an anomaly, not consent to send
 * notes readable.
 *
 * An OAuth account later given a password keeps its original provider, so it
 * still reads as plaintext here. That is correct: its notes never were
 * encrypted, and saying otherwise would be the same lie in reverse.
 */
function tierWithoutKeyring(provider: string | undefined): Tier {
  if (provider === "email") {
    // lockKeyring() makes sync refuse the push (sync.ts). Because syncNow wraps
    // the whole cycle in one try and pushTable uses Promise.all, that stops
    // every table in both directions, not just notes. Deliberate, and said
    // plainly in tierStatement("no-keyring") rather than left to be discovered.
    lockKeyring();
    return "no-keyring";
  }
  usePlaintextNotes();
  return "plaintext";
}

function readAccount(user: { id: string; email?: string | null; app_metadata?: { provider?: string } }): Account {
  return {
    id: user.id,
    email: user.email ?? null,
    provider: user.app_metadata?.provider ?? "email",
  };
}

/**
 * `user_keys` postdates the last type generation, so the generated per-table
 * types do not know it. Confined to one accessor rather than scattered casts.
 * Regenerate with `npm run db:types` and this can go.
 */
function keysTable() {
  const from = remote().from as unknown as (t: string) => {
    select: (c: string) => {
      maybeSingle: () => Promise<{ data: unknown; error: { message: string } | null }>;
    };
    insert: (v: Record<string, unknown>) => Promise<{ error: { message: string } | null }>;
  };
  return from("user_keys");
}

async function fetchKeyRecord(): Promise<KeyRecord | null> {
  const { data, error } = await keysTable().select("*").maybeSingle();
  if (error) throw new Error(error.message);
  return (data as KeyRecord | null) ?? null;
}

export interface SignUpResult {
  account: Account;
  /** Shown ONCE. Never stored, never sent. Losing it plus the password loses the notes. */
  recoveryCode: string;
}

export async function signUp(email: string, password: string): Promise<SignUpResult> {
  // Supabase receives a derivation, never the password itself, so a
  // compromised auth service cannot compute the wrapping key.
  const secret = await authSecret(password, email);
  const { data, error } = await remote().auth.signUp({ email, password: secret });
  if (error) throw new Error(error.message);
  if (!data.user) throw new Error("Sign-up did not return an account.");

  const kr = await createKeyring(password);
  const { error: kerr } = await keysTable()
    .insert({ user_id: data.user.id, ...kr.record });
  if (kerr) throw new Error(`Account made, but the keyring failed: ${kerr.message}`);

  const key = await openKeyring(kr.record, password);
  unlockKeyring(key);
  account = readAccount(data.user);
  currentTier = "encrypted";
  return { account, recoveryCode: kr.recoveryCode };
}

export async function signIn(email: string, password: string): Promise<Account> {
  const secret = await authSecret(password, email);
  const { data, error } = await remote().auth.signInWithPassword({
    email, password: secret,
  });
  if (error) throw new Error(error.message);
  if (!data.user) throw new Error("Sign-in did not return an account.");

  // Both the keyring lookup and the unwrap can throw, so nothing is published
  // to module state until the tier is settled. Assigning `account` first would
  // leave currentAccount() populated while tier() still read "signed-out" — a
  // pair no caller can make sense of, and enough for the UI to render someone
  // as signed in on a sign-in that failed.
  const next = readAccount(data.user);
  let nextTier: Tier;
  try {
    const rec = await fetchKeyRecord();
    if (rec) {
      unlockKeyring(await openKeyring(rec, password));
      nextTier = "encrypted";
    } else {
      // No keyring: made before Stage D, or made via OAuth and later given a
      // password. Which of those it is decides the tier — see below.
      nextTier = tierWithoutKeyring(next.provider);
    }
  } catch (e) {
    // The Supabase session is live but we could not settle a tier. Leave no
    // half-signed-in state behind: a stale account paired with a stale note
    // key is worse than signed-out, and restoreSession() picks the session up
    // cleanly on the next launch.
    account = null;
    currentTier = "signed-out";
    lockKeyring();
    throw e;
  }

  account = next;
  currentTier = nextTier;
  return account;
}

/**
 * GitHub. There is no password here, so there is no wrapping key and no
 * encryption. §4a requires the UI to say so before the user commits — see
 * `tierStatement("plaintext")`.
 */
export async function signInWithGitHub(): Promise<void> {
  const { error } = await remote().auth.signInWithOAuth({
    provider: "github",
    options: { redirectTo: "netrelish://auth-callback" },
  });
  if (error) throw new Error(error.message);
}

/**
 * Restore a session at launch. The Supabase session persists; the note key
 * does not, because it only ever lives in memory. So a password account comes
 * back LOCKED and must be unlocked before notes can sync.
 *
 * That is deliberate for now, and it is the honest behaviour: the alternative
 * is stashing the key in the macOS Keychain, which is the right long-term
 * answer and is a follow-up rather than a silent default.
 */
export async function restoreSession(): Promise<Tier> {
  const { data } = await remote().auth.getSession();
  const user = data.session?.user;
  if (!user) {
    account = null;
    currentTier = "signed-out";
    lockKeyring();
    return currentTier;
  }
  const restored = readAccount(user);
  account = restored;

  // A failed lookup is NOT evidence that no keyring exists, and the two tiers
  // behave in opposite ways: "locked" refuses to push (see sync.ts), while
  // "plaintext" uploads note bodies in the clear. Swallowing the error and
  // falling through to plaintext would silently downgrade an encrypted account
  // on a cold start, a wake from sleep, or a token-refresh race — exactly the
  // conditions this runs under. If we cannot tell, stay locked: the user is
  // asked for a password they can supply, rather than having their notes
  // uploaded readable without being told.
  let rec: KeyRecord | null;
  try {
    rec = await fetchKeyRecord();
  } catch {
    lockKeyring();
    currentTier = "locked";
    return currentTier;
  }

  if (rec) {
    lockKeyring();
    currentTier = "locked";
  } else {
    currentTier = tierWithoutKeyring(restored.provider);
  }
  return currentTier;
}

/** Unlock an already-signed-in account's notes. */
export async function unlock(password: string): Promise<void> {
  const rec = await fetchKeyRecord();
  if (!rec) throw new Error("This account has no encrypted notes.");
  unlockKeyring(await openKeyring(rec, password));
  currentTier = "encrypted";
}

/** Last resort: the recovery code, when the password is gone. */
export async function unlockWithRecoveryCode(code: string): Promise<void> {
  const rec = await fetchKeyRecord();
  if (!rec) throw new Error("This account has no encrypted notes.");
  unlockKeyring(await openKeyring(rec, code.trim().toUpperCase(), "recovery"));
  currentTier = "encrypted";
}

export async function signOut(): Promise<void> {
  await remote().auth.signOut();
  account = null;
  currentTier = "signed-out";
  lockKeyring();
}
