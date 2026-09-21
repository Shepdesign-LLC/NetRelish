# ADR 0005 — A jar's color is the user's data, not a chrome accent

**Status:** proposed · **Date:** 2026-09-21 · **PR:** p1: shelf

The manifest allows one accent (relish) and kills "any second accent" (§3). Ryan asked
for jars to be colored, named, and given a shelf life. The diagram already carries
`Jar.tint`, `Jar.name`, `Jar.shelfLifeDays`.

**Decision.** A jar's tint is content, like a Finder tag color: chosen by the user in the
New Jar sheet, stored on the row as an OKLCH string, and painted on **that jar's glyph on
the Shelf only**. It never colors chrome, text, backgrounds, buttons, or the active-row
tint — that stays `relish100`. No palette is added to `tokens.css`; the picker is the
system color picker and `Sources/UI/OKLCH.swift` converts at runtime.

**Why this isn't a second accent.** An accent is a color the *system* applies to signal
state. A tint is a color the *user* applies to distinguish their own objects. The
manifest's rule is about the former.
