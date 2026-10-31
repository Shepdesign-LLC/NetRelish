# Shepdesign code voice. How every string is written

> **Superseded (2026-10-31).** This guide now lives in two files:
> `docs/voice/SHEPDESIGN-VOICE.md` (house rules, shared across Shepdesign
> products) and `docs/voice/NETRELISH.md` (NetRelish vocabulary, banned words,
> examples). Edit those, not this.

The interface talks. This is how.

The user builds WordPress sites for clients. They are smart and they are not a sysadmin. Write for someone who will happily learn a new idea — *jar*, *brine*, *seal* — and who will close the app the moment it shows them a stack trace.

---

## The test

Read the string out loud to someone who doesn't write code. If they stop to ask what a word means, rewrite it. If they can act on it without a follow-up question, ship it.

---

## Rules

**Say what happened, in a sentence.**

> A plugin is slowing one of your clients' sites down. Old Slider adds about 0.4s to every page and hasn't been updated in 3 years.

Not a log line, not an error code, not a severity enum. A sentence with a subject and a verb.

**Name the thing, then the consequence.** "Old Slider adds about 0.4s" before "hasn't been updated in 3 years." What it's doing to you first; why, second.

**Numbers get units and rounding.** "about 0.4s", not "412ms". "3 years", not "1,094 days".

**Never make the user feel watched.** Dev's footer reads: *"Only you see this. Turn Dev off and it's a normal browser."*

**Explain the mechanic once, where it happens.** The seal banner doesn't just say the jar is full — it says capacity can be raised instead. Guide pages carry the long version; inline copy carries one line of it.

**Second person, present tense, active voice.** "Open a jar and its tabs come back." Not "Tabs will be restored when a jar is opened."

**No exclamation marks.** No "Oops". No "Whoops". No emoji in product copy.

**No hedging.** "This jar is full." Not "It looks like this jar might be full."

---

## Banned words

These never appear in the UI, in any state, behind any toggle:

> terminal · command line · CLI · WP-CLI · SQL · query · stdout · stderr · webhook · endpoint · payload · daemon · instance · container · provision · deprecated · stack trace · exception

And these are banned as *labels for our own things*, because they overwrite the vocabulary:

> folder · workspace · collection · bookmark · trash · history · inspector · sidebar · drawer

---

## Vocabulary

The nouns are load-bearing. Full table in `01-SPEC.md` §1. Short version:

**jar** (a project) · **note** · **tab** (a website) · **keep** (put a tab in a jar) · **seal** (finish a jar) · **brine** (where tabs age out) · **fill** · **shelf** (left) · **bench** (middle) · **panel** (right) · **vault** · **local copy**

Use them consistently in code too. A CSS class called `.sidebar` is a bug.

---

## Examples

| Instead of | Write |
|---|---|
| Error: ENOENT — site directory not found | We can't find juniperbakery.example on this Mac. It may have been moved or renamed. |
| Site provisioning failed | juniperbakery.example didn't start. Try starting it again — if that doesn't work, its files may have moved. |
| 3 items in trash | Brine · 3 |
| Delete jar? This cannot be undone. | Archive jar — *(toast: "Archived. Undo")* |
| Capacity exceeded | This jar is full. |
| Export plugin as .zip archive | ZIP |
| Credentials vault — authenticate to decrypt | Locked. Touch ID to reveal. |
| Toggle developer tools | Dev |
| No items to display | Nothing in here yet. |

---

## US English

Not negotiable:

> color · behavior · organize · recognize · optimize · license · centered · gray · while · among · catalog · canceled

Not *colour*, *behaviour*, *organise*, *recognise*, *optimise*, *licence*, *centred*, *grey*, *whilst*, *amongst*, *catalogue*, *cancelled*.

Run a check before every ship. It has slipped before.
