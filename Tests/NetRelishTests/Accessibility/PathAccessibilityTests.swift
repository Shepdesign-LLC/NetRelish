import AppKit
import Foundation
import Pantry
import Testing
@testable import NetRelish

/// The P5 done-when, "VoiceOver can complete capture → jar → seal", walked through the
/// Workbench the way the keyboard and VoiceOver routes drive it, with no window: ⌘L, ⌘D,
/// Restore, Tab › Move Tab to Jar (the drop's path), ⌘S. And the one rule across surfaces:
/// the same thing is said in the same words wherever it's said.
@Suite("Capture, jar, seal for VoiceOver") @MainActor struct PathAccessibilityTests {

    private func makeBench() throws -> Workbench {
        let defaults = try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
        let bench = Workbench(store: try PantryStore(), defaults: defaults)
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        bench.newJar(name: "Juniper Bakery", tint: nil, shelfLifeDays: 7)
        bench.announcer = { _, _ in }
        return bench
    }

    nonisolated private static func page() -> (Data, Extraction.Result) {
        (Data("WEBARCHIVE".utf8),
         Extraction.Result(title: "Invoice terms", excerpt: "Net thirty.", body: "The client agreed to net thirty."))
    }

    @Test("⌘L asks the key window's address field for the keyboard, once per press")
    func openLocation() throws {
        let bench = try makeBench()
        let before = bench.addressFocusRequest
        bench.focusAddress()
        bench.focusAddress()
        #expect(bench.addressFocusRequest == before + 2)
    }

    @Test("Capture, restore into a jar, move to another without a drag, then Seal: each step is said")
    func wholePath() async throws {
        let bench = try makeBench()
        let meridian = try #require(bench.jars.first { $0.name == "Meridian" })
        let juniper = try #require(bench.jars.first { $0.name == "Juniper Bakery" })
        bench.activate(meridian)

        // Open a page, as Return in the address field does.
        let opened = try #require(bench.newTab(url: "https://juniperbakery.example/invoice"))
        bench.tabDidNavigate(opened.id, url: URL(string: "https://juniperbakery.example/invoice"), title: "Invoice terms")

        // ⌘D: the address row speaks the status line.
        bench.captureActivePage()
        #expect(bench.statusLine?.text == "Captured into Brine")
        #expect(bench.statusLine?.priority == .high)
        let captured = try #require(bench.searchPantry("Invoice").first)
        #expect(captured.state == .brined)

        // Restore to Juniper Bakery, from the Brine row's menu or VoiceOver action: it opens
        // there, in the Shelf's words.
        bench.restore(captured, into: juniper.id)
        #expect(bench.activeJar?.id == juniper.id)
        #expect(SmartJarView.restoreAnnouncement(jarName: juniper.name) == "Opened in Juniper Bakery")

        // Tab › Move Tab to Jar › Meridian: the drop's path, so the jar fills once.
        let inFront = try #require(bench.pageInFront)
        let fillsBefore = bench.jarFill?.serial ?? 0
        #expect(bench.drop([DragPayload.tab(inFront.id).string], onJar: meridian))
        #expect(bench.jarFill?.jarId == meridian.id)
        #expect(bench.jarFill?.serial == fillsBefore + 1)
        #expect(CommandSpeech.moved(to: meridian.name) == "Moved to Meridian")

        // ⌘S from Meridian: the result line names the jar, at .high.
        bench.activate(meridian)
        let moved = try #require(bench.tabs.first { $0.id == inFront.id })
        bench.activateTab(moved)
        bench.tabDidNavigate(moved.id, url: URL(string: "https://juniperbakery.example/invoice"), title: "Invoice terms")
        bench.sealProvider = { _ in Self.page() }
        #expect(await bench.sealActiveTab())
        #expect(bench.statusLine?.text == "Sealed into Meridian")
        #expect(bench.statusLine?.priority == .high)
    }

    @Test("A move into a jar is said in one set of words, whichever route took it there")
    func sameWords() {
        let moved = JarTile.movedLine(jarName: "Meridian")
        #expect(moved == "Moved to Meridian")
        #expect(JarBoard.movedLine(jarName: "Meridian") == moved)
        #expect(CommandSpeech.moved(to: "Meridian") == moved)
        #expect(SmartJarView.restoreAnnouncement(jarName: "Meridian") == JarTile.openedLine(jarName: "Meridian"))
        #expect(CommandSpeech.board(jarName: "Meridian") == ShelfView.boardLine(jarName: "Meridian"))
    }

    @Test("Show Next Tab names a tab as the strip does")
    func tabNamesAgree() {
        let untitled = Pantry.Tab(title: nil, url: "https://www.juniperbakery.example/menu")
        #expect(TabStrip.spokenLabel(of: untitled) == "juniperbakery.example")
        #expect(CommandSpeech.tab(name: TabStrip.spokenLabel(of: untitled), position: 2, count: 4)
                == "juniperbakery.example, 2 of 4")
    }

    @Test("The Panel says it came or went")
    func panelLine() {
        #expect(ContentView.panelLine(shown: true) == "Panel shown")
        #expect(ContentView.panelLine(shown: false) == "Panel hidden")
    }
}
