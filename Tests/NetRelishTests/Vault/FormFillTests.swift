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
    private func loaded(_ html: String = FormFillTests.form) async throws -> JarWebView {
        let web = JarWebView(jarId: "fill-test-\(UUID().uuidString)")
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web.webView
        web.webView.loadHTMLString(html, baseURL: nil)
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

    // MARK: Only what you can see, where you are

    /// One box in view and the rest of the card asked for through fields nobody can see.
    private static let harvest = """
    <!doctype html>
    <form>
      <input id="em" type="email">
      <input id="none" autocomplete="given-name" style="display:none">
      <div style="display:none"><input id="inside-none" autocomplete="family-name"></div>
      <input id="invisible" autocomplete="tel" style="visibility:hidden">
      <input id="clear" autocomplete="address-line1" style="opacity:0">
      <div style="opacity:0"><input id="inside-clear" autocomplete="address-level2"></div>
      <input id="faint" autocomplete="address-line1" style="opacity:.01">
      <div style="opacity:.2"><input id="inside-faint" autocomplete="address-level2" style="opacity:.2"></div>
      <div style="height:0; overflow:hidden"><input id="collapsed" autocomplete="tel"></div>
      <input id="away" autocomplete="postal-code" style="position:absolute; left:-9999px">
      <input id="above" autocomplete="country-name" style="position:absolute; top:-9999px">
      <input id="speck" autocomplete="given-name" style="width:1px; height:1px; padding:0; border:0">
      <div aria-hidden="true"><input id="unannounced" autocomplete="family-name"></div>
    </form>
    """

    @Test("A field nobody can see is left alone, so one visible box can't collect the whole card",
          arguments: ["none", "inside-none", "invisible", "clear", "inside-clear", "faint", "inside-faint", "collapsed",
                      "away", "above", "speck", "unannounced"])
    @MainActor func leavesUnseenFieldsAlone(id: String) async throws {
        let web = try await loaded(Self.harvest)
        let filled = try await FormFill.fill(me, in: web.webView)
        #expect(filled == 1)
        #expect(try await value(web, "em") == "ryan@example.com")
        #expect(try await value(web, id) == "")
    }

    @Test("A page that reveals its hidden fields as the first one fills still gets only what was in view")
    @MainActor func fieldsRevealedMidFillAreLeftAlone() async throws {
        let web = try await loaded(Self.harvest + """

        <script>
          document.getElementById('em').addEventListener('input', () => {
            for (const el of document.querySelectorAll('[style]')) el.removeAttribute('style');
            for (const el of document.querySelectorAll('[aria-hidden]')) el.removeAttribute('aria-hidden');
          });
        </script>
        """)
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "em") == "ryan@example.com")
        #expect(try await value(web, "none") == "")
        #expect(try await value(web, "unannounced") == "")
    }

    @Test("A page that moves a field into the form in focus as it fills still gets only that form")
    @MainActor func fieldsMovedIntoTheFormMidFillAreLeftAlone() async throws {
        let web = try await loaded("""
        <form id="f"><input id="em" type="email"></form>
        <input id="fn" autocomplete="given-name">
        <script>
          document.getElementById('em').addEventListener('input', () => document.getElementById('fn').setAttribute('form', 'f'));
        </script>
        """)
        _ = try await web.webView.evaluateJavaScript("document.getElementById('em').focus(); 0")
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "em") == "ryan@example.com")
        #expect(try await value(web, "fn") == "")
    }

    /// An app shell: the page doesn't scroll, the panel inside it does.
    private static let shell = """
    <!doctype html>
    <style>html, body { height: 100%; margin: 0; overflow: hidden } main { height: 100%; overflow: auto }</style>
    <main><form>
      <input id="em" type="email">
      <div style="height:2000px"></div>
      <input id="st" autocomplete="address-line1">
    </form></main>
    """

    @Test("A field further down a panel that scrolls is filled, wherever the panel is scrolled to", arguments: [0, 99_999])
    @MainActor func fillsInsideAScrollingPanel(scrollTop: Int) async throws {
        let web = try await loaded(Self.shell)
        _ = try await web.webView.evaluateJavaScript("document.querySelector('main').scrollTop = \(scrollTop); 0")
        #expect(try await FormFill.fill(me, in: web.webView) == 2)
        #expect(try await value(web, "em") == "ryan@example.com")
        #expect(try await value(web, "st") == "1 Main St")
    }

    @Test("A field further down a long page is filled")
    @MainActor func fillsBelowTheFold() async throws {
        let web = try await loaded("""
        <!doctype html>
        <form><input id="em" type="email"><div style="height:2000px"></div><input id="st" autocomplete="address-line1"></form>
        """)
        #expect(try await FormFill.fill(me, in: web.webView) == 2)
    }

    @Test("A field parked out of reach inside a scrolling box is still left alone")
    @MainActor func leavesFieldsParkedInsideAScrollerAlone() async throws {
        let web = try await loaded("""
        <!doctype html>
        <form><input id="em" type="email">
          <div style="position:relative; overflow:auto; height:40px">
            <input id="up" autocomplete="tel" style="position:absolute; top:-9999px">
            <input id="lf" autocomplete="given-name" style="position:absolute; left:-9999px">
          </div>
        </form>
        """)
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "up") == "")
        #expect(try await value(web, "lf") == "")
    }

    /// Fields a box cuts off, each hidden a different way. `em` is the one in view.
    private static let cutOff = """
    <!doctype html>
    <form>
      <input id="em" type="email">
      <div style="position:relative; height:0; overflow:hidden"><input id="held" autocomplete="given-name" style="position:absolute; top:0; left:0"></div>
      <div style="height:0; overflow:auto"><input id="shut" autocomplete="family-name"></div>
      <div style="height:200px"></div>
      <div style="position:relative; height:40px; overflow:auto"><input id="over" autocomplete="tel" style="position:absolute; top:-40px; height:20px"></div>
      <div style="position:relative; height:40px; width:200px; overflow:hidden"><input id="beside" autocomplete="postal-code" style="position:absolute; left:400px"></div>
      <div style="position:relative; height:40px; overflow:hidden"><div><input id="below" autocomplete="address-line1" style="position:absolute; top:60px"></div></div>
      <div style="transform:translateZ(0); height:0; overflow:hidden"><input id="turned" autocomplete="address-level2" style="position:absolute; top:0; left:0"></div>
      <div style="filter:blur(0); height:0; overflow:hidden"><input id="pinned" autocomplete="country-name" style="position:fixed; top:10px; left:10px"></div>
    </form>
    """

    @Test("A field cut off by the box it sits in is left alone, however it's positioned",
          arguments: ["held", "shut", "over", "beside", "below", "turned", "pinned"])
    @MainActor func leavesFieldsCutOffByTheirBoxAlone(id: String) async throws {
        let web = try await loaded(Self.cutOff)
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "em") == "ryan@example.com")
        #expect(try await value(web, id) == "")
    }

    @Test("A positioned field that sits outside a plain box that cuts off is still filled: that box doesn't hold it")
    @MainActor func fillsAPositionedFieldItsPlainParentCannotCutOff() async throws {
        let web = try await loaded("""
        <!doctype html>
        <form style="position:relative; height:120px">
          <div style="height:0; overflow:hidden"><input id="em" type="email" style="position:absolute; top:40px; left:10px"></div>
        </form>
        """)
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "em") == "ryan@example.com")
    }

    @Test("On a page that can't scroll, a field outside the window is left alone",
          arguments: ["html, body { height: 100%; overflow: hidden }", "body { overflow: hidden }", "html { overflow: hidden }"])
    @MainActor func leavesFieldsOutsideALockedPageAlone(lock: String) async throws {
        let web = try await loaded("""
        <!doctype html>
        <style>\(lock) body { margin: 0 }</style>
        <form><input id="em" type="email"><div style="height:2000px"></div><input id="st" autocomplete="address-line1"></form>
        """)
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "em") == "ryan@example.com")
        #expect(try await value(web, "st") == "")
    }

    @Test("A dialog over a locked page is filled, down to the bottom of what it scrolls")
    @MainActor func fillsADialogOverALockedPage() async throws {
        let web = try await loaded("""
        <!doctype html>
        <style>body { margin: 0; overflow: hidden } .dialog { position: fixed; inset: 0; overflow-y: auto }</style>
        <form><input id="behind" autocomplete="tel"><div style="height:2000px"></div><input id="far" autocomplete="postal-code"></form>
        <div class="dialog"><form><input id="em" type="email"><div style="height:2000px"></div><input id="st" autocomplete="address-line1"></form></div>
        """)
        _ = try await web.webView.evaluateJavaScript("document.getElementById('em').focus(); 0")
        #expect(try await FormFill.fill(me, in: web.webView) == 2)
        #expect(try await value(web, "st") == "1 Main St")
        #expect(try await value(web, "far") == "")
    }

    @Test("A field fixed in place outside the window is left alone, however long the page is")
    @MainActor func leavesAFixedFieldOutsideTheWindowAlone() async throws {
        let web = try await loaded("""
        <!doctype html>
        <form><input id="em" type="email"><div style="height:3000px"></div>
          <input id="off" autocomplete="tel" style="position:fixed; top:150vh; left:10px"></form>
        """)
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "off") == "")
    }

    @Test("A page that scrolls in its body, not the window, is filled top to bottom wherever it's scrolled to", arguments: [0, 99_999])
    @MainActor func fillsWhenTheBodyScrolls(scrollTop: Int) async throws {
        let web = try await loaded("""
        <!doctype html>
        <style>html { height: 100%; overflow: hidden } body { height: 100%; margin: 0; overflow: auto }</style>
        <form><input id="em" type="email"><div style="height:2000px"></div><input id="st" autocomplete="address-line1"></form>
        """)
        _ = try await web.webView.evaluateJavaScript("document.body.scrollTop = \(scrollTop); 0")
        #expect(try await FormFill.fill(me, in: web.webView) == 2)
    }

    @Test("With the cursor in one form, only that form is filled")
    @MainActor func fillsOnlyTheFormInFocus() async throws {
        let web = try await loaded("""
        <form><input id="news" type="email"></form>
        <form><input id="fn" autocomplete="given-name"><input id="st" autocomplete="address-line1"></form>
        <input id="loose" autocomplete="tel">
        """)
        _ = try await web.webView.evaluateJavaScript("document.getElementById('news').focus(); 0")
        #expect(try await web.webView.evaluateJavaScript("document.activeElement.id") as? String == "news")
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "news") == "ryan@example.com")
        #expect(try await value(web, "fn") == "")
        #expect(try await value(web, "st") == "")
        #expect(try await value(web, "loose") == "")
    }

    @Test("With the cursor in a field outside any form, the forms are left alone")
    @MainActor func fillsOnlyLooseFieldsFromALooseField() async throws {
        let web = try await loaded("""
        <input id="loose" autocomplete="tel"><input id="loose2" type="email">
        <form><input id="fn" autocomplete="given-name"></form>
        """)
        _ = try await web.webView.evaluateJavaScript("document.getElementById('loose').focus(); 0")
        #expect(try await FormFill.fill(me, in: web.webView) == 2)
        #expect(try await value(web, "loose") == "303-555-0100")
        #expect(try await value(web, "loose2") == "ryan@example.com")
        #expect(try await value(web, "fn") == "")
    }

    @Test("A page that swaps out the browser's own functions collects nothing through them")
    @MainActor func pageCannotInterceptTheFill() async throws {
        let web = try await loaded("""
        <form><input id="em" type="email"><input id="fn" autocomplete="given-name"></form>
        <script>
          window.taken = [];
          const take = v => { if (typeof v === 'string' && v) window.taken.push(v); };
          // Stand-in fields, one for each thing on the card, that record whatever is written to them.
          const fake = name => ({
            tagName: 'INPUT', type: 'text', disabled: false, readOnly: false, form: null, name: '', id: '',
            placeholder: '', options: [], selectedIndex: 0,
            getAttribute: a => a === 'autocomplete' ? name : null,
            checkVisibility: () => true, closest: () => null,
            getBoundingClientRect: () => ({ left: 10, top: 10, width: 100, height: 20 }),
            dispatchEvent: () => true,
            get value() { return ''; }, set value(v) { take(v); },
          });
          const tokens = ['given-name', 'family-name', 'email', 'tel', 'address-line1', 'address-level2', 'postal-code', 'country-name'];
          document.querySelectorAll = () => tokens.map(fake);
          Document.prototype.querySelectorAll = () => tokens.map(fake);
          // And listen on every path a value takes to a real field.
          for (const proto of [HTMLInputElement.prototype, HTMLTextAreaElement.prototype]) {
            const real = Object.getOwnPropertyDescriptor(proto, 'value');
            Object.defineProperty(proto, 'value', { get() { return real.get.call(this); }, set(v) { take(v); real.set.call(this, v); } });
          }
          const realDescriptor = Object.getOwnPropertyDescriptor;
          Object.getOwnPropertyDescriptor = (o, k) => {
            const d = realDescriptor(o, k);
            return d && d.set ? { ...d, set(v) { take(v); d.set.call(this, v); } } : d;
          };
          String.prototype.toLowerCase = function () { take(String(this)); return String(this); };
        </script>
        """)
        // The real fields are still filled...
        #expect(try await FormFill.fill(me, in: web.webView) == 2)
        #expect(try await value(web, "em") == "ryan@example.com")
        #expect(try await value(web, "fn") == "Ryan")
        // ...and nothing went through the page's stand-ins on the way.
        let taken = try await web.webView.evaluateJavaScript("window.taken") as? [String] ?? ["unreadable"]
        #expect(taken == [])
    }

    @Test("An element named like a browser function doesn't break or redirect the fill")
    @MainActor func namedElementsCannotStandInForTheDocument() async throws {
        let web = try await loaded("""
        <img name="querySelectorAll"><img name="activeElement"><img name="documentElement">
        <form name="querySelectorAll"><input id="em" type="email"></form>
        """)
        #expect(try await web.webView.evaluateJavaScript("typeof document.querySelectorAll") as? String != "function")
        #expect(try await FormFill.fill(me, in: web.webView) == 1)
        #expect(try await value(web, "em") == "ryan@example.com")
    }
}
