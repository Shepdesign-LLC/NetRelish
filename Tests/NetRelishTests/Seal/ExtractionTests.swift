import Pantry
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

    private static let article = """
    <html><head><title>Kickoff notes</title><script>window.evil = 1</script></head>
    <body>
      <nav><a href="/">Home</a></nav>
      <article>
        <h1>Kickoff notes</h1>
        <p onclick="steal()">The client wants the launch before the holidays, so the schedule runs backwards from the second week of December and every review lands on a Tuesday.</p>
        <p>Design signs off the home page first, then the product pages, then the checkout, which has the most moving parts and the most people with opinions about it.</p>
        <p>Copy is due a week before design on each page, so nobody lays out placeholder text that never gets replaced, which happened twice on the last project.</p>
        <p><a href="javascript:alert(1)">Bad link</a> and <a href="https://example.com/brief">the brief</a> stay readable.</p>
        <form action="/x"><input name="q"></form>
        <iframe src="https://ads.example.com/frame"></iframe>
      </article>
    </body></html>
    """

    @Test("Reader view's article keeps the prose and links, and loses anything that could run")
    @MainActor func readerArticleIsInert() async throws {
        let web = try await load(Self.article, url: "https://example.com/notes")
        let article = try #require(try await Extraction.article(in: web.webView))
        #expect(article.title == "Kickoff notes")
        #expect(article.wordCount >= Extraction.articleMinimumWords)
        #expect(article.html.contains("second week of December"))
        #expect(article.html.contains("https://example.com/brief"))
        for banned in ["<script", "onclick", "javascript:", "<form", "<input", "<iframe"] {
            #expect(!article.html.lowercased().contains(banned), "\(banned) should be stripped")
        }
    }

    @Test("A page with no article gives Reader view nothing to show")
    @MainActor func readerNeedsAnArticle() async throws {
        let web = try await load("<html><body><p>Sign in</p></body></html>", url: "https://example.com/login")
        #expect(try await Extraction.article(in: web.webView) == nil)
    }
}

/// ⌘⇧R, with the extraction stubbed: what Reader view does to the Bench.
@Suite("Reader view") @MainActor struct ReaderTests {
    private let sample = Extraction.Article(title: "Kickoff notes", byline: "Ryan", site: "example.com",
                                            html: "<p>The schedule runs backwards from December.</p>", wordCount: 120)

    private func bench(_ article: Extraction.Article?) throws -> Workbench {
        let bench = Workbench(store: try PantryStore())
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        _ = bench.newTab(url: "https://example.com/notes")
        bench.readerProvider = { _ in article }
        return bench
    }

    @Test("⌘⇧R shows the article for the tab on the Bench, and again goes back to the page")
    func toggles() async throws {
        let bench = try bench(sample)
        await bench.toggleReader()
        #expect(bench.isReading)
        #expect(bench.reader?.article == sample)
        #expect(bench.reader?.tabId == bench.activeTab?.id)
        await bench.toggleReader()
        #expect(!bench.isReading)
    }

    @Test("A page with no article says so and stays as it is")
    func noArticle() async throws {
        let bench = try bench(nil)
        await bench.toggleReader()
        #expect(bench.reader == nil)
        #expect(bench.fillStatus == "This page has no article to read")
    }

    @Test("A new page, another tab or a smart jar leaves Reader view; a late title doesn't")
    func leaves() async throws {
        let bench = try bench(sample)
        let tabId = try #require(bench.activeTab?.id)
        await bench.toggleReader()
        bench.tabDidNavigate(tabId, url: URL(string: "https://example.com/notes"), title: "Kickoff notes")
        #expect(bench.isReading)

        bench.tabDidNavigate(tabId, url: URL(string: "https://example.com/next"), title: "Next")
        #expect(bench.reader == nil)

        await bench.toggleReader()
        _ = bench.newTab(url: "https://example.com/other")
        #expect(bench.reader == nil)                 // a new tab leaves it, so closing that tab can't bring it back
        let other = try #require(bench.tabs.first { $0.id == tabId })
        bench.activateTab(other)
        #expect(bench.reader == nil)

        await bench.toggleReader()
        bench.activate(.today)
        #expect(bench.reader == nil)
    }

