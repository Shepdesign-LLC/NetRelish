# Resources/Zest — generated, never hand-edited

The four free Zest tools as NetRelish.app ships them: Studio at the root (`index.html`), then
`mail/`, `md/` and `image/`, each with its own `index.html`, the fonts and libraries they use
in `vendor/`, and the third-party notices in `NOTICE`, which Help › Acknowledgments shows. The
Zest window (Window › Zest) serves this folder read-only on `zest://app/` (`Sources/Zest/`).

`bash zest/build.sh --app` writes it from the tools under `zest/apps/` and the pinned files
under `zest/vendor/`, leaving out everything only the web has (the store, pricing, Pro
prompts, drafting with a model, the service workers and install manifests). Change the tools
there and rebuild; don't edit these files by hand. CI rebuilds it and fails when the
committed copy differs, scans it for any network address in a load position and for pricing
or Upgrade text, and runs every tool with the network blocked.

`project.yml` adds this folder to the app as a folder reference, not a flat group, so the
four `index.html` files keep their folders in the bundle instead of colliding at the top of
`Contents/Resources`. This README ships in the bundle; it is plain text and nothing loads it.

Decisions: `docs/adr/0015-zest-inside-netrelish.md`, `docs/adr/0033-zest-ships-in-1-0.md`.
How the host works and where it bites: `docs/subsystems/zest-window.md`.
