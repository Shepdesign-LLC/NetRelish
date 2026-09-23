import Foundation
import Testing
import WebKit
@testable import NetRelish

/// Roadmap §P2: seal ≤ 400 ms perceived. "Perceived" is the part that blocks the gesture —
/// the extraction and the archive — measured on a real page in a real web view.
@Suite("Seal performance", .serialized) struct SealPerformanceTests {

    /// A page with real weight: 400 paragraphs, inline CSS, and a few images.
    private static var heavyPage: String {
        let paragraphs = (0..<400).map { "<p>Paragraph \($0) about invoices, schedules, and pumpernickel.</p>" }.joined()
        let images = (0..<8).map { _ in "<img src='data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'>" }.joined()
        return "<html><head><title>Heavy</title><style>body{font:14px/1.5 -apple-system;}</style></head><body><article>\(paragraphs)\(images)</article></body></html>"
    }

    @Test("Extraction plus archive stays inside the 400 ms budget on a heavy page")
    @MainActor func withinBudget() async throws {
        let web = JarWebView(jarId: "perf-\(UUID().uuidString)")
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web.webView
        web.webView.loadHTMLString(Self.heavyPage, baseURL: URL(string: "https://example.com/heavy"))
        for _ in 0..<200 { try await Task.sleep(for: .milliseconds(50)); if !web.webView.isLoading { break } }

        // Warm the isolated world so the measurement is a seal, not a first-run.
        _ = try await Extraction.run(in: web.webView)

        let start = ContinuousClock.now
        let extracted = try await Extraction.run(in: web.webView)
        let archive = try await web.webView.dataForWebArchive()
        let elapsed = ContinuousClock.now - start

        #expect(extracted.body.contains("pumpernickel"))
        #expect(!archive.isEmpty)
        print("seal: \(elapsed) for \(archive.count) bytes of archive, \(extracted.body.count) characters of text")
        #expect(elapsed < .milliseconds(400))
    }
}
