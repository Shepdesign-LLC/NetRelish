import AppKit
import Foundation
import GRDB
import Pantry
import Testing
import WebKit
@testable import NetRelish

/// The test bundle, for its resources: the fixture page lives there, never in Resources/Zest.
private final class FixtureAnchor {}

/// The rule list, compiled once for the whole run (it is shared, as in the app).
@MainActor
private func compiledRules() async throws -> WKContentRuleList {
    ZestRules.shared.prepare()
    for _ in 0..<200 where ZestRules.shared.list == nil && !ZestRules.shared.failed {   // up to 10 s
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(!ZestRules.shared.failed, "WebKit refused the rule list")
    return try #require(ZestRules.shared.list)
}

/// An empty folder to serve from, for tests that never load a page.
private func emptyRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "zest-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

// MARK: Zest's store is never a jar's

@Suite("Zest's data store") struct ZestStoreTests {

    @Test("Zest's identifier is fixed, and is version 4, so no derived jar id can equal it")
    func fixedAndVersion4() {
        let zest = ZestProfile.storeIdentifier
        #expect(zest == JarProfile.zestStoreIdentifier)
        #expect(zest.uuid.6 >> 4 == 4)
        #expect(JarProfile.storeIdentifier(for: "read-later").uuid.6 >> 4 == 5)
    }

    @Test("No jar id maps to Zest's store, and no two jars share one, not even ones that spell it")
    func noJarCollides() {
        let zest = JarProfile.zestStoreIdentifier
        var ids = ["read-later", "reference", "brine", "zest", "Zest", "",
                   zest.uuidString, zest.uuidString.lowercased(),
                   // Strings that once hashed onto the moved jar's store, or might look like it.
                   "jar:" + zest.uuidString, "jar:" + zest.uuidString.lowercased(),
                   "zest:" + zest.uuidString, zest.uuidString + " "]
        for _ in 0..<2000 { ids.append(UUID().uuidString) }
        for i in 0..<2000 { ids.append("jar-\(i)") }
        // Two spellings of one UUID are one jar; anything else is a different jar.
        var owner: [UUID: String] = [:]
        for id in ids {
            let store = JarProfile.storeIdentifier(for: id)
            #expect(store != zest, "jar id \(id) maps to Zest's store")
            let jar = UUID(uuidString: id)?.uuidString ?? id
            if let other = owner[store] {
                #expect(other == jar, "jar ids '\(other)' and '\(id)' share a store")
            } else {
                owner[store] = jar
            }
        }
    }

    @Test("A jar whose id spells Zest's identifier still gets one stable store of its own")
    func spellingJarIsStable() {
        let spelled = JarProfile.zestStoreIdentifier.uuidString
        let first = JarProfile.storeIdentifier(for: spelled)
        #expect(first == JarProfile.storeIdentifier(for: spelled))
        #expect(first == JarProfile.storeIdentifier(for: spelled.lowercased()))   // one jar, one store
        #expect(first != JarProfile.zestStoreIdentifier)
        #expect(first != JarProfile.storeIdentifier(for: "jar:" + spelled))
        // Every other UUID jar id still maps to itself, as it always has.
        let other = UUID()
        #expect(JarProfile.storeIdentifier(for: other.uuidString) == other)
    }
}

// MARK: The rule list

@Suite("Zest rule list") struct ZestRuleListTests {

    private func filters() throws -> [NSRegularExpression] {
        let json = try JSONSerialization.jsonObject(with: Data(ZestRules.json.utf8))
        let rules = try #require(json as? [[String: Any]])
        #expect(!rules.isEmpty)
        return try rules.map { rule in
            let action = try #require(rule["action"] as? [String: Any])
            #expect(action["type"] as? String == "block")
            #expect(action.count == 1)
            let trigger = try #require(rule["trigger"] as? [String: Any])
            // Only a URL filter: no resource types, no domains, no load types, nothing that
            // would narrow a rule to some loads and let the others through.
            #expect(Set(trigger.keys) == ["url-filter"])
            let pattern = try #require(trigger["url-filter"] as? String)
            // WebKit matches url-filter case-insensitively by default.
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
    }

    private func blocked(_ url: String, by filters: [NSRegularExpression]) -> Bool {
        filters.contains { $0.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil }
    }

    @Test("http, https, ws, wss and file are blocked")
    func blocksTheWeb() throws {
        let filters = try filters()
        for url in ["http://example.com/", "https://example.com/a?b=c", "HTTPS://EXAMPLE.COM/",
                    "ws://example.com/", "wss://example.com/socket", "WSS://example.com/",
                    "file:///etc/passwd", "file://localhost/Users/", "FILE:///tmp/x"] {
            #expect(blocked(url, by: filters), "\(url) should be blocked")
        }
    }

    @Test("Nothing else is blocked: the tools' own files, data:, blob:, about:, app links")
    func blocksNothingElse() throws {
        let filters = try filters()
        for url in ["zest://app/index.html", "zest://app/mail/", "zest://app/https://example.com",
                    "data:text/plain,hi", "data:image/png;base64,AAAA", "blob:zest://app/3f2a9c",
                    "about:blank", "about:srcdoc", "mailto:someone@example.com", "javascript:void(0)"] {
            #expect(!blocked(url, by: filters), "\(url) should not be blocked")
        }
    }

    @Test("WebKit compiles it")
    @MainActor func compiles() async throws {
        _ = try await compiledRules()
    }
}

// MARK: The stub, the scheme and the store belong to Zest views only

@Suite("Zest configuration") @MainActor struct ZestConfigurationTests {

    private func carriesStub(_ config: WKWebViewConfiguration) -> Bool {
        config.userContentController.userScripts.contains { ZestWebView.isStub($0) || $0.source.contains("netrelish") }
    }

    @Test("A Zest view carries the stub, the zest: scheme, the rule list's store and Zest's store")
    func zestConfiguration() async throws {
        let config = ZestWebView.configuration(rules: try await compiledRules(), root: try emptyRoot())
        #expect(config.userContentController.userScripts.contains { ZestWebView.isStub($0) })
        #expect(config.urlSchemeHandler(forURLScheme: "zest") != nil)
        #expect(config.websiteDataStore.identifier == JarProfile.zestStoreIdentifier)
        #expect(config.preferences.javaScriptCanOpenWindowsAutomatically == false)
    }

    @Test("A tool's view is made once, on first use, and kept while the window is open")
    func viewsAreKept() async throws {
        let model = ZestWindowModel()
        let rules = try await compiledRules()
        let root = try emptyRoot()
        #expect(model.madeTools.isEmpty)
        let mail = model.view(for: .mail, rules: rules, root: root)
        #expect(model.view(for: .mail, rules: rules, root: root) === mail)
        #expect(model.madeTools == [.mail])
        #expect(mail.webView.configuration.websiteDataStore.identifier == JarProfile.zestStoreIdentifier)
        mail.showTool?(.md)          // a link to another tool moves the switcher
        #expect(model.tool == .md)
    }

    @Test("A jar's web view never carries the stub, the zest: scheme or Zest's store")
    func jarConfigurationIsClean() throws {
        let tab = JarWebView(jarId: "stub-test-\(UUID().uuidString)").webView.configuration
        #expect(!carriesStub(tab))
        #expect(tab.urlSchemeHandler(forURLScheme: "zest") == nil)
        #expect(tab.websiteDataStore.identifier != JarProfile.zestStoreIdentifier)

        // The same for the read-later jar's fixed id, and for Seal from Shortcuts' off-screen page.
        let seeded = JarWebView(jarId: "read-later").webView.configuration
        #expect(!carriesStub(seeded))
        #expect(seeded.websiteDataStore.identifier != JarProfile.zestStoreIdentifier)
        let headless = HeadlessPage(jarId: "stub-test-\(UUID().uuidString)").webView.configuration
        #expect(!carriesStub(headless))
        #expect(headless.urlSchemeHandler(forURLScheme: "zest") == nil)
    }

    @Test("A page in a jar sees no window.netrelish")
    func jarPageHasNoStub() async throws {
        let web = JarWebView(jarId: "stub-test-\(UUID().uuidString)")
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web.webView
        web.webView.loadHTMLString("<html><head><title>jar page</title></head><body>hi</body></html>", baseURL: nil)
        for _ in 0..<100 where web.webView.title != "jar page" { try await Task.sleep(for: .milliseconds(50)) }
        // The page must have loaded: the empty first document has no user scripts, so probing
        // it would pass whatever the jar's configuration carries.
        try #require(web.webView.title == "jar page", "the jar page never loaded")
        let seen = try await web.webView.evaluateJavaScript("typeof window.netrelish")
        #expect(seen as? String == "undefined")
        window.orderOut(nil)
    }
}

// MARK: Routing

@Suite("Zest routing") @MainActor struct ZestRoutingTests {

    private func route(_ url: String, mainFrame: Bool = true, clicked: Bool = true, download: Bool = false,
                       from tool: ZestTool = .mail) -> ZestRoute {
        ZestWebView.route(URL(string: url), mainFrame: mainFrame, clicked: clicked, download: download, from: tool)
    }

    @Test("A tool's own files load; a link to another tool moves the switcher")
    func zestLinks() {
        #expect(route("zest://app/mail/index.html", clicked: false) == .allow)
        #expect(route("zest://app/mail/assets/app.js", mainFrame: false) == .allow)
        #expect(route("zest://app/md/") == .switchTool(.md))
        #expect(route("zest://app/", from: .image) == .switchTool(.studio))
        #expect(route("zest://app/mail/", from: .mail) == .allow)
        #expect(route("zest://elsewhere/") == .cancel)
    }

    @Test("A clicked web link goes to the active jar; anything else on the web goes nowhere")
    func webLinks() {
        let url = URL(string: "https://example.com/docs")!
        #expect(route("https://example.com/docs") == .openInJar(url))
        #expect(route("http://example.com/docs") == .openInJar(URL(string: "http://example.com/docs")!))
        #expect(route("https://example.com/docs", clicked: false) == .cancel)
        #expect(route("https://example.com/frame", mainFrame: false, clicked: false) == .cancel)
        #expect(route("wss://example.com/") == .cancel)
        #expect(route("file:///etc/passwd") == .cancel)
    }

    @Test("blob: and data: download when they'd replace the tool, and show inside a frame")
    func files() {
        #expect(route("blob:zest://app/3f2a") == .download)
        #expect(route("data:text/plain,hi", clicked: false) == .download)
        #expect(route("blob:zest://app/3f2a", mainFrame: false) == .allow)
        #expect(route("about:srcdoc", mainFrame: false) == .allow)
    }

    @Test("A link marked download saves only the tool's own files, blob: and data:")
    func downloadLinks() {
        #expect(route("blob:zest://app/3f2a", mainFrame: false, download: true) == .download)
        #expect(route("data:text/plain,hi", clicked: false, download: true) == .download)
        #expect(route("zest://app/mail/sample.html", download: true) == .download)
        #expect(route("zest://elsewhere/x", download: true) == .cancel)
        #expect(route("about:blank", download: true) == .cancel)
    }

    @Test("A download link to the web is never a download: a click opens it in the jar, a script gets nothing")
    func webDownloadLinks() {
        let leak = "https://example.com/x?d=what-the-tool-holds"
        #expect(route(leak, download: true) == .openInJar(URL(string: leak)!))
        #expect(route(leak, clicked: false, download: true) == .cancel)
        #expect(route(leak, mainFrame: false, clicked: false, download: true) == .cancel)
        #expect(route("http://example.com/x", clicked: false, download: true) == .cancel)
        #expect(route("wss://example.com/x", download: true) == .cancel)
        #expect(route("file:///etc/passwd", download: true) == .cancel)
    }

    @Test("Links for other apps follow the Bench's handoff rules")
    func otherApps() {
        let mail = URL(string: "mailto:someone@example.com")!
        #expect(route("mailto:someone@example.com") == .handOff(.open(mail)))
        let zoom = URL(string: "zoommtg://zoom.us/join")!
        #expect(route("zoommtg://zoom.us/join") == .handOff(.ask(zoom)))
    }

    @Test("Each tool has one URL, and the URL maps back to the tool")
    func toolTable() {
        #expect(ZestTool.studio.url.absoluteString == "zest://app/index.html")
        #expect(ZestTool.mail.url.absoluteString == "zest://app/mail/index.html")
        #expect(ZestTool.md.url.absoluteString == "zest://app/md/index.html")
        #expect(ZestTool.image.url.absoluteString == "zest://app/image/index.html")
        for tool in ZestTool.allCases { #expect(ZestTool(url: tool.url) == tool) }
        #expect(ZestTool(url: URL(string: "zest://app/mail/")!) == .mail)
        #expect(ZestTool(url: URL(string: "zest://app/")!) == .studio)
        #expect(ZestTool(url: URL(string: "zest://app/mail/app.js")!) == nil)
        #expect(ZestTool(url: URL(string: "zest://app/store/")!) == nil)
        #expect(Set(ZestTool.allCases.map(\.title)) == ["Studio", "Mail", "MD", "Image"])
    }
}

// MARK: Seal, Capture and Fill from Me stand down while Zest is in front

@Suite("Zest in front") @MainActor struct ZestGatingTests {

    private func bench() throws -> Workbench {
        let bench = Workbench(store: try PantryStore())
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        _ = bench.newTab(url: "https://example.com/invoice")
        bench.tabDidNavigate(bench.activeTab!.id, url: URL(string: "https://example.com/invoice"), title: "Invoice")
        bench.sealProvider = { _ in
            (Data("WEBARCHIVE".utf8), Extraction.Result(title: "Invoice", excerpt: "", body: "Net thirty."))
        }
        return bench
    }

    @Test("With Zest in front there is no page in front, but the Bench still shows its tab")
    func pageInFront() throws {
        let bench = try bench()
        #expect(bench.pageInFront != nil)
        bench.setZestInFront(true)
        #expect(bench.pageInFront == nil)
        #expect(bench.benchTab != nil)
        bench.setZestInFront(false)
        #expect(bench.pageInFront?.id == bench.activeTab?.id)
    }

    @Test("Seal, Capture, Fill from Me, Reader, Pin and Close Tab do nothing while Zest is in front")
    func commandsStandDown() async throws {
        let bench = try bench()
        var filled = 0
        bench.formFiller = { _, _ in filled += 1; return 1 }
        var read = 0
        bench.readerProvider = { _ in read += 1; return nil }
        bench.setZestInFront(true)

        #expect(await bench.sealActiveTab() == false)
        bench.captureActivePage()
        bench.fillFromMe()
        await bench.toggleReader()
        bench.togglePinActiveTab()
        bench.closeActiveTab()

        let items = try bench.store.read { db in try Item.fetchAll(db) }
        #expect(items.isEmpty)                       // nothing sealed, nothing captured
        #expect(bench.tabs.count == 1)               // the tab neither sealed nor closed
        #expect(bench.tabs.first?.isPinned == false)
        #expect(filled == 0)
        #expect(read == 0)
        #expect(bench.reader == nil)
        await #expect(throws: ShortcutError.nothingOpen) { try await bench.sealFrontPage() }

        // Back in the main window, Seal works again.
        bench.setZestInFront(false)
        #expect(await bench.sealActiveTab() == true)
        #expect(try bench.store.read { db in try Item.fetchCount(db) } == 1)
    }

    @Test("⌘K offers no page commands while Zest is in front")
    func paletteStandsDown() throws {
        let bench = try bench()
        #expect(PaletteSource.rows(for: "", workbench: bench).map(\.title).contains("Seal this page"))
        bench.setZestInFront(true)
        let titles = PaletteSource.rows(for: "", workbench: bench).map(\.title)
        #expect(!titles.contains("Seal this page"))
        #expect(!titles.contains("Capture this page"))
        #expect(!titles.contains("Fill this form"))
    }

    @Test("The Zest window, or a sheet on it, is Zest; any other window is not")
    func whichWindowIsZest() {
        let zest = window(), main = window()
        #expect(Workbench.isZest(zest, zest: zest))
        #expect(!Workbench.isZest(main, zest: zest))
        #expect(!Workbench.isZest(nil, zest: zest))
        #expect(!Workbench.isZest(main, zest: nil))
    }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100), styleMask: .titled,
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test("Main changes: Zest becoming main puts it in front; another window or Zest resigning takes it out")
    func mainChanges() throws {
        let bench = try bench()
        let zest = window(), main = window()
        bench.zestWindow = zest

        bench.mainWindowChanged(zest, becameMain: true)
        #expect(bench.zestInFront)
        bench.mainWindowChanged(main, becameMain: false)   // another window resigning changes nothing
        #expect(bench.zestInFront)
        bench.mainWindowChanged(zest, becameMain: false)   // closed, or the app went to the background
        #expect(!bench.zestInFront)
        bench.mainWindowChanged(zest, becameMain: true)
        bench.mainWindowChanged(main, becameMain: true)    // the main window came forward
        #expect(!bench.zestInFront)
    }

    @Test("A color panel or save panel taking key leaves Zest in front")
    func panelsLeaveZestInFront() async throws {
        let bench = try bench()
        let zest = window()
        bench.zestWindow = zest
        bench.mainWindowChanged(zest, becameMain: true)
        #expect(bench.zestInFront)

        // A panel taking key posts no main change at all: Zest stays main.
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 200, height: 100), styleMask: .titled,
                            backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        #expect(!panel.canBecomeMain)
        // And if one were ever said to become main, it still changes nothing.
        bench.mainWindowChanged(panel, becameMain: true)
        #expect(bench.zestInFront)
        bench.mainWindowChanged(panel, becameMain: false)
        #expect(bench.zestInFront)
        #expect(bench.pageInFront == nil)
        #expect(await bench.sealActiveTab() == false)
    }

    @Test("Before any Zest window exists, main changes leave the page commands alone")
    func noZestWindowYet() throws {
        let bench = try bench()
        bench.mainWindowChanged(window(), becameMain: true)
        #expect(!bench.zestInFront)
        #expect(bench.pageInFront != nil)
    }
}

// MARK: In WebKit, through the real scheme handler (part of ADR 0015 risk 1)

/// Every test here runs on a throwaway data store of its own, never Zest's real one: the tests
/// are hosted in NetRelish.app, so Zest's store here is the person's own saved work.
/// `ZestConfigurationTests` checks that the app's configuration uses Zest's store.
@Suite("Zest host, in WebKit") @MainActor struct ZestHostIntegrationTests {

    /// A folder holding the fixture as its index.html, copied out of the test bundle.
    private func fixtureRoot() throws -> URL {
        let path = try #require(Bundle(for: FixtureAnchor.self).path(forResource: "zest-fixture", ofType: "html"),
                                "the fixture isn't in the test bundle")
        let page = try #require(FileManager.default.contents(atPath: path))
        let root = FileManager.default.temporaryDirectory.appending(path: "zest-host-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try page.write(to: root.appending(path: "index.html"))
        return root
    }

    /// A Zest web view on `store`, in a window (a WKWebView only loads while it's in one).
    private func zestView(rules: WKContentRuleList, root: URL, store: UUID) -> (WKWebView, NSWindow) {
        let config = ZestWebView.configuration(rules: rules, root: root,
                                               dataStore: WKWebsiteDataStore(forIdentifier: store))
        let web = WKWebView(frame: .init(x: 0, y: 0, width: 400, height: 300), configuration: config)
        return (web, host(web))
    }

    private func host(_ web: WKWebView) -> NSWindow {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        return window
    }

    /// Empties a test's store and removes it. Removing can fail while WebKit still holds the
    /// store; what's left is then an empty store in the test host's container.
    private func discard(_ store: UUID, windows: [NSWindow]) async {
        for window in windows { window.contentView = nil; window.orderOut(nil) }
        await WKWebsiteDataStore(forIdentifier: store)
            .removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        try? await WKWebsiteDataStore.remove(forIdentifier: store)
    }

    private func waitForFixture(_ web: WKWebView, _ url: URL) async throws {
        for _ in 0..<200 {   // up to 10 s
            try await Task.sleep(for: .milliseconds(50))
            if !web.isLoading, web.title == "zest fixture" { return }
        }
        Issue.record("timed out loading \(url.absoluteString)")
    }

    private func load(_ web: WKWebView, _ url: URL) async throws {
        web.load(URLRequest(url: url))
        try await waitForFixture(web, url)
    }

    private func string(_ web: WKWebView, _ script: String) async throws -> String {
        let result = try await web.evaluateJavaScript(script)
        return result as? String ?? "<not a string>"
    }

    /// Only that the store is shared between views in one process. Whether WebKit writes
    /// zest:// storage to disk, so it survives a relaunch, and whether IndexedDB works there,
    /// this can't see: both are open checks for phase 2 and the pull request's demo.
    @Test("localStorage on zest:// is shared between two views on one store, in one process")
    func storageShared() async throws {
        let rules = try await compiledRules()
        let root = try fixtureRoot()
        let store = UUID()
        let key = "zest-host-\(UUID().uuidString)"
        let url = try #require(URL(string: "zest://app/index.html?key=\(key)&write=1"))

        let (first, firstWindow) = zestView(rules: rules, root: root, store: store)
        try await load(first, url)
        #expect(try await string(first, "window.fixtureFound") == "null")
        #expect(try await string(first, "String(localStorage.getItem('\(key)'))") == "kept")
        #expect(try await string(first, "location.protocol") == "zest:")
        // Not a pass or fail: what the clipboard and crypto APIs will see, for the phase-2 notes.
        let secure = try await string(first, "String(window.isSecureContext)")
        print("Zest host: isSecureContext on zest:// is \(secure)")

        // A second view, on its own configuration over the same store, reading without writing.
        let (second, secondWindow) = zestView(rules: rules, root: root, store: store)
        try await load(second, try #require(URL(string: "zest://app/index.html?key=\(key)")))
        var seen = ""
        for _ in 0..<40 {   // up to 2 s for the write to reach the storage process
            seen = try await string(second, "String(localStorage.getItem('\(key)'))")
            if seen == "kept" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(seen == "kept", "the second Zest view didn't see the first one's localStorage")

        await discard(store, windows: [firstWindow, secondWindow])
    }

    @Test("A fetch to the web is blocked, with the policy header and by the rule list alone")
    func fetchIsBlocked() async throws {
        let rules = try await compiledRules()
        let store = UUID()
        let (web, window) = zestView(rules: rules, root: try fixtureRoot(), store: store)
        try await load(web, try #require(URL(string: "zest://app/")))
        let attempt = """
        try { await fetch('https://example.com/', {mode: 'no-cors', cache: 'no-store'}); return 'reached'; }
        catch (e) { return 'blocked'; }
        """
        let served = try await web.callAsyncJavaScript(attempt, in: nil, contentWorld: .page)
        #expect(served as? String == "blocked")

        // The same page with no policy header (markup loaded straight in, on the zest origin):
        // only the rule list stands between it and the web.
        web.loadHTMLString("<html><head><title>zest unguarded</title></head><body></body></html>",
                           baseURL: URL(string: "zest://app/"))
        for _ in 0..<100 where web.title != "zest unguarded" { try await Task.sleep(for: .milliseconds(50)) }
        #expect(web.title == "zest unguarded")
        let unguarded = try await web.callAsyncJavaScript(attempt, in: nil, contentWorld: .page)
        #expect(unguarded as? String == "blocked")
        await discard(store, windows: [window])
    }

    @Test("A download link to the web, clicked by a script, starts no download and fetches nothing")
    func webDownloadLinkIsNoDownload() async throws {
        let rules = try await compiledRules()
        let root = try fixtureRoot()
        let store = UUID()
        // The real Zest view, with its navigation delegate: the studio's page is the fixture.
        let zest = ZestWebView(tool: .studio, rules: rules, root: root,
                               dataStore: WKWebsiteDataStore(forIdentifier: store))
        var openedInJar: [URL] = []
        zest.openInJar = { openedInJar.append($0) }
        let window = host(zest.webView)
        try await waitForFixture(zest.webView, ZestTool.studio.url)

        let leak = "https://example.com/zest-download-probe?d=what-the-tool-holds"
        _ = try await zest.webView.evaluateJavaScript("""
        (() => {
          const a = document.createElement('a');
          a.href = '\(leak)';
          a.download = 'probe.txt';
          document.body.appendChild(a);
          a.click();
          return 'clicked';
        })()
        """)
        try await Task.sleep(for: .seconds(1))   // time for a policy decision and a download to start

        #expect(zest.downloadsStarted == 0, "a download link to the web became a WKDownload")
        #expect(zest.webView.title == "zest fixture")          // the tool's page stayed put
        #expect(zest.webView.url?.scheme == ZestFiles.scheme)
        // A scripted click may or may not count as a click to WebKit; either way, the only
        // place the link may go is a page in the active jar.
        #expect(openedInJar.allSatisfy { $0.absoluteString == leak })
        await discard(store, windows: [window])
    }

    @Test("window.netrelish is there, frozen, and can't be replaced")
    func stubIsFrozen() async throws {
        let rules = try await compiledRules()
        let store = UUID()
        let (web, window) = zestView(rules: rules, root: try fixtureRoot(), store: store)
        try await load(web, try #require(URL(string: "zest://app/")))
        let probe = """
        (() => {
          'use strict';
          const before = window.netrelish;
          try { window.netrelish = {network: true}; } catch (e) {}
          try { window.netrelish.network = true; } catch (e) {}
          try { window.netrelish.license = () => 'pro'; } catch (e) {}
          try { delete window.netrelish; } catch (e) {}
          return [Object.isFrozen(window.netrelish), window.netrelish === before,
                  window.netrelish.network, window.netrelish.host, window.netrelish.version,
                  typeof window.netrelish.license].join(',');
        })()
        """
        #expect(try await string(web, probe) == "true,true,false,app,0,undefined")
        await discard(store, windows: [window])
    }

    @Test("A missing file is the plain not-in-this-build page")
    func missingFile() async throws {
        let rules = try await compiledRules()
        let store = UUID()
        let (web, window) = zestView(rules: rules, root: try fixtureRoot(), store: store)
        web.load(URLRequest(url: try #require(URL(string: "zest://app/nothing-here.html"))))
        for _ in 0..<100 where web.title != "Not in this build" { try await Task.sleep(for: .milliseconds(50)) }
        #expect(web.title == "Not in this build")
        await discard(store, windows: [window])
    }
}
