# ADR 0021 — How Reseal & diff works

**Status:** proposed · **Date:** 2026-11-05 · **PR:** feat(pro): Reseal & diff

ADR 0012 puts Reseal & diff in 1.0 as a Pro feature. The plan's demo: seal a pricing page, seal it again later, and the diff shows the price change.

- **Sealing again makes a new seal.** Seal Again loads the page off screen in its jar's own profile (the same path as Shortcuts' Seal with a link) and seals it into the same jar. The earlier seal, its saved copy and its text are never touched (non-negotiable 3). A page's seals are every sealed item with its URL, newest first. No schema change.
- **What's compared is the text frozen at each Seal**, never the live page or its DOM (non-negotiable 4; the plan's risk table: "diff extracted text, not DOM"). That text is stored as one run of words, so the two seals are lined up sentence by sentence, and a changed sentence is compared word by word. It's pure Swift, using the standard library's difference algorithm. No model, no network.
- **Where it's shown (Ryan, Nov 5):** on the Bench, side by side, older seal on the left and newer on the right, in one scroll so the columns stay lined up. Done or Escape goes back.
- **How it looks (Ryan, Nov 5): monochrome.** Removed words are struck through in `--nr-fg-3`, added words are underlined in `--nr-fg`, and changed rows sit on `--nr-surface-2`. No new tokens, no relish (manifest §4). VoiceOver reads "Removed:" and "Added:" because strikethrough and underline aren't spoken.
- **Where you start it:** the Panel's new Seals section on a sealed page lists its seals, and has Seal Again and Compare (the two most recent seals).
- **Pro, for now (Ryan, Nov 5): ungated.** Buying Pro isn't built yet, so one check, `Pro.isUnlocked`, returns yes, and Reseal & diff can be demoed. When StoreKit and the direct build's license key land, that check is the only thing that changes.
- **Speed:** the plan's budget is 1 second for a 2 MB page. A test compares a 2 MB page with one edit and prints the time, so it's measured on every CI run. The comparison runs off the main thread, so the window never stalls. The same start and end of the two pages are set aside first; if the middle that's left is still huge (a page rewritten end to end), it's shown as removed, then added, without lining it up.
- **Proposed follow-ups:**
  - Keep paragraph breaks in the text frozen at Seal, so later comparisons can line up by paragraph as well as sentence. Earlier seals keep working sentence by sentence.
  - A "layout changed" line for pages whose text is the same but whose saved copy differs (the plan's risk table).
  - Choosing any two seals to compare, not just the latest two.
  - A seal stores the address the page ended up at. A page that redirects, or adds to its address, is sealed again under the new address, so its Seals list starts over. Matching on the address that was asked for would keep them together.
  - A long run of text with no sentence punctuation is cut every 400 characters, counted from its start. One word added early moves every later cut, so the whole run shows as changed.
