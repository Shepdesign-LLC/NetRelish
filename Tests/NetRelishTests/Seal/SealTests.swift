import Foundation
import GRDB
import Pantry
import Testing
import WebKit
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

    @Test("A new jar runs Seal & Summarize on Seal")
    func newJarsSealAndSummarize() async throws {
        let bench = try bench()
        #expect(bench.activeJar?.defaultRecipeId == PantryStore.sealAndSummarizeRecipeId)
        await bench.sealActiveTab()
        let batches = try bench.store.read { db in try Batch.fetchAll(db) }
        #expect(batches.map(\.recipeId) == [PantryStore.sealAndSummarizeRecipeId])
    }

    @Test("With no default Recipe on the jar, sealing runs nothing")
    func noDefaultRecipe() async throws {
        let bench = try bench()
        var jar = bench.activeJar!
        try bench.store.write { db in
            jar.defaultRecipeId = nil
            try jar.update(db)
        }
        bench.load()
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
@Suite("Saved copy") @MainActor struct SavedCopyTests {

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
        #expect(bench.savedCopy?.id == item.id)
        #expect(bench.tabs.isEmpty)
        #expect(bench.snapshotData(for: item) == Data("WEBARCHIVE".utf8))
    }

    @Test("Open Live Page leaves the copy and opens the page in the item's jar")
    func opensTheLivePage() async throws {
        let (bench, item) = try await sealedBench()
        bench.open(item)
        bench.openLivePage(item)
        #expect(bench.savedCopy == nil)
        #expect(bench.activeTab?.url == item.url)
        #expect(bench.activeTab?.jarId == item.jarId)
    }

    @Test("Picking a jar or a tab leaves the saved copy")
    func leavesOnNavigation() async throws {
        let (bench, item) = try await sealedBench()
        bench.open(item)
        bench.activate(index: 0)
        #expect(bench.savedCopy == nil)
    }

    @Test("An item captured but not sealed still opens as a live tab")
    func unsealedOpensLive() async throws {
        let (bench, _) = try await sealedBench()
        let captured = try bench.store.write { db in try bench.store.root(db).capture(db, url: "https://example.com/other") }
        bench.open(captured)
        #expect(bench.savedCopy == nil)
        #expect(bench.activeTab?.url == "https://example.com/other")
    }

    @Test("With a saved copy showing, ⌘S, ⌘D and Pin leave the tab behind it alone, and ⌘W closes the copy")
    func commandsSkipTheHiddenTab() async throws {
        let (bench, item) = try await sealedBench()
        let hidden = try #require(bench.newTab(url: "https://example.com/live"))
        bench.tabDidNavigate(hidden.id, url: URL(string: "https://example.com/live"), title: "Live")
        let before = try bench.store.read { db in try Item.fetchCount(db) }
        bench.open(item)
        #expect(bench.benchTab == nil)

        await bench.sealActiveTab()
        bench.captureActivePage()
        bench.togglePinActiveTab()
        #expect(bench.tabs.map(\.id) == [hidden.id])
        #expect(bench.tabs.first?.isPinned == false)
        #expect(try bench.store.read { db in try Item.fetchCount(db) } == before)
        #expect(bench.savedCopy?.id == item.id)

        bench.closeActiveTab()
        #expect(bench.savedCopy == nil)
        #expect(bench.tabs.map(\.id) == [hidden.id])
        #expect(bench.benchTab?.id == hidden.id)
    }

    @Test("A link in the copy opens the live page in a new tab in the copy's jar")
    func linkOpensLive() async throws {
        let (bench, item) = try await sealedBench()
        bench.open(item)
        bench.openLink(URL(string: "https://example.com/terms")!, from: item)
        #expect(bench.savedCopy == nil)
        #expect(bench.activeTab?.url == "https://example.com/terms")
        #expect(bench.activeTab?.jarId == item.jarId)
    }

    @Test("The copy's web view runs no script, keeps nothing, and can't reach the network")
    func frozenConfiguration() {
        let config = SavedCopyNavigator.configuration()
        #expect(config.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(config.websiteDataStore.isPersistent == false)
        #expect(config.websiteDataStore.proxyConfigurations.count == 1)
    }

    @Test("The copy loads the archive once, and only a click leaves it")
    func navigationRules() {
        let page = URL(string: "https://example.com/invoice")!
        let other = URL(string: "https://example.com/terms")!
        func decide(_ url: URL, _ type: WKNavigationType, main: Bool = true, loaded: Bool = true) -> SavedCopyNavigator.Decision {
            SavedCopyNavigator.decide(url: url, type: type, isMainFrame: main, archiveLoaded: loaded, current: page)
        }
        #expect(decide(page, .other, loaded: false) == .allow)                        // the archive
        #expect(decide(other, .other) == .cancel)                                      // a redirect or refresh
        #expect(decide(other, .formSubmitted) == .cancel)
        #expect(decide(page, .reload) == .cancel)
        #expect(decide(other, .linkActivated) == .openInTab(other))
        #expect(decide(URL(string: "https://example.com/invoice#net-30")!, .linkActivated) == .allow)
        #expect(decide(URL(string: "mailto:ap@example.com")!, .linkActivated) == .openInApp(URL(string: "mailto:ap@example.com")!))
        #expect(decide(URL(string: "javascript:alert(1)")!, .linkActivated) == .cancel)
        #expect(decide(URL(string: "smb://example.com/share")!, .linkActivated) == .cancel)   // the copy reaches nothing
        #expect(decide(other, .other, main: false) == .allow)                          // the archive's own frames
    }

    @Test("The palette offers the copy's commands, not the hidden tab's")
    func paletteFollowsTheCopy() async throws {
        let (bench, item) = try await sealedBench()
        _ = bench.newTab(url: "https://example.com/live")
        bench.open(item)
        let titles = PaletteSource.commands(bench).map(\.title)
        #expect(titles.contains("Open Live Page"))
        #expect(titles.contains("Close Saved Copy"))
        #expect(!titles.contains("Seal this page"))
        #expect(!titles.contains("Close Tab"))
    }
}

