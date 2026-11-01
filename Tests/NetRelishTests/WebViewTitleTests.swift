import Pantry
import Testing
import WebKit
@testable import NetRelish

/// WKWebView sets `title` after didFinish for most pages, so the delegate alone misses it.
@Suite("Web view title") struct WebViewTitleTests {

    @Test("The page title reaches the tab, not just the URL")
    @MainActor func titleArrives() async throws {
        let web = JarWebView(jarId: "title-test-\(UUID().uuidString)")
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web.webView

        var reported: String?
        web.onNavigation = { _, title in if !title.isEmpty { reported = title } }
        web.webView.loadHTMLString("<html><head><title>Example Domain</title></head><body>hi</body></html>", baseURL: URL(string: "https://example.com"))

        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            if web.title == "Example Domain" { break }
        }
        #expect(web.title == "Example Domain")
        #expect(reported == "Example Domain")
    }
}

/// target=_blank and window.open: WebKit asks the UI delegate for a web view, and the Bench
/// answers with a new tab in the opener's jar.
@Suite("New windows") @MainActor struct NewWindowTests {

    private func setUp() throws -> (Workbench, BenchWebViews, JarWebView) {
        let bench = Workbench(store: try PantryStore())
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        let opener = try #require(bench.newTab(url: "https://example.com/"))
        let webViews = BenchWebViews()
        webViews.makeTab = { jarId, openerId in bench.newTab(in: jarId, openedBy: openerId) }
        webViews.closeTab = { tabId in bench.closeTab(id: tabId) }
        return (bench, webViews, webViews.view(for: opener))
    }

    @Test("A new window becomes a new, active tab in the opener's jar")
    func opensATab() throws {
        let (bench, webViews, opener) = try setUp()
        let child = try #require(webViews.openNewWindow(from: opener, configuration: opener.webView.configuration))

        #expect(bench.tabs.count == 2)
        let tab = try #require(bench.activeTab)
        #expect(tab.jarId == opener.jarId)
        let adopted = try #require(webViews.existing(for: tab.id))
        #expect(adopted.webView === child)          // WebKit loads the page into the view we returned
        #expect(adopted.openedByPage)
    }

    @Test("A page that closes its own window closes its tab")
    func closesItsTab() throws {
        let (bench, webViews, opener) = try setUp()
        _ = try #require(webViews.openNewWindow(from: opener, configuration: opener.webView.configuration))
        let popupTab = try #require(bench.activeTab)
        let child = try #require(webViews.existing(for: popupTab.id))

        child.webViewDidClose(child.webView)
        #expect(bench.tabs.count == 1)
    }

    @Test("With no way to make a tab, WebKit gets nil and no tab appears")
    func noTabMaker() throws {
        let (bench, webViews, opener) = try setUp()
        webViews.makeTab = nil
        #expect(webViews.openNewWindow(from: opener, configuration: opener.webView.configuration) == nil)
        #expect(bench.tabs.count == 1)
    }

    @Test("Closing a page's window goes back to the tab that opened it")
    func returnsToOpener() throws {
        let (bench, webViews, _) = try setUp()
        let second = try #require(bench.newTab(url: "https://example.com/second"))
        let opener = webViews.view(for: second)            // not the first tab, so first-tab fallback can't pass this
        _ = try #require(webViews.openNewWindow(from: opener, configuration: opener.webView.configuration))
        let popupTab = try #require(bench.activeTab)
        let child = try #require(webViews.existing(for: popupTab.id))

        child.webViewDidClose(child.webView)
        #expect(bench.activeTabId == second.id)
    }

    @Test("A page can't close a tab you pinned")
    func pinnedStays() throws {
        let (bench, webViews, opener) = try setUp()
        _ = try #require(webViews.openNewWindow(from: opener, configuration: opener.webView.configuration))
        let popupTab = try #require(bench.activeTab)
        let child = try #require(webViews.existing(for: popupTab.id))
        bench.togglePinActiveTab()

        child.webViewDidClose(child.webView)
        #expect(bench.tabs.count == 2)
    }

    @Test("A tab you opened yourself ignores window.close()")
    func ownTabIgnoresClose() throws {
        let (bench, _, opener) = try setUp()
        opener.webViewDidClose(opener.webView)
        #expect(bench.tabs.count == 1)
    }

    @Test("A new window on another jar's data store gets no tab")
    func refusesOtherStore() throws {
        let (bench, webViews, opener) = try setUp()
        let foreign = WKWebViewConfiguration()
        foreign.websiteDataStore = JarProfile.dataStore(for: "some-other-jar")
        #expect(webViews.openNewWindow(from: opener, configuration: foreign) == nil)
        #expect(bench.tabs.count == 1)
    }

    @Test("A jar that isn't on the Shelf gets no tab")
    func unknownJar() throws {
        let (bench, _, _) = try setUp()
        #expect(bench.newTab(in: "no-such-jar") == nil)
        #expect(bench.tabs.count == 1)
    }

    @Test("Pages can't open windows without a click")
    func noAutomaticWindows() throws {
        let (_, _, opener) = try setUp()
        #expect(opener.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically == false)
    }

    @Test("mailto: and tel: go to another app; web pages stay in the Bench")
    func otherApps() {
        #expect(JarWebView.forAnotherApp(URL(string: "mailto:ryan@example.com")) != nil)
        #expect(JarWebView.forAnotherApp(URL(string: "tel:+15551234567")) != nil)
        #expect(JarWebView.forAnotherApp(URL(string: "https://example.com")) == nil)
        #expect(JarWebView.forAnotherApp(URL(string: "about:blank")) == nil)
    }
}
