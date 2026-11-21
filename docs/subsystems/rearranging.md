---
title: Rearranging — right-click and drag on the Shelf and tab strip
type: subsystem
created: 2026-11-13
updated: 2026-11-21
sources:
  - code: Sources/App/Workbench.swift
  - code: Sources/App/NetRelishApp.swift
  - code: Sources/Shelf/ShelfView.swift
  - code: Sources/Bench/BenchView.swift
  - code: Sources/Bench/TabStrip.swift
  - code: Sources/Bench/BrineView.swift
  - code: Sources/UI/Components.swift
  - code: Tests/NetRelishTests/RearrangeTests.swift
verified_at: 0d45775
---

# Rearranging

How jars, tabs and Brine rows are moved with the mouse, and what the right-click menus do.
The decisions and what is still open are in `docs/adr/0028-right-click-and-drag.md`. This
page is how the code is put together and where it bites. For how any of it gets compiled
and tested, see [[building-without-a-mac]].

## The split: views ask, the Workbench decides

The views carry no rules. They call one of a handful of functions on `Workbench`, under
`// MARK: Rearranging` (`Sources/App/Workbench.swift:845`), and those decide what moves
and what is left behind. That is why the tests in
`Tests/NetRelishTests/RearrangeTests.swift` drive the
Workbench directly and never a view.

| Gesture | View | Workbench |
|---|---|---|
| Slide a jar along the Shelf | `slideGesture` (`Sources/Shelf/ShelfView.swift:327`) | `moveJar(_:to:)` (`Sources/App/Workbench.swift:853`) |
| Move Up, Move Down, color | jar menu (`Sources/Shelf/ShelfView.swift:244`) | `moveJar(_:by:)`, `setTint` |
| Tab onto a tab | `.draggable` + `.dropDestination` on `TabChip` (`Sources/Bench/TabStrip.swift:233`) | `drop(_:onTab:)` (`Sources/App/Workbench.swift:981`) |
| Tab or Brine row onto a jar | `.dropDestination` on `JarTile` (`Sources/Shelf/ShelfView.swift:190`) | `drop(_:onJar:)` (`Sources/App/Workbench.swift:961`) |
| Tab menu | `menu(for:)` (`Sources/Bench/TabStrip.swift:248`) | `togglePin`, `setGlyph`, `copyLink`, `moveTab(_:toJar:)`, `closeOtherTabs` |
| Jars › Move Jar Up / Down, Tab › Move Tab Left / Right, Tab › Move Tab to Jar | menu bar (`Sources/App/NetRelishApp.swift`) | `moveJar(_:by:)`, `moveTab(_:onto:)`, `drop(_:onJar:)` |

> ⚠️ **Every drag and every right-click item needs a menu-bar route too.** A right-click
> menu can't be opened from the keyboard without VoiceOver, so a move that lives only in a
> context menu or a VoiceOver action is out of reach with Keyboard navigation on and no
> pointer. The menu-bar items act on the jar or tab in front and are off at the ends.

## Two kinds of drag, on purpose

**Jars use their own `DragGesture`, not the system drag.** A jar may only move along the
Shelf. The system drag would let it be carried anywhere, so the row is slid with an
offset, held to the two ends of the list of jars, and the order is written once on release.

**Tabs and Brine rows use the system drag**, carrying a `DragPayload`
(`Sources/App/Workbench.swift:19`) as a plain string. A drop reads it back with
`DragPayload.init?(_:)`; anything else dragged in (a link, text from another app) reads
as nil and nothing happens.

The thing a drag would land on shows `NRDropMark` (`Sources/UI/Components.swift:203`),
relish placement 9 in the manifest. A tab or Brine row that lands on a jar also plays the
jar-fill drip on its tile: `drop(_:onJar:)` calls `fillJar(_:)` once something landed. The
drip itself is [[workbench-shell]]'s.

## Traps

