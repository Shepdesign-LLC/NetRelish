// ZestWebView.swift — one Zest tool's web view (ADR 0015, ADR 0033). It is not a tab: it
// belongs to no jar, never sinks, and can't be sealed. It runs on Zest's own data store, with
// the offline rule list and the zest: scheme, and carries the frozen `window.netrelish` stub
// that tells a tool it is inside the app. A jar's web view carries none of these.
//
// What leaves the tool: a clicked web link opens as an ordinary page in the active jar, in
// the main window; a download goes to the save panel; a link for another app follows the
// Bench's handoff rules. Nothing else gets out.

import AppKit
import OSLog
import Pantry
import WebKit

private let log = Logger(subsystem: "com.shepdesign.netrelish", category: "zest")

/// Where a navigation inside a Zest view goes. Decided by `ZestWebView.route`, a pure
/// function, so the rules are tested without a page.
enum ZestRoute: Equatable {
    case allow                       // the tool's own files, or a frame's about:/data:/blob:
    case download                    // a blob: or data: page, or a local file marked download
    case openInJar(URL)              // a web link: a page in the active jar, main window
    case switchTool(ZestTool)        // a link to another tool: the switcher moves
    case handOff(JarWebView.Handoff) // a link for another app, as the Bench treats it
    case cancel                      // nothing happens
}

@MainActor
final class ZestWebView: NSObject, WKNavigationDelegate, WKUIDelegate {
    let tool: ZestTool
    let webView: WKWebView

    /// Set by the Zest window: open a web link as a page in the active jar.
    var openInJar: ((URL) -> Void)?
    /// Set by the Zest window: show another tool.
    var showTool: ((ZestTool) -> Void)?
    /// Downloads this view has started, for tests: a link to the web must never become one.
    private(set) var downloadsStarted = 0

    /// The stub, frozen and fixed on `window` so a page can't swap it. No methods: there is
    /// nothing to call until the bridge (ADR 0015, 1.2).
    static let stubSource = """
    Object.defineProperty(window, 'netrelish', {
      value: Object.freeze({version: '0', host: 'app', network: false}),
      writable: false, configurable: false, enumerable: false
    });
    """

    /// Whether a user script is the stub. Tests use it to look for the stub in a configuration.
    static func isStub(_ script: WKUserScript) -> Bool { script.source == stubSource }

    /// The configuration every Zest view is built on: Zest's data store (never a jar's,
    /// non-negotiable 6), the zest: scheme over `root`, the offline rule list, and the stub.
    /// The list is not optional: without it there is no configuration, so no view loads.
    /// `dataStore` is for tests only, so they never write into, or wipe, the person's real
    /// Zest store; the app always passes nil and gets Zest's.
    static func configuration(rules: WKContentRuleList, root: URL,
                              dataStore: WKWebsiteDataStore? = nil) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore ?? ZestProfile.dataStore()
        config.setURLSchemeHandler(ZestSchemeHandler(root: root), forURLScheme: ZestFiles.scheme)
        config.userContentController.add(rules)
        config.userContentController.addUserScript(
            WKUserScript(source: stubSource, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return config
    }

    /// A tool's view, loading the tool. Built only once the rule list has compiled.
    /// `dataStore` is for tests only, as in `configuration`.
    init(tool: ZestTool, rules: WKContentRuleList, root: URL, dataStore: WKWebsiteDataStore? = nil) {
        self.tool = tool
        webView = WKWebView(frame: .zero,
                            configuration: Self.configuration(rules: rules, root: root, dataStore: dataStore))
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.load(URLRequest(url: tool.url))
    }

    // MARK: Routing

    /// Where a navigation goes. `clicked` is a link the person clicked; `mainFrame` is the
    /// tool's own page rather than a frame inside it; `download` is WebKit's
    /// `shouldPerformDownload` (an `a[download]`, clicked or scripted).
    ///
    /// `download` is honored only for the tool's own files, blob: and data:. A download link
    /// to the web is routed like any other web link: the active jar for a click, nothing
    /// otherwise. Never a `WKDownload`: that is fetched by the network process on Zest's store,
    /// where neither the rule list nor the policy header reaches (non-negotiable 5).
    static func route(_ url: URL?, mainFrame: Bool, clicked: Bool, download: Bool = false,
                      from tool: ZestTool) -> ZestRoute {
        guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }
        switch scheme {
        case ZestFiles.scheme:
            guard url.host(percentEncoded: false)?.lowercased() == ZestFiles.host else { return .cancel }
            if download { return .download }   // read from the bundle, never the web
            if mainFrame, clicked, let other = ZestTool(url: url), other != tool { return .switchTool(other) }
            return .allow
        case "about":
            return download ? .cancel : .allow
        case "blob", "data":
            // A tool's page replaced by a file is a download; a frame showing one is a preview.
            return (download || mainFrame) ? .download : .allow
        case "http", "https":
            return clicked ? .openInJar(url) : .cancel
        case "ws", "wss", "file", "javascript":
            return .cancel
        default:
            switch JarWebView.handoff(url, clicked: clicked) {
            case .stay: return .cancel   // a scheme WebKit shows itself, but not inside Zest
            case let handoff: return .handOff(handoff)
            }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // Routed first, download or not: `route` decides which downloads are allowed at all.
        let clicked = navigationAction.navigationType == .linkActivated
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch Self.route(navigationAction.request.url, mainFrame: mainFrame, clicked: clicked,
                          download: navigationAction.shouldPerformDownload, from: tool) {
        case .allow:
            decisionHandler(.allow)
        case .download:
            decisionHandler(.download)
        case .openInJar(let url):
            decisionHandler(.cancel)
            openInJar?(url)
        case .switchTool(let other):
            decisionHandler(.cancel)
            showTool?(other)
        case .handOff(.open(let url)):
            decisionHandler(.cancel)
            NSWorkspace.shared.open(url)
        case .handOff(.ask(let url)):
            decisionHandler(.cancel)
            if clicked || mainFrame { JarWebView.askToOpen(url, from: webView) }
        case .handOff(.stay), .cancel:
            decisionHandler(.cancel)
        }
    }

    /// A response WebKit can't show (a file the tool links to) is saved, not shown.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloadsStarted += 1
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloadsStarted += 1
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        log.error("zest \(self.tool.rawValue, privacy: .public): provisional fail \(errorKind(error), privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        log.error("zest \(self.tool.rawValue, privacy: .public): fail \(errorKind(error), privacy: .public)")
    }

    /// The tool's process went away (memory pressure, a crash): load it again. Its saved work
    /// is in Zest's store, so nothing kept is lost.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("zest \(self.tool.rawValue, privacy: .public): content process ended, reloading")
        webView.load(URLRequest(url: tool.url))
    }

