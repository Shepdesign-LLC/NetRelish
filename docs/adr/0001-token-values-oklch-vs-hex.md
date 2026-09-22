# ADR 0001 — Which column of tokens.css is the truth: OKLCH or the hex fallback?

**Status:** accepted — option 1 · **Date:** 2026-09-16 · **PR:** design-system: swift token bridge

`design/tokens.css` says "Colors are authored in OKLCH; hex fallbacks are the sRGB render."
The two columns disagree. Converting each OKLCH value exactly gives a different color than
the hex beside it, and the drift runs one way — darker:

| token | OKLCH renders | hex says |
|---|---|---|
| `--relish-500` | `#9CE700` | `#93E413` (named as *the* relish in CLAUDE.md and the manifest) |
| `--nr-fg` (light) | `#12120F` | `#1D1D1B` |
| `--nr-bg` (dark) | `#090907` | `#171716` |
| `--relish-ink` | `#122505` | `#1E3A12` |

Every color token is off; these are the visible ones. `scripts/gen-tokens.swift` warns on
each mismatch, and `Tests/NRUITests/TokenTests.swift` fails until the file agrees with itself.

**Options**
1. **Hex wins.** Re-derive the OKLCH numbers from the hexes (exact conversions are in the PR)
   and bump tokens.css to v1.1.1 with a changelog line. The app then matches the mocks and
   `#93E413` stays the relish. *Recommended.*
2. **OKLCH wins.** Rewrite the hex comments to the true renders. Dark mode becomes near-black
   and relish becomes `#9CE700`; the brand hex in CLAUDE.md and the manifest would need editing.

**Decision (Ryan, 2026-09-16):** option 1. Every OKLCH value in `tokens.css` is now the exact
conversion of its hex; `--relish-ink` dark, which had no hex, gained one (`#030C00`) from its
OKLCH. `tokens.css` and the manifest are v1.1.1. `scripts/gen-tokens.swift` emits no warnings
and `TokenTests.colorsMatchHexFallbacks` passes.
