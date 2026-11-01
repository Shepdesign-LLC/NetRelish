// WebView.swift — a WKWebView bound to one jar's data store. WebKit fixes the
// configuration at init, so there is one web view per tab (built lazily) and the Bench
// shows the active tab's. A page that opens a new window (target=_blank, or window.open
// from a click) gets a new tab in the same jar, on the configuration WebKit hands over.

import AppKit
import OSLog
import Pantry
import SwiftUI
import WebKit

private let log = Logger(subsystem: "com.shepdesign.netrelish", category: "bench")

/// The live state of one jar's web view, observed by the address bar.
@MainActor
@Observable
final class JarWebView: NSObject, WKNavigationDelegate, WKUIDelegate {
    let jarId: String
    let webView: WKWebView
    /// True when a page opened this view as its new window, so the address bar doesn't grab focus.
    let openedByPage: Bool
    private(set) var url: URL?
    private(set) var title: String = ""
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    /// A tab's web view on its jar's data store. Pages can open windows only from a click:
    /// macOS lets script open them on its own by default, which is how pop-unders work.
    convenience init(jarId: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = JarProfile.dataStore(for: jarId)   // non-negotiable 6
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.init(jarId: jarId, configuration: config, openedByPage: false)
    }

    /// A page's new window. WebKit requires the configuration it passed to
    /// `createWebViewWith`, used as is; it already carries the opener's data store, so the
    /// new tab stays in the opener's jar (non-negotiable 6).
    init(jarId: String, configuration: WKWebViewConfiguration, openedByPage: Bool) {
        self.jarId = jarId
        self.openedByPage = openedByPage
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
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
            log.error("load: not a URL: \(text, privacy: .private)")
            return
        }
        log.info("load: \(url.absoluteString, privacy: .private) in jar \(self.jarId, privacy: .public)")
        webView.load(URLRequest(url: url))
    }

    /// Everything WebKit needs to bring a tab back exactly: history, scroll, form state.
    var interactionState: Data? {
        get { webView.interactionState as? Data }
        set { if let newValue { webView.interactionState = newValue } }
    }

    /// Called after every navigation change, with the tab's URL and title.
    var onNavigation: ((URL?, String) -> Void)?

    /// Set by the Bench: the page asked for a new window. Returns the new tab's web view,
    /// built on `configuration`, or nil when no tab could be made.
    var onNewWindow: ((WKWebViewConfiguration) -> WKWebView?)?

    /// Set by the Bench, for windows a page opened: the page closed it (`window.close()`).
    var onClose: (() -> Void)?

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
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { sync(); log.info("start \(webView.url?.absoluteString ?? "-", privacy: .private)") }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { sync(); log.info("finish \(webView.url?.absoluteString ?? "-", privacy: .private) size=\(webView.bounds.width)x\(webView.bounds.height)") }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { sync(); log.error("fail \(error.localizedDescription, privacy: .public)") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { sync(); log.error("provisional fail \(error.localizedDescription, privacy: .public)") }

    /// Download links stay downloads, never page loads. A link WebKit can't show goes to
    /// another app: mail, phone, Messages and FaceTime links straight away on a click;
    /// anything else (a Zoom or Teams link, smb:, a script jumping to an app) only after
    /// the person says yes, the way Safari asks. A frame inside the page never gets to.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        let clicked = navigationAction.navigationType == .linkActivated
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch Self.handoff(navigationAction.request.url, clicked: clicked) {
        case .stay:
            decisionHandler(.allow)
        case .open(let url):
            decisionHandler(.cancel)
            NSWorkspace.shared.open(url)
        case .ask(let url):
            decisionHandler(.cancel)
            if clicked || mainFrame { askToOpen(url, from: webView) }
        }
    }

    /// The schemes a click hands straight to their app.
    static let schemesForOtherApps: Set<String> = ["mailto", "tel", "sms", "facetime", "facetime-audio"]

    enum Handoff: Equatable {
        case stay            // WebKit shows it
        case open(URL)       // straight to its app
        case ask(URL)        // to another app, once the person says yes
    }

    /// What happens to a URL that may belong to another app.
    static func handoff(_ url: URL?, clicked: Bool) -> Handoff {
        guard let url, let scheme = url.scheme?.lowercased(), scheme != "javascript",
              !WKWebView.handlesURLScheme(scheme) else { return .stay }
        return clicked && schemesForOtherApps.contains(scheme) ? .open(url) : .ask(url)
    }

    /// The URL, if it's a mail, phone, Messages or FaceTime link. The saved copy hands off
    /// these and nothing else.
    static func forAnotherApp(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), schemesForOtherApps.contains(scheme) else { return nil }
        return url
    }

    /// Asks before leaving for another app. Nothing happens if no app on this Mac opens the
    /// link, or if the window is already asking something.
    private func askToOpen(_ url: URL, from webView: WKWebView) {
        guard let window = webView.window, window.attachedSheet == nil,
              let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return }
        var name = FileManager.default.displayName(atPath: app.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        let alert = NSAlert()
        alert.messageText = "Open this link in \(name)?"
        alert.informativeText = "The page you're on wants to open \(name)."
        alert.addButton(withTitle: "Open \(name)")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: WKUIDelegate

    /// target=_blank and window.open land here. Without this, WebKit drops them and the
    /// link does nothing. If the Bench can't make a tab, a clicked link opens in this one.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        log.info("new window: \(navigationAction.request.url?.absoluteString ?? "-", privacy: .private) in jar \(self.jarId, privacy: .public)")
        // An app link with target=_blank shouldn't leave an empty tab behind.
        switch Self.handoff(navigationAction.request.url, clicked: navigationAction.navigationType == .linkActivated) {
        case .open(let url): NSWorkspace.shared.open(url); return nil
        case .ask(let url): askToOpen(url, from: webView); return nil
        case .stay: break
        }
        if let child = onNewWindow?(configuration) { return child }
        if navigationAction.navigationType == .linkActivated { webView.load(navigationAction.request) }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) { onClose?() }
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
