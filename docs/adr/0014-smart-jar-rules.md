# ADR 0014 — What fills each smart jar

**Status:** proposed; the shortcut line decided by Ryan, Nov 1 2026 · **Date:** 2026-11-01 · **PR:** feat(shelf): Today, Sealed and Sinking soon join Brine

**Brine** stays `jar == nil && state == .brined`. **Today** is every item created since local midnight, in any jar. **Sealed** is `state == .sealed`, most recently sealed first. **Sinking soon** is open tabs in the last tenth of their jar's shelf life (`ShelfLife.isFading`, the same tabs the strip fades), soonest first. Only Brine and Sinking soon show a count on the Shelf (manifest §4 placement 6), and Sinking soon reads "Sinking" on the 56pt rail.

**Open from Today or ⌘K** goes to the item's tab if one is already open in any jar; otherwise it opens in the item's jar, or the jar it sank from (as Restore does), or where ⌘T would. **Shortcuts:** ⌘⇧3 and ⌘⇧4 are macOS's default screenshot keys and never reach the app, so the manifest's ⌘⇧1–4 can't work for Sealed and Sinking soon. Ryan chose **⌃⌘1–4** for all four; the manifest's §8 Shelf row now says so, and `SmartJar.shortcutModifiers` holds it in one place.
