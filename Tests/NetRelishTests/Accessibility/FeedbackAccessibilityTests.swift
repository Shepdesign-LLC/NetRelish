import AppKit
import Foundation
import GRDB
import Pantry
import SwiftUI
import Testing
@testable import NetRelish

/// What VoiceOver hears on the way from capture to Seal (P5): the result lines the address
/// field shows, with how urgently they're said, and the lines that are said but never shown
/// (Seal starting, a tab sinking). No window is needed: the Workbench's `announcer` is replaced
/// to hear what it says, and `statusLine` is what the address row speaks.
@Suite("Feedback accessibility") @MainActor struct FeedbackAccessibilityTests {

    struct Spoken: Equatable {
        let text: String
        let priority: NSAccessibilityPriorityLevel
    }

    /// Everything the Workbench said aloud, in order.
    @MainActor final class Heard {
        var lines: [Spoken] = []
    }

    private func makeBench() throws -> (Workbench, Heard) {
        let defaults = try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
        let bench = Workbench(store: try PantryStore(), defaults: defaults)
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        let heard = Heard()
        bench.announcer = { text, priority in heard.lines.append(Spoken(text: text, priority: priority)) }
        return (bench, heard)
    }

    @discardableResult
    private func openTab(_ url: String, title: String, in bench: Workbench) throws -> Pantry.Tab {
        let tab = try #require(bench.newTab(url: url))
        bench.tabDidNavigate(tab.id, url: URL(string: url), title: title)
        return try #require(bench.tabs.first { $0.id == tab.id })
    }

    nonisolated private static func page() -> (Data, Extraction.Result) {
        (Data("WEBARCHIVE".utf8),
         Extraction.Result(title: "Invoice terms", excerpt: "Net thirty.", body: "The client agreed to net thirty."))
    }

    private func spoken(_ line: StatusLine?) -> Spoken? {
        line.map { Spoken(text: $0.text, priority: $0.priority) }
    }

    // MARK: The lines

    @Test("The Seal line names the jar, and falls back when the jar is gone")
    func sealedLine() {
        #expect(Workbench.sealedLine(jarName: "Meridian") == "Sealed into Meridian")
        #expect(Workbench.sealedLine(jarName: nil) == "Sealed into the jar")
        #expect(Workbench.sealingLine == "Sealing")
        #expect(Workbench.sealFailedLine == "Couldn’t seal this page")
        #expect(Workbench.capturedLine == "Captured into Brine")
    }

    @Test("A sinking tab is said by name; several are counted; none says nothing")
    func sankLine() {
        #expect(Workbench.sankLine(titles: []) == nil)
        #expect(Workbench.sankLine(titles: ["Invoice terms"]) == "Invoice terms sank into Brine")
        #expect(Workbench.sankLine(titles: [""]) == "A tab sank into Brine")
        #expect(Workbench.sankLine(titles: ["A", "B", "C"]) == "3 tabs sank into Brine")
    }

    @Test("A float's edge is strong under Increase Contrast or Reduce Transparency, and only then")
    func floatEdge() {
        #expect(!NRFloatModifier.edgeIsStrong(contrast: .standard, reduceTransparency: false))
        #expect(NRFloatModifier.edgeIsStrong(contrast: .increased, reduceTransparency: false))
        #expect(NRFloatModifier.edgeIsStrong(contrast: .standard, reduceTransparency: true))
        #expect(NRFloatModifier.edgeIsStrong(contrast: .increased, reduceTransparency: true))
    }

    @Test("The Sealed pill takes the relish-700 edge in dark and under Increase Contrast")
    func pillEdge() {
        #expect(!NRSealedPill.strongEdge(dark: false, contrast: .standard))
        #expect(NRSealedPill.strongEdge(dark: false, contrast: .increased))
        #expect(NRSealedPill.strongEdge(dark: true, contrast: .standard))
    }

    // MARK: Capture → jar → Seal

    @Test("⌘D says it landed in Brine, at once")
    func capture() throws {
        let (bench, _) = try makeBench()
        try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)

        bench.captureActivePage()
        #expect(spoken(bench.statusLine) == Spoken(text: "Captured into Brine", priority: .high))
        #expect(bench.fillStatus == "Captured into Brine")   // what's said is what's shown
    }

    @Test("Two captures in a row are two lines, so the second is said too")
    func captureTwice() throws {
        let (bench, _) = try makeBench()
        try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)

        bench.captureActivePage()
        let first = try #require(bench.statusLine)
        bench.captureActivePage()
        let second = try #require(bench.statusLine)
        #expect(first.text == second.text)
        #expect(first != second)
    }

    @Test("Nothing to capture is said at once too")
    func nothingToCapture() throws {
        let (bench, _) = try makeBench()
        bench.captureActivePage()
        #expect(bench.statusLine?.text == "Nothing to capture — open a page first")
        #expect(bench.statusLine?.priority == .high)
    }

    @Test("⌘S says Sealing as it starts, and the jar when the write returns, before any overlay")
    func seal() async throws {
        let (bench, heard) = try makeBench()
        try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        bench.sealProvider = { _ in Self.page() }

        #expect(await bench.sealActiveTab())
        // No overlay ran: the result line is there as soon as Seal returns.
        #expect(heard.lines.first == Spoken(text: "Sealing", priority: .medium))
        #expect(spoken(bench.statusLine) == Spoken(text: "Sealed into Meridian", priority: .high))
        guard case .frozen(_) = bench.sealPhase else {
            Issue.record("expected .frozen, got \(bench.sealPhase)")
            return
        }
    }

    @Test("A Seal that fails says so, with phase B, at once when it comes")
    func sealFails() async throws {
        let (bench, heard) = try makeBench()
        try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        struct Boom: Error {}
        bench.sealProvider = { _ in throw Boom() }

        #expect(await bench.sealActiveTab() == false)
        #expect(heard.lines.first == Spoken(text: "Sealing", priority: .medium))
        for _ in 0..<150 where bench.statusLine == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(spoken(bench.statusLine) == Spoken(text: "Couldn’t seal this page", priority: .high))
    }

    @Test("A tab that sinks is said by name, and nothing is shown for it")
    func sink() throws {
        let (bench, heard) = try makeBench()
        let old = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        try openTab("https://example.com/today", title: "Today", in: bench)   // in front; never sinks
        try bench.store.write { db in
            guard var stale = try Pantry.Tab.fetchOne(db, key: old.id) else { return }
            stale.touchedAt = Date().addingTimeInterval(-30 * 86_400)
            try stale.update(db)
        }

        bench.sweep()
        #expect(heard.lines == [Spoken(text: "Invoice terms sank into Brine", priority: .medium)])
        #expect(bench.statusLine == nil)

        bench.sweep()   // nothing left to sink: nothing said
        #expect(heard.lines.count == 1)
    }

    @Test("A page shared from another app waits its turn: it didn't come from a key just pressed")
    func shared() throws {
        let suite = "com.shepdesign.netrelish.tests.feedback-share.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let inbox = try #require(ShareInbox(suiteName: suite))
        let defaults = try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
        let bench = Workbench(store: try PantryStore(), inbox: inbox, defaults: defaults)

        inbox.add(SharedPage(url: "https://example.com/shared", title: "Shared from Safari"))
        bench.receiveShared()
        #expect(spoken(bench.statusLine) == Spoken(text: "Shared into Brine", priority: .medium))
    }
}