    @Test("Seal still works on the live page behind Reader view")
    func sealWhileReading() async throws {
        let bench = try bench(sample)
        bench.sealProvider = { _ in (Data("WEBARCHIVE".utf8), Extraction.Result(title: "Kickoff notes", excerpt: "", body: "December schedule")) }
        await bench.toggleReader()
        #expect(bench.benchTab != nil)
        await bench.sealActiveTab()
        #expect(bench.sealedItems.count == 1)
        #expect(bench.reader == nil)                 // the tab is gone, so is its reader
    }

    @Test("The reader page escapes what we write into it and carries our content policy")
    func page() {
        let html = ReaderPage.html(for: Extraction.Article(title: "<script>x</script> & co", byline: "", site: "a\"b",
                                                          html: "<p>Body</p>", wordCount: 100))
        #expect(html.contains("&lt;script&gt;x&lt;/script&gt; &amp; co"))
        #expect(!html.contains("<script>x"))
        #expect(html.contains("a&quot;b"))
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("<p>Body</p>"))
    }

    @Test("The reader's colors are the tokens in design/tokens.css")
    func colorsAreTokens() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()   // Tests/NetRelishTests/Seal
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let css = try String(contentsOf: repo.appendingPathComponent("design/tokens.css"), encoding: .utf8)
        let lines = css.components(separatedBy: "\n")
        for entry in ReaderPage.palette {
            let defs = lines.filter { $0.contains("\(entry.token):") }
            #expect(defs.contains { $0.contains(entry.light) }, "\(entry.token) light should be \(entry.light)")
            #expect(defs.contains { $0.contains(entry.dark) }, "\(entry.token) dark should be \(entry.dark)")
        }
    }

    @Test("Reader view keeps the page the article came from, even before the tab's URL catches up")
    func usesTheLivePageURL() async throws {
        var live = sample
        live.url = "https://example.com/next"            // the web view is already on the next page
        let bench = try bench(live)                       // the tab still says /notes
        let tabId = try #require(bench.activeTab?.id)
        await bench.toggleReader()
        #expect(bench.reader?.url == "https://example.com/next")
        bench.tabDidNavigate(tabId, url: URL(string: "https://example.com/next"), title: "Next")
        #expect(bench.isReading)                          // that load finishing isn't a new page
    }

    @Test("Fill from Me won't write into a page Reader view is covering")
    func noFillWhileReading() async throws {
        let bench = try bench(sample)
        var filled = 0
        bench.formFiller = { _, _ in filled += 1; return 1 }
        await bench.toggleReader()
        bench.fillFromMe()
        try await Task.sleep(for: .milliseconds(50))
        #expect(filled == 0)
        #expect(bench.fillStatus == "Go back to the page to fill a form")
        #expect(!PaletteSource.commands(bench).map(\.title).contains("Fill this form"))
    }

    @Test("A failure says so in plain words, never the raw error")
    func plainFailure() async throws {
        struct Boom: Error {}
        let bench = try bench(sample)
        bench.readerProvider = { _ in throw Boom() }
        await bench.toggleReader()
        #expect(bench.reader == nil)
        #expect(bench.fillStatus == "Reader view couldn’t read this page")
    }

    @Test("The reader's type is the token scale: sizes, line heights, weights up to 600 (manifest §5)")
    func typeIsTokens() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let css = try String(contentsOf: repo.appendingPathComponent("design/tokens.css"), encoding: .utf8)
        func values(_ pattern: String, in text: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: pattern)
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            }
        }
        let sizes = Set(values(#"--fs-[a-z0-9]+:\s*([0-9]+)px"#, in: css))
        let heights = Set(values(#"--lh-[a-z]+:\s*([0-9.]+)"#, in: css))
        let page = ReaderPage.html(for: sample)
        let used = values(#"font-size:\s*([0-9]+)px"#, in: page) + values(#"font:\s*([0-9]+)px"#, in: page)
        #expect(!used.isEmpty)
        for size in used { #expect(sizes.contains(size), "\(size)px isn't on the --fs scale") }
        for h in values(#"line-height:\s*([0-9.]+)"#, in: page) + values(#"font:\s*[0-9]+px/([0-9.]+)"#, in: page) {
            #expect(heights.contains(h), "line height \(h) isn't an --lh token")
        }
        for w in values(#"font-weight:\s*([0-9]+)"#, in: page) { #expect((Int(w) ?? 0) <= 600, "weight \(w) is over 600") }
    }
}
