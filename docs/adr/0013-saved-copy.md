# ADR 0013 — "Saved copy" is the word for a sealed page's frozen view

**Status:** proposed · **Date:** 2026-11-01 · **PR:** fix(bench): the saved copy stays frozen

A sealed item opens its `.webarchive` read only; the UI and the code call that a **saved copy** (`Workbench.savedCopy`, `SavedCopyView`), never "sealed copy", "snapshot view" or "archive". It is not a **local copy**, which stays the Pickle word for a WordPress site on this Mac (workstation v5 spec §1, ADR 0010 row 9).
