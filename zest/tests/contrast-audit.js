// WCAG text-contrast sweep: walks every text-bearing element (hidden included),
// composites effective backgrounds (alpha + element opacity), exempts disabled controls.
const { chromium } = require('playwright');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {}; // point at a system Chromium when the local playwright has no downloaded browsers
const [,, url, scheme = 'light', label = 'app'] = process.argv;
(async () => {
  const browser = await chromium.launch(LAUNCH);
  const ctx = await browser.newContext({ serviceWorkers: 'block', colorScheme: scheme });
  const page = await ctx.newPage();
  await page.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(800);
  const report = await page.evaluate(() => {
    const parse = c => { const m = c.match(/rgba?\(([\d.]+)[, ]+([\d.]+)[, ]+([\d.]+)(?:[,/ ]+([\d.]+))?\)/); return m ? { r: +m[1], g: +m[2], b: +m[3], a: m[4] === undefined ? 1 : +m[4] } : null; };
    const over = (top, base) => ({ r: top.r * top.a + base.r * (1 - top.a), g: top.g * top.a + base.g * (1 - top.a), b: top.b * top.a + base.b * (1 - top.a), a: 1 });
    const lum = c => { const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b); };
    const ratio = (a, b) => { const l1 = Math.max(lum(a), lum(b)), l2 = Math.min(lum(a), lum(b)); return (l1 + 0.05) / (l2 + 0.05); };
    const hex = c => '#' + [c.r, c.g, c.b].map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
    const effBg = el => {
      const chain = []; let n = el, gradient = false;
      while (n && n.nodeType === 1) {
        const s = getComputedStyle(n);
        if (s.backgroundImage && s.backgroundImage !== 'none') gradient = true;
        chain.push({ c: parse(s.backgroundColor), o: parseFloat(s.opacity) });
        n = n.parentElement;
      }
      let boundary = -1;
      for (let i = 0; i < chain.length; i++) if (chain[i].o < 1) boundary = i;
      let op = 1; for (const l of chain) if (l.o < 1) op *= l.o;
      const comp = (layers, base) => { for (let i = layers.length - 1; i >= 0; i--) { const c = layers[i].c; if (c && c.a > 0) base = c.a >= 1 ? c : over(c, base); } return base; };
      const white = { r: 255, g: 255, b: 255, a: 1 };
      if (boundary < 0) return { bg: comp(chain, white), gradient, op: 1, backdrop: null };
      const backdrop = comp(chain.slice(boundary + 1), white);
      const inner = comp(chain.slice(0, boundary + 1), backdrop);
      const bg = over({ ...inner, a: op }, backdrop);
      return { bg, gradient, op, backdrop };
    };
    const path = el => { const bits = []; let n = el; while (n && n.nodeType === 1 && bits.length < 4) { bits.unshift(n.tagName.toLowerCase() + (n.id ? '#' + n.id : '') + (n.classList.length ? '.' + [...n.classList].slice(0, 2).join('.') : '')); n = n.parentElement; } return bits.join('>'); };
    const seen = new Map(), out = [];
    for (const el of document.querySelectorAll('body *')) {
      if (['SCRIPT', 'STYLE', 'TEMPLATE', 'svg', 'SVG', 'NOSCRIPT', 'IFRAME'].includes(el.tagName)) continue;
      const direct = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
      if (!direct) continue;
      if (el.closest('[disabled], [aria-disabled="true"]')) continue;   // WCAG 1.4.3: inactive controls exempt
      const s = getComputedStyle(el);
      const fg = parse(s.color); if (!fg || fg.a === 0) continue;
      const { bg, gradient, op, backdrop } = effBg(el);
      let fgFlat = fg.a < 1 ? over(fg, bg) : fg;
      if (op < 1 && backdrop) fgFlat = over({ ...fgFlat, a: op }, backdrop);
      const r = ratio(fgFlat, bg);
      const size = parseFloat(s.fontSize) || 16, weight = +s.fontWeight || 400;
      const large = size >= 24 || (size >= 18.66 && weight >= 700);
      const need = large ? 3 : 4.5;
      const hidden = el.closest('[hidden]') !== null || s.display === 'none' || !!el.closest('[aria-hidden="true"]');
      if (r + 0.005 >= need) continue;
      const key = path(el) + '|' + hex(fgFlat) + '|' + hex(bg);
      if (seen.has(key)) continue; seen.set(key, 1);
      out.push({ path: path(el), text: el.textContent.trim().slice(0, 40), fg: hex(fgFlat), bg: hex(bg), ratio: +r.toFixed(2), need, size, weight, hidden, gradient });
    }
    return out;
  });
  console.log(JSON.stringify({ label, scheme, failures: report }, null, 1));
  await browser.close();
})();
