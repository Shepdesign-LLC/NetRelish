import Pantry
import Testing
import WebKit
@testable import NetRelish

/// Non-negotiable 6, as a test: cookies set in one jar are invisible from another.
/// Runs inside the app process (sandboxed, network-client entitlement), against httpbin.org.
@Suite("Jar isolation") struct JarIsolationTests {

    @MainActor
    private func load(_ web: JarWebView, _ url: String) async throws {
        web.load(url)
        for _ in 0..<200 {   // up to 20 s
            try await Task.sleep(for: .milliseconds(100))
            if !web.isLoading, web.url != nil { return }
        }
        Issue.record("timed out loading \(url)")
    }

    @MainActor
    private func bodyText(_ web: JarWebView) async throws -> String {
        let result = try await web.webView.evaluateJavaScript("document.body.innerText")
        return result as? String ?? ""
    }

    @Test("A cookie set in jar A is seen by jar A and not by jar B")
    @MainActor func cookiesDoNotCrossJars() async throws {
        let a = JarWebView(jarId: "isolation-test-a-\(UUID().uuidString)")
        let b = JarWebView(jarId: "isolation-test-b-\(UUID().uuidString)")
        // A WKWebView only loads while it is in a window.
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        host.contentView?.addSubview(a.webView); a.webView.frame = host.contentView!.bounds
        host.contentView?.addSubview(b.webView); b.webView.frame = host.contentView!.bounds

        try await load(a, "https://httpbin.org/cookies/set?jar=A")   // redirects to /cookies
        let seenByA = try await bodyText(a)
        #expect(seenByA.contains("\"jar\": \"A\""), "jar A should see its own cookie; got \(seenByA)")

        try await load(b, "https://httpbin.org/cookies")
        let seenByB = try await bodyText(b)
        #expect(!seenByB.contains("\"jar\": \"A\""), "jar B must not see jar A's cookie; got \(seenByB)")

        // Clean up: a store can't be removed while a web view holds it, so wipe its contents.
        for web in [a, b] {
            await web.webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
    }
}
