# ADR 0006 — Identity lives in the Keychain, not the Pantry

**Status:** accepted 2026-09-21

The Me card (name, email, phone, address; later cards and IDs) is stored as device-only,
non-synchronizing Keychain items, not as rows in the Pantry and not in `design/NetRelish.json`.
It is not browsing data. Keeping it out of GRDB keeps it out of FTS, sqlite-vec, and every
intelligence path by construction (non-negotiables 4 and 5), and lets the OS — not the app —
guard access to any private-tier field.
