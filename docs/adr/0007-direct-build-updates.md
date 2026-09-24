# ADR 0007 — The direct build announces updates; it does not fetch them

**Status:** accepted (Ryan, 2026-09-23) · **Date:** 2026-09-23 · **PR:** docs: ADR for the direct-build updater

The direct tier is Post-1.0 (`NetRelish_Plan_and_Roadmap.md` §5), so nothing is blocked
today. It is written now because the decision stops being free the moment the first
Developer ID binary is handed to anyone: an app can only update itself if the code that
checks for updates was compiled into it. A v1.0 with no updater cannot be reached by
v1.1. The fix is not retroactive; it is paid by whoever downloads first.

The App Store build is unaffected — the App Store is its update mechanism.

**The constraint.** Non-negotiable §5 lists every call the app may make: page loads,
StoreKit, RFC 3161 timestamping, and a one-time license activation. It closes with "Add
an endpoint and you've broken this rule." A Sparkle appcast is a new endpoint, polled on
a schedule. Choosing auto-update means amending a non-negotiable, not just adding a
dependency — which is a bigger decision than picking an updater, and is why this is an
ADR rather than a task.

**Decision.** The direct build ships with **no updater**. A new version is
announced by email to the address that bought the licence, and the app's About window
links to the download page. Nothing polls, nothing self-installs, and §5 stands
unamended.

**Why this is not a cop-out.** Every direct-tier user buys a licence, and §5 already
permits the activation call that accompanies it — so an address on file is not a hopeful
assumption, it is a property of the tier. Bento already holds those addresses and already
sends to them. The only thing lost is silence: the user is told and clicks, rather than
waking to a new version. For a paid tool sold to a small, known audience, that is a
reasonable trade and costs an afternoon rather than a framework.

**What would overturn it.** A direct tier large enough that email stops reaching people,
or a security fix that has to land without waiting on someone to read their inbox. Both
argue for Sparkle with an EdDSA-signed appcast — at which point §5 gains a fifth bullet
naming the update check, written deliberately and in the same commit.

**What must not happen.** A direct binary shipping before this is settled either way.
That is the one order-dependent part: an updater can be added in any release, but only
the users who already have one can receive it.
