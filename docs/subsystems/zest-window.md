---
title: The Zest window — four tools, offline, beside the Bench
type: subsystem
created: 2026-11-13
updated: 2026-11-13
sources:
  - code: Sources/Zest/ZestFiles.swift
  - code: Sources/Zest/ZestSchemeHandler.swift
  - code: Sources/Zest/ZestRules.swift
  - code: Sources/Zest/ZestWebView.swift
  - code: Sources/Zest/ZestWindow.swift
  - code: Sources/App/Workbench.swift
  - code: Sources/App/NetRelishApp.swift
  - code: Sources/Pantry/Store/JarProfile.swift
  - code: project.yml
  - code: Resources/Zest/README.md
  - code: Tests/NetRelishTests/Zest/ZestFilesTests.swift
  - code: Tests/NetRelishTests/Zest/ZestHostTests.swift
  - code: Tests/Fixtures/zest-fixture.html
verified_at: 1d9a0c4
---

# The Zest window

Window › Zest shows the four free Zest tools (Studio, Mail, MD, Image) inside NetRelish,
offline, in a window of their own. They are not tabs: they belong to no jar, never sink
into Brine and can't be sealed. The design is ADR 0015; ADR 0033 moved it into 1.0. The
tools themselves are the web apps under `zest/` (see [[zest-sound]] for one thing they
share); this page is the Swift host around them. Like the rest of the app, it is compiled
and tested only in CI ([[building-without-a-mac]]).

## How it fits together

| Piece | Where | What it does |
|---|---|---|
| The files | `Resources/Zest/` | Today only a README. Phase 2's `zest/build.sh --app` (not written yet) will fill it: Studio at the root, then `mail/`, `md/`, `image/`. Added to the app as a folder reference (`project.yml:93`), so it lands as `Contents/Resources/Zest` with its folders kept |
| The scheme | `Sources/Zest/ZestSchemeHandler.swift:27` | Serves `zest://app/…` from that folder, read-only, and answers every request before returning |
| What a path may reach | `Sources/Zest/ZestFiles.swift:31`, `:63` | Pure functions: the URL's path becomes components, or nothing; the components become a file inside the folder, or nothing |
| The second layer | `Sources/Zest/ZestFiles.swift:140` | A Content-Security-Policy on every response, with no web origin in any directive |
| The third layer | `Sources/Zest/ZestRules.swift:33` | A content rule list that blocks every http(s), ws(s) and file load, compiled once per launch |
| Zest's store | `Sources/Pantry/Store/JarProfile.swift:23` | One fixed website data store, reserved beside the jars' derivation so no jar maps to it |
| A tool's view | `Sources/Zest/ZestWebView.swift:57` | Every Zest web view's configuration: Zest's store, the scheme, the rule list, the frozen `window.netrelish` stub |
| Where links go | `Sources/Zest/ZestWebView.swift:95` | A pure routing function: a clicked web link opens in the active jar, a link to another tool moves the switcher, blob: and data: pages download, other apps follow the Bench's handoff. It decides downloads too: only the tool's own files, blob: and data: are ever downloaded |
| The window | `Sources/Zest/ZestWindow.swift:17` | The tool table, and the window with its segmented switcher; each tool's view is made on first use and kept |
| Gating | `Sources/App/Workbench.swift:162` | While the Zest window is main, `pageInFront` is nil, and Seal, Capture, Reader, Fill from Me, Pin and Close Tab stand down |

## What leaves a tool

- A clicked http(s) link: a new tab in the active jar, in the main window, which is brought
  forward or opened (`Sources/Zest/ZestWindow.swift:128`). The main window is the one
  `ContentView` registers (`Sources/App/NetRelishApp.swift:172`), never Settings or the
  Design Kit. It is an ordinary page load, which non-negotiable 5 already allows.
