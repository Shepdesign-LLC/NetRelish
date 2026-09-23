// WebView.swift — a WKWebView bound to one jar's data store. WebKit fixes the
// configuration at init, so there is one web view per jar (built lazily) and the Bench
// shows the active jar's. Nothing here reads page content: capture and seal are P2.

import OSLog
import Pantry
import SwiftUI
import WebKit

private let log = Logger(subsystem: "com.shepdesign.netrelish", category: "bench")

/// The live state of one jar's web view, observed by the address bar.
@MainActor
@Observable
final class JarWebView: NSObject, WKNavigationDelegate {
    let jarId: String
    let webView: WKWebView
    private(set) var url: URL?
    private(set) var title: String = ""
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    init(jarId: String) {
        self.jarId = jarId
        let config = WKWebViewConfiguration()
        config.websiteDataStore = JarProfile.dataStore(for: jarId)   // non-negotiable 6
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observe()
    }

    /// WebKit sets `title` (and finishes `isLoading`) after didFinish for most pages, so the
    /// delegate alone leaves tabs named after their URL. KVO is the only version that's right.
    private var observations: [NSKeyValueObservation] = []

    private func observe() {
        let keyPaths: [KeyPath<WKWebView, String?>] = [\.title]
        observations = keyPaths.map { keyPath in
            webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.sync() }
            }
        }
        observations.append(webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.sync() }
        })
        observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.sync() }
        })
    }

    func load(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var candidate = trimmed
        if !candidate.contains("://") { candidate = "https://" + candidate }
        guard let url = URL(string: candidate), url.host != nil else {
            log.error("load: not a URL: \(text, privacy: .public)")
            return
        }
        log.info("load: \(url.absoluteString, privacy: .public) in jar \(self.jarId, privacy: .public)")
        webView.load(URLRequest(url: url))
    }

    /// Everything WebKit needs to bring a tab back exactly: history, scroll, form state.
    var interactionState: Data? {
        get { webView.interactionState as? Data }
        set { if let newValue { webView.interactionState = newValue } }
    }

    /// Called after every navigation change, with the tab's URL and title.
    var onNavigation: ((URL?, String) -> Void)?

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    private func sync() {
        url = webView.url
        title = webView.title ?? ""
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        // Tell the Workbench once the page has settled. A title arriving late counts as
        // settling, so the tab gets its name even when it lands after didFinish.
        if !isLoading, url != nil { onNavigation?(url, title) }
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { sync(); log.info("start \(webView.url?.absoluteString ?? "-", privacy: .public)") }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { sync(); log.info("finish \(webView.url?.absoluteString ?? "-", privacy: .public) size=\(webView.bounds.width)x\(webView.bounds.height)") }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { sync(); log.error("fail \(error.localizedDescription, privacy: .public)") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { sync(); log.error("provisional fail \(error.localizedDescription, privacy: .public)") }
}

extension WKWebView {
    /// `createWebArchiveData` as async/await. This is the freeze in Seal: everything the page
    /// needs to render again, in one file, with no network (non-negotiable 5).
    func dataForWebArchive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            createWebArchiveData { continuation.resume(with: $0) }
        }
    }
}

/// Hosts a JarWebView's WKWebView in SwiftUI.
struct WebViewHost: NSViewRepresentable {
    let jarWebView: JarWebView
    func makeNSView(context: Context) -> WKWebView { jarWebView.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
