# ADR 0029 — Pickle is now Mason Jar

**Status:** accepted for the name (Ryan, Nov 13) · **Date:** 2026-11-13 · **PR:** feat(shelf): right-click menus and drag for jars and tabs

Ryan, Nov 13: "change the word pickle to Mason Jar when introducing the local development switch."

**Decision:** the jar with a local dev environment is a **Mason Jar**, and the switch that turns local development on is the **Mason Jar** switch. This replaces "Pickle" everywhere, and it replaces "Dev" as the user-facing name ADR 0010 row 7 gave that switch. What it is and when it ships don't change: direct build only, 1.2.

## What changed in this PR

| Where | Before | After |
|---|---|---|
| `CLAUDE.md` vocabulary, stack, mapping, layout, roadmap | Pickle, `Pickle: Jar`, `/Sources/Pickle/` | Mason Jar, `MasonJar: Jar`, `/Sources/MasonJar/` |
| `design/symbols.svg`, manifest §7, `NRSymbol`, `NRJarGlyph` | `#nr-jar-pickle`, `.jarPickle`, `.pickle` | `#nr-jar-mason`, `.jarMason`, `.mason` |
| Roadmap §10 and the planned schema | `Pickle`, `PickleRuntime`, `sealPickle`, `.pickle` bundles | `MasonJar`, `MasonJarRuntime`, `sealMasonJar`, `.masonjar` bundles |
| Voice (`docs/voice/NETRELISH.md`), `docs/ROADMAP.md`, `docs/SYSTEM_DESIGNER.md`, `docs/KICKOFF.md`, `project.yml` | Pickle | Mason Jar |

The symbol's drawing is the same jar with `</>`. Only its name moved, so the manifest notes it under v1.3 and nothing visual changes.

## What was left alone

- **Accepted ADRs** (0010, 0013, 0016) and the dated plans under `docs/superpowers/` keep the word they were written with. Read "Pickle" there as Mason Jar.
- **`.github/workflows/codeql.yml`** has one comment that says Pickle. It changes the next time that file is edited for a reason of its own.
- **Nothing in the model.** `MasonJar` isn't in System Designer yet; it is added under that name when 1.2 starts.

## Open for Ryan

1. In running copy, is it "a Mason Jar" (capital M, capital J) every time? This PR writes it that way.
2. Does the switch's label read just "Mason Jar", or "Mason Jar mode"? Proposed: just "Mason Jar".
