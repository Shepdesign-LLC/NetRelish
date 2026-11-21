// CaptureJarSealUITests.swift — capture → jar → Seal in the built app (CLAUDE.md: "UI tests
// for capture → jar → seal"; P5 done-when: "VoiceOver can complete capture → jar → seal").
//
// Driven only through the accessibility tree: every element is found by the identifier or the
// name VoiceOver reads, every step is a key or a menu VoiceOver reaches too, and every result
// is checked in the words VoiceOver hears. Nothing is dragged. If this passes, the path has a
// spoken name at every step and a route that needs no pointer gesture.
//
// The app is launched with -NRUITestFixture (Sources/App/UITestFixture.swift, Debug builds
// only): a throwaway Pantry and defaults, the jars Juniper Bakery (⌘1) and Meridian (⌘2), and
// one page served from inside the app. Nothing is read from your Pantry and nothing goes to the
// network. The constants below are the fixture's; UITestFixtureAccessibilityTests checks they
// still match it.

import XCTest

final class CaptureJarSealUITests: XCTestCase {
    // The fixture's page and jars (UITestFixture.pageURL, pageTitle, pageMarker, jarNames).
    static let pageURL = "nr-fixture://juniperbakery.example/invoice-terms"
    static let pageTitle = "Invoice terms"
    static let pageMarker = "Payment is due 30 days after delivery."
    static let pageHost = "juniperbakery.example"
    static let firstJar = "Juniper Bakery"
    static let targetJar = "Meridian"

    /// Generous: a CI Mac can be slow to start WebKit's processes the first time.
    static let timeout: TimeInterval = 30
    /// Seal freezes the page and writes it before it says anything.
    static let sealTimeout: TimeInterval = 60

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: The path

    /// The walkthrough's main route: ⌘L, type the address, Return; ⌘D into Brine; ⌃⌘1 to
    /// Brine; the row's Restore to Meridian (the row's menu, whose items VoiceOver also lists as
    /// the row's actions); ⌘S; the page is sealed in Meridian's board and in Sealed.
    @MainActor
    func testCaptureIntoBrineRestoreToAJarAndSeal() throws {
        let app = launch()

        // 1. Open the page, from the keyboard.
        openFixturePage(in: app)

        // 2. ⌘D (Bench › Capture This Page): the status line says it, and the Brine pill holds it.
        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(statusLine(in: app, "Captured into Brine").waitForExistence(timeout: Self.timeout),
                      "⌘D didn't say Captured into Brine")
        let pill = app.descendants(matching: .any).matching(identifier: "brine-pill")
            .matching(NSPredicate(format: "label == %@ AND value BEGINSWITH %@", "Brine", "1 item")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: Self.timeout), "The Brine pill doesn't say 1 item")

        // 3. ⌃⌘1 (Jars › Brine): the capture is one row, named for the page, its site after it.
        app.typeKey("1", modifierFlags: [.control, .command])
        let row = element(in: app, id: "smart-jar-row", label: Self.pageTitle)
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The capture isn't a row in Brine")
        XCTAssertTrue(spokenValue(of: row).contains(Self.pageHost),
                      "The Brine row doesn't say its site: \(spokenValue(of: row))")

        // 4. Into Meridian without dragging: Restore to Meridian, from the row's menu.
        row.rightClick()
        let restore = app.menuItems["Restore to \(Self.targetJar)"]
        XCTAssertTrue(restore.waitForExistence(timeout: Self.timeout), "The Brine row has no Restore to Meridian")
        restore.click()

        // 5. It opens in Meridian: Meridian's strip holds the page, and the page arrives.
        XCTAssertTrue(chip(in: app, jar: Self.targetJar).waitForExistence(timeout: Self.timeout),
                      "The page didn't open in Meridian's tabs")
        waitForPage(in: app)

