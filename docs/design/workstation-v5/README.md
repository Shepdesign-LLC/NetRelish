# NetRelish Workstation — handoff

> **In this repo (read first).** This bundle landed on 2026-10-31 as the design
> **target** for the workstation shell: layout, interactions, and voice. It is
> a reference, not a replacement for the repo's contract. `CLAUDE.md` is still
> law, and `/design` (`DESIGN_MANIFEST.md`, `tokens.css`, `symbols.svg`) is
> still the design of record until Ryan amends it.
>
> - **Conflicts with the locked rules** (web-UI shell, separate models, glass,
>   whole-jar Seal, Dev vs. Pickle and more) are listed in
>   [`docs/adr/0010-workstation-v5-handoff.md`](../../adr/0010-workstation-v5-handoff.md),
>   each with a proposed default. Where the ADR says "the repo stands," build
>   the repo's way.
> - **`design/tokens.css` here is reference only.** `Sources/UI/Tokens.swift`
>   is still generated from `/design/tokens.css`. Merging v5 values into it is
>   a manifest version bump.
> - **`assets/netrelish-mark.svg` is not `/design/logo-cog.svg`.** It is a
>   variant whose gradient IDs carry an `nr-` prefix. Which one is the mark is a
>   brand decision (ADR 0010).
> - **v5 dropped two decisions from 2026-10-21:** the jar-fill drip (Brand
>   Lock v1.2) and Markdown notes. Both still stand. The previous prototype,
>   `../netrelish-workstation.html`, is kept because it implements both.
> - **`docs/03-VOICE.md` is superseded** by `docs/voice/SHEPDESIGN-VOICE.md`
>   (house) and `docs/voice/NETRELISH.md` (product). It is kept here as
>   delivered.
> - **Scrubbed on landing:** real client names, domains, a contact's name,
>   billing details and a login were replaced with made-up ones (Juniper Bakery,
>   Harbor Signs, Bright Trails; `*.example` / `*.local`). Guide copy that broke
>   the bundle's own voice rules ("recognise", "sidebar") was fixed. Keep
>   real client data out of this public repo.
>
> Everything below is the handoff as delivered.

Everything needed to build the workstation shell. Written for Claude Code. You should not need to ask a question before you start.

```
handoff/
├── README.md                          ← you are here. Read §Constraints before anything.
├── docs/
│   ├── 01-SPEC.md                     the build sheet. Layout, components, data model, interactions.
│   ├── 02-BUILD-ORDER.md              six phases, each with a checklist and a "done when".
│   └── 03-VOICE.md                    how every string in the product is written.
├── design/
│   └── tokens.css                     the only place color, type and timing are defined.
├── assets/
│   └── netrelish-mark.svg             the real NetRelish mark. Do not redraw it.
└── prototype/
    ├── netrelish-workstation.html     the app, v5. Open it. This is the target.
    └── netrelish-beta.html            the marketing/beta page, for the jar renderer and the voice.
```

---

## Run it

Both prototypes are single self-contained files. Open them directly:

```
open prototype/netrelish-workstation.html
```

No build step, no server, no dependencies beyond one Google Fonts link. If you want it on localhost instead:

```
npx serve prototype
```

Then open `http://localhost:3000/netrelish-workstation.html`.

**The prototype is not a mockup.** Most of its CSS is the real CSS. Lift it rather than reinterpreting it. Where this documentation and the prototype disagree, check `docs/01-SPEC.md` — it was written against v5 and it wins — but the prototype is usually right.

---

## What this is

NetRelish is a macOS browser whose unit of organization is a **jar**. A jar is a project: it holds **tabs** and **notes**, it has a name, a color and a capacity, and it visibly fills as you put things in it. Open a jar and its tabs come back.

**Dev mode** is a switch that turns the right panel into a workbench for local WordPress copies. With it off, NetRelish is a normal browser and nothing technical is visible anywhere.

**Zest** is a line of small tools docked in the shelf — Zest MD, ZestMail, ZestImage — that read from the same brand.

Target: a macOS app wrapping **WKWebView**. Swift shell, web UI.

---

## Constraints

Not preferences. These are the decisions the product is built on, and reversing one quietly is the fastest way to get the work rejected.

**1. This isn't a nerd browser. It's a smart, power browser.**
The person using it builds WordPress sites for clients and does not want a terminal. Every string is written for them.

**2. No terminal. Anywhere. Ever.**
No shell, no WP-CLI, no SQL, no log tails, no network waterfall, no stack traces. Not behind a toggle, not in an "advanced" section. The words *webhook*, *endpoint*, *CLI* and *stdout* do not appear in the UI.

**3. Jars are the top of the shelf.**
Jars first, Zest second. Nothing goes above jars. Local copies do not get a shelf section — they live in the Dev panel.

**4. A tab is a website, not a client.**
Clients are jars. Don't collapse the two.

**5. Notes are first-class.**
Not a sidebar afterthought. A jar without notes is half a jar.

**6. Archive, never delete.**
Every destructive action is an archive with a 6-second Undo. Nothing the user made disappears for good from a right-click.

**7. The shelf never closes.**
There is no shelf toggle. The cog mark sits where the toggle would have been.

**8. Dev replaces the right panel. It doesn't open a drawer.**
Flipping the switch must not reflow the layout.

**9. US English only.**
color, behavior, organize, recognize, optimize, license, centered, gray, while, among, catalog, canceled.

**10. The mark is the mark.**
`assets/netrelish-mark.svg` is the real logo. Do not hand-draw a cog, do not restyle it, do not put it on a rounded-square plate. Keep its gradient IDs namespaced `nr-*` or it collides with the jar gradients and renders flat gray.

---

## Where to start

1. Read `docs/01-SPEC.md` §0–§5. Fifteen minutes.
2. Open `prototype/netrelish-workstation.html` and use it — right-click a jar, right-click a tab, flip Dev, click Brine, click the ⓘ on a section label.
3. Start Phase 1 in `docs/02-BUILD-ORDER.md`.

`docs/02-BUILD-ORDER.md` ends with a **Known traps** table. Read it before Phase 1, not after you hit one.

---

## Open questions

Five of them, listed in `docs/01-SPEC.md` §9. **None are blockers** — each has a stated default to build. They are flagged so they get a real decision before 1.0, not so the build waits on one.
