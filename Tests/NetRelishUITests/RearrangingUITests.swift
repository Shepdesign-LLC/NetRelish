// RearrangingUITests.swift — the pointer half of the Shelf and the tab strip (ADR 0028):
// right-click menus and drag.
//
// CaptureJarSealUITests is deliberately the opposite of this file — it drags nothing and uses
// only what VoiceOver reaches, because its job is to prove the keyboard route exists. That
// leaves the pointer route untested, and on 2026-11-24 it went dead in the built app without a
// single check going red: every `.contextMenu` and every `.draggable` was still in the source,
// so nothing looked deleted. The gestures were being swallowed by other gestures over them.
//
// These tests exist to catch exactly that.
//
// 2026-11-24, after the first run: the two right-click tests PASSED, and they were wrong to.
// They asserted that a menu appeared and stopped there, which is true even when every item in
// that menu is dead — which is what Ryan was reporting while they went green. They now click
// the item and assert what it was supposed to do. The rule for this file from here: assert the
// outcome, never the affordance.
//
// Launched with the same fixture as the other file (Sources/App/UITestFixture.swift, Debug
// only): a throwaway Pantry, the jars Juniper Bakery (in front) and Meridian after the two
// every fresh Pantry starts with, and one page served from inside the app. Nothing reads your
// Pantry and nothing goes to the network.

import XCTest

final class RearrangingUITests: XCTestCase {
    static let pageURL = "nr-fixture://juniperbakery.example/invoice-terms"
    static let pageTitle = "Invoice terms"
    static let pageMarker = "Payment is due 30 days after delivery."
    static let firstJar = "Juniper Bakery"
    static let targetJar = "Meridian"

    /// Generous: a CI Mac can be slow to start WebKit's processes the first time.
    static let timeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Right-click
    //
    // These click THROUGH the menu to the thing it is supposed to do. The first version of this
    // file stopped at `XCTAssertTrue(app.menuItems["Pin"].waitForExistence(...))` — it proved a
    // menu appeared and nothing else, and it went green on 2026-11-24 while Ryan was reporting
    // that right-click did nothing. A menu that opens and whose items do nothing passes that
    // assertion. So does a menu wired to the wrong tab. Both are exactly what he described.
    //
    // The rule this file now follows: assert the OUTCOME, never the affordance. The menu items
    // are still checked, but as a precondition inside the test that uses them, so a failure
    // still says which of the two went wrong — the menu never opened, or it opened and did
    // nothing.

    /// Right-click a tab, press Pin, and the tab says it is pinned.
    ///
    /// Stronger than ⌘⇧P: `Tab › Pin Tab` pins `pageInFront` (`NetRelishApp.swift:188`), while
    /// this menu pins the chip that was right-clicked (`workbench.togglePin(tab)`,
    /// `TabStrip.swift:249`). A menu wired to the wrong tab passes the first and fails this.
    @MainActor
    func testRightClickOnATabPinsIt() throws {
        let app = launch()
        openFixturePage(in: app)

        let tab = chip(in: app, jar: Self.firstJar)
        XCTAssertTrue(tab.waitForExistence(timeout: Self.timeout), "The page didn't open in \(Self.firstJar)'s tabs")
        XCTAssertFalse(spokenValue(of: tab).contains("pinned"), "The tab was already pinned before the menu was opened")

        tab.rightClick()

        // Precondition. `TabStrip.menu(for:)` builds these unconditionally, so an empty menu
        // means the right-click never reached the chip — a different fault from a dead item.
        let pin = app.menuItems["Pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: Self.timeout),
                      """
                      Right-clicking a tab opened no menu.
                      TabStrip.menu(for:) always builds Pin, Icon, Copy Link, Move Left, Move Right \
                      and Move to Jar, so an empty menu is not possible — the click did not reach the chip.
                      menuItems seen: \(app.menuItems.count)
                      tree as XCUITest sees it:
                      \(app.debugDescription)
                      """)
        XCTAssertTrue(app.menuItems["Copy Link"].exists, "The tab's menu has no Copy Link")
        XCTAssertTrue(app.menuItems["Move to Jar"].exists, "The tab's menu has no Move to Jar")

        pin.click()

        XCTAssertTrue(waitForValue(of: tab, toContain: "pinned"),
                      """
                      The menu opened and Pin did nothing. This is the half the first version of \
                      this file never tested.
                      the tab says: \(spokenValue(of: tab))
                      """)
    }

