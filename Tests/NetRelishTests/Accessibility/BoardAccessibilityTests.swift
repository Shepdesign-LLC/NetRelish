import Foundation
import Pantry
import Testing
@testable import NetRelish

/// What VoiceOver hears on a jar's board and in the smart jars (P5), and where the arrow keys
/// go in Brine. A card or row is one element: its name is the label, what it is and when is
/// the value, and it reads the same under the pointer as away from it. Every line here is
/// user-facing copy, so the tests pin the exact words.
@Suite("Board and Brine accessibility") @MainActor struct BoardAccessibilityTests {

    // MARK: The board's header

    @Test("The header's line is read with commas, from the same parts as the dotted line")
    func spokenMeta() {
        #expect(JarBoard.spokenMeta(tabs: 3, kept: 12, shelfLifeDays: 7) == "3 tabs, 12 kept, tabs sink after 7 idle days")
        #expect(JarBoard.spokenMeta(tabs: 1, kept: 0, shelfLifeDays: nil) == "1 tab, 0 kept")
        #expect(JarBoard.spokenMeta(tabs: 2, kept: 1, shelfLifeDays: 0) == "2 tabs, 1 kept")
        #expect(JarBoard.metaParts(tabs: 3, kept: 12, shelfLifeDays: 7).joined(separator: " · ")
                == "3 tabs · 12 kept · tabs sink after 7 idle days")
    }

    @Test("The summary the Panel shows keeps its words")
    func summaryUnchanged() {
        #expect(JarBoard.summary(tabs: 1, kept: 0) == "1 tab · 0 kept")
        #expect(JarBoard.summary(tabs: 3, kept: 12) == "3 tabs · 12 kept")
    }

    // MARK: Tiles

    @Test("A tile says it's a tab, then its site, then pinned")
    func tileValue() {
        #expect(TabTile.spokenValue(host: "juniperbakery.example", isPinned: true) == "Tab, juniperbakery.example, pinned")
        #expect(TabTile.spokenValue(host: "juniperbakery.example", isPinned: false) == "Tab, juniperbakery.example")
        #expect(TabTile.spokenValue(host: nil, isPinned: false) == "Tab")
        #expect(TabTile.spokenValue(host: "", isPinned: true) == "Tab, pinned")
    }

    @Test("A tile is called by its title, else its site, else New Tab")
    func tileTitle() {
        #expect(TabTile.spokenTitle(of: Pantry.Tab(title: "Juniper Bakery", url: "https://juniperbakery.example/menu"))
                == "Juniper Bakery")
        #expect(TabTile.spokenTitle(of: Pantry.Tab(title: "", url: "https://juniperbakery.example/menu"))
                == "juniperbakery.example")
        #expect(TabTile.spokenTitle(of: Pantry.Tab()) == "New Tab")
    }

    // MARK: Kept cards

    @Test("A kept card says what it is, sealed or added and when, then its site")
    func keptValue() {
        #expect(KeptCard.spokenValue(kind: .page, isSealed: true, when: "2 days ago", domain: "juniperbakery.example")
                == "Page, sealed 2 days ago, juniperbakery.example")
        #expect(KeptCard.spokenValue(kind: .note, isSealed: false, when: "yesterday", domain: nil) == "Note, added yesterday")
        #expect(KeptCard.spokenValue(kind: .note, isSealed: false, when: "yesterday", domain: "") == "Note, added yesterday")
    }

    @Test("A kept card is called by its title, else its address, else Untitled")
    func keptTitle() {
        #expect(KeptCard.displayTitle(Item(title: "Sourdough notes", url: "https://juniperbakery.example/a")) == "Sourdough notes")
        #expect(KeptCard.displayTitle(Item(title: "", url: "https://juniperbakery.example/a")) == "https://juniperbakery.example/a")
        #expect(KeptCard.displayTitle(Item(title: "")) == "Untitled")
    }

    @Test("Only a sealed card with a saved copy says it opens the saved copy")
    func keptHint() {
        #expect(KeptCard.hint(Item(snapshotPath: "a.webarchive", state: .sealed)) == "Opens the saved copy.")
        #expect(KeptCard.hint(Item(state: .sealed)) == nil)
        #expect(KeptCard.hint(Item(state: .jarred)) == nil)
    }

    // MARK: What the board's actions say

    @Test("Move to, Pin, Close and Copy Link say what happened")
    func boardLines() {
        #expect(JarBoard.movedLine(jarName: "Juniper Bakery") == "Moved to Juniper Bakery")
        #expect(JarBoard.pinLine(wasPinned: false) == "Pinned")
        #expect(JarBoard.pinLine(wasPinned: true) == "Unpinned")
        #expect(JarBoard.closedLine(name: "Juniper Bakery") == "Closed Juniper Bakery")
        #expect(JarBoard.copiedLine == "Link copied")
    }

    // MARK: Smart jar rows

    @Test("A Brine row says its site, the jar it sank from, and when it sank")
    func brineRowValue() {
        #expect(SmartJarRowView.spokenValue(host: "juniperbakery.example", jarName: "Juniper Bakery", fromJar: true,
                                            when: "Sank 2 hours ago")
                == "juniperbakery.example, from Juniper Bakery, sank 2 hours ago")
    }

    @Test("Elsewhere a row says the jar it's in")
    func otherRowValue() {
        #expect(SmartJarRowView.spokenValue(host: "juniperbakery.example", jarName: "Juniper Bakery", fromJar: false,
                                            when: "Sinks in 2 days")
                == "juniperbakery.example, in Juniper Bakery, sinks in 2 days")
    }

    @Test("Missing parts are left out, with no stray commas")
    func rowValueGaps() {
        #expect(SmartJarRowView.spokenValue(host: nil, jarName: nil, fromJar: true, when: "") == "")
        #expect(SmartJarRowView.spokenValue(host: "", jarName: "Juniper Bakery", fromJar: false, when: "") == "in Juniper Bakery")
        #expect(SmartJarRowView.spokenValue(host: nil, jarName: "", fromJar: true, when: "Sealed yesterday") == "sealed yesterday")
    }

    @Test("A row is called by its title, else its address, else Untitled")
    func rowTitle() {
        #expect(SmartJarRowView.displayTitle(title: "Menu", url: "https://juniperbakery.example/menu") == "Menu")
        #expect(SmartJarRowView.displayTitle(title: "", url: "https://juniperbakery.example/menu")
                == "https://juniperbakery.example/menu")
        #expect(SmartJarRowView.displayTitle(title: "", url: nil) == "Untitled")
    }

    // MARK: Smart jar headers

    @Test("Each smart jar counts in its own word")
    func badges() {
        #expect(SmartJarView.badge(.brine, count: 3) == "3 sunk")
        #expect(SmartJarView.badge(.today, count: 1) == "1 new")
        #expect(SmartJarView.badge(.sealed, count: 0) == "0 sealed")
        #expect(SmartJarView.badge(.sinking, count: 2) == "2 sinking")
    }

    @Test("The header's line is read as two sentences")
    func summary() {
        #expect(SmartJarView.spokenSummary(SmartJarView.spokenCount(.brine, count: 3), blurb: SmartJar.brine.blurb)
                == "3 items. Tabs sink here when their jar's shelf life runs out. Nothing is lost.")
    }

    @Test("Brine's header counts aloud in the Brine pill's words, not \"sunk\"")
    func brineSpokenCount() {
        #expect(SmartJarView.spokenCount(.brine, count: 3) == ShellText.brineValue(count: 3, fresh: 0))
        #expect(SmartJarView.spokenCount(.brine, count: 1) == "1 item")
        #expect(SmartJarView.spokenCount(.brine, count: 0) == "Empty")
        #expect(SmartJarView.spokenCount(.today, count: 1) == "1 new")
        #expect(SmartJarView.spokenCount(.sinking, count: 2) == "2 sinking")
    }

    // MARK: Restore

    @Test("A restore says where the page opened, in the Shelf's words for a drop")
    func restoreLines() {
        #expect(SmartJarView.restoreAnnouncement(jarName: "Juniper Bakery") == "Opened in Juniper Bakery")
        #expect(SmartJarView.restoreHint(jarName: "Juniper Bakery") == "Opens it again in Juniper Bakery.")
        #expect(SmartJarView.restoreHint(jarName: nil) == nil)
        #expect(SmartJarView.sinkingHint == "Opens it, and its shelf life starts over.")
    }

    // MARK: The arrow keys

    @Test("Up and Down step one row at a time and stop at either end, with no wrap")
    func neighbors() {
        let ids = ["a", "b", "c"]
        #expect(SmartJarView.neighbor(of: "a", in: ids, by: 1) == "b")
        #expect(SmartJarView.neighbor(of: "c", in: ids, by: -1) == "b")
        #expect(SmartJarView.neighbor(of: "a", in: ids, by: -1) == nil)
        #expect(SmartJarView.neighbor(of: "c", in: ids, by: 1) == nil)
        #expect(SmartJarView.neighbor(of: "gone", in: ids, by: 1) == nil)
        #expect(SmartJarView.neighbor(of: "b", in: ids, by: 0) == nil)
    }

    @Test("The keys walk the rows as drawn: Today's card, then Yesterday's, then Earlier's")
    func orderAsDrawn() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)   // mid-morning, UTC
        let items = [
            Item(id: "earlier", updatedAt: now.addingTimeInterval(-5 * 86_400)),
            Item(id: "today1", updatedAt: now.addingTimeInterval(-3_600)),
            Item(id: "yesterday", updatedAt: now.addingTimeInterval(-86_400)),
            Item(id: "today2", updatedAt: now.addingTimeInterval(-60)),
        ]
        let order = SmartJarView.order(items, by: SmartJarView.groupDate(.brine), now: now, calendar: calendar)
        #expect(order == ["today1", "today2", "yesterday", "earlier"])
    }

    @Test("Brine files a row by when it sank; the others by when it was sealed or came in")
    func groupDates() {
        let created = Date(timeIntervalSince1970: 1_000)
        let sealed = Date(timeIntervalSince1970: 2_000)
        let updated = Date(timeIntervalSince1970: 3_000)
        let item = Item(createdAt: created, sealedAt: sealed, updatedAt: updated)
        let fresh = Item(createdAt: created, updatedAt: updated)
        #expect(SmartJarView.groupDate(.brine)(item) == updated)
        #expect(SmartJarView.groupDate(.sealed)(item) == sealed)
        #expect(SmartJarView.groupDate(.today)(fresh) == created)
    }
}
