// Cards suite: ZestImage's eight layouts, rendered through the live stage across the matrix
// (8 layouts × 6 targets × Light/Dark × 2 sample brands × short/long copy, plus logo + photo on three
// targets). For every line of type on every card it checks what a designer would check by eye:
//   – it sits inside the canvas, and inside the layout's safe rect (svg[data-safe]);
//   – no word is split across lines, and nothing is cut short with an ellipsis;
//   – it is at least 0.042 of the short side (about 11px when a 1200px card shows at 500px in a feed);
//   – it reads against what it sits on (data-bg): 4.5:1, or 3:1 for bold type at 0.06 of the short side.
// Decorative glyphs (data-deco: the tonal initial, the quote mark, the series numeral) may bleed and are skipped.
// Every logo (<image data-logo>) sits inside the safe rect too, like type; photos are fields and may bleed.
// On square and tall targets a short headline is at least 0.1 of the short side in every layout that sets one:
// a decorative panel gives way before the headline shrinks to the floor.
// Plus: on targets with a platform safe zone, the card's safe rect sits inside the zone the stage draws.
// And: the layout picker draws a live thumbnail of every layout, logos are placed by their measured
// aspect, a dark wordmark on a Dark card is set in one color that reads, a brand whose head face is
// 400-only still gets it (the weighted request fails, the plain one is made), the thumbnails repaint once after
// typing stops and not at all for a format change, and user text is escaped. Serve: image :8772.
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
  await pg.route(/^https?:\/\/(?!(localhost|127\.0\.0\.1)[:/])/, r => r.abort());
  // The matrix runs in the brand's own faces from vendor/ (what people see) by default. CARDS_FONTS=system blocks
  // them, so the same matrix is judged in the system fallback too (CI's Ubuntu runner falls back to DejaVu Sans).
  if (process.env.CARDS_FONTS === 'system') await pg.route(/\/vendor\/fonts\//, r => r.abort());
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
      if (!bg || !/^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(bg)) bad.push(`${label} names no background`);
      else { const need = weight >= 700 && size >= u * 0.06 ? 3 : 4.5, r = cr(fill, bg);
        if (r < need - 0.005) bad.push(`${label} ${fill} on ${bg} is ${r.toFixed(2)}:1, needs ${need}`); }
    }
    if (!svg.querySelector('text:not([data-deco])')) bad.push('no type on the card');
    for (const im of svg.querySelectorAll('image[data-logo]')) {
      const x = +im.getAttribute('x'), y = +im.getAttribute('y'), w = +im.getAttribute('width'), h = +im.getAttribute('height');
      if (x < x0 - tol || y < y0 - tol || x + w > x1 + tol || y + h > y1 + tol) bad.push(`logo leaves the safe rect (${[x, y, x + w, y + h].map(Math.round)} vs ${[x0, y0, x1, y1].map(Math.round)})`);
    }
    const ti = svg.querySelector('text[data-role="title"]');
    if (copy.cTitle.split(' ').length < 6 && W / H < 1.3 && ti && +ti.getAttribute('font-size') < u * 0.1 - 0.05) bad.push(`the headline is ${ti.getAttribute('font-size')}px, under 0.1u (${(u * 0.1).toFixed(1)}) — the panel should give way first`);
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

  console.log('== a dark wordmark on a Dark card is set in one color ==');
  const dark = await pg.evaluate(() => {   // a transparent 4:1 wordmark in near-black ink: the logo most brands actually have
    const c = document.createElement('canvas'); c.width = 400; c.height = 100; const x = c.getContext('2d');
    x.fillStyle = '#1d1d1f'; x.font = 'bold 72px sans-serif'; x.textBaseline = 'middle'; x.fillText('Wordmark', 8, 52);
    return c.toDataURL('image/png').split(',')[1];
  });
  await pg.setInputFiles('#fLogo', { name: 'wordmark.png', mimeType: 'image/png', buffer: Buffer.from(dark, 'base64') });
  await pg.waitForTimeout(400); await pick('#mDark');
  const reads = async () => {
    const out = [];
    for (const l of LAYOUTS) {
      await pick(`#layoutGrid [data-l="${l}"]`);
      out.push(...await pg.evaluate(l => {
        const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
        const L = h => { const [r, g, b] = hex(h).map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
        const cr = (a, b) => { const p = L(a), q = L(b); return (Math.max(p, q) + 0.05) / (Math.min(p, q) + 0.05); };
        return [...document.querySelectorAll('#stageSvg image[data-logo]')].map(im => {
          const ink = im.getAttribute('data-ink') || '#1d1d1f', bg = im.getAttribute('data-bg');
          return { l, ink: !!im.getAttribute('data-ink'), filter: !!im.getAttribute('filter') && !!document.querySelector('#stageSvg ' + im.getAttribute('filter').slice(4, -1) + ' feFlood'), r: cr(ink, bg) };
        });
      }, l));
    }
    return out;
  };
  const dk = await reads();
  ok(dk.length >= 7 && dk.every(d => d.r >= 3 && (!d.ink || d.filter)), `in Dark, the wordmark reads at 3:1 or better on every card — set in one color where its own ink would vanish (${dk.filter(d => d.ink).length} recolored; worst ${Math.min(...dk.map(d => d.r)).toFixed(2)}:1)`);
  ok(await pg.$eval('#logoInk', e => !e.hidden && e.querySelector('[data-ink="auto"]').getAttribute('aria-pressed') === 'true'), 'the Logo color control shows with a logo, on Auto');
  await pick('#logoInk [data-ink="original"]');
  ok(await pg.evaluate(() => !document.querySelector('#stageSvg image[filter]')), 'Original keeps the logo in its own colors everywhere');
  await pick('#logoInk [data-ink="auto"]'); await pick('#mLight');
  await pg.setInputFiles('#fLogo', { name: 'wide.png', mimeType: 'image/png', buffer: Buffer.from(assets.logo, 'base64') });
  await pg.waitForTimeout(300);

  console.log('== the layout picker shows the layouts ==');
  const thumbsAre = (fn, arg) => pg.waitForFunction(fn, arg, { timeout: 4000 }).then(() => true, () => false);
  await thumbsAre(() => [...document.querySelectorAll('#layoutGrid .lthumb > svg')].length === 8 && [...document.querySelectorAll('#layoutGrid .lthumb > svg')].every(s => s.getAttribute('viewBox') === '0 0 1200 630'));
  const th = await pg.evaluate(() => [...document.querySelectorAll('#layoutGrid .lcell')].map(c => {
    const s = c.querySelector('.lthumb > svg'); return { l: c.dataset.l, ok: !!s && !!s.querySelector('rect') && s.getAttribute('viewBox') === '0 0 1200 630', name: c.querySelector('b').textContent };
  }));
  ok(th.length === 8 && th.every(t => t.ok && t.name), `all eight layouts show a live thumbnail in the current target, with their name (${th.filter(t => t.ok).length}/8)`);
  const thumbs = await pg.evaluate(() => [...document.querySelectorAll('#layoutGrid .lthumb')].map(e => e.innerHTML));
  ok(thumbs.every(h => h.includes('#1f4ed8') && !h.includes('@font-face') && !h.includes('data:image')), 'thumbnails use the brand, and stay light: no embedded fonts, no data URIs');
  await pick('#mDark');
  ok(await thumbsAre(() => [...document.querySelectorAll('#layoutGrid .lthumb')].every(e => /#8fb0ff|#0f1420/.test(e.innerHTML))), 'thumbnails follow the Light/Dark switch (each wears the Dark primary or the Dark ground)');
  await pick('[data-t="story"]');
  ok(await thumbsAre(() => [...document.querySelectorAll('#layoutGrid .lthumb > svg')].every(s => s.getAttribute('viewBox') === '0 0 1080 1920')), 'thumbnails follow the target');
  // they repaint once typing stops, not per key, and a redraw that changes nothing they show (format, scale) costs nothing
  await pg.waitForTimeout(600);
  await pg.evaluate(() => { window.__tp = 0; new MutationObserver(() => window.__tp++).observe(document.querySelector('#layoutGrid [data-l="title"] .lthumb'), { childList: true }); });
  await pick('#layoutGrid [data-l="kicker"]'); await pg.waitForTimeout(600);
  await pg.click('#cTitle'); await pg.keyboard.press('End');
  for (const ch of ' and now') { await pg.keyboard.type(ch); await pg.waitForTimeout(90); }
  await pg.waitForTimeout(900);
  const typed = await pg.evaluate(() => window.__tp);
  const sel = (id, v) => pg.evaluate(([id, v]) => { const e = document.getElementById(id); e.value = v; e.dispatchEvent(new Event('change', { bubbles: true })); }, [id, v]);
  await sel('eFmt', 'webp'); await sel('eScale', '1'); await pg.waitForTimeout(900);
  const fmt = await pg.evaluate(() => window.__tp) - typed;
  await sel('eFmt', 'png'); await sel('eScale', '2');
  ok(typed === 1 && fmt === 0, `thumbnails repaint once after 8 keystrokes (${typed}) and not for a format or scale change (${fmt})`);
  await setCopy(COPY.short);
  ok(await pg.evaluate(() => document.querySelector('#layoutGrid [data-l="kicker"]').getAttribute('aria-pressed') === 'true'), 'the picked layout stays marked');

  console.log('== the Safe zone overlay and the cards agree ==');
  // The stage draws each target's zone from safeInsets(); compose() hands the same insets to G(). The card's own
  // safe rect (data-safe, which the matrix above holds every line of type to) must sit inside the drawn zone.
  await pick('#mLight');
  const agree = [];
  for (const tg of ['og', 'portrait', 'story', 'pinterest']) {
    await setTarget(tg);
    for (const l of LAYOUTS) {
      await pick(`#layoutGrid [data-l="${l}"]`);
      const a = await pg.evaluate(() => {
        const svg = document.querySelector('#stageSvg svg'), [, , W] = svg.getAttribute('viewBox').split(' ').map(Number);
        const [x0, y0, x1, y1] = svg.getAttribute('data-safe').split(' ').map(Number);
        const f = document.querySelector('#frame').getBoundingClientRect(), i = document.querySelector('#safe i').getBoundingClientRect(), k = W / f.width;
        const z = { l: (i.left - f.left) * k, t: (i.top - f.top) * k, r: (i.right - f.left) * k, b: (i.bottom - f.top) * k };
        return { on: document.querySelector('#safe').classList.contains('on'), x0, y0, x1, y1, z, tol: 1.5 * k };
      });
      if (!a.on || a.x0 < a.z.l - a.tol || a.y0 < a.z.t - a.tol || a.x1 > a.z.r + a.tol || a.y1 > a.z.b + a.tol)
        agree.push(`${l} ${tg}: card ${[a.x0, a.y0, a.x1, a.y1].map(Math.round)} vs zone ${[a.z.l, a.z.t, a.z.r, a.z.b].map(Math.round)}${a.on ? '' : ' (zone not drawn)'}`);
      if (tg === 'story' && (Math.abs(a.y0 - 250) > 0.5 || Math.abs(a.y1 - 1580) > 0.5)) agree.push(`${l} story: type runs ${Math.round(a.y0)}–${Math.round(a.y1)}, not 250–1580`);
    }
  }
  ok(agree.length === 0, `every card keeps its type inside the Safe zone the stage draws (OG, Portrait, Story, Pinterest × 8 layouts; Story clears the top 250px and bottom 340px)${agree.length ? '\n    ' + agree.slice(0, 8).join('\n    ') : ''}`);

  console.log('== user text is text ==');
  await pick('#layoutGrid [data-l="title"]');
  await setCopy({ cTitle: '<img src=x onerror="window.__zx=1"> & "quotes" </text><script>window.__zx=1</script>', cByline: '</tspan><g onload="window.__zx=1">' });
  await pg.waitForTimeout(400);
  const xs = await pg.evaluate(() => ({ el: document.querySelectorAll('#stageSvg img, #stageSvg script, #stageSvg g[onload], #layoutGrid img, #layoutGrid script').length, txt: document.querySelector('#stageSvg svg').textContent, zx: window.__zx }));
  ok(xs.el === 0 && !xs.zx && xs.txt.includes('<img') && xs.txt.includes('</tspan>'), 'titles and bylines are drawn as text, never as markup (stage and thumbnails)');

  console.log('== a head face with one weight still loads ==');
  // DM Serif Display ships one face, 400. The head role asks for 500, 600 and 800; with none of those the app must take
  // the faces the family has, and set the headline at the weight it got. Every face is read from vendor/ on this origin.
  const fpg = await ctx.newPage(), asked = [];
  fpg.on('pageerror', e => errs.push(e.message));
  fpg.on('request', r => asked.push(r.url()));
  await fpg.route(/^https?:\/\/(?!(localhost|127\.0\.0\.1)[:/])/, r => r.abort());
  await fpg.goto(process.env.ZI_URL || 'http://localhost:8772/', { waitUntil: 'domcontentloaded' }); await fpg.waitForTimeout(400);
  const serif = { zest: 1, name: 'Serif Press', fonts: { head: 'DM Serif Display' }, light: { primary: '#ffc928', ink: '#1d1d1f', muted: '#5c5c66', paper: '#fbf8f1', sheet: '#ffffff', line: '#e8e2d4', dark: '#1d1d1f' } };
  await fpg.setInputFiles('#fBrand', { name: 'serif.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(serif)) });
  await fpg.waitForFunction(() => { const t = document.querySelector('#stageSvg text[data-role="title"]'); return t && t.getAttribute('font-family').startsWith("'DM Serif Display'"); }, null, { timeout: 5000 }).catch(() => {});
  const ff = await fpg.evaluate(() => { const t = document.querySelector('#stageSvg text[data-role="title"]'); return { fam: t.getAttribute('font-family'), w: t.getAttribute('font-weight'), note: document.querySelector('#fontNote').hidden }; });
  const serifFiles = asked.filter(u => /\/vendor\/fonts\/dm-serif-display\//.test(u));
  ok(asked.some(u => /\/vendor\/fonts\/fonts\.json$/.test(u)) && serifFiles.length >= 1 && serifFiles.every(u => /-400-normal\.woff2$/.test(u)), `the family's one face is read from vendor/fonts (${serifFiles.map(u => u.split('/').pop()).join(', ') || 'none'})`);
  ok(asked.every(u => !/^https?:/.test(u) || /^https?:\/\/(localhost|127\.0\.0\.1)[:/]/.test(u)), 'and nothing is asked of a font host');
  ok(ff.fam.startsWith("'DM Serif Display'") && ff.w === '400' && ff.note, `the headline is set in the brand's own face at the weight that loaded (${ff.fam.split(',')[0]} ${ff.w}), with no offline note`);
  await fpg.close();

  ok(errs.length === 0, `no exceptions${errs.length ? ' — ' + errs.slice(0, 3).join(' | ') : ''}`);
  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
