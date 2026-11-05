# ADR 0020 — How Seal & Summarize works

**Status:** proposed · **Date:** 2026-11-05 · **PR:** feat(recipes): Seal & Summarize

ADR 0012 ships one built-in Recipe in 1.0, "Seal & Summarize", using on-device Foundation Models. V1 seeded its Recipe row with no steps, and no jar used it, so a Seal ran nothing.

- **Every jar runs it.** Migration V2 gives the Recipe one step (`summarize`) and makes it the default Recipe of every jar that has none. New jars get it too. Choosing another Recipe per jar comes with the Recipe picker.
- **Seal stays instant.** The Recipe runs inside Seal's write, as before; the `summarize` step itself is still a no-op in the Pantry, exactly as the diagram says. A `SummaryWorker` writes the summary afterwards, off the main thread. Seal never waits on the model.
- **Nothing is queued in memory.** "Waiting for a summary" is a question the Pantry answers: a sealed item whose last Recipe run had a summarize step and has no summary yet. A page sealed just before quitting is summarized at next launch.
- **Where it's stored:** `Item.meta["summary"]` (`status`, and `text` or `reason`), beside the keys already there. No schema change, so no System Designer round trip for 1.0. If summaries need to be searchable or sortable later, they become a real `summary` property in the diagram first.
- **It never touches the snapshot.** Like labels, a summary is metadata about a sealed page. The `.webarchive`, `body` and `sealedAt` are unchanged (non-negotiable 3).
- **The model reads sealed text only** (non-negotiable 4). `SealedText` can only be made from a sealed item, from the title and the Defuddle text frozen at Seal, cut to about 6,000 characters. It's told the page is material to summarize, never instructions.
- **On-device only** (non-negotiable 5). Apple's model through Foundation Models: no network, no account. If Apple Intelligence is off or this Mac can't run it, the Panel says so in one line, and the page is summarized once it's available. While the model is still downloading, pages wait, and the app looks again every minute and whenever you come back to it. A model failure (often passing: busy, or limited in the background) gets three tries across sweeps, then the page is marked failed.
- **Where you see it:** the Panel's Summary section, and the Summary property of Shortcuts' Pantry Item, so a Shortcut can pass it on.
- **Proposed follow-up:** add the summarize step and the jars' default Recipe to the System Designer components, so the diagram matches V2 the next time `/design/NetRelish.json` is synced.