    /// Right-click a jar on the Shelf, press New Tab in <jar>, and that jar gains a tab.
    ///
    /// Asserted on the jar's own spoken value — `JarTile.spokenValue` reads "0 tabs, 0 kept, …"
    /// and "1 tab, 0 kept, …" (`ShelfView.swift:584`) — so it holds whichever board the Bench
    /// happens to be showing afterwards.
    @MainActor
    func testRightClickOnAJarTileOpensANewTabThere() throws {
        let app = launch()

        let tile = jarTile(in: app, named: Self.targetJar)
        XCTAssertTrue(tile.waitForExistence(timeout: Self.timeout), "\(Self.targetJar) isn't on the Shelf")
        XCTAssertTrue(spokenValue(of: tile).contains("0 tabs"),
                      "\(Self.targetJar) didn't start empty, so a new tab proves nothing: \(spokenValue(of: tile))")

        tile.rightClick()

        let newTab = app.menuItems["New Tab in \(Self.targetJar)"]
        XCTAssertTrue(newTab.waitForExistence(timeout: Self.timeout),
                      """
                      Right-clicking a jar on the Shelf opened no menu.
                      ShelfView.menu(for:at:) always builds New Tab in <jar>, Edit Jar…, Color, \
                      Move Up and Move Down, so an empty menu is not possible — the click did not \
                      reach the tile.
                      menuItems seen: \(app.menuItems.count)
                      tree as XCUITest sees it:
                      \(app.debugDescription)
                      """)
        XCTAssertTrue(app.menuItems["Edit Jar…"].exists, "The jar's menu has no Edit Jar…")

        newTab.click()

        XCTAssertTrue(waitForValue(of: tile, toContain: "1 tab"),
                      """
                      The menu opened and New Tab in \(Self.targetJar) did nothing.
                      the jar says: \(spokenValue(of: tile))
                      """)
    }

    // MARK: The same moves, from the menu bar
    //
    // These use no pointer at all, and they are the control for the three above. Ryan also
    // can't pin a tab or move things around (2026-11-24), and that symptom has two very
    // different causes: either the pointer routes are swallowed and the menu bar still works,
    // or the moves themselves are broken and nothing can reach them. A tab says its own state
    // to VoiceOver — "pinned, 1 of 2", "2 of 2" — so both are answerable without asking him
    // which route he used.

    /// ⌘⇧P (Tab › Pin Tab). The chip then says "pinned" before its position.
    @MainActor
    func testPinFromTheKeyboard() throws {
        let app = launch()
        openFixturePage(in: app)

        let tab = chip(in: app, jar: Self.firstJar)
        XCTAssertTrue(tab.waitForExistence(timeout: Self.timeout), "The page didn't open in \(Self.firstJar)'s tabs")
        XCTAssertFalse(spokenValue(of: tab).contains("pinned"), "The tab was already pinned before ⌘⇧P")

        app.typeKey("p", modifierFlags: [.command, .shift])

        XCTAssertTrue(waitForValue(of: tab, toContain: "pinned"),
                      """
                      ⌘⇧P didn't pin the tab. If this fails while the right-click tests also fail, \
                      the moves themselves are broken, not just the pointer routes.
                      the tab says: \(spokenValue(of: tab))
                      """)
    }

