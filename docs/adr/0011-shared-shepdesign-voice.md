# ADR 0011 — One house voice, shared across Shepdesign products

**Status:** proposed · **Date:** 2026-10-31 · **PR:** docs(voice): the Shepdesign voice, house + product layers

Ryan retitled the v5 handoff's voice guide "Shepdesign code voice", which makes it
a studio standard rather than a NetRelish one. It now has two layers. The
**house** layer (`docs/voice/SHEPDESIGN-VOICE.md`) holds what is true of every
product. A **product** layer (`docs/voice/NETRELISH.md` here, `docs/voice/TVV.md`
in true-vet-value) adds vocabulary, banned words, punctuation, and examples. A
product layer may tighten the house rules, never loosen them.

The canonical house file lives in this repo, because it is public and the other
repos can link to it. Each other repo carries a byte-identical mirror. If a
`Shepdesign-LLC` house repo is ever created, the canonical copy moves there and
this ADR is superseded.

The jargon ban became reader-relative ("use a technical word only when the
reader uses it in their own work"), because True Vet Value's customers do use
"webhook" and "endpoint". Em-dash and hyphen rules stay per product, by Ryan's
decision on 2026-10-31 (house voice v1.1).
