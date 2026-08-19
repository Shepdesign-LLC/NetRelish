import { useCallback, useEffect, useState } from "react";
import {
  signIn, signUp, signOut, signInWithGitHub, restoreSession, unlock,
  unlockWithRecoveryCode, tier, currentAccount, tierStatement, type Tier,
} from "../lib/auth";
import { syncNow, type SyncResult } from "../lib/sync";

interface Props {
  onClose(): void;
}

type Mode = "in" | "up";

/**
 * NetRelish ID — sign in, and the privacy tier stated in words.
 *
 * CLAUDE.md §4a requires two things of this surface, and both are the point of
 * it rather than decoration: account settings must show which tier the account
 * is on in plain words (not a padlock icon), and the product may never tell an
 * OAuth user their notes are private even from us.
 *
 * So the tier sentence is shown BEFORE the GitHub button, not after.
 */
export default function AccountView({ onClose }: Props) {
  const [t, setT] = useState<Tier>(tier());
  const [mode, setMode] = useState<Mode>("in");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [recoveryCode, setRecoveryCode] = useState<string | null>(null);
  const [result, setResult] = useState<SyncResult | null>(null);

  useEffect(() => {
    void restoreSession().then(setT).catch(() => setT("signed-out"));
  }, []);

  const run = useCallback(async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      setT(tier());
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }, []);

  const account = currentAccount();
  const signedIn = t !== "signed-out";

  const doSync = () =>
    run(async () => {
      const acc = currentAccount();
      if (!acc) throw new Error("Sign in first.");
      setResult(await syncNow(acc.id));
    });

  return (
    <div className="nr-account">
      <header className="nr-account__head">
        <h1>NetRelish ID</h1>
        <button className="nr-account__close" onClick={onClose} aria-label="Close">
          Done
        </button>
      </header>

      {/* §4a: the tier, in words, before anything else. */}
      <p className="nr-account__tier" data-tier={t}>
        {tierStatement(t)}
      </p>

      {!signedIn && (
        <>
          <div className="nr-account__tabs" role="tablist">
            <button role="tab" aria-selected={mode === "in"} onClick={() => setMode("in")}>
              Sign in
            </button>
            <button role="tab" aria-selected={mode === "up"} onClick={() => setMode("up")}>
              Create an ID
            </button>
          </div>

          <label className="nr-account__field">
            <span>Email</span>
            <input
              type="email" value={email} autoComplete="username"
              onChange={(e) => setEmail(e.target.value)}
            />
          </label>
          <label className="nr-account__field">
            <span>Password</span>
            <input
              type="password" value={password}
              autoComplete={mode === "up" ? "new-password" : "current-password"}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>

          <button
            className="nr-account__go" disabled={busy || !email || !password}
            onClick={() =>
              run(async () => {
                if (mode === "up") {
                  const r = await signUp(email, password);
                  setRecoveryCode(r.recoveryCode);
                } else {
                  await signIn(email, password);
                }
                setPassword("");
              })
            }
          >
            {busy ? "Working…" : mode === "up" ? "Create ID" : "Sign in"}
          </button>

          <button
            className="nr-account__github" disabled={busy}
            onClick={() => run(signInWithGitHub)}
          >
            Continue with GitHub
          </button>
        </>
      )}

      {t === "locked" && (
        <>
          <label className="nr-account__field">
            <span>Password</span>
            <input
              type="password" value={password} autoComplete="current-password"
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>
          <button
            className="nr-account__go" disabled={busy || !password}
            onClick={() => run(async () => { await unlock(password); setPassword(""); })}
          >
            Unlock notes
          </button>
          <button
            className="nr-account__link" disabled={busy}
            onClick={() =>
              run(async () => {
                const code = window.prompt("Recovery code (ABCDE-FGHIJ-KLMNO-PQRST)");
                if (code) await unlockWithRecoveryCode(code);
              })
            }
          >
            Use a recovery code instead
          </button>
        </>
      )}

      {signedIn && (
        <div className="nr-account__signed">
          <p className="nr-account__who">
            {account?.email ?? "signed in"}
            <span className="nr-account__provider">{account?.provider}</span>
          </p>
          <button className="nr-account__go" disabled={busy} onClick={doSync}>
            {busy ? "Syncing…" : "Sync now"}
          </button>
          <button className="nr-account__link" disabled={busy} onClick={() => run(signOut)}>
            Sign out
          </button>
        </div>
      )}

      {recoveryCode && (
        <div className="nr-account__recovery" role="alert">
          <p><strong>Write this down now. It is shown once.</strong></p>
          <code>{recoveryCode}</code>
          <p>
            If you forget your password, this code is the only way back to your
            notes. Without it they cannot be recovered — not by you, not by us.
          </p>
          <button onClick={() => setRecoveryCode(null)}>I've written it down</button>
        </div>
      )}

      {result && (
        <p className="nr-account__result">
          {result.error
            ? `Sync failed: ${result.error}`
            : `Pushed ${Object.values(result.pushed).reduce((a, b) => a + b, 0)}, ` +
              `pulled ${Object.values(result.pulled).reduce((a, b) => a + b, 0)}.`}
        </p>
      )}

      {error && <p className="nr-account__error" role="alert">{error}</p>}
    </div>
  );
}