    /// Tab › Move Tab Left, clicked in the menu bar. With the fixture page and one new tab, the
    /// page starts at "1 of 2"; moving the new tab left puts the page second.
    @MainActor
    func testMoveTabFromTheMenuBar() throws {
        let app = launch()
        openFixturePage(in: app)

        let page = chip(in: app, jar: Self.firstJar)
        XCTAssertTrue(page.waitForExistence(timeout: Self.timeout), "The page didn't open in \(Self.firstJar)'s tabs")
        app.typeKey("t", modifierFlags: .command)   // a second tab, which comes forward
        XCTAssertTrue(waitForValue(of: page, toContain: "1 of 2"),
                      "The page's tab isn't first of two after ⌘T: \(spokenValue(of: page))")

        let tabMenu = app.menuBars.menuBarItems["Tab"]
        XCTAssertTrue(tabMenu.waitForExistence(timeout: Self.timeout), "There's no Tab menu")
        tabMenu.click()
        let moveLeft = tabMenu.menuItems["Move Tab Left"]
        XCTAssertTrue(moveLeft.waitForExistence(timeout: Self.timeout), "The Tab menu has no Move Tab Left")
        XCTAssertTrue(moveLeft.isEnabled, "Move Tab Left is disabled with the new tab second of two")
        moveLeft.click()

        XCTAssertTrue(waitForValue(of: page, toContain: "2 of 2"),
                      """
                      Move Tab Left didn't reorder the strip. The menu item exists and was enabled, \
                      so the move itself did nothing.
                      the page's tab says: \(spokenValue(of: page))
                      """)
    }

    // MARK: Drag

    /// A tab dragged onto a jar on the Shelf moves there (ADR 0028). The keyboard route for the
    /// same move — Tab › Move Tab to Jar — is covered by CaptureJarSealUITests; this is the
    /// pointer one, and the two can break independently.
    @MainActor
    func testDraggingATabOntoAJarMovesIt() throws {
        let app = launch()
        openFixturePage(in: app)

        let tab = chip(in: app, jar: Self.firstJar)
        XCTAssertTrue(tab.waitForExistence(timeout: Self.timeout), "The page didn't open in \(Self.firstJar)'s tabs")
        let source = jarTile(in: app, named: Self.firstJar)
        let target = jarTile(in: app, named: Self.targetJar)
        XCTAssertTrue(target.waitForExistence(timeout: Self.timeout), "\(Self.targetJar) isn't on the Shelf")
        XCTAssertTrue(spokenValue(of: target).contains("0 tabs"),
                      "\(Self.targetJar) didn't start empty: \(spokenValue(of: target))")

        // Dragged from the BOTTOM of the chip, not its centre, and that is the experiment.
        //
        // A chip's hit area is the full 44pt of the title strip, so its centre is ~22pt from the
        // window's top edge — inside AppKit's title-bar region, which is about 30pt tall and the
        // full width of the window. AppKit reads a press-and-drag there as window-move and
        // claims it before SwiftUI can start a drag session, while a right-click has no
        // title-bar control to consume it and falls through. That is exactly the split in this
        // file: every right-click passes, every drag from a chip centre fails, and the Brine
        // control — whose rows are nowhere near the strip — passes.
        //
        // 0.85 down the chip is ~37pt, below the title-bar region. If this passes where the
        // centre failed, the geometry is the cause and the fix belongs in WindowChrome.
        let from = tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let onto = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.8, thenDragTo: onto)