> ⚠️ **One Workbench, many windows.** `NetRelishApp` holds a single `Workbench` for a
> `WindowGroup`, and every `BenchView.wire()` (`Sources/Bench/BenchView.swift:118`)
> replaces `onTabsGone` and the other callbacks with its own. Only the window wired last
> hears them. Never rely on a Workbench callback to clean up something each window keeps
> for itself. Put the check where the per-window thing is used.

> ⚠️ **A tab that changes jars must not keep its page.** Each jar has its own
> `WKWebsiteDataStore` (non-negotiable 6), and a `JarWebView` is bound to one jar for
> life. `BenchWebViews.view(for:)` (`Sources/Bench/BenchView.swift:25`) therefore reuses a
> cached web view only while its `jarId` matches the tab's. Remove that comparison and a
> second window shows the moved tab still signed in on the jar it left.

> ⚠️ **A web view left behind in another window is still a live page.** Until that window
> lets it go, it can navigate and report back by tab id. So `tabDidNavigate`
> (`Sources/App/Workbench.swift:1023`) is told which jar's web view is reporting and
> ignores one that isn't the tab's jar, and each window drops moved tabs' web views in
> `forgetStale` (`Sources/Bench/BenchView.swift:69`) when the open tabs change. The same
> function lets go of pages whose tab was closed in the other window. A new
> callback from a web view to the Workbench needs the same jar check.

> ⚠️ **`moveTab(_:toJar:)` clears `interactionState` deliberately.** History and form
> state were made with the old jar's sign-ins. The same rule is in
> `restore(_:into:)` (`Sources/App/Workbench.swift:1655`): a Brine row gets its history
> back only in the jar it sank from. Both look like lost data. Both are the rule.

> ⚠️ **Anything that awaits and then acts on a tab must check the tab's jar again.** A
> move keeps the tab's id and address, so a check on those two alone passes for a tab that
> is now somewhere else. Seal froze a page, came back, and closed the tab in the jar it
> had just been moved to. `closeIfStillOn` (`Sources/App/Workbench.swift:1352`) now
> requires the same jar as well, and so does `toggleReader` (`Sources/App/Workbench.swift:1522`),
> which would otherwise lay the old jar's article over the tab in its new jar.

> ⚠️ **`sortOrder` has gaps.** Closing or moving a tab does not renumber the strip. A new
> tab takes `max + 1` (`Sources/App/Workbench.swift:777`), never the count of tabs. The
> count put new tabs in the middle of a strip that had lost its first tabs.

> ⚠️ **Do not call `load()` after reordering jars.** `load()` resets the active jar from
> the database, which throws the user out of Brine or any other smart jar. Use
> `reloadJars()` (`Sources/App/Workbench.swift:848`), which re-reads the order and
> nothing else.

> ⚠️ **Every way into a jar plays the jar fill, through `fillJar(_:)`.** A drop on a jar
> calls it in `drop(_:onJar:)` (`Sources/App/Workbench.swift:975`), and Seal's overlay calls
> it when its chip lands. A new path that puts something in a jar (a menu item, a Shortcut
> with a window) must call it too, once, after the write, or the jar's level changes with no
> drip and no count badge.

> ⚠️ **The jar slide is measured in `.global` space.** The row moves with the drag, so a
> gesture measured in the row's own space sees almost no movement and jitters.

> ⚠️ **The jar slide is a `highPriorityGesture` on a `Button`.** It has not been tried in
> a running build yet (`(unverified)`). If a click on a jar stops activating it, or the
> slide never starts, this is the first place to look. Move Up and Move Down in the menu
> do the same job without it.

> ⚠️ **Tab icons live in `UserDefaults`, not the Pantry**, because `Tab` has no field for
> them (ADR 0028). They are pruned in `forgetGlyphsOfGoneTabs`
> (`Sources/App/Workbench.swift:995`) against every open tab in the database. A test that
> sets an icon must give its `Workbench` its own `UserDefaults`, or another test's
> Workbench on a different Pantry prunes it.

## Not built, and why

Lock, Archive with Undo, Duplicate, jar capacity and notes are in the v5 handoff but each
needs a field the model does not have. Model changes start in System Designer, so they
wait for that round. See [[building-without-a-mac]].
