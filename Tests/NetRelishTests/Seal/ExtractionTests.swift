import Testing
import WebKit
@testable import NetRelish

/// Defuddle against a real page in a real web view, in the isolated world seal uses.
@Suite("Extraction") struct ExtractionTests {

    private static let page = """
    <html><head><title>Invoice terms</title><meta name="description" content="Net 30 versus net 45."></head>
    <body>
      <nav><a href="/">Home</a><a href="/about">About</a></nav>
      <article>
        <h1>Invoice terms</h1>
        <p>The client agreed to net thirty with a pumpernickel clause on late payment.</p>
        <p>Second paragraph about the schedule.</p>
      </article>
      <footer>Copyright nobody</footer>
    </body></html>
    """

    @MainActor
    private func load(_ html: String, url: String?) async throws -> JarWebView {
        let web = JarWebView(jarId: "extract-\(UUID().uuidString)")
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web.webView
        web.webView.loadHTMLString(html, baseURL: url.flatMap(URL.init(string:)))
        for _ in 0..<100 { try await Task.sleep(for: .milliseconds(50)); if !web.webView.isLoading { break } }
        return web
    }

    @Test("The article's prose comes out; the nav and footer chrome does not")
    @MainActor func extractsBody() async throws {
        let web = try await load(Self.page, url: "https://example.com/invoice")
        let result = try await Extraction.run(in: web.webView)
        #expect(result.body.contains("pumpernickel"))
        #expect(result.body.contains("Second paragraph"))
        #expect(!result.body.contains("Copyright nobody"))
        #expect(!result.body.contains("href"))          // text, not markup
    }

    @Test("Title and excerpt come back for search")
    @MainActor func titleAndExcerpt() async throws {
        let web = try await load(Self.page, url: "https://example.com/invoice")
        let result = try await Extraction.run(in: web.webView)
        #expect(result.title == "Invoice terms")
        #expect(!result.excerpt.isEmpty)
        #expect(result.excerpt.count <= Extraction.excerptLimit)
    }

    @Test("Defuddle runs in an isolated world: the page never sees it")
    @MainActor func isolatedFromThePage() async throws {
        let web = try await load(Self.page, url: "https://example.com/invoice")
        _ = try await Extraction.run(in: web.webView)
        let leaked = try await web.webView.evaluateJavaScript("typeof Defuddle !== 'undefined'") as? Bool
        #expect(leaked == false)
    }

    @Test("A page with nothing to extract yields empty text rather than throwing")
    @MainActor func emptyPage() async throws {
        let web = try await load("<html><body></body></html>", url: nil)
        #expect(try await Extraction.run(in: web.webView).body.isEmpty)
    }
}
