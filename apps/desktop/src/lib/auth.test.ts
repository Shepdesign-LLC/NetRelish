/**
 * The tier decisions in auth.ts, pinned.
 *
 * §4a draws the line at whether a note leaves this Mac readable, and the whole
 * of that decision lives in three places: restoreSession(), signIn(), and
 * tierStatement(). Each test below is a regression test for a real defect —
 * every one of them was a way the client could quietly decide the encrypted
 * tier did not apply.
 *
 * ./sync and ./crypto are stubbed. remote() reads import.meta.env and returns a
 * live Supabase client, and crypto.ts wants real WebCrypto; neither is the
 * subject here. What IS the subject is which keyring call auth.ts makes, so the
 * stubs count those.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { KeyRecord } from "./crypto";

type User = { id: string; email?: string | null; app_metadata?: { provider?: string } };

const KEY_RECORD: KeyRecord = {
  wrapped_key: "wrapped", wrap_nonce: "nonce", kdf: "pbkdf2",
  kdf_salt: "salt", kdf_iterations: 100_000,
  recovery_wrapped_key: null, recovery_nonce: null, recovery_salt: null,
};

const emailUser: User = { id: "u1", email: "a@b.co", app_metadata: { provider: "email" } };
const githubUser: User = { id: "u2", email: "a@b.co", app_metadata: { provider: "github" } };

/** Mutable across tests; hoisted so the vi.mock factories below can close over it. */
const h = vi.hoisted(() => ({
  session: null as { user: User } | null,
  signInUser: null as User | null,
  keyRecord: null as KeyRecord | null,
  /** Simulates a lookup that fails rather than one that finds nothing. */
  lookupFails: false,
  openKeyringFails: false,
  calls: [] as string[],
}));

vi.mock("./sync", () => ({
  remote: () => ({
    auth: {
      getSession: async () => ({ data: { session: h.session } }),
      signInWithPassword: async () => ({ data: { user: h.signInUser }, error: null }),
      signOut: async () => ({}),
    },
    from: () => ({
      select: () => ({
        maybeSingle: async () => {
          if (h.lookupFails) return { data: null, error: { message: "network is down" } };
          return { data: h.keyRecord, error: null };
        },
      }),
      insert: async () => ({ error: null }),
    }),
  }),
  unlockKeyring: () => { h.calls.push("unlock"); },
  usePlaintextNotes: () => { h.calls.push("plaintext"); },
  lockKeyring: () => { h.calls.push("lock"); },
}));

vi.mock("./crypto", () => ({
  authSecret: async () => "derived-secret",
  createKeyring: async () => ({ record: KEY_RECORD, recoveryCode: "CODE" }),
  openKeyring: async () => {
    if (h.openKeyringFails) throw new Error("wrong password");
    return new Uint8Array(32);
  },
}));

/** Fresh module state per test — account and currentTier are module-level. */
async function load() {
  vi.resetModules();
  return import("./auth");
}

beforeEach(() => {
  h.session = null;
  h.signInUser = null;
  h.keyRecord = null;
  h.lookupFails = false;
  h.openKeyringFails = false;
  h.calls = [];
});

describe("restoreSession", () => {
  it("stays locked when the keyring lookup FAILS, and never falls through to plaintext", async () => {
    // The defect: .catch(() => null) conflated "no keyring" with "couldn't
    // check", so a blip on a cold start downgraded an encrypted account and
    // the next sync pushed note bodies in the clear.
    h.session = { user: emailUser };
    h.lookupFails = true;

    const auth = await load();
    expect(await auth.restoreSession()).toBe("locked");
    expect(h.calls).toContain("lock");
    expect(h.calls).not.toContain("plaintext");
  });

  it("locks when a keyring row exists", async () => {
    h.session = { user: emailUser };
    h.keyRecord = KEY_RECORD;

    const auth = await load();
    expect(await auth.restoreSession()).toBe("locked");
    expect(h.calls).not.toContain("plaintext");
  });

  it("reports no-keyring for a password account whose keyring row is missing", async () => {
    h.session = { user: emailUser };

    const auth = await load();
    expect(await auth.restoreSession()).toBe("no-keyring");
    expect(h.calls).toContain("lock");
    expect(h.calls).not.toContain("plaintext");
  });

  it("syncs plaintext for an OAuth account, which genuinely has no keyring", async () => {
    h.session = { user: githubUser };

    const auth = await load();
    expect(await auth.restoreSession()).toBe("plaintext");
    expect(h.calls).toContain("plaintext");
  });

  it("is signed-out with no session", async () => {
    const auth = await load();
    expect(await auth.restoreSession()).toBe("signed-out");
    expect(auth.currentAccount()).toBeNull();
  });
});

describe("signIn", () => {
  it("reports no-keyring for a password account whose keyring row is missing", async () => {
    h.signInUser = emailUser;

    const auth = await load();
    await auth.signIn("a@b.co", "pw");
    expect(auth.tier()).toBe("no-keyring");
    expect(h.calls).not.toContain("plaintext");
  });

  it("syncs plaintext for an OAuth-provisioned account given a password later", async () => {
    h.signInUser = githubUser;

    const auth = await load();
    await auth.signIn("a@b.co", "pw");
    expect(auth.tier()).toBe("plaintext");
    expect(h.calls).toContain("plaintext");
  });

  it("unlocks and reports encrypted when the keyring opens", async () => {
    h.signInUser = emailUser;
    h.keyRecord = KEY_RECORD;

    const auth = await load();
    await auth.signIn("a@b.co", "pw");
    expect(auth.tier()).toBe("encrypted");
    expect(h.calls).toContain("unlock");
  });

  it("leaves no half-signed-in state when the unwrap throws", async () => {
    // The defect: `account` was assigned before the throwing calls, so a
    // failure left currentAccount() populated while tier() read "signed-out".
    h.signInUser = emailUser;
    h.keyRecord = KEY_RECORD;
    h.openKeyringFails = true;

    const auth = await load();
    await expect(auth.signIn("a@b.co", "pw")).rejects.toThrow("wrong password");
    expect(auth.currentAccount()).toBeNull();
    expect(auth.tier()).toBe("signed-out");
    expect(h.calls).toContain("lock");
  });
});

describe("tierStatement", () => {
  it("does not blame GitHub for a password account", async () => {
    const auth = await load();
    expect(auth.tierStatement("plaintext", "email")).not.toMatch(/GitHub/);
  });

  it("names GitHub for an OAuth account", async () => {
    const auth = await load();
    expect(auth.tierStatement("plaintext", "github")).toMatch(/GitHub/);
  });

  it("keeps the GitHub warning when there is no account yet", async () => {
    // signInWithGitHub shows this BEFORE the user commits, when provider is
    // unknown. Defaulting the unknown case the other way would silently drop
    // the one warning §4a requires.
    const auth = await load();
    expect(auth.tierStatement("plaintext", undefined)).toMatch(/GitHub/);
  });

  it("promises encryption only on the encrypted tier", async () => {
    const auth = await load();
    expect(auth.tierStatement("encrypted")).toMatch(/can't read them/);
    expect(auth.tierStatement("no-keyring")).toMatch(/nothing syncs at all/);
  });
});
