# ADR 0004 — The diagram generates the Pantry's shape; its behavior is mirrored by hand

**Status:** proposed · **Date:** 2026-09-19 · **PR:** p0: pantry from mson

CLAUDE.md says System Designer is the design of record and Swift is regenerated from it,
never the reverse; `method` bodies "mirror the JS behavior in the bundle". A generator can
turn schemas, models, types, events and components into Swift mechanically. It cannot turn
JavaScript into Swift.

**Decision.** Two layers, with a compile-time seam between them:

- `scripts/gen-pantry.swift` generates `Sources/Pantry/Models/` — every enum, one GRDB
  record per schema (columns, links as foreign keys, collections as associations or join
  tables), an `AsyncStream` per event, the table definitions (`PantrySchema`), the seed rows
  (`PantrySeed`), and **a `<Model>Methods` protocol per model** listing each method with its
  JavaScript body quoted above the requirement. CI diffs the directory against a fresh run.
- `Sources/Pantry/Behaviors/<Model>+Behavior.swift` is hand-written and conforms each record
  to its protocol. A method that exists in the diagram and not in Swift is a compile error;
  a body that drifts from the JS is visible in the same file's doc comment.

**Migrations.** `PantrySchema.create` is generated and is what `V1` calls today. Once V1 has
shipped it is frozen; later diagram changes regenerate `PantrySchema` (the target shape) and
get a hand-written `V2`, `V3`… that moves the real database toward it.

**What this gives Prompt 4.** Change a property in `NetRelish.json`, regenerate, and the diff
is confined to `Sources/Pantry/Models/`. Change a method body and the diff is a doc comment
plus whatever hand-written mirror the reviewer updates to match.

**Pre-1.0 addendum (2026-09-21).** Until V1 ships, DEBUG builds set GRDB's
`eraseDatabaseOnSchemaChange`: a dev Pantry whose schema no longer matches the generated
`PantrySchema` is discarded, not migrated. Release builds never do this. Removed at 1.0,
when V1 freezes and V2 begins.
