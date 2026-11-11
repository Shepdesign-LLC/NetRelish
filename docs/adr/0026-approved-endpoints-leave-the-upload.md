# ADR 0026 — An approved endpoint isn't uploaded as an alert

**Status:** accepted · **Date:** 2026-11-11 · **PR:** ci(codeql): the gate decides what code scanning sees

**The problem.** The timestamp request (ADR 0022) is one of the four network calls rule 5 allows. It carries `NETRELISH-ALLOW-ENDPOINT: adr-0022`, and the build gate passes it. Code scanning can't read that comment, though, so the Security tab listed it as two open "Outbound network call in app code" alerts (#4 and #5), both High. Dismissing them there by hand doesn't last: it's invisible from the repository, and an edit that moves the call to another line closes the old alert and opens a new one. #5 appeared exactly that way.

**What changed.** `Analyze (swift)` no longer uploads its own SARIF. `scripts/codeql_gate.py` judges it as before and also writes a copy for code scanning. A call is left out of that copy only when two things hold:

- **The gate approves it:** one gate finding on its line, and a real `//` marker on that line or the one above citing an ADR that exists.
- **It's listed in `.github/codeql/approved-endpoints.txt`** as `path  API  adr-NNNN`, with the same ADR its marker cites and the API the query reports. Each line covers one call. Today there are two lines, both the timestamp request.

Everything else is uploaded unchanged: a call with no marker, a marker in a string or block comment, an ADR that doesn't exist, two calls on one line, a finding outside the checkout, a different call put under an approved marker, a second call of the same API, an approved call nobody listed, and every other query's results. The upload happens before the job fails, so an unapproved call is still an alert on the pull request that adds it. A flaw in the list itself (a bad line, a missing ADR, a path outside the checkout, a symlink) fails the gate.

**Why the list.** A marker can cite any ADR that exists, and the gate accepts that; the gate has always worked that way. If a marker alone also took the call out of code scanning, a new endpoint with a marker citing an unrelated ADR would pass the gate and leave no alert anywhere. Review of this change found exactly that. The list keeps the Security tab as the second signal for anything that isn't one of the endpoints rule 5 names, and adding to it is a visible line in the same pull request as the ADR that approves it.

**Why this way.** The marker beside the code stays the approval, as `codeql_gate.py` already insists. Nothing is dismissed in the Security tab, and nothing there can approve a call. The query is unchanged, so the gate still sees every call it matches, and it prints each approved one on every run, saying whether it's listed. Tests in `scripts/tests/test_codeql_gate.py` hold each case above, and one checks that every listed call still has its marker.

**What happens to #4 and #5.** Both are listed, so the first upload from main without them closes both as fixed. If the API names in the list don't match what the query reports, they stay open, and the gate's notice on each says which line to write.
