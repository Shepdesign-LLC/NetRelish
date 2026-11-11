// FormFill.swift — puts the Me card into a page's form, only when asked (⌘⇧F).
// Nothing is injected at load; this script runs once, in the main frame, and returns how
// many fields it filled. It sets values through the native setter and dispatches input +
// change so framework forms (React, Vue) notice, the way a keystroke would.
//
// It runs in its own content world, not the page's. The page's JavaScript can't see the
// script or the card, and can't swap out the functions the script calls to collect what
// passes through them. The page only ever learns what lands in a field.
//
// It never touches: password or hidden inputs, autocomplete="off", autocomplete tokens we
// don't hold (cc-*, username, one-time-code…), disabled/readonly fields, or anything that
// already has a value. And it fills only what you can see, where you are:
//   - a field that isn't drawn (display:none, hidden, fully transparent, a pixel wide,
//     parked off the page, or marked aria-hidden) is left alone, so a page can't show one
//     box and collect the rest of the card through fields you never saw;
//   - with the cursor in a form, only that form is filled.
// Those checks are a best effort, not a proof: a page can still disguise a field it draws.

import WebKit

enum FormFill {
    /// Fills `identity` into the page's main-frame form fields. Returns the number filled.
    @MainActor
    static func fill(_ identity: Identity, in webView: WKWebView) async throws -> Int {
        guard !identity.isEmpty else { return 0 }
        var card: [String: String] = [:]
        var tokens: [String: [String]] = [:]
        var hints: [String: String] = [:]
        for field in IdentityField.allCases where !identity[field].isEmpty {
            card[field.rawValue] = identity[field]
            tokens[field.rawValue] = field.autocompleteTokens
            hints[field.rawValue] = field.nameHint
        }
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: ["card": card, "tokens": tokens, "hints": hints],
            in: nil,
            contentWorld: world
        )
        return result as? Int ?? 0
    }

    /// The fill script's own JavaScript world. The page's scripts can't reach into it.
    @MainActor private static let world = WKContentWorld.world(name: "netrelish.fill")

    // `card`, `tokens`, `hints` arrive as arguments. Returns the fill count.
    //
    // `document` is reached through `Document.prototype`, never by name: an element named
    // "querySelectorAll" or "activeElement" replaces that name on `document` in every world.
    static let script = """
    const byToken = {};
    for (const f in tokens) for (const t of tokens[f]) byToken[t] = f;
    const order = Object.keys(hints);
    const rx = {};
    for (const f of order) rx[f] = new RegExp(hints[f], 'i');

    function getter(proto, name) {
      for (let p = proto; p; p = Object.getPrototypeOf(p)) {
        const d = Object.getOwnPropertyDescriptor(p, name);
        if (d && d.get) return d.get;
      }
      return null;
    }
    const fields = Array.from(Document.prototype.querySelectorAll.call(document, 'input, textarea, select'));
    const activeOf = getter(Document.prototype, 'activeElement');
    const active = activeOf ? activeOf.call(document) : null;
    const root = getter(Document.prototype, 'documentElement').call(document);

    function fieldFor(el) {
      if (el.disabled || el.readOnly) return null;
      const tag = el.tagName;
      const type = (el.type || 'text').toLowerCase();
      if (tag === 'INPUT' && !['text', 'email', 'tel', 'search', ''].includes(type)) return null;
      const ac = (el.getAttribute('autocomplete') || '').trim().toLowerCase();
      if (ac && ac !== 'on') {
        const last = ac.split(/\\s+/).pop();
        return byToken[last] || null;          // a token we don't hold means hands off
      }
      if (type === 'email') return card.email ? 'email' : null;
      if (type === 'tel') return card.phone ? 'phone' : null;
      const key = [el.name, el.id, el.placeholder, el.getAttribute('aria-label')].filter(Boolean).join(' ');
      if (/pass|pwd|secret|token|otp|code/i.test(key)) return null;
      for (const f of order) if (rx[f].test(key)) return f;
      return null;
    }

    // Drawn, big enough to be a field, and somewhere on the page.
    function canBeSeen(el) {
      if (!el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) return false;
      if (el.closest('[aria-hidden="true"], [inert]')) return false;
      const box = el.getBoundingClientRect();
      if (box.width < 8 || box.height < 8) return false;
      const left = box.left + window.scrollX, top = box.top + window.scrollY;
      if (left + box.width <= 0 || top + box.height <= 0) return false;
      const pageWidth = Math.max(root.scrollWidth, window.innerWidth);
      const pageHeight = Math.max(root.scrollHeight, window.innerHeight);
      return left < pageWidth && top < pageHeight;
    }

    function setValue(el, value) {
      if (el.tagName === 'SELECT') {
        const want = value.toLowerCase();
        const opt = Array.from(el.options).find(o => o.value.toLowerCase() === want || o.text.trim().toLowerCase() === want);
        if (!opt) return false;
        el.value = opt.value;
      } else {
        const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
      }
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    }

    // With the cursor in a field, only that field's form (or, outside any form, only the
    // other fields outside any form). With the cursor nowhere, the whole page.
    const here = fields.includes(active) ? active.form : undefined;

    let filled = 0;
    for (const el of fields) {
      if (here !== undefined && el.form !== here) continue;
      const f = fieldFor(el);
      if (!f || !card[f]) continue;
      if (el.tagName === 'SELECT' ? el.selectedIndex > 0 : el.value) continue;   // never overwrite
      if (!canBeSeen(el)) continue;
      if (setValue(el, card[f])) filled++;
    }
    return filled;
    """
}

extension IdentityField {
    /// Case-insensitive pattern tried against name/id/placeholder when there's no autocomplete.
    /// Tried in `allCases` order, so the more specific patterns come first.
    var nameHint: String {
        switch self {
        case .givenName: "first|given|fname|forename"
        case .familyName: "last|family|surname|lname"
        case .email: "e-?mail"
        case .phone: "phone|mobile|\\btel"
        case .street: "street|addr(ess)?[-_ ]?(line)?[-_ ]?1|^address$|\\baddress\\b"
        case .city: "city|town|locality"
        case .state: "\\bstate\\b|province|region"
        case .postalCode: "zip|postal|postcode"
        case .country: "country"
        }
    }
}
