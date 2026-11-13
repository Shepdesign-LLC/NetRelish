# Resources/Zest — generated, never hand-edited

This folder is the four free Zest tools as they ship inside NetRelish.app: Studio at the
root, then `mail/`, `md/` and `image/`, each with its own `index.html`. The Zest window
(Window › Zest) serves it read-only on `zest://app/` (`Sources/Zest/`).

It is written by `zest/build.sh --app` from the tools under `zest/apps/`. Change the tools
there and rebuild; an edit made here is lost on the next build, and CI rebuilds the folder
and fails if it differs from what is committed (ADR 0015).

`project.yml` adds this folder to the app as a folder reference, not a flat group, so the
four `index.html` files keep their folders in the bundle instead of colliding at the top of
`Contents/Resources`. This README ships in the bundle with the tools; it is plain text and
nothing loads it.

Decisions: `docs/adr/0015-zest-inside-netrelish.md`, `docs/adr/0033-zest-ships-in-1-0.md`.
How the host works and where it bites: `docs/subsystems/zest-window.md`.
