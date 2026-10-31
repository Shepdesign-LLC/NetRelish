// Mobile suite: every surface at 390x844 (touch, DPR 3). Guards the phone layouts —
// no layout-viewport blowout, panels reachable, each app's core flow works by tap.
// Serve: studio :8771, image :8772, mail :8773, md :8774, dist (store at /pricing/) :8780.
const { chromium } = require('playwright');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {}; // point at a system Chromium when the local playwright has no downloaded browsers
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.error('  FAIL ' + m); } };
(async () => {
  const browser = await chromium.launch(LAUNCH);
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 3, serviceWorkers: 'block' });
  const page = async url => {
    const pg = await ctx.newPage();
    await pg.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
    await pg.goto(url, { waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(600);
    return pg;
  };
  const fits = pg => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth && window.innerWidth <= 390);
  const inVp = (pg, sel) => pg.evaluate(s => { const e = document.querySelector(s); if (!e) return false; const b = e.getBoundingClientRect(); return b.left >= 0 && b.right <= window.innerWidth && b.width > 0; }, sel);

  console.log('== studio at 390 ==');
  const st = await page('http://localhost:8771/');
  ok(await fits(st), 'studio: no layout-viewport blowout');
  ok(await st.evaluate(() => getComputedStyle(document.querySelector('.jump')).display === 'flex'), 'studio: jump nav present');
  ok(await st.evaluate(() => document.querySelector('#pv').getBoundingClientRect().height <= innerHeight * 0.52 + 2), 'studio: preview capped, no first-screen takeover');
  ok(await st.evaluate(() => { const d = document.querySelector('#pv').contentDocument; return d && d.documentElement.scrollWidth <= document.querySelector('#pv').clientWidth + 1; }), 'studio: generated preview doc fits its frame');
  await st.tap('.jump a[href="#exportsec"]'); await st.waitForTimeout(400);
  ok(await st.evaluate(() => { const s = document.querySelector('#exportsec').getBoundingClientRect(); return s.top > -60 && s.top < innerHeight; }), 'studio: jump nav reaches Export');
  await st.close();

  console.log('== mail at 390 ==');
  const ml = await page('http://localhost:8773/');
  await ml.evaluate(() => localStorage.clear()); await ml.reload({ waitUntil: 'domcontentloaded' }); await ml.waitForTimeout(600);
  ok(await fits(ml), 'mail: no layout-viewport blowout (was 983px)');
  ok(await inVp(ml, '#btnExport'), 'mail: Export is on screen and tappable');
  await ml.tap('#btnLib'); await ml.waitForTimeout(250);
  ok(await ml.evaluate(() => document.querySelector('.pane.left').dataset.open === 'true'), 'mail: library drawer opens');
  await ml.tap('#tpl button'); await ml.waitForTimeout(450);
  ok(await ml.evaluate(() => document.querySelectorAll('.cv-block').length > 0), 'mail: template populates the canvas by tap');
  ok(await ml.evaluate(() => document.querySelector('.pane.left').dataset.open === 'false'), 'mail: drawer closes after adding');
  ok(await ml.evaluate(() => { const z = +document.querySelector('#canvasWrap').style.zoom; return z > 0 && z < 1; }), 'mail: canvas scales to fit the stage');
  await ml.tap('.cv-block'); await ml.waitForTimeout(350);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'true'), 'mail: tapping a block opens the inspector sheet');
  await ml.tap('#tabs button[data-t="message"]'); await ml.fill('#subject', 'mobile');
  ok((await ml.inputValue('#subject')) === 'mobile', 'mail: subject is typeable in the sheet');
  await ml.tap('#sheetClose'); await ml.waitForTimeout(250);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'false'), 'mail: the sheet closes');
  await ml.close();

  console.log('== md at 390 ==');
  const md = await page('http://localhost:8774/');
  ok(await fits(md), 'md: empty state fits (was 501px)');
  await md.tap('[data-act="sample"]'); await md.waitForTimeout(700);
  ok(await fits(md), 'md: document view fits (was 646px)');
  ok(await inVp(md, '#btnExport'), 'md: Export is reachable');
  await md.tap('#btnToc'); await md.waitForTimeout(350);
  ok(await md.evaluate(() => { const t = document.querySelector('.toc').getBoundingClientRect(); return t.left === 0 && t.width > 100; }), 'md: Contents opens as a drawer (was a silent no-op)');
  await md.tap('#toc a'); await md.waitForTimeout(400);
  ok(await md.evaluate(() => document.querySelector('#work').dataset.toc === 'false'), 'md: the drawer closes on selection');
  await md.tap('#btnExport'); await md.waitForTimeout(250);
  ok(await md.evaluate(() => { const p = document.querySelector('#popExport').getBoundingClientRect(); return p.left >= 0 && p.right <= window.innerWidth && p.width > 200; }), 'md: export menu fits the viewport');
  await md.close();

  console.log('== image at 390 ==');
  const im = await page('http://localhost:8772/');
  ok(await fits(im), 'image: no horizontal overflow');
  await im.tap('#cTitle'); await im.type('#cTitle', 'Mobile');
  await im.waitForTimeout(350);
  ok(await im.evaluate(() => { const f = document.querySelector('#frame').getBoundingClientRect(); return f.bottom > 0 && f.top < innerHeight; }), 'image: docked preview stays visible while typing');
  ok(await im.evaluate(() => document.querySelector('#stageSvg svg').textContent.includes('Mobile')), 'image: typing updates the visible stage');
  ok(await im.evaluate(() => getComputedStyle(document.querySelector('#cTitle')).fontSize === '16px'), 'image: inputs at 16px (no iOS focus-zoom)');
  await im.close();

  console.log('== store (dist /pricing/) at 390 ==');
  const sr = await page('http://localhost:8780/pricing/');
  ok(await fits(sr), 'store: no horizontal overflow');
  await sr.tap('.menu summary'); await sr.waitForTimeout(250);
  ok(await sr.evaluate(() => document.querySelector('.menu').open && !!document.querySelector('.mnav a[href="/"]')), 'store: menu opens and links to the Studio');
  ok(await sr.evaluate(() => document.querySelector('.vs .vs-a').getBoundingClientRect().width > 250), 'store: comparison cells span the card (were 68px slivers)');
  ok(await sr.evaluate(() => { const s = getComputedStyle(document.querySelector('.vs .vs-b'), '::before').content; return s.includes('Zest'); }), 'store: stacked comparison cells are re-labeled');
  ok(await sr.evaluate(() => [...document.querySelectorAll('footer a')].some(a => a.getAttribute('href') === '/')), 'store: footer carries the Studio link');
  await sr.close();

  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
