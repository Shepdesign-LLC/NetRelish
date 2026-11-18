import Foundation
import Pantry
import Testing
@testable import NetRelish

/// What VoiceOver hears from the menu bar and ⌘K (P5), and where Show Next Tab and Show
/// Previous Tab land. Every line here is user-facing copy, so the tests pin the exact words.
@Suite("Keyboard and ⌘K accessibility") @MainActor struct KeyboardAccessibilityTests {

    // MARK: A ⌘K row, as one spoken line

    @Test("A Pantry item says it's sealed, then its jar")
    func sealedItem() {
        let row = PaletteRow(id: "item.1", kind: .item, title: "Pricing", subtitle: "Client site", sealed: true) {}
        #expect(row.spokenLabel == "Pricing, sealed, Client site")
    }

    @Test("A Pantry item with no jar comes from Brine")
    func brineItem() {
        let row = PaletteRow(id: "item.2", kind: .item, title: "Pricing", subtitle: "Brine") {}
        #expect(row.spokenLabel == "Pricing, Brine")
        let bare = PaletteRow(id: "item.3", kind: .item, title: "Pricing") {}
        #expect(bare.spokenLabel == "Pricing, Brine")
    }

    @Test("An open tab says so, then its jar")
    func openTab() {
        let row = PaletteRow(id: "tab.1", kind: .tab, title: "Docs", subtitle: "Client site") {}
        #expect(row.spokenLabel == "Docs, open tab, Client site")
    }

    @Test("A smart jar says what it is, then its shortcut")
    func smartJar() {
        let row = PaletteRow(id: "jar.brine", kind: .jar, title: "Brine", subtitle: "Everything unsorted",
                             shortcut: "⌃⌘1") {}
        #expect(row.spokenLabel == "Brine, Everything unsorted, ⌃⌘1")
    }

    @Test("A jar says it's a jar")
    func jar() {
        let row = PaletteRow(id: "jar.a", kind: .jar, title: "Client site", subtitle: "Jar") {}
        #expect(row.spokenLabel == "Client site, Jar")
    }

    @Test("A command says what it does, then its shortcut; with neither, only its name")
    func command() {
        let seal = PaletteRow(id: "cmd.seal", kind: .command, title: "Seal this page",
                              subtitle: "Into the jar, frozen", shortcut: "⌘S") {}
        #expect(seal.spokenLabel == "Seal this page, Into the jar, frozen, ⌘S")
        let close = PaletteRow(id: "cmd.close", kind: .command, title: "Close Tab", shortcut: "⌘W") {}
        #expect(close.spokenLabel == "Close Tab, ⌘W")
        let live = PaletteRow(id: "cmd.livepage", kind: .command, title: "Open Live Page") {}
        #expect(live.spokenLabel == "Open Live Page")
    }

    // MARK: ⌘K's result count

    @Test("The result line counts the matches and reads the first")
    func resultsLine() {
        let first = PaletteRow(id: "item.1", kind: .item, title: "Pricing", subtitle: "Client site") {}
        #expect(PaletteSource.resultsLine(count: 3, first: first) == "3 matches. Pricing, Client site")
        let capture = PaletteRow(id: "cmd.capture", kind: .command, title: "Capture this page",
                                 subtitle: "Into Brine", shortcut: "⌘D") {}
        #expect(PaletteSource.resultsLine(count: 1, first: capture) == "1 match. Capture this page, Into Brine, ⌘D")
    }

    @Test("When nothing matches, it says so")
    func nothingMatches() {
        #expect(PaletteSource.resultsLine(count: 0, first: nil) == "Nothing matches")
    }

    // MARK: Menu commands

    @Test("A jar from the Jars menu says how many tabs are open in it")
    func jarLine() {
        #expect(CommandSpeech.jar("Client site", openTabs: 3) == "Client site, 3 tabs")
        #expect(CommandSpeech.jar("Client site", openTabs: 1) == "Client site, 1 tab")
        #expect(CommandSpeech.jar("Client site", openTabs: 0) == "Client site, no open tabs")
    }

    @Test("A smart jar says what it holds, in the Shelf's units")
    func smartJarLine() {
        #expect(CommandSpeech.smartJar(.brine, count: 2) == "Brine, 2 items")
        #expect(CommandSpeech.smartJar(.today, count: 1) == "Today, 1 item")
        #expect(CommandSpeech.smartJar(.sealed, count: 0) == "Sealed, empty")
        #expect(CommandSpeech.smartJar(.sinking, count: 1) == "Sinking soon, 1 tab")
        #expect(CommandSpeech.smartJar(.sinking, count: 4) == "Sinking soon, 4 tabs")
        #expect(CommandSpeech.smartJar(.sinking, count: 0) == "Sinking soon, none")
    }

    @Test("Show Board and Move Tab to Jar say where you are now")
    func boardAndMove() {
        #expect(CommandSpeech.board(jarName: "Client site") == "Client site board")
        #expect(CommandSpeech.moved(to: "Client site") == "Moved to Client site")
    }

    @Test("Stepping tabs says the tab's name as the strip says it, and its place")
    func tabLine() {
        let titled = Pantry.Tab(title: "Pricing", url: "https://a.example")
        let untitled = Pantry.Tab(title: "", url: "https://www.a.example/pricing")
        let blank = Pantry.Tab()
        #expect(CommandSpeech.tab(name: TabStrip.spokenLabel(of: titled), position: 2, count: 5) == "Pricing, 2 of 5")
        #expect(CommandSpeech.tab(name: TabStrip.spokenLabel(of: untitled), position: 1, count: 2) == "a.example, 1 of 2")
        #expect(CommandSpeech.tab(name: TabStrip.spokenLabel(of: blank), position: 3, count: 3) == "New Tab, 3 of 3")
    }

    // MARK: Show Next Tab and Show Previous Tab

    @Test("The next and previous tabs wrap round the strip")
    func cycleWraps() {
        let ids = ["a", "b", "c"]
        #expect(TabCycle.neighbor(of: "a", in: ids, step: 1) == "b")
        #expect(TabCycle.neighbor(of: "c", in: ids, step: 1) == "a")
        #expect(TabCycle.neighbor(of: "a", in: ids, step: -1) == "c")
        #expect(TabCycle.neighbor(of: "b", in: ids, step: -1) == "a")
    }

    @Test("With no tab in front, or one that has gone, the first tab")
    func cycleWithNoActiveTab() {
        #expect(TabCycle.neighbor(of: nil, in: ["a", "b"], step: 1) == "a")
        #expect(TabCycle.neighbor(of: "gone", in: ["a", "b"], step: -1) == "a")
    }

    @Test("One tab stays put; no tabs, nowhere to go")
    func cycleEdges() {
        #expect(TabCycle.neighbor(of: "a", in: ["a"], step: 1) == "a")
        #expect(TabCycle.neighbor(of: "a", in: ["a"], step: -1) == "a")
        #expect(TabCycle.neighbor(of: nil, in: [], step: 1) == nil)
    }

    // MARK: The Me sheets

    @Test("A Keychain or Contacts failure is a sentence, not an error's description")
    func meLines() {
        #expect(MeText.couldntReadContacts == "Couldn’t read your card in Contacts.")
        #expect(MeText.couldntSave == "Couldn’t save your card in the Keychain. Try again in a moment.")
        #expect(MeText.couldntLoad == "Couldn’t read your card from the Keychain.")
    }

    @Test("Zest's failure line is the one the window shows")
    func zestFailed() {
        #expect(ZestWindow.failedLine == "Zest couldn’t start. Quit NetRelish and open it again.")
    }
}
