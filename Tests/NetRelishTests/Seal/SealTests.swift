import Foundation
import GRDB
import Pantry
import Testing
@testable import NetRelish

/// Seal, with the web view stubbed: the archive bytes and the extraction are handed in, so
/// this suite is about what Seal *does to the Pantry*, not about WebKit.
@Suite("Seal") @MainActor struct SealTests {

    private func bench() throws -> Workbench {
        let store = try PantryStore()
        let bench = Workbench(store: store)
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        _ = bench.newTab(url: "https://example.com/invoice")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com/invoice"), title: "Invoice terms")
        bench.sealProvider = { _ in
            (Data("WEBARCHIVE".utf8),
             Extraction.Result(title: "Invoice terms", excerpt: "Net thirty.",
                               body: "The client agreed to net thirty with a pumpernickel clause."))
        }
        return bench
    }

    @Test("Sealing makes one Item in the jar, stamped and snapshotted, and closes the tab")
    func sealsIntoTheJar() async throws {
        let bench = try bench()
        let jarId = bench.activeJar!.id
        await bench.sealActiveTab()

        let items = try bench.store.read { db in try Item.fetchAll(db) }
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.jarId == jarId)                 // sealing is how a tab becomes pantry
        #expect(item.state == .sealed)
        #expect(item.sealedAt != nil)
        #expect(item.title == "Invoice terms")
        #expect(item.body?.contains("pumpernickel") == true)
        #expect(bench.tabs.isEmpty)                  // the tab closed
    }

    @Test("The snapshot is on disk at the path the Item records")
    func writesTheArchive() async throws {
        let bench = try bench()
        await bench.sealActiveTab()
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        let path = try #require(item.snapshotPath)
        #expect(try bench.store.snapshots.read(path) == Data("WEBARCHIVE".utf8))
    }

    @Test("A sealed page is findable by a phrase from its body, not just its title")
    func bodyReachesFTS() async throws {
        let bench = try bench()
        await bench.sealActiveTab()
        #expect(bench.searchPantry("pumpernickel").count == 1)
        #expect(bench.searchPantry("invoice").count == 1)
    }

    @Test("With no default Recipe on the jar, sealing runs nothing (P3 fills this in)")
    func noDefaultRecipe() async throws {
        let bench = try bench()
        await bench.sealActiveTab()
        let batches = try bench.store.read { db in try Batch.fetchCount(db) }
        #expect(batches == 0)
    }

    @Test("With a default Recipe, sealing runs it on the new item — non-negotiable 3")
    func runsTheJarsDefaultRecipe() async throws {
        let bench = try bench()
        var jar = bench.activeJar!
        try bench.store.write { db in
            var recipe = Recipe(name: "File it", trigger: .onSeal)
            try recipe.insert(db)
            jar.defaultRecipeId = recipe.id
            try jar.update(db)
        }
        bench.load()
        await bench.sealActiveTab()

        let batches = try bench.store.read { db in try Batch.fetchAll(db) }
        #expect(batches.count == 1)
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.batchId == batches.first?.id)
    }

    @Test("Sealing with no tab open does nothing and says so")
    func nothingToSeal() async throws {
        let bench = try bench()
        bench.closeActiveTab()
        await bench.sealActiveTab()
        #expect(try bench.store.read { db in try Item.fetchCount(db) } == 0)
        #expect(bench.fillStatus?.contains("Nothing") == true)
    }
}

/// Opening a sealed item from search shows its saved copy, not the live page.
@Suite("Sealed copy") @MainActor struct SealedCopyTests {

    private func sealedBench() async throws -> (Workbench, Item) {
        let store = try PantryStore()
        let bench = Workbench(store: store)
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        _ = bench.newTab(url: "https://example.com/invoice")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com/invoice"), title: "Invoice terms")
        bench.sealProvider = { _ in
            (Data("WEBARCHIVE".utf8),
             Extraction.Result(title: "Invoice terms", excerpt: "Net thirty.", body: "Net thirty with a pumpernickel clause."))
        }
        await bench.sealActiveTab()
        let item = try #require(bench.searchPantry("pumpernickel").first)
        return (bench, item)
    }

    @Test("Opening a sealed item shows its saved copy and opens no tab")
    func opensTheCopy() async throws {
        let (bench, item) = try await sealedBench()
        bench.open(item)
        #expect(bench.sealedCopy?.id == item.id)
        #expect(bench.tabs.isEmpty)
        #expect(bench.snapshotData(for: item) == Data("WEBARCHIVE".utf8))
    }

    @Test("Open Live Page leaves the copy and opens the page in the item's jar")
    func opensTheLivePage() async throws {
        let (bench, item) = try await sealedBench()
        bench.open(item)
        bench.openLivePage(item)
        #expect(bench.sealedCopy == nil)
        #expect(bench.activeTab?.url == item.url)
        #expect(bench.activeTab?.jarId == item.jarId)
    }

    @Test("Picking a jar or a tab leaves the saved copy")
    func leavesOnNavigation() async throws {
        let (bench, item) = try await sealedBench()
        bench.open(item)
        bench.activate(index: 0)
        #expect(bench.sealedCopy == nil)
    }

    @Test("An item captured but not sealed still opens as a live tab")
    func unsealedOpensLive() async throws {
        let (bench, _) = try await sealedBench()
        let captured = try bench.store.write { db in try bench.store.root(db).capture(db, url: "https://example.com/other") }
        bench.open(captured)
        #expect(bench.sealedCopy == nil)
        #expect(bench.activeTab?.url == "https://example.com/other")
    }
}
