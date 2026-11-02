// HeadlessPage.swift — a page loaded off screen, for Seal from Shortcuts. The same engine and
// the same jar profile as a tab (non-negotiable 6), never on screen: nothing is shown, no
// popup opens, nothing downloads or plays, and no link is handed to another app. It loads
// one page, the one you named, and is let go once Seal has its snapshot.

import AppKit
import Foundation
import Pantry
import WebKit

@MainActor
final class HeadlessPage: NSObject, WKNavigationDelegate {
    enum Failure: Error, CustomStringConvertible {
        case timedOut(Int)
        case failed(String)

        var description: String {
            switch self {
            case .timedOut(let seconds): "It took longer than \(seconds) seconds."
            case .failed(let why): why
            }
        }
    }

    let webView: WKWebView
    /// Never shown. Hosting the web view gives the page a real layout, the way a tab has one,
    /// so the text Seal pulls out matches what you'd see.
    private let window: NSWindow
    private var pending: CheckedContinuation<Void, Error>?

    /// A page in `jarId`'s profile, so it loads with that jar's sign-ins and nobody else's.
    init(jarId: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = JarProfile.dataStore(for: jarId)
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // A desktop-sized viewport, so the page lays out as it would in a tab.
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        webView = WKWebView(frame: frame, configuration: config)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    /// Loads `url` and returns once it has finished, plus a short pause for scripts that fill
    /// the page after load.
    func load(_ url: URL, timeout seconds: Int = 30, settle: Duration = .milliseconds(800)) async throws {
        try await wait(seconds: seconds) { $0.load(URLRequest(url: url)) }
        try? await Task.sleep(for: settle)
    }

    /// Tests load markup directly, with no network.
    func load(html: String, baseURL: URL?, timeout seconds: Int = 10) async throws {
        try await wait(seconds: seconds) { $0.loadHTMLString(html, baseURL: baseURL) }
    }

    private func wait(seconds: Int, start: (WKWebView) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending = continuation
            start(webView)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.finish(.failure(Failure.timedOut(seconds)))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let pending else { return }
        self.pending = nil
        if case .failure = result { webView.stopLoading() }
        pending.resume(with: result)
    }

    // MARK: WKNavigationDelegate

    /// Set when the page turned out to be a file, so the failure says so rather than WebKit's
    /// "Frame load interrupted".
    private var refusedFile = false

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        failed(error)
    }

    private func failed(_ error: any Error) {
        // A page that redirects itself while loading cancels the first navigation; the next
        // one carries on, and finishes or times out.
        if (error as NSError).domain == NSURLErrorDomain, (error as NSError).code == NSURLErrorCancelled { return }
        finish(.failure(Failure.failed(refusedFile ? "That link is a file, not a page." : error.localizedDescription)))
    }

    /// Web pages only: no other app is asked to open anything, and nothing opens a window.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame != nil, !navigationAction.shouldPerformDownload else {
            decisionHandler(.cancel); return
        }
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        decisionHandler(["http", "https", "about", "data", "blob"].contains(scheme) ? .allow : .cancel)
    }

    /// Nothing downloads: a link to a file the engine can't show isn't a page to seal.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            if navigationResponse.isForMainFrame { refusedFile = true }
            decisionHandler(.cancel)
        }
    }
}
