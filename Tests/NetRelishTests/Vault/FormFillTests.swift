import Testing
import WebKit
@testable import NetRelish

/// The fill script against a real form in a real WKWebView, inside the app process.
@Suite("Form fill") struct FormFillTests {

    private static let form = """
    <form>
      <input id="fn" autocomplete="given-name">
      <input id="ln" name="lastname">
      <input id="em" type="email">
      <input id="ph" autocomplete="shipping tel">
      <input id="st" autocomplete="address-line1">
      <input id="ci" name="city">
      <input id="zip" autocomplete="postal-code" value="already">
      <select id="co" autocomplete="country-name"><option>Canada</option><option>United States</option></select>
      <input id="pw" type="password" name="email_password">
      <input id="off" autocomplete="off" name="email">
      <input id="hid" type="hidden" name="email">
      <input id="cc" autocomplete="cc-number">
    </form>
    <script>
      window.events = [];
      document.getElementById('fn').addEventListener('input', () => window.events.push('fn:input'));
      document.getElementById('fn').addEventListener('change', () => window.events.push('fn:change'));
    </script>
    """

    private var me: Identity {
        var i = Identity()
        i.givenName = "Ryan"; i.familyName = "Shepherd"; i.email = "ryan@example.com"; i.phone = "303-555-0100"
        i.street = "1 Main St"; i.city = "Denver"; i.postalCode = "80202"; i.country = "United States"
        return i
    }

    @MainActor
    private func loaded() async throws -> JarWebView {
        let web = JarWebView(jarId: "fill-test-\(UUID().uuidString)")
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web.webView
        web.webView.loadHTMLString(Self.form, baseURL: nil)
        for _ in 0..<100 { try await Task.sleep(for: .milliseconds(50)); if !web.webView.isLoading { break } }
        return web
    }

    @MainActor
    private func value(_ web: JarWebView, _ id: String) async throws -> String {
        try await web.webView.evaluateJavaScript("document.getElementById('\(id)').value") as? String ?? ""
    }

    @Test("Fills by autocomplete token, then by name/type; skips password, hidden, off, cc-*, and non-empty")
    @MainActor func fills() async throws {
        let web = try await loaded()
        let filled = try await FormFill.fill(me, in: web.webView)
        #expect(filled == 7)
        #expect(try await value(web, "fn") == "Ryan")
        #expect(try await value(web, "ln") == "Shepherd")
        #expect(try await value(web, "em") == "ryan@example.com")
        #expect(try await value(web, "ph") == "303-555-0100")
        #expect(try await value(web, "st") == "1 Main St")
        #expect(try await value(web, "ci") == "Denver")
        #expect(try await value(web, "co") == "United States")
        #expect(try await value(web, "zip") == "already")   // never overwrite what's there
        #expect(try await value(web, "pw") == "")
        #expect(try await value(web, "off") == "")
        #expect(try await value(web, "hid") == "")
        #expect(try await value(web, "cc") == "")
    }

    @Test("Framework forms see input and change events, like a keystroke")
    @MainActor func dispatchesEvents() async throws {
        let web = try await loaded()
        _ = try await FormFill.fill(me, in: web.webView)
        let events = try await web.webView.evaluateJavaScript("window.events") as? [String] ?? []
        #expect(events == ["fn:input", "fn:change"])
    }

    @Test("An empty card fills nothing")
    @MainActor func emptyCard() async throws {
        let web = try await loaded()
        #expect(try await FormFill.fill(Identity(), in: web.webView) == 0)
        #expect(try await value(web, "fn") == "")
    }
}
