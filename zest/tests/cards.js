// Cards suite: ZestImage's eight layouts, rendered through the live stage across the matrix
// (8 layouts × 6 targets × Light/Dark × 2 sample brands × short/long copy, plus logo + photo on three
// targets). For every line of type on every card it checks what a designer would check by eye:
//   – it sits inside the canvas, and inside the layout's safe rect (svg[data-safe]);
//   – no word is split across lines, and nothing is cut short with an ellipsis;
//   – it is at least 0.042 of the short side (about 11px when a 1200px card shows at 500px in a feed);
//   – it reads against what it sits on (data-bg): 4.5:1, or 3:1 for bold type at 0.06 of the short side.
// Decorative glyphs (data-deco: the tonal initial, the quote mark, the series numeral) may bleed and are skipped.
// Plus: the layout picker draws a live thumbnail of every layout, logos are placed by their measured
// aspect, and user text is escaped. Serve: image :8772.
const { chromium } = require('playwright');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {};
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.error('  FAIL ' + m); } };

const LAYOUTS = ['title', 'kicker', 'split', 'scrim', 'stat', 'quote', 'series', 'logo'];
const TARGETS = ['og', 'square', 'story', 'pinterest', 'custom:1500x500', 'custom:800x1200'];
const COPY = {
  short: { cTitle: 'Zest launches today', cKicker: 'Announcement', cByline: 'Ryan Shepherd · netrelish.com', cStat: '4×', cStatLabel: 'tools, one brand', cQuote: 'It looks like us, not like AI.' },
  long: { cTitle: 'How we rebuilt our design system in six weeks without stopping a single release',   // 14 words
    cKicker: 'Case study', cByline: 'Ryan Shepherd · Design lead, netrelish.com', cStat: '38%', cStatLabel: 'faster from brief to shipped page',
    cQuote: 'We stopped arguing about colors the week the tokens became the only place they lived' },
};

