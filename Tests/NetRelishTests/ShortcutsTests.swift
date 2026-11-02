import AppKit
import Foundation
import GRDB
import Pantry
import Testing
@testable import NetRelish

/// What a stub saw, for the tests that check what Seal asked for.
@MainActor private final class Seen {
    var jarIds: [String] = []
    var names: [[String]] = []
}

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

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("waited three seconds and it didn't happen")
    }

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
        bench.livePageAvailable = { _ in true }
        #expect(try await bench.sealFrontPage() == "Live page")
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.source == .browse)   // the same Seal as ⌘S
        #expect(try bench.store.snapshots.read(try #require(item.snapshotPath)) == Data("LIVE".utf8))
    }

    @Test("Seal with no link, a window open but the page not loaded yet, loads it off screen")
    func sealsAnUnloadedFrontPageOffScreen() async throws {
        let bench = try bench()
        _ = bench.newTab(url: "https://example.com/unloaded")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com/unloaded"), title: "Unloaded")
        bench.sealProvider = { _ in Issue.record("froze a page that hadn't loaded"); return (Data(), Extraction.Result(title: "", excerpt: "", body: "")) }
        bench.livePageAvailable = { _ in false }
        #expect(try await bench.sealFrontPage() == "Invoice terms")   // the off-screen stub's title
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.source == .shortcut)
    }

    @Test("Seal with no link and a jar named seals the page in front into that jar")
    func sealsTheFrontPageIntoTheNamedJar() async throws {
        let bench = try bench()
        _ = bench.newTab(url: "https://example.com/front")
        let tab = try #require(bench.activeTab)
        bench.tabDidNavigate(tab.id, url: URL(string: "https://example.com/front"), title: "Front page")
        let other = try #require(bench.jars.first { $0.id != tab.jarId })
        _ = try await bench.sealFrontPage(into: other.id)
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.jarId == other.id)

        _ = bench.newTab(url: "https://example.com/again")
        await #expect(throws: ShortcutError.jarGone) { try await bench.sealFrontPage(into: "no-such-jar") }
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

    @Test("A tab that goes to another page while Seal loads stays open, and only the first page is sealed")
    func tabMovesOnDuringSeal() async throws {
        let bench = try bench()
        _ = bench.newTab(url: "https://example.com/first")
        let tabId = try #require(bench.activeTab).id
        bench.tabDidNavigate(tabId, url: URL(string: "https://example.com/first"), title: "First")
        bench.offscreenLoader = { url, _ in
            bench.tabDidNavigate(tabId, url: URL(string: "https://example.com/second"), title: "Second")
            return Workbench.OffscreenPage(
                archive: Data("FIRST".utf8),
                extracted: Extraction.Result(title: "First", excerpt: "", body: "The first page."),
                url: url.absoluteString, title: "First")
        }
        #expect(try await bench.sealFrontPage() == "First")
        let open = try #require(bench.tabs.first { $0.id == tabId })
        #expect(open.url == "https://example.com/second")
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.url == "https://example.com/first")
    }

    @Test("Seal with no link loads the page in the tab's own jar, even when it seals into another")
    func loadsInTheTabsProfile() async throws {
        let bench = try bench()
        _ = bench.newTab(url: "https://example.com/account")
        let tab = try #require(bench.activeTab)
        let tabJar = try #require(tab.jarId)
        bench.tabDidNavigate(tab.id, url: URL(string: "https://example.com/account"), title: "Account")
        let other = try #require(bench.jars.first { $0.id != tabJar })
        let seen = Seen()
        let stub = bench.offscreenLoader
        bench.offscreenLoader = { url, jarId in
            seen.jarIds.append(jarId)
            return try await stub(url, jarId)
        }
        _ = try await bench.sealFrontPage(into: other.id)
        #expect(seen.jarIds == [tabJar])
        let item = try #require(try bench.store.read { db in try Item.fetchOne(db) })
        #expect(item.jarId == other.id)

        // A link is a page nobody has open: it loads in the jar it's going into.
        _ = try await bench.sealPage(at: URL(string: "https://example.com/link")!, into: other.id)
        #expect(seen.jarIds.last == other.id)
    }

    @Test("A page that loads but can't be frozen says so in plain words")
    func freezeFailureIsPlain() async throws {
        let bench = try bench()
        bench.offscreenLoader = { _, _ in throw NSError(domain: "WKErrorDomain", code: 4) }
        await #expect(throws: ShortcutError.couldNotSeal) {
            try await bench.sealPage(at: URL(string: "https://example.com/odd")!, into: nil)
        }
        #expect(try bench.store.read { db in try Item.fetchCount(db) } == 0)
    }

    @Test("A Shortcut stopped while the live page freezes keeps nothing and leaves the tab open")
    func stoppedLiveSeal() async throws {
        let bench = try bench()
        _ = bench.newTab(url: "https://example.com/live")
        let tabId = try #require(bench.activeTab).id
        bench.tabDidNavigate(tabId, url: URL(string: "https://example.com/live"), title: "Live page")
        bench.livePageAvailable = { _ in true }
        bench.sealProvider = { _ in
            withUnsafeCurrentTask { $0?.cancel() }   // the Shortcut is stopped mid-freeze
            return (Data("LIVE".utf8), Extraction.Result(title: "Live page", excerpt: "", body: ""))
        }
        let run = Task { try await bench.sealFrontPage() }
        let result = await run.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try bench.store.read { db in try Item.fetchCount(db) } == 0)
        #expect(bench.tabs.contains { $0.id == tabId })
    }

    @Test("Siri hears the jar names at launch and again when a jar is added")
    func jarNamesReachSiri() async throws {
        let bench = try bench()
        let seen = Seen()
        bench.onJarsChanged = { jars in seen.names.append(jars.map(\.name)) }
        let watching = Task { await bench.observe() }
        defer { watching.cancel() }
        try await until { !seen.names.isEmpty }
        #expect(seen.names.last?.contains("Meridian") == true)
        bench.newJar(name: "Pumpernickel", tint: nil, shelfLifeDays: 3)
        try await until { seen.names.last?.contains("Pumpernickel") == true }
    }

    @Test("The off-screen page follows a redirect after it loads, and a redirect that fails fails the load")
    func headlessPageFollowsRedirects() async throws {
        let page = HeadlessPage(jarId: "headless-\(UUID().uuidString)")
        await #expect(throws: HeadlessPage.Failure.self) {
            try await page.load(html: """
                <html><head><title>Moved</title></head><body><p>This page has moved.</p>
                <script>setTimeout(() => { location.href = "http://127.0.0.1:1/"; }, 20)</script>
                </body></html>
                """, baseURL: URL(string: "https://example.com/moved"), timeout: 10, settle: .seconds(2))
        }
    }
}
