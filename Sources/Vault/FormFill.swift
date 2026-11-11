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
//     by a box it sits in or by one further out, or parked where no scrolling gets to
//     (above or to the left of the page, or of a panel that scrolls; anywhere outside the
//     window on a page that doesn't scroll). Further down a page that scrolls, or down a
//     panel that scrolls, counts as seen;
//   - with the cursor in a form, only that form is filled;
//   - what to fill is decided before anything is written, so a page can't reveal more
//     fields, or move them into the form, as the first one fills.
// That stops the plain version of showing one box and collecting the rest of the card. It
// is a best effort, not a proof: a page that sets out to can still hide a field this
// passes, under another element, in the page's own color, cut away with clip or clip-path,
// or parked far to the right or far down a page that scrolls there.
// One more cost: while a site has the page locked from scrolling (a dialog is open), only
// the fields in the window or in the dialog are filled.
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
    const get = (e, n) => own[n].call(e);
    const rectOf = e => Element.prototype.getBoundingClientRect.call(e);

    // What the window does with a page too big for it comes from <html>, or from <body> when
    // <html> says nothing. When it comes from <html>, <body> is a box like any other.
    const rootStyle = getComputedStyle(root);
    const bodyIsABox = body && (rootStyle.overflowX !== 'visible' || rootStyle.overflowY !== 'visible');
    const windowStyle = bodyIsABox || !body ? rootStyle : getComputedStyle(body);
    const scrollingOf = getter(Document.prototype, 'scrollingElement');
    const scrolling = (scrollingOf && scrollingOf.call(document)) || root;

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

    // How big a box is drawn, against how big it is laid out: a transformed box is drawn at
    // another size, and everything below is measured as drawn, in the window.
    const laidOut = { x: getter(HTMLElement.prototype, 'offsetWidth'), y: getter(HTMLElement.prototype, 'offsetHeight') };
    function drawnPer(p, r, axis) {
      const size = p instanceof HTMLElement && laidOut[axis] ? laidOut[axis].call(p) : 0;
      return size > 0 ? (axis === 'x' ? r.width : r.height) / size : 1;
    }

    // How far a box's contents can still move each way if it is scrolled, as [back, forward].
    function room(position, most, rightToLeft) {
      const least = rightToLeft ? -most : 0, greatest = rightToLeft ? 0 : most;
      return [position - Math.max(greatest, position), position - Math.min(least, position)];
    }

    // A box that holds the positioned boxes inside it even when it isn't positioned itself:
    // one that is transformed, filtered, or contained.
    function holdsPositioned(s) {
      return s.transform !== 'none' || s.translate !== 'none' || s.rotate !== 'none' || s.scale !== 'none'
          || s.perspective !== 'none' || s.filter !== 'none'
          || (s.backdropFilter !== undefined && s.backdropFilter !== 'none')
          || /paint|layout|strict|content/.test(s.contain)
          || /transform|perspective|filter|translate|rotate|scale/.test(s.willChange);
    }

    // Somewhere a person could bring into view.
    //
    // It follows one thing outward from the field: the strip of the window, across and down,
    // where some of the field could ever be shown. Each box the field sits in changes it. A
    // box that scrolls slides it, by as far as that box can scroll each way, and then, like a
    // box that only cuts off, trims it to what the box itself shows. The window does the same
    // last. If the strip is ever thinner than a field, nobody could have seen it.
    //
    // A box changes only what it holds, and what holds a positioned field isn't always its
    // parent. position:absolute is held by the nearest box above that is itself positioned
    // (or transformed), and the plain boxes in between don't touch it. position:fixed is
    // held by the window, unless a transformed box is above it.
    function reachable(el, box) {
      let x0 = box.left, x1 = box.left + box.width, y0 = box.top, y1 = box.top + box.height;
      let free = 'no';   // 'no', or what the box in hand is free of: 'plain' boxes, or 'all' but transformed ones
      for (let p = el; p; p = get(p, 'parentElement')) {
        const s = getComputedStyle(p);
        if (p !== el) {
          if (p === root || (p === body && !bodyIsABox)) continue;
          if (free === 'plain' && s.position === 'static' && !holdsPositioned(s)) continue;
          if (free === 'all' && !holdsPositioned(s)) continue;
          free = 'no';
          const ox = s.overflowX, oy = s.overflowY;
          if ((ox !== 'visible' || oy !== 'visible') && !/^(inline|contents)$/.test(s.display)) {
            const r = rectOf(p);
            if (ox !== 'visible') {
              const k = drawnPer(p, r, 'x'), shown = r.left + get(p, 'clientLeft') * k;
              if (/auto|scroll/.test(ox)) {
                const [back, forward] = room(get(p, 'scrollLeft'), get(p, 'scrollWidth') - get(p, 'clientWidth'), s.direction === 'rtl');
                x0 += back * k; x1 += forward * k;
              }
              x0 = Math.max(x0, shown); x1 = Math.min(x1, shown + get(p, 'clientWidth') * k);
              if (x1 - x0 < 8) return false;
            }
            if (oy !== 'visible') {
              const k = drawnPer(p, r, 'y'), shown = r.top + get(p, 'clientTop') * k;
              if (/auto|scroll/.test(oy)) {
                const [back, forward] = room(get(p, 'scrollTop'), get(p, 'scrollHeight') - get(p, 'clientHeight'), false);
                y0 += back * k; y1 += forward * k;
              }
              y0 = Math.max(y0, shown); y1 = Math.min(y1, shown + get(p, 'clientHeight') * k);
              if (y1 - y0 < 8) return false;
            }
          }
        }
        if (s.position === 'fixed') free = 'all';
        else if (s.position === 'absolute') free = 'plain';
      }
      // The window, last. A page that scrolls slides the strip as any scrolling box does. One
      // that doesn't (overflow hidden on the page, as a site sets while a dialog is open)
      // shows what's in the window now, and so does anything fixed to the window.
      if (free !== 'all') {
        if (!/hidden|clip/.test(windowStyle.overflowX)) {
          const most = Math.max(root.scrollWidth, get(scrolling, 'scrollWidth')) - window.innerWidth;
          const [back, forward] = room(window.scrollX, Math.max(most, 0), false);
          x0 += back; x1 += forward;
        }
        if (!/hidden|clip/.test(windowStyle.overflowY)) {
          const most = Math.max(root.scrollHeight, get(scrolling, 'scrollHeight')) - window.innerHeight;
          const [back, forward] = room(window.scrollY, Math.max(most, 0), false);
          y0 += back; y1 += forward;
        }
      }
      return Math.min(x1, window.innerWidth) - Math.max(x0, 0) >= 8
          && Math.min(y1, window.innerHeight) - Math.max(y0, 0) >= 8;
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
