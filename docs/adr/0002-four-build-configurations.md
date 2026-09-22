# ADR 0002 — Four build configurations, not two

**Status:** proposed · **Date:** 2026-09-16 · **PR:** p0: scaffold

Prompt 2 asks for "two configurations: `AppStore` and `Direct` (defines `DIRECT_BUILD`)".
Its demo also asks for *Window → Design Kit*, which is `#if DEBUG`. A configuration is
either a debug build or a release build; two configurations cannot be both.

**Decision:** the two are *flavors*, crossed with debug/release: `Debug-AppStore`,
`Debug-Direct`, `Release-AppStore`, `Release-Direct`. Two schemes, *NetRelish (App Store)*
and *NetRelish (Direct)*, run Debug and archive Release. `DIRECT_BUILD` is defined on both
Direct configurations; `DEBUG` on both Debug ones. CI builds both Release flavors and tests
Debug-AppStore.

Fewer configurations would mean either shipping `DEBUG` code to the store or losing the
Design Kit from local builds.