    // MARK: WKUIDelegate

    /// target=_blank and window.open. Nothing opens a second Zest view: a web link goes to the
    /// active jar, a link to another tool moves the switcher, a blob: or data: file downloads.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        let clicked = navigationAction.navigationType == .linkActivated
        switch Self.route(url, mainFrame: true, clicked: true, from: tool) {
        case .openInJar(let url):
            openInJar?(url)
        case .switchTool(let other):
            showTool?(other)
        case .download:
            if let url { Task { @MainActor [weak self] in await self?.startDownload(url) } }
        case .handOff(.open(let url)):
            NSWorkspace.shared.open(url)
        case .handOff(.ask(let url)):
            if clicked { JarWebView.askToOpen(url, from: webView) }
        case .allow, .handOff(.stay), .cancel:
            break
        }
        return nil
    }

    /// A blob: or data: file opened as a window: saved through the panel instead.
    private func startDownload(_ url: URL) async {
        let download = await webView.startDownload(using: URLRequest(url: url))
        downloadsStarted += 1
        download.delegate = self
    }

    /// File inputs: the native open panel, as a sheet on the Zest window.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        let response: NSApplication.ModalResponse
        if let window = webView.window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.urls : nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = self.alert(message)
        alert.addButton(withTitle: "OK")
        _ = await present(alert, in: webView)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = self.alert(message)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await present(alert, in: webView) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = self.alert(prompt)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return await present(alert, in: webView) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// The tool's own words, under the tool's name, so it's clear which tool is asking.
    private func alert(_ message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = tool.title
        alert.informativeText = message
        return alert
    }

    /// As a sheet on the Zest window, or on its own if the view has no window.
    private func present(_ alert: NSAlert, in webView: WKWebView) async -> NSApplication.ModalResponse {
        guard let window = webView.window else { return alert.runModal() }
        return await alert.beginSheetModal(for: window)
    }
}

// MARK: Downloads

extension ZestWebView: @preconcurrency WKDownloadDelegate {
    /// Exports: the native save panel, with the name the tool suggested. A file already
    /// there is replaced only after the panel has asked.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        let answer: NSApplication.ModalResponse
        if let window = download.webView?.window ?? webView.window {
            answer = await panel.beginSheetModal(for: window)
        } else {
            answer = panel.runModal()
        }
        guard answer == .OK, let url = panel.url else { return nil }
        // WKDownload won't write over a file; the panel has already asked to replace it.
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        log.error("zest \(self.tool.rawValue, privacy: .public): download failed \(errorKind(error), privacy: .public)")
    }
}

/// Zest's one website data store. Never a jar's: its identifier is reserved in JarProfile,
/// where every jar's is derived, so no jar can map to it (non-negotiable 6).
enum ZestProfile {
    static var storeIdentifier: UUID { JarProfile.zestStoreIdentifier }

    @MainActor
    static func dataStore() -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: storeIdentifier)
    }
}
