# ADR 0026 — An approved endpoint isn't uploaded as an alert

**Status:** accepted · **Date:** 2026-11-11 · **PR:** ci(codeql): the gate decides what code scanning sees

**The problem.** The timestamp request (ADR 0022) is one of the four network calls rule 5 allows. It carries `NETRELISH-ALLOW-ENDPOINT: adr-0022`, and the build gate passes it. Code scanning can't read that comment, though, so the Security tab listed it as two open "Outbound network call in app code" alerts (#4 and #5), both High. Dismissing them there by hand doesn't last: it's invisible from the repository, and an edit that moves the call to another line closes the old alert and opens a new one. #5 appeared exactly that way.

**What changed.** `Analyze (swift)` no longer uploads its own SARIF. `scripts/codeql_gate.py` judges it as before and also writes a copy without the findings it approved. That copy is what goes to code scanning. A finding is left out only when the gate would pass it: one gate finding on its line, and a real `//` marker on that line or the one above citing an ADR that exists. Everything else is uploaded unchanged: a call with no marker, a marker in a string or block comment, an ADR that doesn't exist, two calls on one line, a finding outside the checkout, and every other query's results. The upload happens before the job fails, so an unapproved call is still an alert on the pull request that adds it.

**Why this way.** The marker beside the code stays the only approval, as `codeql_gate.py` already insists. Nothing is dismissed in the Security tab, and nothing there can approve a call. The query is unchanged, so the gate still sees every call it matches and still prints each approved one on every run. The filter uses the gate's own approval, so the two can't disagree. Tests in `scripts/tests/test_codeql_gate.py` hold each case above.

**What happens to #4 and #5.** The first upload from main without them closes both as fixed.