(async () => {
  const browser = await chromium.launch(LAUNCH);
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1, serviceWorkers: 'block' });
  const pg = await ctx.newPage();
  const errs = []; pg.on('pageerror', e => errs.push(e.message));
  await pg.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
  await pg.goto(process.env.ZI_URL || 'http://localhost:8772/', { waitUntil: 'domcontentloaded' });
  await pg.evaluate(() => localStorage.clear()); await pg.reload({ waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(500);

  const setCopy = copy => pg.evaluate(c => {   // fields a layout leaves out sit in a closed disclosure; set them all the way the app reads them
    for (const [id, v] of Object.entries(c)) { const e = document.getElementById(id); e.value = v; }
    document.getElementById('cTitle').dispatchEvent(new Event('input', { bubbles: true }));
  }, copy);
  const pick = async sel => { await pg.click(sel); };
  const setTarget = async t => {
    const [id, size] = t.split(':');
    await pick(`[data-t="${id}"]`);
    if (size) { const [w, h] = size.split('x'); await pg.fill('#cw', w); await pg.fill('#ch', h); }
  };

  // one card, judged in the page
  const judge = copy => pg.evaluate(copy => {
    const svg = document.querySelector('#stageSvg svg');
    const [, , W, H] = svg.getAttribute('viewBox').split(' ').map(Number), u = Math.min(W, H);
    const [x0, y0, x1, y1] = (svg.getAttribute('data-safe') || '').split(' ').map(Number);
    const hex = h => { h = h.replace('#', ''); if (h.length === 3) h = [...h].map(c => c + c).join(''); return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16) / 255); };
    const L = h => { const [r, g, b] = hex(h).map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
    const cr = (a, b) => { const p = L(a), q = L(b); return (Math.max(p, q) + 0.05) / (Math.min(p, q) + 0.05); };
    const cv = document.createElement('canvas').getContext('2d');
    const norm = w => w.toUpperCase().replace(/^[“"(]+|[.,;:!?”")]+$/g, '');
    const brands = [...document.querySelectorAll('.brandrow b')].map(b => b.textContent);
    const vocab = new Set([...Object.values(copy), ...brands, 'Part of 1 2 3 4 5 6 7 8 9 Brand Untitled'].join(' ').split(/\s+/).filter(Boolean).flatMap(w => [w.toUpperCase(), norm(w)]));
    const tol = Math.max(1.5, u * 0.006), bad = [];
    for (const t of svg.querySelectorAll('text')) {
      if (t.hasAttribute('data-deco')) continue;
      const text = [...t.querySelectorAll('tspan')].map(s => s.textContent);
      const label = `"${text.join(' / ').slice(0, 48)}"`;
      const size = +t.getAttribute('font-size'), weight = +t.getAttribute('font-weight') || 400;
      // ink extents of every line, measured with the face the card uses (the line box would count a descender a numeral never has)
      cv.font = `${weight} ${size}px ${t.getAttribute('font-family')}`;
      cv.letterSpacing = (+t.getAttribute('letter-spacing') || 0) + 'px';
      cv.textAlign = { end: 'right', middle: 'center' }[t.getAttribute('text-anchor')] || 'left';
      const ink = [...t.querySelectorAll('tspan')].map(s => { const m = cv.measureText(s.textContent), x = +s.getAttribute('x'), y = +s.getAttribute('y');
        return { l: x - m.actualBoundingBoxLeft, r: x + m.actualBoundingBoxRight, t: y - m.actualBoundingBoxAscent, b: y + m.actualBoundingBoxDescent, y }; });
      const box = { l: Math.min(...ink.map(i => i.l)), r: Math.max(...ink.map(i => i.r)), t: Math.min(...ink.map(i => i.t)), b: Math.max(...ink.map(i => i.b)), base: Math.max(...ink.map(i => i.y)) };
      if (box.l < -1 || box.t < -1 || box.r > W + 1 || box.b > H + 1) bad.push(`${label} leaves the canvas`);
      if (box.l < x0 - tol || box.r > x1 + tol || box.t < y0 - tol || box.base > y1 + tol) bad.push(`${label} leaves the safe rect (${[box.l, box.t, box.r, box.base].map(Math.round)} vs ${[x0, y0, x1, y1].map(Math.round)})`);
      if (size < u * 0.042 - 0.05) bad.push(`${label} is ${size}px, under 0.042u (${(u * 0.042).toFixed(1)})`);
      for (const w of text.join(' ').split(/\s+/).filter(Boolean)) {
        if (w.includes('…')) bad.push(`${label} is cut short`);
        else if (!vocab.has(w.toUpperCase()) && !vocab.has(norm(w))) bad.push(`${label} splits a word ("${w}")`);
      }
      const bg = t.getAttribute('data-bg'), fill = t.getAttribute('fill');
      if (!bg || !/^#[0-9a-f]{3,6}$/i.test(bg)) bad.push(`${label} names no background`);
      else { const need = weight >= 700 && size >= u * 0.06 ? 3 : 4.5, r = cr(fill, bg);
        if (r < need - 0.005) bad.push(`${label} ${fill} on ${bg} is ${r.toFixed(2)}:1, needs ${need}`); }
    }
    if (!svg.querySelector('text:not([data-deco])')) bad.push('no type on the card');
    return bad;
  }, copy);

  const failures = []; let cards = 0;
  const sweep = async (tag, targets, copies) => {
    for (const len of copies) {
      await setCopy(COPY[len]);
      for (const bi of [0, 1]) {
        await pick(`[data-i="${bi}"]`);
        for (const mode of ['light', 'dark']) {
          await pick(mode === 'light' ? '#mLight' : '#mDark');
          for (const tg of targets) {
            await setTarget(tg);
            for (const l of LAYOUTS) {
              await pick(`#layoutGrid [data-l="${l}"]`);
              const bad = await judge(COPY[len]); cards++;
              if (bad.length) failures.push(`${tag} ${l} ${tg} ${bi ? 'zest' : 'shepdesign'} ${mode} ${len}: ${bad.slice(0, 3).join('; ')}`);
            }
          }
        }
      }
    }
  };

  console.log('== the matrix: no logo, no photo ==');
  await sweep('bare', TARGETS, ['short', 'long']);
  const bare = failures.length;
  ok(bare === 0, `every card sets inside the canvas and its safe rect, whole words, nothing cut, ≥0.042u, readable (${cards} cards)${bare ? '\n    ' + failures.slice(0, 12).join('\n    ') : ''}`);

  console.log('== the matrix: a wide logo and a photo ==');
  const assets = await pg.evaluate(() => {
    const c = document.createElement('canvas'); c.width = 400; c.height = 100; const x = c.getContext('2d');   // a 4:1 wordmark-shaped logo
    x.fillStyle = '#222'; x.fillRect(0, 0, 400, 100); x.fillStyle = '#fff'; x.fillRect(20, 20, 360, 60);
    const logo = c.toDataURL('image/png');
    const p = document.createElement('canvas'); p.width = 1200; p.height = 800; const y = p.getContext('2d');   // a photo with a white sky and a black ground: the worst case for a veil
    y.fillStyle = '#ffffff'; y.fillRect(0, 0, 1200, 400); y.fillStyle = '#000000'; y.fillRect(0, 400, 1200, 400);
    return { logo: logo.split(',')[1], photo: p.toDataURL('image/jpeg', 0.9).split(',')[1] };
  });
  await pg.setInputFiles('#fLogo', { name: 'wide.png', mimeType: 'image/png', buffer: Buffer.from(assets.logo, 'base64') });
  await pg.setInputFiles('#fPhoto', { name: 'photo.jpg', mimeType: 'image/jpeg', buffer: Buffer.from(assets.photo, 'base64') });
  await pg.waitForTimeout(300);
  const before = cards;
  await sweep('assets', ['og', 'story', 'custom:1500x500'], ['short', 'long']);
  ok(failures.length === bare, `with a logo and a photo, every card still passes (${cards - before} cards)${failures.length > bare ? '\n    ' + failures.slice(bare, bare + 12).join('\n    ') : ''}`);

  console.log('== logos are placed by their measured aspect ==');
  await pick('[data-i="0"]'); await pick('#mLight'); await setTarget('og'); await pick('#layoutGrid [data-l="kicker"]');
  const lg = await pg.evaluate(() => {
    const svg = document.querySelector('#stageSvg svg'), im = svg.querySelector('image[href^="data:image/png"]');
    const [, , x1] = svg.getAttribute('data-safe').split(' ').map(Number);
    return im && { ar: im.getAttribute('width') / im.getAttribute('height'), right: +im.getAttribute('x') + +im.getAttribute('width'), x1 };
  });
  ok(lg && Math.abs(lg.ar - 4) < 0.05, `a 4:1 logo is drawn 4:1, not boxed into a guess (${lg && lg.ar.toFixed(2)})`);
  ok(lg && Math.abs(lg.right - lg.x1) < 1, `a logo on the right of the rail ends on the right margin (${lg && lg.right.toFixed(1)} vs ${lg && lg.x1})`);

  console.log('== the layout picker shows the layouts ==');
  await pg.waitForTimeout(400);
  const th = await pg.evaluate(() => [...document.querySelectorAll('#layoutGrid .lcell')].map(c => {
    const s = c.querySelector('.lthumb > svg'); return { l: c.dataset.l, ok: !!s && !!s.querySelector('rect') && s.getAttribute('viewBox') === '0 0 1200 630', name: c.querySelector('b').textContent };
  }));
  ok(th.length === 8 && th.every(t => t.ok && t.name), `all eight layouts show a live thumbnail in the current target, with their name (${th.filter(t => t.ok).length}/8)`);
  const thumbs = await pg.evaluate(() => [...document.querySelectorAll('#layoutGrid .lthumb')].map(e => e.innerHTML));
  ok(thumbs.every(h => h.includes('#1f4ed8') && !h.includes('@font-face') && !h.includes('data:image')), 'thumbnails use the brand, and stay light: no embedded fonts, no data URIs');
  await pick('#mDark'); await pg.waitForTimeout(400);
  ok(await pg.evaluate(() => [...document.querySelectorAll('#layoutGrid .lthumb')].every(e => e.innerHTML.includes('#8fb0ff'))), 'thumbnails follow the Light/Dark switch');
  await pick('[data-t="story"]'); await pg.waitForTimeout(400);
  ok(await pg.evaluate(() => [...document.querySelectorAll('#layoutGrid .lthumb > svg')].every(s => s.getAttribute('viewBox') === '0 0 1080 1920')), 'thumbnails follow the target');
  ok(await pg.evaluate(() => document.querySelector('#layoutGrid [data-l="kicker"]').getAttribute('aria-pressed') === 'true'), 'the picked layout stays marked');

  console.log('== user text is text ==');
  await pick('#layoutGrid [data-l="title"]');
  await setCopy({ cTitle: '<img src=x onerror="window.__zx=1"> & "quotes" </text><script>window.__zx=1</script>', cByline: '</tspan><g onload="window.__zx=1">' });
  await pg.waitForTimeout(400);
  const xs = await pg.evaluate(() => ({ el: document.querySelectorAll('#stageSvg img, #stageSvg script, #stageSvg g[onload], #layoutGrid img, #layoutGrid script').length, txt: document.querySelector('#stageSvg svg').textContent, zx: window.__zx }));
  ok(xs.el === 0 && !xs.zx && xs.txt.includes('<img') && xs.txt.includes('</tspan>'), 'titles and bylines are drawn as text, never as markup (stage and thumbnails)');

  ok(errs.length === 0, `no exceptions${errs.length ? ' — ' + errs.slice(0, 3).join(' | ') : ''}`);
  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
