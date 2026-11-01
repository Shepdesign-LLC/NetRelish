# ADR 0014 — What fills each smart jar

**Status:** proposed · **Date:** 2026-11-01 · **PR:** feat(shelf): Today, Sealed and Sinking soon join Brine

**Brine** stays `jar == nil && state == .brined`. **Today** is every item created since local midnight, in any jar. **Sealed** is `state == .sealed`, most recently sealed first. **Sinking soon** is open tabs in the last tenth of their jar's shelf life (`ShelfLife.isFading`, the same tabs the strip fades), soonest first. Only Brine and Sinking soon show a count on the Shelf (manifest §4 placement 6), and Sinking soon reads "Sinking" on the 56pt rail.
