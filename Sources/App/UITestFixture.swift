// UITestFixture.swift — DEBUG only: what the capture → jar → seal UI test
// (Tests/NetRelishUITests) launches the app with. `-NRUITestFixture` gives the app a
// throwaway Pantry and defaults, two jars, and one page served from inside the app on
// `nr-fixture:`, so the test never touches your data and never reaches the network
// (non-negotiable 5: no new endpoint; the page is a string in this file). The whole file is
// compiled out of Release, and so is every line that calls it.

#if DEBUG
import Foundation
import Pantry
import WebKit

enum UITestFixture {
    /// The launch argument the UI test passes.
    static let argument = "-NRUITestFixture"

    /// Whether this launch is the UI test's. Read once, from the command line only: an
    /// environment variable or a default can't switch it on.
    static let isOn: Bool = ProcessInfo.processInfo.arguments.contains(argument)

    /// The scheme the fixture page is served on. WebKit doesn't handle it, so without the
    /// fixture a link to it is another app's (`JarWebView.handoff`), as it always was.
    static let scheme = "nr-fixture"

    /// The page the test types into the address field. Every address on the scheme gets the
    /// same page; the host is the one the walkthrough and the voice docs use.
    static let pageURL = "nr-fixture://juniperbakery.example/invoice-terms"
    static let pageTitle = "Invoice terms"
    /// A line only the page has, so the test can tell the page arrived in the web view.
    static let pageMarker = "Payment is due 30 days after delivery."

    /// The jars on the fixture's Shelf, in order: ⌘1 and ⌘2. The test seals into the second.
    static let jarNames = ["Juniper Bakery", "Meridian"]

    /// The fixture page: a title, a heading and enough of an article for Seal's extraction.
    /// No script, no image, no style sheet, no link: nothing on it asks for anything else.
    static let page = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>\(pageTitle)</title>
    </head>
    <body>
    <main>
    <article>
    <h1>\(pageTitle)</h1>
    <p>\(pageMarker)</p>
    <p>Juniper Bakery sends one invoice a week, every Monday, for everything delivered the week \
    before. Each invoice lists the order number, the date it was delivered, and what was in it.</p>
    <p>A late payment is reminded once, a week after it falls due. Nothing is added for paying \
    late. If an order arrives short or damaged, say so within two days and that part comes off \
    the next invoice.</p>
    <p>Questions about an invoice go to the same address the invoice came from. Keep this page: \
    these are the terms every invoice refers to.</p>
    </article>
    </main>
    </body>
    </html>
    """

    /// True when `scheme` is the fixture's and this is the fixture's launch: the page stays in
    /// the web view instead of being handed to another app.
    static func serves(_ scheme: String) -> Bool {
        isOn && scheme == Self.scheme
    }

    /// Serves the fixture page in a tab's web view. WebKit takes a scheme handler only before
    /// the web view is made, so `JarWebView` calls this on the configuration it builds. A page's
    /// new window gets the opener's configuration, handler included.
    @MainActor
    static func install(on configuration: WKWebViewConfiguration) {
        guard isOn else { return }
        configuration.setURLSchemeHandler(UITestFixturePages(), forURLScheme: scheme)
    }

    /// The fixture's Workbench, or nil when this isn't the fixture's launch. An in-memory
    /// Pantry, defaults in a suite of their own (emptied first), a Keychain service of its own,
    /// no Share inbox, no summarizer, no timestamp authority and Pro unlocked without StoreKit:
    /// nothing here reads what you keep or reaches the network.
    @MainActor
    static func makeWorkbench() -> Workbench? {
        guard isOn else { return nil }
        let suite = "com.shepdesign.netrelish.uitest"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("The UI test fixture couldn't make its own defaults")
        }
        let store: PantryStore
        do {
            store = try PantryStore(inMemory: ())
        } catch {
            fatalError("The UI test fixture couldn't open its Pantry: \(error)")
        }
        let workbench = Workbench(store: store,
                                  vault: VaultStore(service: "com.shepdesign.netrelish.vault.uitest"),
                                  inbox: nil, summarizer: nil, timestamps: nil,
                                  pro: ProStore(unlocked: true), defaults: defaults)
        // The jars the Shelf's New Jar would make, through the same call; the first is in front.
        workbench.newJar(name: jarNames[0], tint: nil, shelfLifeDays: 7)
        workbench.newJar(name: jarNames[1], tint: nil, shelfLifeDays: 3)
        workbench.activate(index: 0)
        return workbench
    }
}

/// Serves the fixture page on `nr-fixture:`, from memory. No file is read, nothing is written,
/// and nothing leaves the app.
///
/// Isolation, as `ZestSchemeHandler`: WebKit calls a scheme handler on the main thread, but the
/// SDK doesn't mark the protocol @MainActor, so this steps onto the main actor with
/// `MainActor.assumeIsolated` and answers each request in full inside `start`.
final class UITestFixturePages: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        nonisolated(unsafe) let task = urlSchemeTask
        MainActor.assumeIsolated {
            Self.answer(task)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Nothing to stop: every request was answered before `start` returned.
    }

    @MainActor
    private static func answer(_ task: any WKURLSchemeTask) {
        let body = Data(UITestFixture.page.utf8)
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "text/html; charset=utf-8",
                                                            "Content-Length": String(body.count)]) else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
#endif
