import Foundation
import Testing
@testable import NetRelish

/// What VoiceOver hears on the Shelf and in the jar sheet (P5), and where the arrow keys go.
/// A tile's name is its label; what it holds and how its tabs sink is its value. Every line
/// here is user-facing copy, so the tests pin the exact words.
@Suite("Shelf accessibility") @MainActor struct ShelfAccessibilityTests {

    // MARK: A jar tile's value

    @Test("A jar tile says its open tabs and what it keeps, with units, and how its tabs sink")
    func jarValue() {
        #expect(JarTile.spokenValue(tabs: 3, kept: 2, sinking: 0, shelfLifeDays: 3) == "3 tabs, 2 kept, tabs sink after 3 idle days")
        #expect(JarTile.spokenValue(tabs: 1, kept: 0, sinking: 0, shelfLifeDays: 1) == "1 tab, 0 kept, tabs sink after 1 idle day")
        #expect(JarTile.spokenValue(tabs: 0, kept: 2, sinking: 0, shelfLifeDays: 0.5) == "0 tabs, 2 kept, tabs sink after 12 idle hours")
    }

    @Test("A jar with no shelf life says its tabs never sink")
    func emptyAndNeverSinks() {
        #expect(JarTile.spokenValue(tabs: 0, kept: 0, sinking: 0, shelfLifeDays: nil) == "0 tabs, 0 kept, tabs never sink")
        #expect(JarTile.spokenValue(tabs: 4, kept: 1, sinking: 0, shelfLifeDays: 0) == "4 tabs, 1 kept, tabs never sink")
    }

    @Test("Tabs sinking soon come before the shelf life")
    func sinkingSoon() {
        #expect(JarTile.spokenValue(tabs: 3, kept: 2, sinking: 1, shelfLifeDays: 3)
                == "3 tabs, 2 kept, 1 sinking soon, tabs sink after 3 idle days")
    }

    @Test("The tile speaks the shelf life in the board's words")
    func sameWordsAsTheBoard() {
        let days = 60.0 / 86_400
        #expect(JarTile.spokenValue(tabs: 1, kept: 0, sinking: 0, shelfLifeDays: days) == "1 tab, 0 kept, \(JarBoard.sinkLine(days: days))")
    }

    @Test("The tile, the jar's chip and the board say one jar's contents in the same words")
    func tileChipAndBoardAgree() {
        let tile = JarTile.spokenValue(tabs: 3, kept: 2, sinking: 0, shelfLifeDays: 3)
        #expect(tile.hasPrefix(JarChip.accessibilityValue(tabs: 3, kept: 2)))
        #expect(tile == JarBoard.spokenMeta(tabs: 3, kept: 2, shelfLifeDays: 3))
    }

    // MARK: Drops and moves

    @Test("A tab dropped on a jar is moved; a Brine row is opened there")
    func dropLines() {
        let tab = DragPayload.tab("t1").string
        let brine = DragPayload.brine("b1").string
        #expect(JarTile.dropAnnouncement(payloads: [tab], jarName: "Meridian") == "Moved to Meridian")
        #expect(JarTile.dropAnnouncement(payloads: [brine], jarName: "Meridian") == "Opened in Meridian")
        #expect(JarTile.dropAnnouncement(payloads: [brine, tab], jarName: "Meridian") == "Moved to Meridian")
    }

    @Test("A drop that wasn't ours says nothing")
    func foreignDrop() {
        #expect(JarTile.dropAnnouncement(payloads: ["https://juniperbakery.example"], jarName: "Meridian") == nil)
        #expect(JarTile.dropAnnouncement(payloads: [], jarName: "Meridian") == nil)
    }

    @Test("Move Tab Here says what happened, or why nothing did")
    func moveTabHereLines() {
        #expect(JarTile.movedLine(jarName: "Meridian") == "Moved to Meridian")
        #expect(JarTile.alreadyHereLine(jarName: "Meridian") == "Already in Meridian.")
        #expect(JarTile.noPageLine == "Open a page first.")
    }

    @Test("Move Up and Move Down say where the jar is now, counting from 1, or that it's at an end")
    func moveLines() {
        #expect(JarTile.moveLine(jarName: "Meridian", index: 1, count: 5) == "Meridian, 2 of 5")
        #expect(JarTile.endLine(jarName: "Meridian", up: true) == "Meridian is already at the top.")
        #expect(JarTile.endLine(jarName: "Meridian", up: false) == "Meridian is already at the bottom.")
    }

    // MARK: Smart jars

    @Test("Sinking soon counts open tabs, and says None when there are none")
    func sinkingValue() {
        #expect(SmartJarRow.spokenValue(smart: .sinking, count: 0) == "None")
        #expect(SmartJarRow.spokenValue(smart: .sinking, count: 1) == "1 tab")
        #expect(SmartJarRow.spokenValue(smart: .sinking, count: 3) == "3 tabs")
    }

    @Test("Today, Sealed and Brine count items, and say Empty when there are none")
    func itemValues() {
        for smart in [SmartJar.today, .sealed, .brine] {
            #expect(SmartJarRow.spokenValue(smart: smart, count: 0) == "Empty")
            #expect(SmartJarRow.spokenValue(smart: smart, count: 1) == "1 item")
            #expect(SmartJarRow.spokenValue(smart: smart, count: 12) == "12 items")
        }
    }

    // MARK: The keyboard on the Shelf

    @Test("The keyboard's stops run top to bottom as drawn, and Brine isn't one")
    func focusOrder() {
        let order = ShelfView.focusOrder(jarIds: ["a", "b"])
        #expect(order == [.jar("a"), .jar("b"), .newJar,
                          .smart(.today), .smart(.sealed), .smart(.sinking), .zest])
        #expect(!order.contains(.smart(.brine)))
        #expect(ShelfView.focusOrder(jarIds: []).first == .newJar)
    }

    @Test("The arrows step one stop at a time and stop at either end, with no wrap")
    func neighbors() {
        let order = ShelfView.focusOrder(jarIds: ["a", "b"])
        #expect(ShelfView.neighbor(of: .jar("a"), in: order, by: 1) == .jar("b"))
        #expect(ShelfView.neighbor(of: .jar("b"), in: order, by: 1) == .newJar)
        #expect(ShelfView.neighbor(of: .newJar, in: order, by: -1) == .jar("b"))
        #expect(ShelfView.neighbor(of: .jar("a"), in: order, by: -1) == nil)
        #expect(ShelfView.neighbor(of: .zest, in: order, by: 1) == nil)
        #expect(ShelfView.neighbor(of: .jar("gone"), in: order, by: 1) == nil)
    }

    // MARK: Announcements

    @Test("Opening a jar's board, making a jar and saving one are spoken")
    func announcements() {
        #expect(ShelfView.boardLine(jarName: "Meridian") == "Meridian board")
        #expect(ShelfView.createdLine(name: "Meridian ") == "Meridian is on the Shelf.")
        #expect(ShelfView.savedLine(name: " Meridian") == "Saved Meridian.")
    }

    // MARK: The jar sheet

    @Test("The shelf-life stepper says its amount with its unit, singular at 1")
    func spokenAmount() {
        #expect(JarSheet.spokenAmount(amount: 3, unit: .days) == "3 days")
        #expect(JarSheet.spokenAmount(amount: 1, unit: .days) == "1 day")
        #expect(JarSheet.spokenAmount(amount: 1, unit: .minutes) == "1 minute")
        #expect(JarSheet.spokenAmount(amount: 60, unit: .seconds) == "60 seconds")
        #expect(JarSheet.spokenAmount(amount: 1, unit: .hours) == "1 hour")
    }
}
