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
  ok(await st.evaluate(() => { const s = document.querySelector('#exportsec').getBoundingClientRect(); const j = document.querySelector('.jump').getBoundingClientRect(); return s.top >= j.bottom - 2 && s.top < innerHeight; }), 'studio: jump targets land below the sticky bar, not under it');
  ok(await st.evaluate(() => getComputedStyle(document.querySelector('#pv')).pointerEvents === 'none'), 'studio: the preview no longer swallows touch pans');
  ok(await st.evaluate(() => [...document.querySelectorAll('details.fold > summary')].every(s => s.getBoundingClientRect().height >= 36)), 'studio: every fold has a 36px tap target');
  await st.tap('#sendFold > summary'); await st.waitForTimeout(300);
  ok(await st.$eval('#sendFold', d => d.open) && await inVp(st, '[data-send="md"]') && await fits(st), 'studio: a fold opens by tap, its buttons on screen, still no blowout');
  await st.close();

  console.log('== mail at 390 ==');
  const ml = await page('http://localhost:8773/');
  await ml.evaluate(() => localStorage.clear()); await ml.reload({ waitUntil: 'domcontentloaded' }); await ml.waitForTimeout(600);
  ok(await fits(ml), 'mail: no layout-viewport blowout (was 983px)');
  ok(await inVp(ml, '#btnExport'), 'mail: Export is on screen and tappable');
  // the toolbar is two rows on a phone: the most-used controls stay out, the rest sit in one More menu, and nothing is lost
  const barH = () => ml.evaluate(() => Math.round(document.querySelector('.bar').getBoundingClientRect().height));
  ok(await barH() <= 104, `mail: the toolbar is at most two rows at 390 (${await barH()}px, was 207)`);
  ok((await Promise.all(['#btnLib', '#modeSeg', '#viewSeg', '#btnUndo', '#btnPanel', '#btnExport', '#btnMore'].map(s => inVp(ml, s)))).every(Boolean), 'mail: library, mode, views, Undo, panel, Export and More stay on the toolbar');
  await ml.tap('#btnMore'); await ml.waitForTimeout(250);
  ok(await ml.evaluate(() => document.querySelector('#btnMore').getAttribute('aria-expanded') === 'true' && ['#btnSave', '#btnNew', '#btnSound', '#sizePill', '#lintPill'].every(s => { const b = document.querySelector(s), r = b.getBoundingClientRect(), at = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return b.closest('#popMore') && r.width > 0 && at && (at === b || b.contains(at)); })), 'mail: More holds Save, New, Sound and the two status pills, each hit-testable');
  ok(await ml.evaluate(() => document.querySelectorAll('#btnSave, #btnNew, #btnSound, #btnUndo, #btnExport, #btnPanel, #btnLib, #modeSeg button, #viewSeg button').length === 13), 'mail: every toolbar action is still there, once');
  const pressed = () => ml.$eval('#btnSound', b => b.getAttribute('aria-pressed'));
  const snd0 = await pressed(); await ml.tap('#btnSound'); const snd1 = await pressed(); await ml.tap('#btnSound');
  ok(snd0 === 'true' && snd1 === 'false' && await pressed() === 'true' && await ml.evaluate(() => document.querySelector('#popMore').dataset.open === 'true'), 'mail: Sound still toggles from inside More, and the menu stays open for it');
  await ml.tap('#btnMore'); await ml.waitForTimeout(200);
  ok(await ml.evaluate(() => document.querySelector('#popMore').dataset.open === 'false' && document.querySelector('#btnMore').getAttribute('aria-expanded') === 'false'), 'mail: More closes again');
  for (const w of [360, 480]) {
    await ml.setViewportSize({ width: w, height: 844 }); await ml.waitForTimeout(350);
    ok(await barH() <= 104 && await ml.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), `mail: two rows and no overflow at ${w} too (${await barH()}px)`);
  }
  await ml.setViewportSize({ width: 600, height: 844 }); await ml.waitForTimeout(350);
  ok(await ml.evaluate(() => !document.querySelector('#popMore').contains(document.querySelector('#btnSave')) && ['#btnSave', '#btnNew', '#btnSound', '#sizePill', '#lintPill'].every(s => document.querySelector(s).getBoundingClientRect().width > 0) && getComputedStyle(document.querySelector('#btnMore')).display === 'none'), 'mail: above 480 the same controls are back on the toolbar and More is gone');
  await ml.setViewportSize({ width: 390, height: 844 }); await ml.waitForTimeout(350);
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
  ok(await ml.evaluate(() => { const b = document.querySelector('.cv-block[aria-selected="true"] .tools button').getBoundingClientRect(); return b.width >= 30 && b.height >= 30; }), 'mail: block tools stay tappable under the canvas zoom');
  await ml.tap('#sheetClose'); await ml.waitForTimeout(250);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'false'), 'mail: the sheet closes');
  // with the sheet open, Export must close it and every menu item must be hit-testable
  await ml.tap('.cv-block'); await ml.waitForTimeout(300);
  await ml.tap('#btnExport'); await ml.waitForTimeout(250);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'false'), 'mail: opening Export dismisses the sheet');
  ok(await ml.evaluate(() => [...document.querySelectorAll('#popExport [data-do]')].every(b => { const r = b.getBoundingClientRect(); const at = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return at && (at === b || b.contains(at)); })), 'mail: every export action is hit-testable');
  await ml.tap('#centerTitle').catch(() => {}); await ml.waitForTimeout(200);
  // Source mode opens the drawer that holds the textarea
  await ml.tap('#modeSeg button[data-m="source"]'); await ml.waitForTimeout(350);
  ok(await ml.evaluate(() => { const s = document.querySelector('#src').getBoundingClientRect(); return s.left >= 0 && s.width > 100 && document.querySelector('.pane.left').dataset.open === 'true'; }), 'mail: Source mode brings the textarea on screen');
  await ml.close();

  console.log('== md at 390 ==');
  const md = await page('http://localhost:8774/');
  ok(await fits(md), 'md: empty state fits (was 501px)');
  // the empty state carries Open and Paste, so the bar hides its own pair — except while the phone editor covers the empty state
  const barPairHidden = await md.evaluate(() => document.querySelector('#btnOpen').hidden && document.querySelector('#btnPaste').hidden);
  await md.tap('#btnEdit'); await md.waitForTimeout(300);
  ok(barPairHidden && await inVp(md, '#btnOpen') && await inVp(md, '#btnPaste') && await fits(md), 'md: Open and Paste stay reachable when the editor covers the empty state');
  await md.tap('#btnEdit'); await md.waitForTimeout(300);
  await md.tap('[data-act="sample"]'); await md.waitForTimeout(700);
  ok(await fits(md), 'md: document view fits (was 646px)');
  ok(await inVp(md, '#btnExport') && await inVp(md, '#btnExportMenu'), 'md: Export is reachable, and so is its menu');
  await md.tap('#btnToc'); await md.waitForTimeout(350);
  ok(await md.evaluate(() => { const t = document.querySelector('.toc').getBoundingClientRect(); return t.left === 0 && t.width > 100; }), 'md: Contents opens as a drawer (was a silent no-op)');
  await md.tap('#toc a'); await md.waitForTimeout(400);
  ok(await md.evaluate(() => document.querySelector('#work').dataset.toc === 'false'), 'md: the drawer closes on selection');
  await md.tap('#btnExportMenu'); await md.waitForTimeout(250);
  ok(await md.evaluate(() => { const p = document.querySelector('#popExport').getBoundingClientRect(); return p.left >= 0 && p.right <= window.innerWidth && p.width > 200; }), 'md: export menu fits the viewport');
  ok(await md.evaluate(() => { const p = document.querySelector('#popExport').getBoundingClientRect(); const b = document.querySelector('.bar').getBoundingClientRect(); return p.top >= b.bottom; }), 'md: the menu anchors below the grown bar (bar-h stays live)');
  await md.tap('body', { position: { x: 10, y: 700 } }).catch(() => {});
  // Contents + Edit together must not blow the layout viewport (the combined-state grid override)
  await md.tap('#btnEdit'); await md.waitForTimeout(300);
  await md.tap('#btnToc'); await md.waitForTimeout(300);
  ok(await fits(md), 'md: Edit + Contents together still fit (combined grid override)');
  await md.close();

  console.log('== image at 390 ==');
  const im = await page('http://localhost:8772/');
  ok(await fits(im), 'image: no horizontal overflow');
  await im.tap('#cTitle'); await im.type('#cTitle', 'Mobile');
  await im.waitForTimeout(350);
  ok(await im.evaluate(() => { const f = document.querySelector('#frame').getBoundingClientRect(); return f.bottom > 0 && f.top < innerHeight; }), 'image: docked preview stays visible while typing');
  ok(await im.evaluate(() => document.querySelector('#stageSvg svg').textContent.includes('Mobile')), 'image: typing updates the visible stage');
  ok(await im.evaluate(() => getComputedStyle(document.querySelector('#cTitle')).fontSize === '16px'), 'image: inputs at 16px (no iOS focus-zoom)');
  await im.evaluate(() => document.querySelector('.sec.exportsec').scrollIntoView({ block: 'center' })); await im.waitForTimeout(300);
  await im.tap('#exMenu summary'); await im.waitForTimeout(250);
  ok(await im.evaluate(() => document.querySelector('#exMenu').open && ['#bAlt', '#bManifest', '#bOg'].every(s => { const r = document.querySelector(s).getBoundingClientRect(); return r.height >= 44 && r.left >= 0 && r.right <= innerWidth; })) && await fits(im), 'image: More opens by tap; its three items are full-size targets inside the screen');
  ok(await im.evaluate(() => [...document.querySelectorAll('summary')].every(s => s.getBoundingClientRect().height >= 44)), 'image: every disclosure is a 44px tap target');
  // scrolled deep into the form, the docked stage is still a solid surface: nothing under it shows through the bar or beside the frame
  ok(await im.evaluate(() => {
    const sw = document.querySelector('.stagewrap'), b = document.querySelector('.stagebar').getBoundingClientRect(), f = document.querySelector('#frame').getBoundingClientRect();
    const pts = [[b.left + 4, b.top + b.height / 2], [b.right - 4, b.top + b.height / 2], [4, f.top + f.height / 2], [innerWidth - 4, f.top + f.height / 2]];
    return scrollY > 300 && getComputedStyle(sw).backgroundColor !== 'rgba(0, 0, 0, 0)' && parseFloat(getComputedStyle(sw).borderBottomWidth) >= 1 && pts.every(([x, y]) => sw.contains(document.elementFromPoint(x, y)));
  }), 'image: the docked stage is opaque with an edge — the form scrolls under it, not through it');
  await im.tap('#exMenu summary'); await im.waitForTimeout(200);
  ok(await im.evaluate(() => { const fn = document.querySelector('#fname'); return fn.textContent.endsWith('-og@2x.png') && fn.textContent.startsWith('shepdesign-') && fn.scrollHeight <= fn.clientHeight + 1 && fn.getBoundingClientRect().width >= 150; })
    && !(await im.textContent('#dims')).includes('→'), 'image: the whole filename is readable in the stage bar, and the size there is short');
  // a tall target docks small, so tapping the preview opens it full size
  await im.evaluate(() => { document.querySelector('#targetGrid [data-t="story"]').click(); scrollTo(0, 0); }); await im.waitForTimeout(300);
  const docked = await im.$eval('#frame', f => f.getBoundingClientRect().width);
  await im.tap('#frame'); await im.waitForTimeout(300);
  ok(await im.evaluate(d => { const v = document.querySelector('#pview'), s = document.querySelector('#pvSvg svg').getBoundingClientRect(), c = document.querySelector('#pvClose').getBoundingClientRect();
    return v.open && s.width >= d * 2 && s.left >= 0 && s.right <= innerWidth && s.top >= 0 && s.bottom <= innerHeight && c.width >= 44 && c.height >= 44; }, docked),
    `image: tapping the docked preview opens it full screen, inside the screen (${Math.round(docked)}px docked)`);
  await im.tap('#pvClose'); await im.waitForTimeout(200);
  const closedByButton = await im.$eval('#pview', v => !v.open);
  await im.tap('#frame'); await im.waitForTimeout(250); await im.keyboard.press('Escape'); await im.waitForTimeout(200);
  ok(closedByButton && await im.$eval('#pview', v => !v.open), 'image: the full-size preview closes with its button and with Esc');
  ok(await im.evaluate(() => !document.querySelector('#safeLab').hidden && document.querySelector('#safe').classList.contains('on')), 'image: Story has a safe zone, and its toggle shows');
  await im.evaluate(() => document.querySelector('#targetGrid [data-t="blog"]').click()); await im.waitForTimeout(200);
  ok(await im.evaluate(() => document.querySelector('#safeLab').hidden && !document.querySelector('#safe').classList.contains('on')), 'image: Blog has none, so the toggle hides instead of showing checked and doing nothing');
  await im.evaluate(() => document.querySelector('.pro').scrollIntoView({ block: 'center' })); await im.waitForTimeout(250);
  await im.tap('.pro'); await im.waitForTimeout(400);
  ok(await im.evaluate(() => { const t = document.querySelector('#toast'), r = t.getBoundingClientRect(), f = document.querySelector('#frame').getBoundingClientRect();
    return t.classList.contains('show') && (r.bottom <= f.top || r.top >= f.bottom); }), 'image: a toast never covers the docked preview');
  await im.close();

  console.log('== store (dist /pricing/) at 390 ==');
  const sr = await page('http://localhost:8780/pricing/');
  ok(await fits(sr), 'store: no horizontal overflow');
  await sr.tap('.menu summary'); await sr.waitForTimeout(250);
  ok(await sr.evaluate(() => document.querySelector('.menu').open && !!document.querySelector('.mnav a[href="/"]')), 'store: menu opens and links to the Studio');
  ok(await sr.evaluate(() => document.querySelector('.vs .vs-a').getBoundingClientRect().width > 250), 'store: comparison cells span the card (were 68px slivers)');
  ok(await sr.evaluate(() => { const s = getComputedStyle(document.querySelector('.vs .vs-b'), '::before').content; return s.includes('Zest'); }), 'store: stacked comparison cells are re-labeled');
  ok(await sr.evaluate(() => [...document.querySelectorAll('footer a')].some(a => a.getAttribute('href') === '/')), 'store: footer carries the Studio link');
  await sr.evaluate(() => { document.querySelector('.menu').open = true; });
  await sr.tap('.mnav a[href="#pricing"]'); await sr.waitForTimeout(350);
  ok(await sr.evaluate(() => document.querySelector('.menu').open === false), 'store: the menu closes once a destination is picked');
  await sr.close();

  console.log('== image at 844x390 (landscape phone) ==');
  const land = await browser.newContext({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true, deviceScaleFactor: 3, serviceWorkers: 'block' });
  const lp = await land.newPage();
  await lp.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
  await lp.goto('http://localhost:8772/', { waitUntil: 'domcontentloaded' }); await lp.waitForTimeout(600);
  await lp.evaluate(() => document.querySelector('.sec.exportsec').scrollIntoView({ block: 'center' })); await lp.waitForTimeout(300);
  ok(await lp.evaluate(() => {
    const sw = document.querySelector('.stagewrap').getBoundingClientRect();
    const ex = document.querySelector('.sec.exportsec').getBoundingClientRect();
    return !(sw.bottom > ex.top && ex.bottom > sw.top); // the two never overlap: no sticky sandwich hiding controls
  }), 'image: landscape phones get no sticky sandwich');
  await lp.evaluate(() => { document.querySelector('#targetGrid [data-t="story"]').click(); scrollTo(0, 0); }); await lp.waitForTimeout(300);
  ok(await lp.evaluate(() => document.querySelector('#frame').getBoundingClientRect().height >= innerHeight * 0.6), `image: in landscape a tall target gets most of the height, not a postage stamp (${await lp.$eval('#frame', f => Math.round(f.getBoundingClientRect().height))}px, was 101)`);
  await land.close();

  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
