// RearrangingUITests.swift — the pointer half of the Shelf and the tab strip (ADR 0028):
// right-click menus and drag.
//
// CaptureJarSealUITests is deliberately the opposite of this file — it drags nothing and uses
// only what VoiceOver reaches, because its job is to prove the keyboard route exists. That
// leaves the pointer route untested, and on 2026-11-24 it went dead in the built app without a
// single check going red: every `.contextMenu` and every `.draggable` was still in the source,
// so nothing looked deleted. The gestures were being swallowed by other gestures over them.
//
// These tests exist to catch exactly that. They are expected to FAIL when first written, on
// main at 830f70b, and the fix is only believable once they pass.
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

    /// A tab's menu: Pin, the icon palette, Copy Link, Move Left / Right, Move to Jar
    /// (`TabStrip.menu(for:)`). The menu builds those unconditionally, so if nothing appears
    /// the right-click never reached the chip.
    @MainActor
    func testRightClickOnATabOpensItsMenu() throws {
        let app = launch()
        openFixturePage(in: app)

        let tab = chip(in: app, jar: Self.firstJar)
        XCTAssertTrue(tab.waitForExistence(timeout: Self.timeout), "The page didn't open in \(Self.firstJar)'s tabs")
        tab.rightClick()

        // "Pin" is the first item and takes no state to be there.
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
    }

    /// A jar's menu: New Tab in <jar>, Edit Jar…, the color palette, Move Up / Move Down
    /// (`ShelfView.menu(for:at:)`), all built unconditionally.
    @MainActor
    func testRightClickOnAJarTileOpensItsMenu() throws {
        let app = launch()

        let tile = jarTile(in: app, named: Self.firstJar)
        XCTAssertTrue(tile.waitForExistence(timeout: Self.timeout), "\(Self.firstJar) isn't on the Shelf")
        tile.rightClick()

        let newTab = app.menuItems["New Tab in \(Self.firstJar)"]
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
        let target = jarTile(in: app, named: Self.targetJar)
        XCTAssertTrue(target.waitForExistence(timeout: Self.timeout), "\(Self.targetJar) isn't on the Shelf")

        // Held before it travels: a drag that starts instantly is read as a click.
        tab.press(forDuration: 0.8, thenDragTo: target)

        // The tab left Juniper Bakery's strip and is in Meridian's.
        XCTAssertTrue(chip(in: app, jar: Self.targetJar).waitForExistence(timeout: Self.timeout),
                      """
                      Dragging the tab onto \(Self.targetJar) didn't move it.
                      The tab carries .draggable and the jar tile carries .dropDestination, so if \
                      neither end is missing, something over them took the drag.
                      tree as XCUITest sees it:
                      \(app.debugDescription)
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
