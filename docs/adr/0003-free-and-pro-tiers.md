# ADR 0003 — What Free and Pro contain

**Status:** accepted (Ryan, 2026-09-16) · **Date:** 2026-09-16 · **PR:** netrelish-site v1

The roadmap fixes the prices — Free, and Pro at $39/yr or $99 lifetime — but nowhere
says which features sit on which side. The site needs the split now; P4 (Pro gating)
needs it later. Ryan's Sept 12 site draft carried a split, and he adopted it.

**Decision:**

| Free | Pro |
|---|---|
| Capture, jars, seal, full-text search | Everything in Free |
| 3 Recipes | Unlimited Recipes |
| Share extension, Spotlight, Shortcuts | Reseal and diff — seal a page again, see what changed |
| | Provenance — RFC 3161 timestamp and fingerprint on every seal, exportable |
| | Jar bundles — share a whole jar over AirDrop, no account either end |
| | Semantic search across everything sealed |

Pro is one price with no seats and no telemetry, bought on the App Store or (Direct
build) from the site. The site's pricing block ends with "Buy once, use forever."

P4 gates exactly this list. Adding a Pro item is a new ADR, not a site edit.
