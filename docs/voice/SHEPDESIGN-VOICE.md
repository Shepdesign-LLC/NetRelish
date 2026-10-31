# Shepdesign voice

**v1.1 · 2026-10-31.** How every string in a Shepdesign-built product is written:
UI, email, reports, errors, guides, and marketing.

> **Canonical copy:** `Shepdesign-LLC/NetRelish` → `docs/voice/SHEPDESIGN-VOICE.md`.
> **Mirror:** `Shepdesign-LLC/true-vet-value` → `docs/voice/SHEPDESIGN-VOICE.md`.
> Edit the canonical copy, bump the version and changelog, then copy the file
> **byte for byte** to every mirror in the same week. A mirror is never edited in
> place. Product-specific rules never go here; they go in the product's own layer
> (see "Two layers").

---

## Two layers

This file is the **house** layer: what is true of every product.

Each product adds a **product** layer on top, which holds its vocabulary,
register, banned words, punctuation rules, and examples. The product layer can
add rules and tighten them. It cannot loosen a house rule; that takes a version
bump here.

| Product | Product layer |
|---|---|
| NetRelish (and Zest) | `NetRelish/docs/voice/NETRELISH.md` |
| True Vet Value | `true-vet-value/docs/voice/TVV.md` |

---

## The test

Read the string out loud to the person it is for. If they stop to ask what a
word means, rewrite it. If they can act on it without a follow-up question,
ship it.

"The person it is for" is the product's reader, named in its product layer.
They are never us.

---

## Rules

**Say what happened, in a sentence.** A subject and a verb. Not a log line, not
an error code, not a status enum.

**Name the thing, then the consequence.** What it is doing to the reader
comes first; why comes second.

**Numbers get units and rounding.** "about 0.4s", not "412ms". "3 years", not
"1,094 days". "$50", not "50.00 USD".

**Second person, present tense, active voice.** "Open a jar and its tabs come
back." Not "Tabs will be restored when a jar is opened."

**No hedging.** "This jar is full." Not "It looks like this jar might be
full."

**Never claim more than is true.** Say exactly what we verified, stored,
encrypted, or promised, and no more. If a claim needs a caveat to be honest,
it is the wrong claim. This rule beats every marketing line.

**Dignity over hype.** Never salesy. No urgency we invented, no superlatives
we can't prove, no flattery.

**No AI filler.** No "seamlessly", "effortlessly", "unlock the power of",
"in today's fast-paced world", "it's important to note", or "delve". If a
sentence would survive in any product's copy, cut it.

**No exclamation marks.** No "Oops", no "Whoops", no "Uh-oh". No emoji in
product copy.

**Explain a mechanic once, where it happens.** Inline copy carries one line;
the guide or help page carries the long version.

**Never make the reader feel watched or judged.** Tell them what we see only
when it helps them act. Never imply they did something wrong.

---

## Words

**Write in the reader's words, not ours.** A technical word is allowed only
when the reader uses it in their own work. Each product layer lists the words
its reader does not use (the banned list) and the words it does (the
vocabulary).

**Our nouns are load-bearing.** Each product defines a small vocabulary and uses
it everywhere: UI, docs, support, and code identifiers. No synonyms, ever.

**Error and empty states are copy too.** They follow every rule above. "Nothing
in here yet." beats "No items to display."

---

## US English

Not negotiable, in every product:

> color · behavior · organize · recognize · optimize · license · centered ·
> gray · while · among · catalog · canceled

Not *colour*, *behaviour*, *organise*, *recognise*, *optimise*, *licence*,
*centred*, *grey*, *whilst*, *amongst*, *catalogue*, *cancelled*.

Run a check before every ship. It has slipped before.

---

## Punctuation

**Set per product, by decision** (Ryan, 2026-10-31). Each product layer states
its rule for **em-dashes** and **hyphenated compounds**. True Vet Value bans
both in customer copy; NetRelish uses em-dashes. Don't propose a house-wide
punctuation rule without new cause.

---

## Changelog

- **v1.1 (2026-10-31).** Ryan decided punctuation stays per product. Em-dash
  and hyphen rules live in each product layer for good, not pending a
  house-wide rule.
- **v1.0 (2026-10-31).** Lifted out of the NetRelish Workstation v5 handoff
  (`03-VOICE.md`, retitled "Shepdesign code voice" by Ryan), merged with True
  Vet Value's voice (`MISSION.md` principle 5, `tvv-dashboard/CLAUDE.md` copy
  standards). Product vocabulary, banned words, and punctuation moved to each
  product's layer. The jargon ban became a reader-relative rule, because True
  Vet Value's readers use "webhook" and "endpoint" in their own work.
