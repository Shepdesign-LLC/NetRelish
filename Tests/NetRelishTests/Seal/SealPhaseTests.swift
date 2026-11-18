import Foundation
import GRDB
import Pantry
import Testing
@testable import NetRelish

/// Seal's two phases (ADR 0035): what the Workbench reports while the page freezes and when
/// the write returns, the sealed tab the strip still draws, and the jar-fill event. The motion
/// is presentation only, so every check here is also a check that Seal's effects happen when
/// they always did (non-negotiable 3).
@Suite("Seal phases") @MainActor struct SealPhaseTests {

    /// Holds Seal inside the provider until the test opens it.
    @MainActor final class Gate {
        private(set) var waiting = false
        private var continuation: CheckedContinuation<Void, Error>?

        func wait() async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                self.waiting = true
            }
        }

        func open() {
            continuation?.resume()
            continuation = nil
        }

        func fail() {
            continuation?.resume(throwing: Boom())
            continuation = nil
        }
    }

    struct Boom: Error {}

    nonisolated private static func page() -> (Data, Extraction.Result) {
        (Data("WEBARCHIVE".utf8),
         Extraction.Result(title: "Invoice terms", excerpt: "Net thirty.", body: "The client agreed to net thirty."))
    }

    private func bench() throws -> Workbench {
        let defaults = try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
        let bench = Workbench(store: try PantryStore(), defaults: defaults)
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        return bench
    }

    @discardableResult
    private func openTab(_ url: String, title: String, in bench: Workbench) throws -> Tab {
        let tab = try #require(bench.newTab(url: url))
        bench.tabDidNavigate(tab.id, url: URL(string: url), title: title)
        return try #require(bench.tabs.first { $0.id == tab.id })
    }

    /// Lets the Seal task run up to the provider.
    private func untilWaiting(_ gate: Gate) async {
        for _ in 0..<1000 where !gate.waiting { await Task.yield() }
        #expect(gate.waiting)
    }

    @Test("While the page freezes the phase is started, for the tab in front; the tab is still open")
    func startedWhileFreezing() async throws {
        let bench = try bench()
        let tab = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        let gate = Gate()
        bench.sealProvider = { _ in
            try await gate.wait()
            return Self.page()
        }
        #expect(bench.sealPhase == .idle)

        let sealing = Task { await bench.sealActiveTab() }
        await untilWaiting(gate)
        guard case .started(let run) = bench.sealPhase else {
            Issue.record("expected .started, got \(bench.sealPhase)")
            gate.open()
            _ = await sealing.value
            return
        }
        #expect(run.tab.id == tab.id)
        #expect(run.jarId == bench.activeJar?.id)
        #expect(run.index == 0)
        #expect(bench.tabs.contains { $0.id == tab.id })     // nothing has happened yet
        #expect(bench.sealHeldTab == nil)

        gate.open()
        #expect(await sealing.value)
    }

    @Test("When the write returns: frozen, the tab already closed, and the strip still draws it until it's let go")
    func frozenAtWriteReturn() async throws {
        let bench = try bench()
        try openTab("https://example.com/first", title: "First", in: bench)
        let tab = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        try openTab("https://example.com/last", title: "Last", in: bench)
        bench.activateTab(tab)
        let index = try #require(bench.tabs.firstIndex { $0.id == tab.id })
        bench.sealProvider = { _ in Self.page() }

        #expect(await bench.sealActiveTab())

        guard case .frozen(let run) = bench.sealPhase else {
            Issue.record("expected .frozen, got \(bench.sealPhase)")
            return
        }
        #expect(run.tab.id == tab.id && run.index == index)
        // Non-negotiable 3: the tab closed when the write returned, not when the motion ends.
        #expect(!bench.tabs.contains { $0.id == tab.id })
        let items = try bench.store.read { db in try Item.fetchAll(db) }
        #expect(items.count == 1 && items.first?.sealedAt != nil)
        // The strip draws its picture at its old place, and nothing else.
        var expected = bench.tabs.map(\.id)
        expected.insert(tab.id, at: index)
        #expect(bench.stripTabs.map(\.id) == expected)
        #expect(bench.isHeldBySeal(run.tab))
        #expect(!bench.isHeldBySeal(bench.tabs[0]))
        // The strip and the field keep the sealed tab in front until its chip leaves, while
        // the real active tab has already moved on.
        #expect(bench.sealHeldFrontTab?.id == tab.id)
        #expect(bench.activeTab?.id != tab.id)

        bench.releaseSealedTab(run.id)
        #expect(!bench.stripTabs.contains { $0.id == tab.id })
        #expect(bench.stripTabs == bench.tabs)
        #expect(!bench.isHeldBySeal(run.tab))
        #expect(bench.sealHeldFrontTab == nil)

        bench.sealPresentationEnded(run.id)
        #expect(bench.sealPhase == .idle)
        #expect(bench.sealPhase.isIdle)
    }

    @Test("Choosing where to go hands the front back at once; the strip still draws the sealed tab")
    func explicitNavigationReleasesFront() async throws {
        let bench = try bench()
        let other = try openTab("https://example.com/other", title: "Other", in: bench)
        let tab = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        bench.sealProvider = { _ in Self.page() }
        #expect(await bench.sealActiveTab())
        #expect(bench.sealHeldFrontTab?.id == tab.id)       // Seal's own successor: still held

        bench.activateTab(other)
        #expect(bench.sealHeldFrontTab == nil)              // picked a tab: it is in front now
        #expect(bench.stripTabs.contains { $0.id == tab.id })   // the chip hasn't left yet

        // ⌘T after a second Seal: the new tab is in front, with its own (empty) address.
        let next = try openTab("https://example.com/next", title: "Next", in: bench)
        bench.activateTab(next)
        #expect(await bench.sealActiveTab())
        #expect(bench.sealHeldFrontTab?.id == next.id)
        let blank = try #require(bench.newTab())
        #expect(bench.sealHeldFrontTab == nil)
        #expect(bench.activeTab?.id == blank.id)
    }

    @Test("Moving on while the page freezes: the write returns and the sealed tab doesn't take the front back")
    func navigatingDuringFreezeKeepsTheChoice() async throws {
        let bench = try bench()
        let other = try openTab("https://example.com/other", title: "Other", in: bench)
        let tab = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        let gate = Gate()
        bench.sealProvider = { _ in
            try await gate.wait()
            return Self.page()
        }
        let sealing = Task { await bench.sealActiveTab() }
        await untilWaiting(gate)

        bench.activateTab(other)                            // picked another tab mid-freeze
        gate.open()
        #expect(await sealing.value)

        #expect(!bench.tabs.contains { $0.id == tab.id })   // Seal still closed it (non-negotiable 3)
        #expect(bench.stripTabs.contains { $0.id == tab.id })   // its picture until the chip leaves
        #expect(bench.sealHeldFrontTab == nil)              // but the front stays where you put it
        #expect(bench.activeTab?.id == other.id)
    }

    @Test("Ending the presentation lets go of the tab and goes back to idle in one step")
    func presentationEndedReleases() async throws {
        let bench = try bench()
        let tab = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        bench.sealProvider = { _ in Self.page() }
        #expect(await bench.sealActiveTab())
        let run = try #require(bench.sealPhase.run)
        #expect(bench.stripTabs.contains { $0.id == tab.id })

        bench.sealPresentationEnded(run.id)
        #expect(bench.sealPhase == .idle)
        #expect(bench.sealHeldTab == nil)
        #expect(bench.stripTabs.isEmpty)
    }

    @Test("A failed write: failed, nothing written, the tab stays open, and the field says so with phase B")
    func failedKeepsTheTab() async throws {
        let bench = try bench()
        let tab = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        bench.sealProvider = { _ in throw Boom() }

        #expect(await bench.sealActiveTab() == false)

        guard case .failed(let run) = bench.sealPhase else {
            Issue.record("expected .failed, got \(bench.sealPhase)")
            return
        }
        #expect(run.tab.id == tab.id)
        #expect(bench.tabs.contains { $0.id == tab.id })
        #expect(bench.sealHeldTab == nil)
        #expect(bench.stripTabs == bench.tabs)
        #expect(!bench.isHeldBySeal(tab))
        // The failure line waits for phase B (never sooner than SealTiming.minimumA after the
        // press), so it never lands while the drops are still forming.
        let said = run.startedAt.addingTimeInterval(SealTiming.minimumA)
        if Date() < said { #expect(bench.fillStatus == nil) }
        for _ in 0..<150 where bench.fillStatus == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(bench.fillStatus == "Couldn’t seal this page")
        #expect(try bench.store.read { db in try Item.fetchCount(db) } == 0)
        #expect(bench.jarFill == nil)
    }

    @Test("A freeze that fails mid-way through the gate reports failed too")
    func failedWhileWaiting() async throws {
        let bench = try bench()
        let tab = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        let gate = Gate()
        bench.sealProvider = { _ in
            try await gate.wait()
            return Self.page()
        }
        let sealing = Task { await bench.sealActiveTab() }
        await untilWaiting(gate)
        gate.fail()
        #expect(await sealing.value == false)
        #expect(bench.sealPhase.run?.tab.id == tab.id)
        if case .failed = bench.sealPhase {} else { Issue.record("expected .failed, got \(bench.sealPhase)") }
        #expect(bench.tabs.contains { $0.id == tab.id })
    }

    @Test("Two overlapping seals: the second is a newer run, and the first still fills its jar")
    func overlappingSeals() async throws {
        let bench = try bench()
        let first = try openTab("https://example.com/first", title: "First", in: bench)
        let second = try openTab("https://example.com/second", title: "Second", in: bench)
        let jarId = try #require(bench.activeJar?.id)
        bench.activateTab(first)

        let gate = Gate()
        bench.sealProvider = { tab in
            if tab.id == first.id { try await gate.wait() }
            return Self.page()
        }
        let sealingFirst = Task { await bench.sealActiveTab() }
        await untilWaiting(gate)
        let firstRun = try #require(bench.sealPhase.run)
        #expect(firstRun.tab.id == first.id)

        bench.activateTab(second)
        #expect(await bench.sealActiveTab())
        let secondRun = try #require(bench.sealPhase.run)
        #expect(secondRun.tab.id == second.id)
        #expect(secondRun.id > firstRun.id)
        let fillsBefore = bench.jarFill?.serial ?? 0

        gate.open()
        #expect(await sealingFirst.value)
        // The overlay is presenting the second run; the first plays nothing, but its jar fills.
        #expect(bench.sealPhase.run?.id == secondRun.id)
        #expect(bench.jarFill?.jarId == jarId)
        #expect((bench.jarFill?.serial ?? 0) > fillsBefore)
        // Both tabs closed when their writes returned.
        #expect(bench.tabs.isEmpty)
        #expect(try bench.store.read { db in try Item.fetchCount(db) } == 2)
    }

    @Test("Each fill is a new event, even into the same jar")
    func fillsAreEvents() throws {
        let bench = try bench()
        let jarId = try #require(bench.activeJar?.id)
        bench.fillJar(jarId)
        let first = try #require(bench.jarFill)
        bench.fillJar(jarId)
        let second = try #require(bench.jarFill)
        #expect(first.jarId == jarId && second.jarId == jarId)
        #expect(first != second)
    }

    @Test("Dropping a tab on a jar fills that jar")
    func dropFillsTheJar() throws {
        let bench = try bench()
        let tab = try openTab("https://example.com/invoice", title: "Invoice terms", in: bench)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let ash = try #require(bench.jars.first { $0.name == "Ash" })
        #expect(bench.jarFill == nil)

        #expect(bench.drop([DragPayload.tab(tab.id).string], onJar: ash))
        #expect(bench.jarFill?.jarId == ash.id)
    }

    @Test("A drop that lands nothing fills nothing")
    func emptyDropFillsNothing() throws {
        let bench = try bench()
        let ash = try #require(bench.activeJar)
        #expect(!bench.drop(["some text from another app"], onJar: ash))
        #expect(bench.jarFill == nil)
    }
}
