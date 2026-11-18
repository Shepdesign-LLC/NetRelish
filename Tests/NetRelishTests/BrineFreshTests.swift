import Foundation
import GRDB
import Pantry
import Testing
@testable import NetRelish

/// The bottom bar's Brine pill is lit only for what landed in Brine since Brine was last open
/// (manifest v2.1 §4 #13). `brine.seenAt` lives in the injected defaults, so each test has its
/// own and none touches the app's.
@Suite("Brine fresh") @MainActor struct BrineFreshTests {

    private func scratchDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
    }

    /// Puts an item straight into Brine, last changed at `updatedAt`.
    private func brine(_ title: String, updatedAt: Date, in store: PantryStore) throws {
        var item = Item(state: .brined, title: title, updatedAt: updatedAt, url: "https://\(title.lowercased()).example")
        try store.write { db in try item.insert(db) }
    }

    @Test("Nothing is fresh at first launch, however much is already in Brine")
    func nothingFreshAtFirstLaunch() throws {
        let store = try PantryStore()
        try brine("Already", updatedAt: Date(), in: store)
        let defaults = try scratchDefaults()
        #expect(defaults.object(forKey: "brine.seenAt") == nil)

        let bench = Workbench(store: store, defaults: defaults)
        #expect(bench.brine.count == 1)
        #expect(bench.brineFresh == 0)
        #expect(defaults.object(forKey: "brine.seenAt") is Date)   // stamped "now", once
    }

    @Test("A tab that sinks afterwards is fresh")
    func sunkLaterIsFresh() async throws {
        let bench = Workbench(store: try PantryStore(), defaults: try scratchDefaults())
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let tab = try #require(bench.newTab(url: "https://ash.example"))
        #expect(bench.brineFresh == 0)

        try await Task.sleep(for: .milliseconds(20))   // past the stamp, at the store's precision
        try bench.store.write { db in
            guard var sinking = try Tab.fetchOne(db, key: tab.id) else { return }
            _ = try sinking.sink(db)
        }
        bench.load()
        #expect(bench.brine.count == 1)
        #expect(bench.brineFresh == 1)
    }

    @Test("Opening Brine sees everything in it, and leaving keeps it seen")
    func openingBrineSeesIt() async throws {
        let bench = Workbench(store: try PantryStore(), defaults: try scratchDefaults())
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        try await Task.sleep(for: .milliseconds(20))
        try brine("Sunk", updatedAt: Date(), in: bench.store)
        bench.load()
        #expect(bench.brineFresh == 1)

        bench.activateBrine()
        #expect(bench.activeSmartJar == .brine)
        #expect(bench.brineFresh == 0)

        let ash = try #require(bench.jars.first { $0.name == "Ash" })
        bench.activate(ash)
        #expect(bench.activeSmartJar == nil)
        #expect(bench.brineFresh == 0)
    }

    @Test("A saved copy over Brine hides it: what lands meanwhile stays fresh, and leaving from there doesn't see it")
    func savedCopyHidesBrine() async throws {
        let bench = Workbench(store: try PantryStore(), defaults: try scratchDefaults())
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        // The store is watched as in the app, so Brine stays selected while things land in it
        // (load() would put the stored jar back in front).
        let watching = Task { await bench.observe() }
        defer { watching.cancel() }
        bench.activateBrine()
        #expect(bench.brineShowing)

        let kept = Item(state: .sealed, title: "Kept", updatedAt: Date(), url: "https://kept.example")
        bench.savedCopy = kept
        #expect(!bench.brineShowing)
        try await Task.sleep(for: .milliseconds(20))
        try brine("Sunk", updatedAt: Date(), in: bench.store)
        for _ in 0..<200 where bench.brine.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(bench.brine.count == 1)
        #expect(bench.activeSmartJar == .brine)            // still selected...
        #expect(bench.brineFresh == 1)                     // ...but out of sight, so not yet seen

        let ash = try #require(bench.jars.first { $0.name == "Ash" })
        bench.activate(ash)                                // left from the saved copy
        #expect(bench.activeSmartJar == nil)
        #expect(bench.brineFresh == 1)                     // still unseen

        bench.activateBrine()
        bench.activate(ash)
        #expect(bench.brineFresh == 0)                     // seen once Brine itself was showing
    }

    @Test("Something older than the last look at Brine doesn't count")
    func olderDoesNotCount() throws {
        let bench = Workbench(store: try PantryStore(), defaults: try scratchDefaults())
        try brine("Old", updatedAt: bench.brineSeenAt.addingTimeInterval(-3600), in: bench.store)
        bench.load()
        #expect(bench.brine.count == 1)
        #expect(bench.brineFresh == 0)
    }

    @Test("The last look at Brine is remembered across launches")
    func seenAtIsRemembered() throws {
        let store = try PantryStore()
        let defaults = try scratchDefaults()
        let first = Workbench(store: store, defaults: defaults)
        let seen = first.brineSeenAt
        try brine("Later", updatedAt: seen.addingTimeInterval(60), in: store)

        let second = Workbench(store: store, defaults: defaults)
        #expect(abs(second.brineSeenAt.timeIntervalSince(seen)) < 0.001)
        #expect(second.brineFresh == 1)
    }
}