        // Asserted on the two jars' own spoken values, never on a strip. `moveTab(_:toJar:)`
        // moves the tab WITHOUT activating the jar (`Workbench.swift:976`), so the Bench stays
        // on \(Self.firstJar) and a strip labelled "\(Self.targetJar) tabs" is never created.
        // The first version of this test waited for exactly that strip, which no correct fix
        // could ever have satisfied — it would have called a working drag broken.
        XCTAssertTrue(waitForValue(of: target, toContain: "1 tab"),
                      """
                      Dragging the tab onto \(Self.targetJar) didn't move it.
                      Both ends of the contract are present and their types match — the chip is \
                      .draggable(String) and the tile is .dropDestination(for: String.self) — so \
                      something over them took the drag before it started.
                      \(Self.targetJar) says: \(spokenValue(of: target))
                      \(Self.firstJar) says: \(spokenValue(of: source))
                      tree as XCUITest sees it:
                      \(app.debugDescription)
                      """)
        XCTAssertTrue(waitForValue(of: source, toContain: "0 tabs"),
                      "The tab arrived in \(Self.targetJar) but never left \(Self.firstJar): \(spokenValue(of: source))")
    }

    /// The control for the test above, and the reason it exists: nothing in this project has
    /// ever had a passing XCUITest drag, so a red drag test has two readings and only one of
    /// them is about the app.
    ///
    /// Brine is the surface Ryan says still works in the built app. It drags the same `String`
    /// (`BrineView.swift:112`) into the same destination (`ShelfView.swift:190`) — there is only
    /// one Shelf drop destination in the whole tree, so this lands on the identical code the
    /// tab's drag does. The only difference is which view the drag starts from.
    ///
    /// | This test | What the tab's red means |
    /// |---|---|
    /// | passes | XCUITest can drive a drag, so the tab's drag is genuinely broken |
    /// | fails   | XCUITest cannot drive `.draggable` at all, and neither red is about the app |
    ///
    /// Until it passes once, `testDraggingATabOntoAJarMovesIt` going red is not evidence of a bug.
    ///
    /// Its first run failed — and that was the test's fault, not XCUITest's: both drags called
    /// `press(forDuration:thenDragTo:)`, the touch idiom, where macOS wants
    /// `click(forDuration:thenDragTo:)`. Fixed in both. If Brine passes now, the instrument works
    /// and the tab's red can finally be read.
    @MainActor
    func testDraggingABrineRowOntoAJarRestoresIt() throws {
        let app = launch()
        openFixturePage(in: app)

        // ⌘D (Bench › Capture This Page), then ⌃⌘1 (Jars › Brine) — the keyboard route, so a
        // failure before the drag is never the pointer's.
        app.typeKey("d", modifierFlags: .command)
        app.typeKey("1", modifierFlags: [.control, .command])

        let row = app.descendants(matching: .any).matching(identifier: "smart-jar-row")
            .matching(NSPredicate(format: "label == %@", Self.pageTitle)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The capture isn't a row in Brine")

        let target = jarTile(in: app, named: Self.targetJar)
        XCTAssertTrue(target.waitForExistence(timeout: Self.timeout), "\(Self.targetJar) isn't on the Shelf")
        XCTAssertTrue(spokenValue(of: target).contains("0 tabs"),
                      "\(Self.targetJar) didn't start empty: \(spokenValue(of: target))")

        row.click(forDuration: 0.8, thenDragTo: target)

        // Workbench.drop(_:onJar:) restores a Brine row with `restore(item, into:)`, which calls
        // newTab — so it arrives as a TAB in the jar, not as something kept.
        XCTAssertTrue(waitForValue(of: target, toContain: "1 tab"),
                      """
                      Dragging a Brine row onto \(Self.targetJar) didn't restore it either.
                      Brine's drag is the one the built app still does, and it lands on the same \
                      ShelfView drop destination as the tab's. Both reds together mean XCUITest \
                      is not driving a drag session at all, and this file cannot measure drag \
                      until that is solved — a red here is about the test, not the app.
                      \(Self.targetJar) says: \(spokenValue(of: target))
                      """)
    }

    /// A tab dragged sideways onto another tab reorders the strip — "like a regular browser"
    /// (Ryan, 2026-11-24). Nothing covered this before today.
    ///
    /// It is also the sharpest discriminator left for the tab→jar drag that does not work.
    /// Both start from the same chip and carry the same `.draggable`; they differ only in where
    /// they land — `TabStrip`'s own drop destination, inside the strip, versus `ShelfView`'s,
    /// across the window.
    ///
    /// | This test | What it means for the broken drag |
    /// |---|---|
    /// | passes | `.draggable` on a chip works. The fault is in crossing to the Shelf |
    /// | fails  | a chip cannot be dragged anywhere at all, and the fault is on the chip |
    ///
    /// The menu-bar route for the same move is `testMoveTabFromTheMenuBar`, which passes, so
    /// `Workbench.drop(_:onTab:)` and `moveTab(_:onto:)` are already known good.
    @MainActor
    func testDraggingATabOntoAnotherTabReordersTheStrip() throws {
        let app = launch()
        openFixturePage(in: app)

        let page = chip(in: app, jar: Self.firstJar)
        XCTAssertTrue(page.waitForExistence(timeout: Self.timeout), "The page didn't open in \(Self.firstJar)'s tabs")
        app.typeKey("t", modifierFlags: .command)   // a second tab, which comes forward
        XCTAssertTrue(waitForValue(of: page, toContain: "1 of 2"),
                      "The page's tab isn't first of two after ⌘T: \(spokenValue(of: page))")

        let others = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "\(Self.firstJar) tabs")).firstMatch
            .descendants(matching: .any).matching(identifier: "tab-chip")
        let newTab = others.element(boundBy: 1)
        XCTAssertTrue(newTab.waitForExistence(timeout: Self.timeout), "There's no second tab chip to drop onto")

        page.click(forDuration: 0.8, thenDragTo: newTab)

        XCTAssertTrue(waitForValue(of: page, toContain: "2 of 2"),
                      """
                      Dragging a tab onto another tab didn't reorder the strip.
                      Tab › Move Tab Left does the same move and passes, so Workbench's side is \
                      fine — a chip cannot be dragged at all, not merely onto a jar.
                      the page's tab says: \(spokenValue(of: page))
                      """)
    }

    // MARK: Steps
    //
    // This file carries its own launch so it stands alone: the two UI test files prove opposite
    // routes, and sharing a base class would make one able to break the other.

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Every argument is a "-key value" pair, so none is left standing alone: AppKit takes a
        // lone argument for a file to open, and a launch that opens a file opens no window.
        app.launchArguments = [
            "-NRUITestFixture", "YES",
            "-ApplePersistenceIgnoreState", "YES",   // no windows restored from a last run
            "-panel.visible", "NO",                  // the Panel closed, whatever this Mac remembers
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Self.timeout),
                      "The main window didn't open. app.state = \(app.state.rawValue)")
        return app
    }

    /// ⌘L, the address, Return — the keyboard route, so a failure here is never the pointer's.
    @MainActor
    private func openFixturePage(in app: XCUIApplication) {
        let field = app.descendants(matching: .any).matching(identifier: "address-field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "There's no address field")
        app.typeKey("l", modifierFlags: .command)
        app.typeText(Self.pageURL)
        app.typeKey(.return, modifierFlags: [])
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", Self.pageMarker, Self.pageMarker)).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: Self.timeout), "The fixture page didn't load")
    }

    /// The page's tab chip, inside the strip VoiceOver enters as "<jar> tabs".
    @MainActor
    private func chip(in app: XCUIApplication, jar: String) -> XCUIElement {
        let strip = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "\(jar) tabs")).firstMatch
        return strip.descendants(matching: .any).matching(identifier: "tab-chip")
            .matching(NSPredicate(format: "label == %@", Self.pageTitle)).firstMatch
    }

    /// A jar's tile on the Shelf, by the name VoiceOver reads.
    @MainActor
    private func jarTile(in app: XCUIApplication, named jar: String) -> XCUIElement {
        let shelf = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Shelf")).firstMatch
        return shelf.descendants(matching: .any).matching(NSPredicate(format: "label == %@", jar)).firstMatch
    }

    /// What VoiceOver says after an element's name. A tab's is "pinned, 1 of 2" or "2 of 2"
    /// (`TabChip.accessibilityValue`), so a state change is readable without a screenshot.
    @MainActor
    private func spokenValue(of element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    /// Waits for a value to settle, since a move animates and the strip re-reads afterwards.
    @MainActor
    private func waitForValue(of element: XCUIElement, toContain text: String) -> Bool {
        let matches = NSPredicate(format: "value CONTAINS %@", text)
        let settled = XCTNSPredicateExpectation(predicate: matches, object: element)
        return XCTWaiter().wait(for: [settled], timeout: Self.timeout) == .completed
    }
}
