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