/// A summarizer that always answers the same, for the Workbench's half of Seal & Summarize.
private struct FixedSummarizer: Summarizer {
    let text: String
    func readiness() async -> SummarizerReadiness { .ready }
    func summarize(_ page: SealedText) async throws -> String { text }
}

/// ⌘S, then the summary: Seal returns at once, and the summary lands after for the Panel.
@Suite("Seal & Summarize on the Bench") @MainActor struct SealAndSummarizeTests {

    @Test("After ⌘S the tab closes at once, and the summary lands for the Panel")
    func summaryLandsAfterSeal() async throws {
        let bench = Workbench(store: try PantryStore(), summarizer: FixedSummarizer(text: "Net thirty, with a pumpernickel clause."))
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        _ = bench.newTab(url: "https://example.com/invoice")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com/invoice"), title: "Invoice terms")
        bench.sealProvider = { _ in
            (Data("WEBARCHIVE".utf8),
             Extraction.Result(title: "Invoice terms", excerpt: "Net thirty.",
                               body: "The client agreed to net thirty with a pumpernickel clause."))
        }
        #expect(await bench.sealActiveTab())
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(bench.tabs.isEmpty, "the tab closed without waiting on the model")

        await bench.summarizeWaitingNow()   // joins the sweep ⌘S started, if it's still going
        #expect(bench.summary(of: item) == .done("Net thirty, with a pumpernickel clause."))
        #expect(bench.summaryRevision > 0, "the Panel is told to read it again")
    }

    @Test("The Panel's summary lines")
    func panelWords() {
        #expect(PanelText.summary(.done("Net thirty.")) == .summary("Net thirty."))
        #expect(PanelText.summary(.pending) == .note("Summarizing on this Mac…"))
        #expect(PanelText.summary(.unavailable(.appleIntelligenceOff))
                == .note("Turn on Apple Intelligence in System Settings and sealed pages get a summary here."))
        #expect(PanelText.summary(.retrying(attempts: 1)) == .note("Summarizing on this Mac…"))
        #expect(PanelText.summary(.failed) == .note("Apple Intelligence couldn’t summarize this page."))
    }
}

/// The live page's price, which a reseal finds changed.
@MainActor private final class PricePage {
    var price = "$29/mo"
}

/// Reseal & diff on the Bench: Seal Again loads the page off screen (stubbed), seals it, and
/// shows the two seals side by side.
@Suite("Reseal & diff on the Bench") @MainActor struct ResealTests {

    @Test("Seal Again makes a second seal and compares it with the first")
    func sealAgainCompares() async throws {
        let bench = Workbench(store: try PantryStore())
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        let jarId = try #require(bench.activeJar?.id)
        let link = "https://example.com/pricing"
        let page = PricePage()
        bench.offscreenLoader = { url, _ in
            Workbench.OffscreenPage(
                archive: Data("WEBARCHIVE".utf8),
                extracted: Extraction.Result(title: "Pricing", excerpt: "", body: "Pro costs \(page.price). Support is by email."),
                url: url.absoluteString, title: "Pricing")
        }
        let first = try await bench.sealPage(at: URL(string: link)!, into: jarId)
        page.price = "$39/mo"

        await bench.resealAndCompare(first)

        let seals = bench.seals(of: first)
        #expect(seals.count == 2)
        #expect(seals.last?.id == first.id)
        let comparison = try #require(bench.comparison)
        #expect(comparison.older.id == first.id)
        #expect(comparison.newer.id == seals.first?.id)
        #expect(comparison.diff?.changeCount == 1)
        #expect(bench.panelSubject == .savedCopy(comparison.newer))
        #expect(bench.resealingURL == nil)

        bench.closeComparison()
        #expect(bench.comparison == nil)
    }

    @Test("Compare with only one seal says so and opens nothing")
    func compareNeedsTwo() async throws {
        let bench = Workbench(store: try PantryStore())
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        bench.offscreenLoader = { url, _ in
            Workbench.OffscreenPage(archive: Data("W".utf8),
                                    extracted: Extraction.Result(title: "Pricing", excerpt: "", body: "Once."),
                                    url: url.absoluteString, title: "Pricing")
        }
        let only = try await bench.sealPage(at: URL(string: "https://example.com/once")!, into: bench.activeJar?.id)
        await bench.compareWithPrevious(only)
        #expect(bench.comparison == nil)
        #expect(bench.fillStatus == "This page has only been sealed once")
    }

    @Test("The comparison's words")
    func words() {
        #expect(ComparisonText.spoken([.init("Pro costs", .same), .init("$29/mo.", .removed)]) == "Pro costs Removed: $29/mo.")
        #expect(PanelText.moreSeals(1) == "1 earlier seal")
        #expect(PanelText.moreSeals(3) == "3 earlier seals")
    }
}
