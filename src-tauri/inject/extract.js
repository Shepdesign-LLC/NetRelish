// Extraction content script. Evaluated in the preview webview after every
// main-frame load; the returned object comes back to Rust JSON-serialized
// (extract.rs::on_page_finished). Everything is wrapped in one IIFE so the
// page's globals are never touched — and the page gets nothing in return.
//
// Rust splices the vendored Readability source over the marker line below.
(function () {
  "use strict";
  try {
    var t0 = performance.now();

    // Shadow CommonJS globals so readability.js's export guard stays inert
    // on pages that define `module` themselves.
    var module = undefined;
    var exports = undefined;

    /*__NR_READABILITY__*/

    // Readability mutates the DOM it is given — always hand it a clone.
    var article = null;
    try {
      article = new Readability(document.cloneNode(true), {
        charThreshold: 250,
      }).parse();
    } catch (_e) {
      // Non-article layouts routinely throw; the fallback below covers them.
    }

    var text =
      article && article.textContent
        ? article.textContent
        : document.body
          ? document.body.innerText
          : "";

    var descEl = document.querySelector('meta[name="description"]');

    return {
      ok: true,
      url: String(location.href),
      title:
        (article && article.title) || document.title || String(location.href),
      byline: (article && article.byline) || null,
      excerpt:
        (article && article.excerpt) ||
        (descEl ? descEl.getAttribute("content") : null),
      site: (article && article.siteName) || null,
      // Cap pathological pages; FTS on 800k chars of one page helps no one.
      text: String(text).slice(0, 800000),
      ms: performance.now() - t0,
    };
  } catch (e) {
    return {
      ok: false,
      url: String(location.href),
      title: (document && document.title) || "",
      error: String(e),
    };
  }
})();