- A download (`a[download]` of the tool's own file, a blob: or data: page, a file WebKit
  can't show): the save panel, through `WKDownload` (`Sources/Zest/ZestWebView.swift:274`).
  An `a[download]` pointing at the web is a web link, not a download.
- A file input: the open panel, as a sheet on the Zest window.
- Nothing else. A script that navigates to the web without a click is cancelled, and the
  rule list blocks what the policy might miss.

## Traps

> ⚠️ **`WKURLSchemeHandler` is called on the main thread but is not marked `@MainActor` in
> the SDK** (unverified here: taken from the brief, and CI's compiler is the check).
> `ZestSchemeHandler` has no isolation of its own and steps onto the main actor with
> `MainActor.assumeIsolated`, which traps if WebKit ever calls from elsewhere; the task goes
> in through a `nonisolated(unsafe)` local because it isn't Sendable. A `@MainActor` class
> would have main-actor methods, which a nonisolated protocol requirement doesn't accept
> under Swift 6. `WKDownloadDelegate` is conformed to with `@preconcurrency` for the same
> reason, which costs only a warning if the SDK does mark it.

> ⚠️ **Never read a Zest file with `Data(contentsOf:)`.** The CodeQL query
> `netrelish/remote-capable-url-read` has a baseline of zero, and a URL read is a hit. The
> handler reads by path (`FileManager.contents(atPath:)`), and the tests do the same.

> ⚠️ **Path checks resolve with `realpath(3)`, not `resolvingSymlinksInPath`.** The
> Foundation call drops a leading `/private` only when the result exists, so a folder and a
> file in it can come back spelled differently and an inside file reads as outside. The
> tests build their folders under `/var/folders`, which is exactly that case.

> ⚠️ **A Zest view can't be made before the rule list compiles, and that is on purpose.**
> `ZestWebView` takes the list as a non-optional argument, so nothing ever loads unblocked.
> If compiling fails, the window says Zest couldn't start; it does not fall back to an
> unblocked view.

> ⚠️ **Zest's store identifier must never change, and no jar may ever map to it.** It is a
> version-4 UUID and every derived jar id is version 5; a jar whose id is that UUID's own
> text is moved to an id derived under a namespace of its own
> (`Sources/Pantry/Store/JarProfile.swift:37`), so the move can't land on another jar's
> store. Changing either constant loses saved work. `ZestStoreTests` checks that no jar maps
> to Zest's store and no two jars share one.

> ⚠️ **`Resources/Zest` must stay out of the flat `Resources` group.** A flat group copies
> every file to the top of `Contents/Resources`, where four index.html files collide. The
> flat entry excludes it, and a second entry adds it with `type: folder`
> (`project.yml:89`). After changing either, the Xcode project is regenerated.

> ⚠️ **`zestInFront` only changes once a Zest window has registered.** Any window becoming
> main reaches every `Workbench`; without that guard (`Sources/App/Workbench.swift:188`), a
> test's window, or the app's own main window appearing, would switch gating off in the
> middle of another test.

> ⚠️ **Gating follows the main window, not the key window.** A tool's color picker (the
> color panel, or WebKit's popover for `<input type=color>`), an alert or a save panel
> takes key while the Zest window stays main. Gating by key switched Seal back on under the
> color panel, so ⌘S there sealed the hidden tab in the main window.

> ⚠️ **A download link is routed before it is downloaded.** `shouldPerformDownload` is
> true for any `a[download]`, scripted clicks included. Answering `.download` for an
> https URL would have the network process fetch it on Zest's store, past the rule list and
> the policy header. `route` sees the flag and allows a download only for the tool's own
> files, blob: and data:.

> ⚠️ **The integration tests never touch Zest's real store.** They are hosted in
> NetRelish.app, where that store is the person's saved work. Each test passes a
> throwaway store to `ZestWebView.configuration(rules:root:dataStore:)` and removes it; only
> the app passes nil.

> ⚠️ **The gating is `pageInFront`, not `benchTab`.** `benchTab` still drives what the main
> window shows (the Panel, Reader view), and must not change when the Zest window comes
> forward. A new command that acts on the page in front reads `pageInFront`.

> ⚠️ **The stub is injected into the main frame only.** A tool's `srcdoc` preview frame
> sees no `window.netrelish`. A tool that checks for the app should check the `zest:`
> protocol of its own page, as ADR 0015's `IN_APP` does.

> ⚠️ **CI doesn't show that storage on `zest://` survives a relaunch.** The integration
> test shows two views in one process sharing localStorage, which would pass if WebKit kept
> it in memory only. Relaunch persistence and IndexedDB (ADR 0015 risk 1) are checked by
> hand in phase 2's demo: write in a tool, quit, open NetRelish again.

> ⚠️ **Whether `zest://` is a secure context is not settled.** The integration test prints
> `window.isSecureContext` to the CI log rather than asserting it. If it is false, the
> clipboard API and `crypto.subtle` are missing inside the tools; phase 2 checks this
> before it relies on them.

## Tests

`ZestFilesTests` covers the path rules (every traversal spelling), symlinks on disk, the
content types, the policy and byte ranges. `ZestHostTests` covers Zest's store against
jar ids (and jar ids against each other), the rule list's JSON (it blocks exactly http,
https, ws, wss and file), the stub being in Zest configurations and in no jar's, routing
(download links included), the tool table and the gating, panels included. Its last suite
loads `Tests/Fixtures/zest-fixture.html` through the real scheme handler, each test on a
throwaway store: it checks that two views on one store share localStorage in one process
(part of ADR 0015 risk 1, not persistence across a relaunch), that a fetch to the web is
blocked with and without the policy header, that a download link to the web clicked by a
script starts no download, and that the stub is frozen.