        // 6. ⌘S (Bench › Seal), and the rest.
        sealAndCheck(in: app, jar: Self.targetJar)
    }

    /// The keyboard route into a jar for a page that's open: Tab › Move Tab to Jar › Meridian
    /// in the menu bar (Ctrl-F2 or VO-M reaches it), then ⌘2 (Jars › Meridian), then ⌘S.
    @MainActor
    func testMoveTabToJarFromTheMenuBarAndSeal() throws {
        let app = launch()
        openFixturePage(in: app)

        let tabMenu = app.menuBars.menuBarItems["Tab"]
        XCTAssertTrue(tabMenu.waitForExistence(timeout: Self.timeout), "There's no Tab menu")
        tabMenu.click()
        let move = tabMenu.menuItems["Move Tab to Jar"]
        XCTAssertTrue(move.waitForExistence(timeout: Self.timeout), "The Tab menu has no Move Tab to Jar")
        move.click()
        let target = move.menuItems[Self.targetJar]
        XCTAssertTrue(target.waitForExistence(timeout: Self.timeout), "Move Tab to Jar doesn't list Meridian")
        target.click()

        // The tab left Juniper Bakery's strip; Meridian's has it.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(chip(in: app, jar: Self.targetJar).waitForExistence(timeout: Self.timeout),
                      "The tab isn't in Meridian's tabs after Move Tab to Jar")
        // It changed jars, so it loads again in Meridian's own profile (non-negotiable 6).
        waitForPage(in: app)

        sealAndCheck(in: app, jar: Self.targetJar)
    }

    // MARK: Steps

    /// A fresh launch of the fixture, with its window up and its jars on the Shelf.
    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Every flag is a `-key value` pair. macOS pairs each `-key` with the NEXT token on the
        // command line, so a bare flag swallows whatever follows it: `-NRUITestFixture` on its own
        // took `-ApplePersistenceIgnoreState` as its value, which left `YES` dangling and state
        // restoration switched ON — so the second test inherited the first one's empty scene.
        // `UITestFixture.isOn` asks `ProcessInfo.arguments.contains`, so the value here is never
        // read; it exists only to keep the pairing honest.
        app.launchArguments = [
            "-NRUITestFixture", "YES",
            "-ApplePersistenceIgnoreState", "YES",   // no windows restored from a last run
            "-panel.visible", "NO",                  // the Panel closed, whatever this Mac remembers
        ]
        app.launch()
        // The app is brought to the front explicitly: a window that exists but belongs to an
        // inactive app is not always in the accessibility tree on a headless CI Mac.
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: Self.timeout) {
            // On the CI Mac the app comes up with its whole menu bar and no window at all. The
            // Jars menu lists the fixture's own jars, so the fixture ran to the end; File › New
            // NetRelish Window is enabled while Close and Bring All to Front are not, so the
            // scene can make a window and none was ever made. WHY macOS opens no initial window
            // for a WindowGroup on that virtual Mac is still unexplained — the app logs nothing
            // and nothing in Sources/ withholds it. So ask for one through the menu, a route
            // VoiceOver has too, rather than leave the whole path unproven.
            openWindowFromTheMenuBar(in: app)
        }
        if !app.windows.firstMatch.waitForExistence(timeout: Self.timeout) {
            // Still nothing. "The main window didn't open" alone cannot say why, and the .xcresult
            // that holds the detail needs Xcode to read. `debugDescription` is the whole tree as
            // XCUITest sees it, and `state` separates "not running" from "running, no window".
            XCTFail("""
                The main window didn't open, and File › New NetRelish Window didn't make one.
                app.state = \(app.state.rawValue) (1 notRunning, 2 runningBackground, \
                3 runningBackgroundSuspended, 4 runningForeground)
                windows.count = \(app.windows.count), dialogs = \(app.dialogs.count), \
                sheets = \(app.sheets.count), alerts = \(app.alerts.count)
                tree as XCUITest sees it:
                \(app.debugDescription)
                """)
            return app
        }
        let shelf = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Shelf")).firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: Self.timeout), "There's no Shelf")
        for jar in [Self.firstJar, Self.targetJar] {
            let tile = shelf.descendants(matching: .any).matching(NSPredicate(format: "label == %@", jar)).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: Self.timeout), "\(jar) isn't on the Shelf")
        }
        return app
    }

    /// Asks for the main window through File › New NetRelish Window, for the CI Mac that starts
    /// the app without one. It is the same menu item a person reaches with Ctrl-F2 or VO-M, so a
    /// window opened this way is the window the rest of the walkthrough would have had. Quiet on
    /// failure: the caller's XCTFail prints the tree, which says far more than an error here.
    @MainActor
    private func openWindowFromTheMenuBar(in app: XCUIApplication) {
        let file = app.menuBars.menuBarItems["File"]
        guard file.waitForExistence(timeout: Self.timeout) else { return }
        file.click()
        let newWindow = file.menuItems["New NetRelish Window"]
        guard newWindow.waitForExistence(timeout: Self.timeout) else { return }
        newWindow.click()
    }

    /// Step 0 and 1: ⌘L (Bench › Open Location…) gives the address field the keyboard; the
    /// address is typed and Return opens it in the jar in front, Juniper Bakery.
    @MainActor
    private func openFixturePage(in app: XCUIApplication) {
        let field = app.descendants(matching: .any).matching(identifier: "address-field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "There's no address field")
        // Its name may come through as the label or the title, depending on how AppKit hands a
        // text field's name over; VoiceOver reads either.
        XCTAssertTrue(field.label == "Address" || field.title == "Address",
                      "The address field isn't called Address (label \(field.label), title \(field.title))")
        app.typeKey("l", modifierFlags: .command)
        app.typeText(Self.pageURL)
        app.typeKey(.return, modifierFlags: [])
        // The tab knows the page's name once the page has settled: its chip says the title.
        XCTAssertTrue(chip(in: app, jar: Self.firstJar).waitForExistence(timeout: Self.timeout),
                      "The page didn't open in Juniper Bakery's tabs")
        waitForPage(in: app)
    }

    /// ⌘S, then everything Seal leaves behind, in the words VoiceOver hears: the status line,
    /// the page kept and sealed on the jar's board (the tab closed, so the board shows), and the
    /// page in Sealed (⌃⌘3) in that jar.
    @MainActor
    private func sealAndCheck(in app: XCUIApplication, jar: String) {
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(statusLine(in: app, "Sealed into \(jar)").waitForExistence(timeout: Self.sealTimeout),
                      "⌘S didn't say Sealed into \(jar)")

        let kept = element(in: app, id: "kept-card", label: Self.pageTitle)
        XCTAssertTrue(kept.waitForExistence(timeout: Self.timeout), "\(jar)'s board doesn't keep the page")
        XCTAssertTrue(spokenValue(of: kept).hasPrefix("Page, sealed"),
                      "The kept page doesn't say it's sealed: \(spokenValue(of: kept))")

        app.typeKey("3", modifierFlags: [.control, .command])
        let sealed = element(in: app, id: "smart-jar-row", label: Self.pageTitle)
        XCTAssertTrue(sealed.waitForExistence(timeout: Self.timeout), "The page isn't in Sealed")
        XCTAssertTrue(spokenValue(of: sealed).contains("in \(jar)"),
                      "Sealed doesn't say the page is in \(jar): \(spokenValue(of: sealed))")
    }

    // MARK: Finding things

    /// An element by its identifier and the name VoiceOver reads.
    @MainActor
    private func element(in app: XCUIApplication, id: String, label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// The page's tab chip, inside the strip VoiceOver enters as "<jar> tabs".
    @MainActor
    private func chip(in app: XCUIApplication, jar: String) -> XCUIElement {
        let strip = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "\(jar) tabs")).firstMatch
        return strip.descendants(matching: .any).matching(identifier: "tab-chip")
            .matching(NSPredicate(format: "label == %@", Self.pageTitle)).firstMatch
    }

    /// The address field's status line: shown for 2.5 seconds and said by VoiceOver. A static
    /// text carries its words as its value; the predicate takes either.
    @MainActor
    private func statusLine(in app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "fill-status")
            .matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }

    /// Waits for a line only the fixture page has, so the page is in the web view, not just
    /// asked for.
    @MainActor
    private func waitForPage(in app: XCUIApplication) {
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", Self.pageMarker, Self.pageMarker)).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: Self.timeout), "The fixture page didn't load")
    }

    /// What VoiceOver says after an element's name.
    @MainActor
    private func spokenValue(of element: XCUIElement) -> String {
        element.value as? String ?? ""
    }
}
