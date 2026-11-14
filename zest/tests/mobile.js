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
  // the library drawer hangs below the toolbar: its head and close button are on screen, and the toolbar stays live
  ok(await ml.evaluate(() => { const c = document.querySelector('#libClose'), r = c.getBoundingClientRect(), at = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return r.top >= document.querySelector('.bar').getBoundingClientRect().bottom - 1 && at && (at === c || c.contains(at)); }), 'mail: the drawer opens below the toolbar, its close button hit-testable (was under the bar)');
  await ml.tap('#tpl button'); await ml.waitForTimeout(450);
  ok(await ml.evaluate(() => document.querySelectorAll('.cv-block').length > 0), 'mail: template populates the canvas by tap');
  ok(await ml.evaluate(() => document.querySelector('.pane.left').dataset.open === 'false'), 'mail: drawer closes after adding');
  // a phone edits the email at 1:1, at screen width, with the email's own phone rules — not a 55% desktop layout
  const bodyPx = await ml.evaluate(() => { const e = document.querySelector('[data-edit][data-rich="1"]'), w = document.querySelector('#canvasWrap'); return parseFloat(getComputedStyle(e).fontSize) * (+w.style.zoom || 1); });
  ok(bodyPx >= 15 && await ml.evaluate(() => document.querySelector('#canvasWrap').getBoundingClientRect().right <= innerWidth), `mail: canvas text reads at phone size (${bodyPx}px, was 8.8px) and the canvas fits the screen`);
  ok(await ml.evaluate(() => { const s = document.querySelector('.cv-block .stack'); return !s || getComputedStyle(s).display === 'block'; }), 'mail: columns stack on the phone canvas, as they do on a phone');
  ok(await ml.evaluate(() => getComputedStyle(document.querySelector('.phone-note')).display !== 'none'), 'mail: the Message tab says Width is for desktop clients on a phone');
  // merge tags are chips: a stray tap cannot land inside one
  ok(await ml.evaluate(() => { const c = document.querySelector('#canvas .mtag'); return !!c && c.contentEditable === 'false' && c.dataset.tag === '{{ visitor.first_name | default: "there" }}'; }), 'mail: the merge tag on the canvas is a chip that cannot be typed into');
  // a tap on the chip puts the caret after it, never a selection of it: the next key types beside the tag instead of replacing it
  const chipAt = await ml.$eval('#canvas .mtag', e => { const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
  await ml.touchscreen.tap(chipAt.x, chipAt.y); await ml.waitForTimeout(300);
  ok(await ml.evaluate(() => { const s = getSelection(); return s.isCollapsed && s.toString() === ''; }), 'mail: a tap on a merge-tag chip places the caret beside it (was: selected the whole chip)');
  await ml.keyboard.type('X'); await ml.waitForTimeout(600);
  ok((await ml.evaluate(() => JSON.parse(localStorage.getItem('mailpress:draft')).blocks[2].props.body)).includes('{{ visitor.first_name | default: "there" }}X'), 'mail: typing after a chip tap keeps the merge tag exactly (was: the key replaced it)');
  await ml.evaluate(() => document.activeElement.blur()); await ml.waitForTimeout(150);
  // a tap on text places the caret and nothing else: no sheet over what is being typed
  const bodySel = '.cv-block:nth-child(3) [data-edit="body"]';
  await ml.tap(bodySel); await ml.waitForTimeout(350);
  ok(await ml.evaluate(s => document.querySelector('#inspector').dataset.open !== 'true' && document.activeElement === document.querySelector(s), bodySel), 'mail: tapping text keeps the sheet closed and the text focused');
  ok(await ml.evaluate(() => { const f = document.querySelector('#fmtBar'); return f.dataset.open === 'true' && [...f.querySelectorAll('button')].every(b => b.getBoundingClientRect().height >= 40); }), 'mail: B · I · Link appear for the focused text on touch');
  await ml.keyboard.type(' typed');
  await ml.evaluate(s => { const t = [...document.querySelector(s).querySelectorAll('p')].map(p => [...p.childNodes].find(n => n.nodeType === 3 && n.nodeValue.includes('first version'))).find(Boolean); const i = t.nodeValue.indexOf('first'); const r = document.createRange(); r.setStart(t, i); r.setEnd(t, i + 5); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); }, bodySel);
  await ml.tap('#fmtBar [data-fmt="bold"]'); await ml.waitForTimeout(500);
  const body = await ml.evaluate(() => JSON.parse(localStorage.getItem('mailpress:draft')).blocks[2].props.body);
  ok(body.includes('{{ visitor.first_name | default: "there" }}') && body.includes('typed'), 'mail: typing on the canvas keeps the merge tag exactly as it was');
  ok(body.includes('**first**'), 'mail: B on the touch bar makes the selected word bold');
  // a resize (keyboard, rotation) while editing never rebuilds the canvas: the field keeps focus
  await ml.setViewportSize({ width: 390, height: 600 }); await ml.waitForTimeout(450);
  ok(await ml.evaluate(s => document.activeElement === document.querySelector(s) && document.activeElement.isConnected, bodySel), 'mail: a resize while editing keeps the field and its focus (was dropped)');
  await ml.setViewportSize({ width: 390, height: 844 }); await ml.waitForTimeout(450);
  // a tap on a block itself (not its text) opens the sheet, with the block scrolled above it
  await ml.tap('.cv-block:nth-child(4)', { position: { x: 4, y: 4 } }); await ml.waitForTimeout(700);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'true'), 'mail: tapping a block opens the inspector sheet');
  ok(await ml.evaluate(() => { const b = document.querySelector('.cv-block[aria-selected="true"]').getBoundingClientRect(), st = document.querySelector('#stage').getBoundingClientRect(), sh = document.querySelector('#inspector').getBoundingClientRect(); return b.top >= st.top - 1 && b.top + 40 <= sh.top; }), 'mail: the selected block scrolls into view above the sheet');
  ok(await ml.evaluate(() => { const s = document.querySelector('#inspector').getBoundingClientRect(); return s.height <= innerHeight * 0.56 + 1 && s.top > document.querySelector('.bar').getBoundingClientRect().bottom + 120; }), 'mail: the sheet leaves canvas showing above it');
  await ml.tap('#tabs button[data-t="message"]'); await ml.fill('#subject', 'mobile');
  ok((await ml.inputValue('#subject')) === 'mobile', 'mail: subject is typeable in the sheet');
  ok(await ml.evaluate(() => [...document.querySelectorAll('#inspector input:not([type=checkbox]):not([type=range]):not([type=color]), #inspector select, #inspector textarea, #src, #nameInput')].every(e => parseFloat(getComputedStyle(e).fontSize) >= 16)), 'mail: every field is 16px, so iOS does not zoom the page on focus');
  ok(await ml.evaluate(() => [...document.querySelectorAll('#panelMessage input[type=text], #panelMessage select')].filter(e => e.getClientRects().length).every(e => e.getBoundingClientRect().height >= 44)), 'mail: sheet fields are 44px touch targets');
  // with the sheet open the block's actions are the sheet's own top row (the sheet already is its properties), so nothing floats over the block
  ok(await ml.evaluate(() => { const bar = document.querySelector('#blockBar'), bs = [...bar.querySelectorAll('button')].filter(b => b.getClientRects().length); return bar.closest('#inspector') && bs.length === 4 && bs.every(b => { const r = b.getBoundingClientRect(), at = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return r.width >= 44 && r.height >= 44 && at && (at === b || b.contains(at)); }); }), 'mail: with the sheet open, move, duplicate and delete are the sheet\'s top row, each 44px and hit-testable');
  ok(await ml.evaluate(() => { const b = document.querySelector('#blockBar').getBoundingClientRect(), s = document.querySelector('#inspector').getBoundingClientRect(); return b.top >= s.top - 1 && document.querySelector('#blockName').textContent.length > 2; }), 'mail: nothing floats over the block while the sheet is open (was a bar over the block\'s content)');
  // a toast while the sheet is open lands above it, never on its fields
  await ml.tap('#tabs button[data-t="block"]'); await ml.selectOption('#tagPick', { index: 1 }); await ml.waitForTimeout(300);
  ok(await ml.evaluate(() => { const t = document.querySelector('#toast'), r = t.getBoundingClientRect(), s = document.querySelector('#inspector').getBoundingClientRect(); return t.classList.contains('show') && r.bottom <= s.top + 1 && r.right <= innerWidth; }), 'mail: the toast sits above the open sheet');
  // the sheet closes from a tap beside the email, a swipe on its grabber, and its X
  const textAbove = await ml.evaluate(() => { const s = document.querySelector('#inspector').getBoundingClientRect().top, e = [...document.querySelectorAll('#canvas [data-edit]')].find(x => { const r = x.getBoundingClientRect(); return r.height > 8 && r.top > document.querySelector('#stage').getBoundingClientRect().top && r.bottom < s - 70; }); const r = e.getBoundingClientRect(); return { x: r.left + Math.min(20, r.width / 2), y: r.top + r.height / 2 }; });
  await ml.touchscreen.tap(textAbove.x, textAbove.y); await ml.waitForTimeout(300);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'false' && !!document.activeElement.closest('[data-edit]')), 'mail: a tap on text above the sheet closes it and places the caret there');
  ok(await ml.evaluate(() => getComputedStyle(document.querySelector('#blockBar')).display === 'none'), 'mail: the block bar steps aside while text is being typed into');
  await ml.evaluate(() => document.activeElement.blur()); await ml.waitForTimeout(100);
  await ml.tap('#blockBar [data-act="props"]'); await ml.waitForTimeout(400);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'true'), 'mail: Properties opens the sheet for the selected block');
  const g = await ml.evaluate(() => { const r = document.querySelector('#sheetGrab').getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
  await ml.mouse.move(g.x, g.y); await ml.mouse.down(); await ml.mouse.move(g.x, g.y + 40, { steps: 4 }); await ml.mouse.move(g.x, g.y + 120, { steps: 4 }); await ml.mouse.up(); await ml.waitForTimeout(350);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'false'), 'mail: a swipe down on the grabber closes the sheet');
  await ml.tap('#blockBar [data-act="props"]'); await ml.waitForTimeout(400);
  await ml.tap('#sheetClose'); await ml.waitForTimeout(250);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'false'), 'mail: the sheet closes from its X');
  ok(await ml.evaluate(() => { const bar = document.querySelector('#blockBar'), t = document.querySelector('#toast');
    t.textContent = 'Replaced the canvas with Newsletter'; t.classList.add('show'); const a = t.getBoundingClientRect(), b = bar.getBoundingClientRect(); t.classList.remove('show');
    return !bar.closest('#inspector') && b.height > 0 && (a.bottom <= b.top || b.bottom <= a.top); }), 'mail: with a block selected and the sheet closed, a toast sits above the block bar, not on its buttons');
  // with the sheet open, Export must close it and every menu item must be hit-testable
  await ml.tap('#blockBar [data-act="props"]'); await ml.waitForTimeout(300);
  await ml.tap('#btnExport'); await ml.waitForTimeout(250);
  ok(await ml.evaluate(() => document.querySelector('#inspector').dataset.open === 'false'), 'mail: opening Export dismisses the sheet');
  ok(await ml.evaluate(() => [...document.querySelectorAll('#popExport [data-do]')].every(b => { const r = b.getBoundingClientRect(); const at = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return r.height >= 44 && at && (at === b || b.contains(at)); })), 'mail: every export action is hit-testable and 44px tall');
  await ml.tap('#centerTitle').catch(() => {}); await ml.waitForTimeout(200);
  // Source mode opens the drawer that holds the textarea, below the toolbar, with Build still in reach
  await ml.tap('#modeSeg button[data-m="source"]'); await ml.waitForTimeout(350);
  ok(await ml.evaluate(() => { const s = document.querySelector('#src').getBoundingClientRect(), bar = document.querySelector('.bar').getBoundingClientRect(); return s.left >= 0 && s.width > 100 && s.top >= bar.bottom - 1 && document.querySelector('.pane.left').dataset.open === 'true'; }), 'mail: Source mode brings the textarea on screen, below the toolbar');
  ok(await ml.evaluate(() => ['#libClose', '#modeSeg [data-m="build"]'].every(q => { const c = document.querySelector(q), r = c.getBoundingClientRect(), at = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return at && (at === c || c.contains(at)); })), 'mail: in Source the drawer close button and Build are both tappable');
  ok((await ml.$eval('#toast', t => t.textContent)).includes('Source is empty'), 'mail: an empty Source offers the canvas HTML');
  await ml.tap('#modeSeg button[data-m="build"]'); await ml.waitForTimeout(350);
  ok(await ml.evaluate(() => document.querySelector('#viewSeg [data-w="canvas"]').getAttribute('aria-pressed') === 'true' && getComputedStyle(document.querySelector('#canvasWrap')).display !== 'none'), 'mail: back in Build, the canvas comes back (was the Desktop preview)');
  ok(await ml.evaluate(() => document.querySelector('.pane.left').dataset.open === 'false' && !document.querySelector('#toast').classList.contains('show')), 'mail: back in Build, the drawer Source opened closes and its toast goes (was left open over the canvas)');
  await ml.close();

  for (const [w, h, what] of [[768, 1024, 'tablet'], [844, 390, 'landscape phone'], [375, 667, 'small phone'], [1024, 768, 'iPad landscape']]) {
    console.log(`== mail at ${w}x${h} (${what}) ==`);
    const c2 = await browser.newContext({ viewport: { width: w, height: h }, isMobile: true, hasTouch: true, deviceScaleFactor: 2, serviceWorkers: 'block' });
    const m2 = await c2.newPage();
    await m2.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
    await m2.goto('http://localhost:8773/', { waitUntil: 'domcontentloaded' }); await m2.evaluate(() => localStorage.clear()); await m2.reload({ waitUntil: 'domcontentloaded' }); await m2.waitForTimeout(500);
    const libX = () => m2.evaluate(() => Math.round(document.querySelector('.pane.left').getBoundingClientRect().right));
    const closed0 = await libX(); await m2.tap('#btnLib'); await m2.waitForTimeout(350); const opened = await libX();
    ok(closed0 <= 0 && opened > 200, `mail ${what}: the library button opens the drawer (was a dead button)`);
    await m2.tap('#tpl button'); await m2.waitForTimeout(450);
    ok(await m2.evaluate(() => document.querySelector('.pane.left').dataset.open === 'false' && document.querySelector('.cv-block')), `mail ${what}: a template fills the canvas and the drawer closes`);
    ok(await m2.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `mail ${what}: no horizontal overflow`);
    if (what === 'tablet') {
      ok(await m2.evaluate(() => document.querySelector('#canvasWrap').getBoundingClientRect().width >= 600), 'mail tablet: the canvas gets the full width (was squeezed to 73% by a fixed library column)');
      await m2.tap('.cv-block:nth-child(2)', { position: { x: 4, y: 4 } }); await m2.waitForTimeout(500);
      const gutter = await m2.evaluate(() => { const st = document.querySelector('#stage').getBoundingClientRect(); return { x: st.left + 6, y: st.top + 60 }; });
      await m2.touchscreen.tap(gutter.x, gutter.y); await m2.waitForTimeout(300);
      ok(await m2.evaluate(() => document.querySelector('#inspector').dataset.open === 'false'), 'mail tablet: a tap on the stage beside the email closes the sheet');
    } else if (what === 'landscape phone') {
      ok(await m2.evaluate(() => document.querySelector('.bar').getBoundingClientRect().height <= 60 && document.querySelector('#stage').getBoundingClientRect().height >= 300), 'mail landscape: one toolbar row and a stage of at least 300px (was 244)');
    } else if (what === 'iPad landscape') {
      ok(await m2.evaluate(() => { const b = document.querySelector('#btnExport'), r = b.getBoundingClientRect(), at = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return innerWidth === 1024 && document.querySelector('.bar').scrollWidth <= innerWidth && r.right <= innerWidth && at && (at === b || b.contains(at)); }), 'mail iPad landscape: the toolbar wraps inside 1024px and Export is hit-testable (was a 1146px layout viewport, Export clipped)');
    }
    await m2.tap('.cv-block:nth-child(4)', { position: { x: 4, y: 4 } }); await m2.waitForTimeout(800);
    ok(await m2.evaluate(() => { const b = document.querySelector('.cv-block[aria-selected="true"]').getBoundingClientRect(), s = document.querySelector('#inspector').getBoundingClientRect(), st = document.querySelector('#stage').getBoundingClientRect(); const right = s.left > innerWidth / 3; return document.querySelector('#inspector').dataset.open === 'true' && b.top >= st.top - 1 && (right ? b.right <= s.left + 1 : b.top + 40 <= s.top); }), `mail ${what}: the sheet opens and the selected block stays in view beside or above it`);
    // the canvas never drops below 100% to make room for the sheet: beside a docked sheet it becomes the 1:1 phone canvas
    const px = await m2.evaluate(() => { const e = document.querySelector('[data-edit][data-rich="1"]'), w = document.querySelector('#canvasWrap'); return parseFloat(getComputedStyle(e).fontSize) * (+w.style.zoom || 1); });
    ok(px >= 15, `mail ${what}: with the sheet open, canvas text still reads at ${px}px${what === 'landscape phone' ? ' (was 11.2px at 70%)' : ''}`);
    if (what === 'small phone') ok(await m2.evaluate(() => { const st = document.querySelector('#stage').getBoundingClientRect(), s = document.querySelector('#inspector').getBoundingClientRect(); return s.top - st.top >= 200 && document.querySelector('#blockBar').closest('#inspector'); }), `mail small phone: the open sheet leaves at least 200px of the block in sight, with no bar over it (${await m2.evaluate(() => Math.round(document.querySelector('#inspector').getBoundingClientRect().top - document.querySelector('#stage').getBoundingClientRect().top))}px, was about 110)`);
    await c2.close();
  }

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
  await im.evaluate(() => document.querySelector('#targetGrid [data-t="og"]').click()); await im.waitForTimeout(250);
  ok(await im.evaluate(() => { const em = document.querySelector('#safe em'), i = document.querySelector('#safe i').getBoundingClientRect(), r = em.getBoundingClientRect();
    return document.querySelector('#safe').classList.contains('on') && (!em.checkVisibility() || r.bottom <= i.top + 0.5); }),
    'image: on the small docked OG preview the Safe zone label never sits on the card: above the line, or hidden when there is no room');
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
