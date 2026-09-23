// Extraction.swift — Defuddle (MIT, vendored at Resources/Extraction/defuddle.js) pulls the
// article out of a page at seal time. It runs in an ISOLATED content world: the page's own
// JavaScript never sees Defuddle, and Defuddle's globals never touch the page.
//
// This is the only code that reads a live page's DOM, it runs only when you press ⌘S, and
// what comes back is plain text that goes straight into the Pantry. No model is involved
// (non-negotiable 4) and nothing is sent anywhere (non-negotiable 5).

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

    /// The vendored bundle, read once.
    private static let library: String? = {
        guard let url = Bundle.main.url(forResource: "defuddle", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return source
    }()

    @MainActor
    static func run(in webView: WKWebView) async throws -> Result {
        guard let library else { throw Failure.libraryMissing }
        let world = WKContentWorld.world(name: "netrelish.extraction")
        _ = try await webView.callAsyncJavaScript(library, in: nil, contentWorld: world)
        let raw = try await webView.callAsyncJavaScript(script, arguments: ["limit": excerptLimit],
                                                        in: nil, contentWorld: world)
        guard let dict = raw as? [String: Any] else { return Result(title: "", excerpt: "", body: "") }
        let result = Result(
            title: dict["title"] as? String ?? "",
            excerpt: dict["excerpt"] as? String ?? "",
            body: dict["body"] as? String ?? ""
        )
        log.info("extracted \(result.body.count, privacy: .public) characters")
        return result
    }

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
