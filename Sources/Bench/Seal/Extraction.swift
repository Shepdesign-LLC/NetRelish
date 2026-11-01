// Extraction.swift — Defuddle (MIT, vendored at Resources/Extraction/defuddle.js) pulls the
// article out of a page at seal time. It runs in an ISOLATED content world: the page's own
// JavaScript never sees Defuddle, and Defuddle's globals never touch the page.
//
// This is the only code that reads a live page's DOM. It runs only when you ask: ⌘S, where
// plain text goes straight into the Pantry, and ⌘⇧R, where the article's markup, stripped
// of anything that could run, goes to the reader on screen and nowhere else. No model is
// involved (non-negotiable 4) and nothing is sent anywhere (non-negotiable 5).

import Foundation
import OSLog
import WebKit

private let log = Logger(subsystem: "com.shepdesign.netrelish", category: "seal")

enum Extraction {
    /// Long enough to be a useful search hit and a two-line Inspector preview.
    static let excerptLimit = 280

    struct Result: Sendable, Equatable {
        var title: String
        var excerpt: String
        var body: String
    }

    enum Failure: Error, CustomStringConvertible {
        case libraryMissing
        var description: String { "The extraction library is missing from the app bundle." }
    }

    /// The article as Reader view shows it: markup with every script, frame, form, style and
    /// event handler removed in the isolated world before it leaves the page.
    struct Article: Sendable, Equatable {
        var title: String
        var byline: String
        var site: String
        var html: String
        var wordCount: Int
    }

    /// Fewer words than this and it isn't an article: a home page, a search, a login.
    static let articleMinimumWords = 60

    /// The vendored bundle, read once.
    private static let library: String? = {
        guard let url = Bundle.main.url(forResource: "defuddle", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return source
    }()

    @MainActor
    static func run(in webView: WKWebView) async throws -> Result {
        let raw = try await evaluate(script, arguments: ["limit": excerptLimit], in: webView)
        guard let dict = raw as? [String: Any] else { return Result(title: "", excerpt: "", body: "") }
        let result = Result(
            title: dict["title"] as? String ?? "",
            excerpt: dict["excerpt"] as? String ?? "",
            body: dict["body"] as? String ?? ""
        )
        log.info("extracted \(result.body.count, privacy: .public) characters")
        return result
    }

    /// Reader view's article, or nil when the page has none worth reading.
    @MainActor
    static func article(in webView: WKWebView) async throws -> Article? {
        let raw = try await evaluate(articleScript, arguments: [:], in: webView)
        guard let dict = raw as? [String: Any] else { return nil }
        let article = Article(
            title: dict["title"] as? String ?? "",
            byline: dict["byline"] as? String ?? "",
            site: dict["site"] as? String ?? "",
            html: dict["html"] as? String ?? "",
            wordCount: (dict["words"] as? NSNumber)?.intValue ?? 0
        )
        log.info("reader: \(article.wordCount, privacy: .public) words")
        return article.wordCount >= articleMinimumWords ? article : nil
    }

    /// Loads Defuddle into the isolated world, then runs `script` there.
    @MainActor
    private static func evaluate(_ script: String, arguments: [String: Any], in webView: WKWebView) async throws -> Any? {
        guard let library else { throw Failure.libraryMissing }
        let world = WKContentWorld.world(name: "netrelish.extraction")
        _ = try await webView.callAsyncJavaScript(library, in: nil, contentWorld: world)
        return try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: world)
    }

    /// Defuddle's article, made inert: the reader renders it with JavaScript off, and this
    /// takes out what could still reach out or run if it ever weren't.
    private static let articleScript = """
    const parsed = new Defuddle(document).parse();
    const holder = document.implementation.createHTMLDocument("").body;
    holder.innerHTML = parsed.content || "";
    holder.querySelectorAll("script, style, link, meta, iframe, frame, object, embed, form, input, button, select, textarea, noscript, base").forEach((el) => el.remove());
    holder.querySelectorAll("*").forEach((el) => {
      for (const attr of [...el.attributes]) {
        const name = attr.name.toLowerCase();
        const value = (attr.value || "").trim().toLowerCase();
        if (name.startsWith("on") || name === "style" || name === "srcdoc" ||
            ((name === "href" || name === "src" || name === "action") && value.startsWith("javascript:"))) {
          el.removeAttribute(attr.name);
        }
      }
    });
    const words = (holder.textContent || "").split(/\\s+/).filter(Boolean).length;
    return {
      title: (parsed.title || document.title || "").trim(),
      byline: (parsed.author || "").trim(),
      site: (parsed.site || location.hostname || "").trim(),
      html: holder.innerHTML,
      words: words,
    };
    """

    /// Defuddle returns HTML; the Pantry wants text, because FTS5 indexes words, not markup.
    private static let script = """
    const parsed = new Defuddle(document).parse();
    const holder = document.implementation.createHTMLDocument("").body;
    holder.innerHTML = parsed.content || "";
    const body = (holder.textContent || "").replace(/\\s+/g, " ").trim();
    const described = parsed.description || body;
    return {
      title: (parsed.title || document.title || "").trim(),
      excerpt: described.slice(0, limit).trim(),
      body: body,
    };
    """
}
