import AppKit
import Foundation
import GRDB
import Pantry
import Testing
@testable import NetRelish

/// The app side of Shortcuts: Seal with a link (the off-screen load stubbed), Seal the page in
/// front, Open a Jar, and the off-screen page itself.
@Suite("Shortcuts in the app") @MainActor struct ShortcutsTests {

    private func bench() throws -> Workbench {
        let bench = Workbench(store: try PantryStore())
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        bench.offscreenLoader = { url, _ in
            Workbench.OffscreenPage(
                archive: Data("WEBARCHIVE".utf8),
                extracted: Extraction.Result(title: "Invoice terms", excerpt: "Net thirty.", body: "Net thirty with a pumpernickel clause."),
                url: url.absoluteString + "?redirected", title: "Invoice")
        }
        return bench
    }

    private var meridian: (Workbench) -> Jar? { { bench in bench.jars.first { $0.name == "Meridian" } } }

    @Test("Seal with a link makes a sealed, snapshotted item in the jar named, from Shortcuts")
    func sealsALink() async throws {
        let bench = try bench()
        let jar = try #require(meridian(bench))
        let item = try await bench.sealPage(at: URL(string: "https://example.com/invoice")!, into: jar.id)

        #expect(item.state == .sealed)
        #expect(item.jarId == jar.id)
        #expect(item.source == .shortcut)
        #expect(item.title == "Invoice terms")
        #expect(item.url == "https://example.com/invoice?redirected")   // where the page ended up
        let path = try #require(item.snapshotPath)
        #expect(try bench.store.snapshots.read(path) == Data("WEBARCHIVE".utf8))
        #expect(bench.fillStatus == "Sealed into Meridian")
        #expect(bench.sealedItems.contains { $0.id == item.id })      // the Sealed smart jar has it at once
    }

    @Test("With no jar named, a link seals into the jar it was last kept in")
    func sealsIntoTheKeptJar() async throws {
        let bench = try bench()
        let jar = try #require(meridian(bench))
        try bench.store.write { db in
            var kept = Item(title: "Kept", url: "https://example.com/kept", jarId: jar.id)
            try kept.insert(db)
        }
        let item = try await bench.sealPage(at: URL(string: "https://example.com/kept")!, into: nil)
        #expect(item.jarId == jar.id)
    }

    @Test("A link that isn't a web page, a jar that's gone, or a page that won't load seals nothing")
    func refusals() async throws {
        let bench = try bench()
        await #expect(throws: ShortcutError.notAWebPage) {
            try await bench.sealPage(at: URL(string: "file:///etc/hosts")!, into: nil)
        }
        await #expect(throws: ShortcutError.jarGone) {
            try await bench.sealPage(at: URL(string: "https://example.com/")!, into: "no-such-jar")
        }
        bench.offscreenLoader = { _, _ in throw HeadlessPage.Failure.timedOut(30) }
        await #expect(throws: ShortcutError.pageDidNotLoad("It took longer than 30 seconds.")) {
            try await bench.sealPage(at: URL(string: "https://example.com/slow")!, into: nil)
        }
        #expect(try bench.store.read { db in try Item.fetchCount(db) } == 0)
    }

    @Test("Seal with no link and no window seals the page in front off screen and closes its tab")
    func sealsTheFrontPageWithoutAWindow() async throws {
        let bench = try bench()
        _ = bench.newTab(url: "https://example.com/front")
        let tab = try #require(bench.activeTab)
        bench.tabDidNavigate(tab.id, url: URL(string: "https://example.com/front"), title: "Front page")
        #expect(bench.sealProvider == nil)   // no Bench on screen

        let title = try await bench.sealFrontPage()
        #expect(title == "Invoice terms")
        #expect(!bench.tabs.contains { $0.id == tab.id })
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.state == .sealed)
        #expect(item.jarId == tab.jarId)
    }

    @Test("Seal with no link and a window open seals the live tab, as ⌘S does")
    func sealsTheLiveFrontPage() async throws {
        let bench = try bench()
        _ = bench.newTab(url: "https://example.com/live")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com/live"), title: "Live page")
        bench.sealProvider = { _ in
            (Data("LIVE".utf8), Extraction.Result(title: "Live page", excerpt: "", body: "From the live tab."))
        }
        #expect(try await bench.sealFrontPage() == "Live page")
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.source == .browse)   // the same Seal as ⌘S
        #expect(try bench.store.snapshots.read(try #require(item.snapshotPath)) == Data("LIVE".utf8))
    }

    @Test("Seal with no link and nothing open says so")
    func nothingInFront() async throws {
        let bench = try bench()
        await #expect(throws: ShortcutError.nothingOpen) { try await bench.sealFrontPage() }
    }

    @Test("Open a Jar shows the jar, and refuses one that's gone")
    func openAJar() throws {
        let bench = try bench()
        let jar = try #require(meridian(bench))
        bench.activateBrine()
        #expect(bench.show(jarId: jar.id))
        #expect(bench.activeJar?.id == jar.id)
        #expect(!bench.show(jarId: "no-such-jar"))
    }

    @Test("The off-screen page loads, and Seal can read and freeze it")
    func headlessPage() async throws {
        let page = HeadlessPage(jarId: "headless-\(UUID().uuidString)")
        try await page.load(html: """
            <html><head><title>Terms</title></head><body><article><h1>Terms</h1>
            <p>The client agreed to net thirty with a pumpernickel clause on late payment, and the
            schedule runs from the first of the month to the last working day after it.</p>
            </article></body></html>
            """, baseURL: URL(string: "https://example.com/terms"))
        let extracted = try await Extraction.run(in: page.webView)
        #expect(extracted.body.contains("pumpernickel"))
        let archive = try await page.webView.dataForWebArchive()
        #expect(!archive.isEmpty)
    }
}
