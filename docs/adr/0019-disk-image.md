# ADR 0019 — The disk image opens to a window laid out to the brand

**Status:** proposed · **Date:** 2026-11-02 · **PR:** feat(shortcuts): Capture, a full Seal, Open a Jar, Search (with the disk image)

The Developer ID disk image was a bare `hdiutil` folder: Finder's default window, icons wherever they fell, a generic disk icon. It now opens to a 640 × 400 window built from the manifest:

- **Base:** `--nr-bg`, with a footer on `--nr-surface-2` under a `--nr-hairline` rule (§3, §6). One line of copy in the system font at `--fs-md`, `--nr-fg-2`: "Drag NetRelish into Applications."
- **Objects:** NetRelish and Applications at 128 pt, side by side, with a 1.5 pt arrow in `--nr-fg-3` between them. No relish, because the disk image isn't on the §4 list. The mark appears as the app's icon and as the disk's own icon, never drawn into the background (§2).
- **Light only:** Finder draws any window that has a background picture in Light Mode, whatever the system appearance, so the light tokens are correct in both.
- **How:** `scripts/dmg/gen-dmg-background.swift` draws the art at 1× and 2× with AppKit, so the type is the real system font. `dmgbuild` (MIT, pinned by hash) writes the Finder window without scripting Finder. `scripts/dmg/layout.json` holds every position, so the art and the window agree. The release job calls `scripts/dmg/make-dmg.sh` and then signs, notarizes and staples as before. `dmg-preview.yml` puts a picture of the window on any PR that changes it.
