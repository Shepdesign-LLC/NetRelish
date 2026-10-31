# NetRelish voice — product layer

Sits on top of the house voice, [`SHEPDESIGN-VOICE.md`](SHEPDESIGN-VOICE.md).
Read that first. This file adds; it never loosens.

Covers NetRelish.app and the Zest tools.

---

## The reader

Someone who builds websites for clients. Smart, busy, not a sysadmin. They will
happily learn a new idea (*jar*, *brine*, *seal*) and will close the app the
moment it shows them a stack trace.

---

## Vocabulary

The full table, with "never call it" synonyms, is `CLAUDE.md` § Vocabulary
together with `docs/design/workstation-v5/docs/01-SPEC.md` §1. Where they
differ, ADR 0010 says which one wins. Short version:

**Pantry · jar** (a project; also a profile) · **note** · **tab** (a website) ·
**keep** (put a tab in a jar) · **seal** · **brine** (where idle tabs sink) ·
**fill** · **shelf** (left) · **bench** (middle) · **panel** (right) ·
**vault** · **local copy** · **recipe** · **Ask the Pantry**

Use them in code too. A CSS class or Swift type called `Sidebar` is a bug.

---

## Banned words

These never appear in the UI, in any state, behind any toggle:

> terminal · command line · CLI · WP-CLI · SQL · query · stdout · stderr ·
> webhook · endpoint · payload · daemon · instance · container · provision ·
> deprecated · stack trace · exception

These are banned as *labels for our own things*, because they would overwrite
the vocabulary:

> folder · workspace · collection · bookmark · trash · history · inspector ·
> sidebar · drawer

Privacy copy never says "end-to-end encrypted", "we can't read", or "E2E"
unless that claim has been verified for the exact data it describes. This is
the house rule "Never claim more than is true", applied (see
`docs/design/README.md`).

---

## Punctuation

Em-dashes are allowed. Use them for an aside or a consequence, not as a
reflexive comma. Hyphenate compounds normally.

---

## Fixed lines

| Where | Line |
|---|---|
| Dev panel footer | Only you see this. Turn Dev off and it's a normal browser. |
| Seal banner | This jar is full. *(plus one line saying capacity can be raised instead)* |
| Vault, locked | Locked. Touch ID to reveal. |
| Archive toast | Archived. Undo |
| Empty state | Nothing in here yet. |

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
| A plugin issue was detected | A plugin is slowing one of your clients' sites down. Old Slider adds about 0.4s to every page and hasn't been updated in 3 years. |

Client names in examples are always made up (`*.example`, `*.local`). This repo
is public.
