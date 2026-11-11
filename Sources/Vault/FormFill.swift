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
// already has a value. And it fills only what you could have seen, where you are:
//   - a field is left alone if it's display:none, hidden, transparent or nearly so, a pixel
//     wide, marked aria-hidden, or out of reach: inside a box collapsed to nothing, cut off
//     by a box it sits in, or parked where no scrolling gets to (above or to the left of
//     the page, or of a panel that scrolls). Further down the page, or down a panel that
//     scrolls, counts as seen;
//   - with the cursor in a form, only that form is filled;
//   - what to fill is decided before anything is written, so a page can't reveal more
//     fields, or move them into the form, as the first one fills.
// That stops the plain version of showing one box and collecting the rest of the card. It
// is a best effort, not a proof: a page that sets out to can still hide a field this
// passes, under another element, in the page's own color, cut away with clip or clip-path,
// or parked far to the right or far down a page that scrolls there.
// One cost: a site that hides its real <select> and draws its own dropdown doesn't get
// State or Country filled, because the real one can't be seen.

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
    const bodyOf = getter(Document.prototype, 'body');
    const body = bodyOf ? bodyOf.call(document) : null;

    // Boxes above a field are read through the prototypes too: a <form> hands back its own
    // field for any name a field has taken (name="parentElement", name="scrollTop").
    const own = {};
    for (const n of ['parentElement', 'clientLeft', 'clientTop', 'clientWidth', 'clientHeight',
                     'scrollLeft', 'scrollTop', 'scrollWidth', 'scrollHeight'])
      own[n] = getter(Element.prototype, n);
    // When the page scrolls in <body> rather than the window, that scroll counts as the page's.
    const scrollingOf = getter(Document.prototype, 'scrollingElement');
    const bodyScrolls = body && scrollingOf && scrollingOf.call(document) !== body;
    const pageScroll = n => (bodyScrolls ? get(body, n) : 0);
    const get = (e, n) => own[n].call(e);
    const rectOf = e => Element.prototype.getBoundingClientRect.call(e);

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

    // Inside what the page itself can scroll to.
    function onPage(box) {
      const left = box.left + window.scrollX + pageScroll('scrollLeft');
      const top = box.top + window.scrollY + pageScroll('scrollTop');
      if (left + box.width <= 0 || top + box.height <= 0) return false;
      const pageWidth = Math.max(root.scrollWidth, body ? get(body, 'scrollWidth') : 0, window.innerWidth);
      const pageHeight = Math.max(root.scrollHeight, body ? get(body, 'scrollHeight') : 0, window.innerHeight);
      return left < pageWidth && top < pageHeight;
    }

    // One direction of one box the field sits in. `at` is where the field starts inside the
    // box as it is scrolled now. A box that scrolls can bring into view anything within what
    // it scrolls over; a box that only cuts off shows what is inside it now and nothing else.
    function within(overflow, at, size, client, scroll, scrolled, rightToLeft) {
      if (overflow === 'visible') return true;
      if (/auto|scroll/.test(overflow)) {
        const start = at + scrolled;
        return rightToLeft ? (start < client && start + size > client - scroll)
                           : (start + size > 0 && start < scroll);
      }
      return Math.min(at + size, client) - Math.max(at, 0) >= 8;
    }

    // Somewhere a person could bring into view: not cut off by any box it sits in, and on
    // the page or inside a scrolling box that is (an app's main panel, a long dialog).
    //
    // A box cuts off or scrolls only what it contains, and what contains a positioned field
    // isn't always its parent: position:absolute is held by the nearest positioned box above
    // it, and the plain boxes in between don't touch it; position:fixed is held by the window.
    function reachable(el, box) {
      let passing = 'none';   // 'none', or which boxes above don't hold this one: 'plain' or 'all'
      for (let p = el; p; p = get(p, 'parentElement')) {
        const s = getComputedStyle(p);
        if (p !== el && p !== root && p !== body) {
          let holds = passing !== 'all';
          if (passing === 'plain') { if (s.position === 'static') holds = false; else passing = 'none'; }
          const ox = s.overflowX, oy = s.overflowY;
          if (holds && (ox !== 'visible' || oy !== 'visible') && !/^(inline|contents)$/.test(s.display)) {
            const r = rectOf(p);
            // Collapsed to nothing in a direction it cuts off or scrolls.
            if (ox !== 'visible' && r.width < 8) return false;
            if (oy !== 'visible' && r.height < 8) return false;
            const x = box.left - r.left - get(p, 'clientLeft'), y = box.top - r.top - get(p, 'clientTop');
            if (!within(ox, x, box.width, get(p, 'clientWidth'), get(p, 'scrollWidth'), get(p, 'scrollLeft'), s.direction === 'rtl')) return false;
            if (!within(oy, y, box.height, get(p, 'clientHeight'), get(p, 'scrollHeight'), get(p, 'scrollTop'), false)) return false;
            // Inside a box that scrolls, it's the box that has to be reachable from here up.
            if (/auto|scroll/.test(ox + ' ' + oy)) return reachable(p, r);
          }
        }
        if (s.position === 'fixed') passing = 'all';
        else if (s.position === 'absolute' && passing !== 'all') passing = 'plain';
      }
      return onPage(box);
    }

    // Too faint to notice: its own opacity times that of every box it sits in.
    function faint(el) {
      let opacity = 1;
      for (let p = el; p; p = get(p, 'parentElement')) opacity *= parseFloat(getComputedStyle(p).opacity);
      return opacity < 0.1;
    }

    // Drawn, big enough to be a field, and somewhere you could bring into view.
    function canBeSeen(el) {
      if (!el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) return false;
      if (el.closest('[aria-hidden="true"], [inert]')) return false;
      if (faint(el)) return false;
      const box = el.getBoundingClientRect();
      if (box.width < 8 || box.height < 8) return false;
      return reachable(el, box);
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

    // Decide first, write second. Writing a field runs the page's own input and change
    // listeners, and one of those could un-hide the rest of its fields, or move them into
    // this form, before the loop reached them. Nothing in the first pass runs page code.
    const isEmpty = el => !(el.tagName === 'SELECT' ? el.selectedIndex > 0 : el.value);
    const plan = [];
    for (const el of fields) {
      if (here !== undefined && el.form !== here) continue;
      const f = fieldFor(el);
      if (!f || !card[f]) continue;
      if (!isEmpty(el)) continue;                 // never overwrite
      if (!canBeSeen(el)) continue;
      plan.push([el, card[f]]);
    }
    let filled = 0;
    for (const [el, value] of plan) {
      if (!isEmpty(el)) continue;                 // the page filled it in the meantime
      if (setValue(el, value)) filled++;
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
