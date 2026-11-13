---
title: Zest sound — one kit, four tools
type: subsystem
created: 2026-11-13
updated: 2026-11-13
sources:
  - code: zest/apps/zest/index.html
  - code: zest/apps/mail/index.html
  - code: zest/apps/md/index.html
  - code: zest/apps/image/index.html
  - code: zest/tests/sound.js
  - code: zest/tests/run.js
  - code: zest/README.md
verified_at: 2c4c510
---

# Zest sound

The four Zest web tools (the studio, ZestMail, Zest MD, ZestImage) play five short sounds
and share one Sound toggle. This page is how that is put together. Unlike the Swift app,
these tools can be run and tested in a cloud session; see [[building-without-a-mac]].

## How it works

Each tool is one self-contained HTML file, so there is no shared script. The kit is a
block of about 95 lines between `/* zest-sound:start v1 */` and `/* zest-sound:end */`,
inlined in its own `<script>` in each of the four tool files listed in this page's sources. It exposes
`window.ZestSound` with `play(name)`, `muted` and `setMuted(bool)`.

| Sound | Used for |
|---|---|
| `tap` | selecting, toggling, switching |
| `pop` | something added |
| `drop` | something removed, or a drag landing inside the page |
| `done` | copied, saved, exported |
| `nope` | blocked or failed |

The sounds are synthesized with Web Audio oscillators. There are no audio files and the
kit makes no requests. Any button carrying `data-zest-sound` is the mute toggle: the kit
handles its click and keeps `aria-pressed` in step, so a tool only adds the markup. The
choice is stored under one `localStorage` key, `zest.sound`, so on one origin muting one
tool mutes all four.

Most call sites go through each tool's existing helpers, not `ZestSound.play` directly:
the toast function takes a sound name, and the copy and download helpers play `done`.

## Traps

> ⚠️ **The four copies of the kit must stay byte-identical.** `zest/tests/sound.js` fails
> if they differ. Change the kit in one file, then copy the whole block into the other
> three. `zest/tests/README.md` has the note.

> ⚠️ **Nothing plays before a real click or key press.** The kit ignores events that are
> not trusted and only then creates its `AudioContext`. A test that calls `play()` from a
> script, or dispatches a synthetic click, hears nothing. That is the design, not a bug.

> ⚠️ **In ZestMail and Zest MD, `toast(msg, x)` has two meanings.** A string second
> argument is a sound name. An object is still the toast's action button. Passing a
> label string where an action object was meant plays nothing and shows no button.

> ⚠️ **A file drop plays the result (`pop` or `nope`), not `drop`.** `drop` is for
> removals and for drags that land inside the page. Wiring both gives two sounds for one
> action.

> ⚠️ **To run the suites in a cloud session, point them at the installed browser:**
> `ZEST_CHROMIUM=/opt/pw-browsers/chromium npm test` from `zest/tests`, after `npm ci`.
> Do not run `playwright install`. The variable changes nothing when it is unset.

> ⚠️ **The suites bind fixed ports, so two runs at once collide.** A second `npm test` on
> the same machine dies with `EADDRINUSE`, or worse, talks to the other run's server.
> When more than one run can be going (several workers, or a run left in the background),
> give each its own network: `unshare -n`, bring loopback up, then run the suite inside it.

> ⚠️ **In a test, do not use `offsetParent` to ask whether something inside a `<details>` is
> visible.** In this Chromium an element inside a closed `<details>` still reports an
> `offsetParent` and a non-zero box. Ask Playwright (`isVisible`) instead. Two checks
> passed for the wrong reason before this was found.

> ⚠️ **The suites allow three outside hosts and no others.** The tools already ask for
> Google Fonts, and Zest MD for cdnjs; the tests abort those requests and fail on any
> other host. Adding a host to that list is a change to what the tools reach, not a test
> fix.

> ⚠️ **None of this is in the Mac app.** Zest opens inside NetRelish in 1.1
> (`docs/adr/0015-zest-inside-netrelish.md`). Until then a Zest change is demonstrated in
> a browser, not in the built app.

## Not yet judged

The sounds were tuned by measurement (peak gain, length), in a sandbox with no audio
output. Nobody has listened to them yet `(unverified)`. Only Chromium was exercised;
Safari's audio unlock is handled in code but untested.
