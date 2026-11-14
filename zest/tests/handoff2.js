// THE HANDOFF, part 2 — studio zest-brand.json → ZestMail (Brand tab) + Zest MD (custom skin).
// Serve: studio :8771, mail :8773, md :8774.
const { chromium } = require('playwright');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {}; // point at a system Chromium when the local playwright has no downloaded browsers
const fs = require('fs');
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.error('  FAIL ' + m); } };
const mixB = (a, b, t) => { const h = x => [parseInt(x.slice(1, 3), 16), parseInt(x.slice(3, 5), 16), parseInt(x.slice(5, 7), 16)];
  const [A, B] = [h(a), h(b)]; return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0')).join(''); };
(async () => {
  const browser = await chromium.launch(LAUNCH);
  const ctx = await browser.newContext({ serviceWorkers: 'block' });
  const block = p => p.route(/^https?:\/\/(?!(localhost|127\.0\.0\.1)[:/])/, r => r.abort()); // nothing off this machine: every run sees the same page state, with or without egress

  console.log('== studio: export the Pantry brand ==');
  const st = await ctx.newPage(); await block(st);
  await st.goto('http://localhost:8771', { waitUntil: 'domcontentloaded' }); await st.waitForTimeout(700);
  await st.click('.pcell:nth-child(3)'); await st.waitForTimeout(300);   // Pantry: #5f7a0d, Technical modern, radius 10
  const dl = st.waitForEvent('download'); await st.click('#xBrand');
  const brandPath = await (await dl).path();
  const brand = JSON.parse(fs.readFileSync(brandPath, 'utf8'));
  ok(brand.zest === 1 && brand.light.primary === '#5f7a0d', 'studio exported Pantry (#5f7a0d)');
  const brandBuf = Buffer.from(JSON.stringify(brand));
  const expectDarkPrimary = mixB('#5f7a0d', '#ffffff', 0.3);
  ok(brand.dark.primary === expectDarkPrimary, `export carries the derived dark primary (${brand.dark.primary})`);
  await st.close();

  console.log('== ZestMail: Brand tab import ==');
  const ml = await ctx.newPage(); await block(ml);
  const mlErrs = []; ml.on('pageerror', e => mlErrs.push(e.message));
  const mlDialogs = []; ml.on('dialog', d => { mlDialogs.push(d.message()); d.accept(); });   // ZestMail asks nothing in a native dialog; one that opens is counted and fails below
  await ml.goto('http://localhost:8773', { waitUntil: 'domcontentloaded' }); await ml.waitForTimeout(700);
  const brandCount0 = await ml.$$eval('#brandSel option', o => o.length);
  ok(await ml.$eval('#brandImport', b => (b.offsetParent !== null || !!b.closest('.panel')) && b.tagName === 'BUTTON'), 'an Import… button exists in the Brand panel');
  await ml.setInputFiles('#jsonFile', { name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf });
  await ml.waitForTimeout(500);
  ok(await ml.$$eval('#brandSel option', o => o.length) === brandCount0 + 1, 'import created a new brand');
  ok(await ml.$eval('#brandSel', s => s.selectedOptions[0].textContent) === 'Pantry', 'new brand is selected and named Pantry');
  ok(await ml.$eval('[data-bk="primary"]', e => e.value) === '#5f7a0d', 'light primary landed');
  ok(await ml.$eval('[data-bk="line"]', e => e.value) === brand.light.line.toLowerCase(), 'hairline landed');
  const stack = await ml.$eval('[data-bk="font"]', e => e.value);
  ok(stack.startsWith("'Work Sans'") && /Helvetica/.test(stack), `body font became an email-safe stack (${stack})`);
  ok(+(await ml.$eval('[data-bk="radius"]', e => e.value)) === brand.radius, 'radius landed');
  // update, not duplicate — and identity fields survive
  await ml.$eval('[data-bk="company"]', e => { e.value = 'Pantry LLC'; e.dispatchEvent(new Event('input', { bubbles: true })); });
  await ml.waitForTimeout(200);
  await ml.setInputFiles('#jsonFile', { name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf });
  await ml.waitForTimeout(500);
  ok(await ml.$$eval('#brandSel option', o => o.length) === brandCount0 + 1, 're-import updates, never duplicates');
  ok(await ml.$eval('[data-bk="company"]', e => e.value) === 'Pantry LLC', 'identity fields stay the user’s own');
  // the old hole: random JSON through Import design must not clear the canvas or claim success
  const blocks0 = await ml.$$eval('.cv-block', b => b.length);
  await ml.setInputFiles('#jsonFile', { name: 'junk.json', mimeType: 'application/json', buffer: Buffer.from('{"hello":1}') });
  await ml.waitForTimeout(400);
  ok((await ml.$eval('#toast', e => e.textContent)).includes('isn’t a ZestMail design'), 'random JSON via Import design is refused honestly');
  ok(await ml.$$eval('.cv-block', b => b.length) === blocks0, 'canvas untouched by the refusal');
  // a zest file through Import design routes to the brand, not an empty design
  await ml.setInputFiles('#jsonFile', { name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf });
  await ml.waitForTimeout(400);
  ok((await ml.$eval('#toast', e => e.textContent)).includes('updated from zest-brand.json'), 'Import design routes a zest-brand.json to the brand');
  ok(await ml.$$eval('.cv-block', b => b.length) === blocks0, 'canvas still untouched');
  // drop anywhere
  await ml.evaluate(j => { const dt = new DataTransfer(); dt.items.add(new File([j], 'pantry-zest-brand.json', { type: 'application/json' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true })); }, JSON.stringify(brand));
  await ml.waitForTimeout(400);
  ok((await ml.$eval('#toast', e => e.textContent)).includes('zest-brand.json'), 'dropping the file anywhere imports it');
  // round 1 regressions: style-attribute injection, serif classification, empty-canvas persistence, iframe drop
  const inj = JSON.parse(JSON.stringify(brand)); inj.name = 'Injection';
  inj.fonts = { head: 'Geist', body: '&#39;;background:url(https://evil.example/x)', mono: 'Geist Mono', googleFontsUrl: '', custom: [] };
  await ml.setInputFiles('#jsonFile', { name: 'i-zest-brand.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(inj)) });
  await ml.waitForTimeout(400);
  const injStack = await ml.$eval('[data-bk="font"]', e => e.value);
  ok(!/[&#;:(){}"]/.test(injStack), `numeric char refs cannot reach style attributes (${injStack.slice(0, 48)})`);
  const news = JSON.parse(JSON.stringify(brand)); news.name = 'Serif Brand';
  news.fonts = { head: 'Fraunces', body: 'Newsreader', mono: 'Geist Mono', googleFontsUrl: '', custom: [] };
  await ml.setInputFiles('#jsonFile', { name: 'n-zest-brand.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(news)) });
  await ml.waitForTimeout(400);
  ok(/Newsreader.*Georgia/.test(await ml.$eval('[data-bk="font"]', e => e.value)), 'Newsreader classifies as serif (Georgia fallback)');
  await ml.click('#btnNew'); await ml.waitForTimeout(300);        // empty canvas: run() skips persist()
  await ml.setInputFiles('#jsonFile', { name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf });
  await ml.waitForTimeout(400);
  await ml.reload({ waitUntil: 'domcontentloaded' }); await ml.waitForTimeout(700);
  ok(await ml.$eval('#brandSel', s => s.selectedOptions[0].textContent) === 'Pantry', 'imported brand stays selected after reload on an empty canvas');
  await ml.click('#viewSeg [data-w="600"]'); await ml.waitForTimeout(500);   // preview mode: the center is an iframe
  const fr = await (await ml.$('#frame')).contentFrame();
  await fr.evaluate(j => { const dt = new DataTransfer(); dt.items.add(new File([j], 'pantry-zest-brand.json', { type: 'application/json' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true })); }, JSON.stringify(brand));
  await ml.waitForTimeout(400);
  ok((await ml.$eval('#toast', e => e.textContent)).includes('zest-brand.json'), 'dropping on the preview iframe imports too');

  console.log('== ZestMail: design import is checked, and an honest design is unchanged by the checks ==');
  // an honest design first: export it, import it back, and the compiled email must be byte-identical
  await ml.click('#viewSeg [data-w="canvas"]'); await ml.waitForTimeout(300);
  await ml.$eval('#tpl [data-tpl="newsletter"]', b => b.click()); await ml.waitForTimeout(400);
  await ml.click('#viewSeg [data-w="600"]'); await ml.waitForTimeout(500);
  const compiledBefore = await ml.$eval('#frame', f => f.srcdoc);
  const designDl = ml.waitForEvent('download'); await ml.$eval('#popExport [data-do="json"]', b => b.click());
  const designPath = await (await designDl).path();
  await ml.setInputFiles('#jsonFile', { name: 'newsletter.mailpress.json', mimeType: 'application/json', buffer: fs.readFileSync(designPath) });
  await ml.waitForTimeout(600);
  await ml.click('#viewSeg [data-w="600"]'); await ml.waitForTimeout(500);
  ok(compiledBefore.length > 2000 && await ml.$eval('#frame', f => f.srcdoc) === compiledBefore, 'an exported design re-imports to the same compiled email');
  await ml.click('#viewSeg [data-w="canvas"]'); await ml.waitForTimeout(300);
  ok(await ml.$$eval('.cv-block', b => b.length) === 7, 'every block of the exported design comes back');
  // a hostile design: every field that becomes markup structure (ids, fonts, colors, numbers, select values,
  // block types, link schemes) carries markup. None of it may reach the page as markup, now or after a reload.
  const X = '"><img src=x onerror="window.__pwned=1">';
  const evil = { name: 'Evil' + X, id: 'd' + X, subject: 's', width: '600' + X, bg: '#ffffff' + X,
    brand: { id: 'evil' + X, name: 'Evil brand', esp: 'custom', tagBrowser: 'x' + X, tagUnsub: 'javascript:window.__pwned=1', font: 'x' + X, primary: '#000000' + X, ink: X, muted: X, sheet: X, line: X,
      logo: 'icons/icon-112.png', logoWidth: '140' + X, radius: '8' + X, website: 'javascript:window.__pwned=1', unsubscribe: 'javascript:window.__pwned=1' },
    blocks: [
      { id: 'b' + X, type: 'spacer', props: { height: '24' + X, bg: 'x' + X } },
      { id: 'b2', type: 'header', props: { align: 'left' + X, browser: true, pad: '24' + X, padX: '36' + X, bg: 'brand.font' } },
      { id: 'b3', type: 'text', props: { size: '16' + X, color: X, body: 'hi [link](javascript:window.__pwned=1)' } },
      { id: 'b4', type: 'nope' + X, props: {} },
      { id: 'b5', type: 'constructor', props: {} },
      { id: 'b6', type: 'footer', props: { browser: true, snooze: true, prefs: true } },
    ] };
  const HOSTILE = '[onerror], #canvas script, #canvas a[href^="javascript:" i]';
  await ml.setInputFiles('#jsonFile', { name: 'evil.mailpress.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(evil)) });
  await ml.waitForTimeout(700);
  ok(await ml.evaluate(() => window.__pwned === undefined), 'a hostile design import runs nothing');
  ok(await ml.$$eval(HOSTILE, n => n.length) === 0, 'the import adds no elements, handlers or script URLs');
  ok(await ml.$$eval('.cv-block', b => b.length) === 4, 'known block types load; unknown ones are dropped');
  ok(await ml.$eval('#brandSel', s => s.selectedOptions[0].textContent) === 'Evil brand', 'the imported brand is selected');
  ok(await ml.$eval('[data-bk="primary"]', e => e.value) === '#1f4ed8', 'a color that is not a six-digit hex falls back to the default');
  ok(!/[<>"=;:(){}]/.test(await ml.$eval('[data-bk="font"]', e => e.value)), 'an imported font stack is reduced to font-name characters');
  ok(await ml.$eval('[data-bk="tagUnsub"]', e => e.value) === '', 'a custom merge tag that is used as a link cannot be a script URL');
  await ml.$eval('.cv-block', b => b.click()); await ml.waitForTimeout(300);      // inspector renders the block's fields
  await ml.click('#viewSeg [data-w="600"]'); await ml.waitForTimeout(500);       // and the compiled preview
  ok(await ml.$eval('#frame', f => new DOMParser().parseFromString(f.srcdoc, 'text/html').querySelectorAll('[onerror], script, a[href^="javascript:" i]').length) === 0, 'the compiled preview carries no handlers or script URLs');
  ok(await ml.evaluate(() => window.__pwned === undefined) && await ml.$$eval(HOSTILE, n => n.length) === 0, 'still nothing after the inspector and the preview render');
  await ml.reload({ waitUntil: 'domcontentloaded' }); await ml.waitForTimeout(700);
  ok(await ml.evaluate(() => window.__pwned === undefined), 'nothing runs when the imported design comes back from storage');
  ok(await ml.$$eval(HOSTILE, n => n.length) === 0 && await ml.$$eval('.cv-block', b => b.length) === 4, 'the reloaded canvas is the same four clean blocks');
  // a design never changes a brand that is already here, even when it carries that brand's id (the first brand's id is the same on every install)
  const storedBrand = id => ml.evaluate(i => JSON.stringify((JSON.parse(localStorage.getItem('mailpress:brands')) || []).find(b => b.id === i) || null), id);
  const brandTotal = () => ml.evaluate(() => JSON.parse(localStorage.getItem('mailpress:brands')).length);
  const ownBrand = await storedBrand('shepdesign'), total0 = await brandTotal();
  const otherBuf = Buffer.from(JSON.stringify({ name: 'Free template', blocks: [{ type: 'footer', props: {} }],
    brand: { id: 'shepdesign', unsubscribe: 'https://other.example/u', website: 'https://other.example', company: 'Other Co', logo: 'https://other.example/pixel.png' } }));
  await ml.setInputFiles('#jsonFile', { name: 'template.mailpress.json', mimeType: 'application/json', buffer: otherBuf });
  await ml.waitForTimeout(600);
  ok(ownBrand !== 'null' && await storedBrand('shepdesign') === ownBrand, 'a design that carries an existing brand id leaves that brand as it was');
  ok(await brandTotal() === total0 + 1, 'the brand in the file arrives as a separate brand');
  ok(await ml.$eval('[data-bk="company"]', e => e.value) === 'Other Co', 'the Brand tab shows the brand that came with the design, with no block selected');
  ok((await ml.$eval('#toast', e => e.textContent)).includes('its brand was added as'), 'the import says a brand was added');
  await ml.setInputFiles('#jsonFile', { name: 'template.mailpress.json', mimeType: 'application/json', buffer: otherBuf });
  await ml.waitForTimeout(600);
  ok(await brandTotal() === total0 + 1, 'opening the same design again adds no second copy');
  // checking a design never costs an honest one anything: a long logo, a font named in another script, long text and
  // many blocks all come back whole, on import and again after a reload
  const LOGO = 'data:image/png;base64,' + 'A'.repeat(300000), LONG = 'word '.repeat(5000).trim();
  const honest = { name: 'Honest', brand: { name: 'Honest brand', font: "游ゴシック, 'Hiragino Sans', sans-serif", logo: LOGO },
    blocks: [{ type: 'text', props: { body: LONG } }].concat(Array.from({ length: 450 }, () => ({ type: 'spacer', props: {} }))) };
  await ml.setInputFiles('#jsonFile', { name: 'honest.mailpress.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(honest)) });
  await ml.waitForTimeout(900);
  const honestBrand = () => ml.evaluate(() => JSON.stringify((JSON.parse(localStorage.getItem('mailpress:brands')) || []).find(b => b.name === 'Honest brand') || null));
  const wholeDesign = async when => {
    const b = JSON.parse(await honestBrand());
    ok(b && b.logo.length === LOGO.length, `a long data: image logo is kept whole (${when})`);
    ok(b && b.font.startsWith('游ゴシック'), `a font family named in another script is kept (${when})`);
    ok(await ml.$$eval('.cv-block', n => n.length) === 451, `every block of a large design is kept (${when})`);
    ok((await ml.$eval('#canvas', c => c.textContent)).includes(LONG), `a long text block is kept whole (${when})`);
  };
  await wholeDesign('on import');
  await ml.reload({ waitUntil: 'domcontentloaded' }); await ml.waitForTimeout(900);
  await wholeDesign('after a reload');
  // an import over the documented budget is refused whole, with a message, and the editor is left as it was
  const before = await ml.evaluate(() => JSON.stringify(JSON.parse(localStorage.getItem('mailpress:brands'))) + document.querySelectorAll('.cv-block').length);
  const tooMany = { name: 'Too many', blocks: Array.from({ length: 2001 }, () => ({ type: 'spacer', props: {} })) };
  const tooLong = { name: 'Too long', blocks: [{ type: 'text', props: { body: 'a'.repeat(200001) } }] };
  for (const [what, d] of [['blocks', tooMany], ['text', tooLong]]) {
    await ml.setInputFiles('#jsonFile', { name: 'big.mailpress.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(d)) });
    await ml.waitForTimeout(500);
    ok((await ml.$eval('#toast', e => e.textContent)).includes('not imported'), `a design over the ${what} budget is refused with a message`);
    ok(await ml.evaluate(() => JSON.stringify(JSON.parse(localStorage.getItem('mailpress:brands'))) + document.querySelectorAll('.cv-block').length) === before, `a refused design (${what}) changes nothing`);
  }
  const brackets = { name: 'Brackets', blocks: [{ type: 'text', props: { body: '['.repeat(150000) + '[a]('.repeat(12500) } }] };
  const t0 = Date.now();
  await ml.setInputFiles('#jsonFile', { name: 'brackets.mailpress.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(brackets)) });
  await ml.waitForFunction(() => document.querySelector('#toast')?.textContent.includes('Imported'), null, { timeout: 15000 });
  ok(Date.now() - t0 < 10000, 'a long run of unclosed link brackets is read in linear time');
  // storage itself is untrusted too: brands, the draft, modules and saved designs are checked on the way in
  await ml.evaluate(x => {
    const put = (k, v) => localStorage.setItem('mailpress:' + k, JSON.stringify(v));
    put('brands', [{ id: 'b' + x, name: 'Tampered', font: 'f' + x, ink: x, sheet: x, radius: x, logoWidth: x, esp: 'custom', tagUnsub: 'JaVaScRiPt:window.__pwned=1', tagBrowser: ' java\tscript:window.__pwned=1' }]);
    put('draft', { blocks: [{ id: x, type: 'spacer', props: { height: x, bg: x } }, { id: 'k', type: x, props: {} }, { type: 'header', props: { browser: true } }, { type: 'footer', props: { browser: true } }], brandId: 'b' + x, designId: x, designName: 'n' + x, width: x, bg: x });
    put('modules', [{ id: 'm' + x, name: 'M', type: 'spacer', props: { height: x, bg: x } }, { id: 'm2', name: 'N', type: 't' + x, props: {} }]);
    put('designs', [{ id: 'd' + x, name: 'D', saved: x, blocks: [{ id: x, type: 'divider', props: { color: x } }] }]);
  }, X);
  await ml.reload({ waitUntil: 'domcontentloaded' }); await ml.waitForTimeout(700);
  ok(await ml.evaluate(() => window.__pwned === undefined) && await ml.$$eval('[onerror]', n => n.length) === 0, 'tampered storage runs nothing at boot');
  ok(await ml.$$eval('#canvas a', a => a.length) > 0 && await ml.$$eval('#canvas a[href^="javascript:" i]', a => a.length) === 0, 'script URLs in stored merge tags never become link addresses');
  await ml.$eval('#mods [data-mod]', e => e.click()); await ml.waitForTimeout(300);            // a stored module onto the canvas
  await ml.$eval('#savedList [data-load]', e => e.click()); await ml.waitForTimeout(400);      // a stored design opened
  ok(await ml.evaluate(() => window.__pwned === undefined) && await ml.$$eval('[onerror]', n => n.length) === 0, 'stored modules and saved designs are checked before they reach the canvas');
  ok(mlErrs.length === 0, 'ZestMail: no exceptions (' + mlErrs.slice(0, 1).join('').slice(0, 80) + ')');
  ok(mlDialogs.length === 0, 'ZestMail: no native dialog opened (' + mlDialogs.slice(0, 1).join('').slice(0, 60) + ')');
  await ml.close();

  console.log('== ZestMail: one import, folded defaults, naming and Undo without a native dialog ==');
  const zctx = await browser.newContext({ serviceWorkers: 'block' });   // its own storage: a first visit
  const mz = await zctx.newPage(); await block(mz);
  const mzErrs = [], mzDialogs = []; mz.on('pageerror', e => mzErrs.push(e.message)); mz.on('dialog', d => { mzDialogs.push(d.message()); d.dismiss(); });
  await mz.goto('http://localhost:8773', { waitUntil: 'domcontentloaded' }); await mz.waitForTimeout(700);
  const toastText = () => mz.$eval('#toast', e => e.textContent);
  const stored = k => mz.evaluate(key => localStorage.getItem('mailpress:' + key), k);
  const draft = async () => { await mz.waitForTimeout(350); return stored('draft'); };   // run() is debounced; the draft is what a reload would bring back
  ok(await mz.evaluate(() => { const c = document.querySelector('.pane.center').getBoundingClientRect(), i = document.querySelector('#inspector').getBoundingClientRect(); return i.left >= c.right - 1 && Math.abs(i.top - c.top) < 2 && c.width > 400; }), 'desktop: the canvas sits between the library and the inspector');
  // one import: a single file input, reached from the Export menu and from the Brand tab, and either file works from either place
  ok(await mz.$$eval('input[type=file]', n => n.length === 1 && n[0].id === 'jsonFile'), 'there is one file input');
  ok(/Import…/.test(await mz.$eval('#popExport [data-do="importjson"]', b => b.textContent)) && /design or brand/.test(await mz.$eval('#popExport [data-do="importjson"]', b => b.textContent)), 'the Export menu has one Import… item that says it takes a design or a brand');
  const designBuf = Buffer.from(JSON.stringify({ name: 'From a file', subject: 'Hello', blocks: [{ type: 'text', props: { body: 'one' } }, { type: 'footer', props: {} }] }));
  const viaMenu = async () => { await mz.click('#btnExport'); const fc = mz.waitForEvent('filechooser'); await mz.click('#popExport [data-do="importjson"]'); return fc; };
  const viaBrandTab = async () => { await mz.click('#tabs button[data-t="brand"]'); const fc = mz.waitForEvent('filechooser'); await mz.click('#brandImport'); return fc; };
  for (const [where, pick] of [['the Export menu', viaMenu], ['the Brand tab', viaBrandTab]]) {
    let fc = await pick();
    ok(await fc.element().evaluate(e => e.id) === 'jsonFile', `Import… from ${where} opens the one picker`);
    await fc.setFiles({ name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf }); await mz.waitForTimeout(450);
    ok((await toastText()).includes('from zest-brand.json') && await mz.$eval('#brandSel', s => s.selectedOptions[0].textContent) === 'Pantry', `a brand file imports from ${where}`);
    fc = await pick();
    await fc.setFiles({ name: 'd.mailpress.json', mimeType: 'application/json', buffer: designBuf }); await mz.waitForTimeout(450);
    ok((await toastText()).includes('Imported “From a file”') && await mz.$$eval('.cv-block', n => n.length) === 2, `a design file imports from ${where}`);
  }
  // Message tab: the three defaults are folded away, still on, and the compiler still gets them; Fallback fonts shows in Source only
  await mz.click('#tabs button[data-t="message"]');
  ok(await mz.$eval('#foldCompat', d => d.tagName === 'DETAILS' && !d.open && ['darkMeta', 'wrap', 'mirror'].every(id => d.querySelector('#' + id).checked)), 'Message: dark-mode meta, wrapper and mirroring sit in one fold, closed, all still on');
  await mz.click('#viewSeg [data-w="600"]'); await mz.waitForTimeout(450);
  ok(await mz.$eval('#frame', f => /supported-color-schemes/.test(f.srcdoc) && /class="container"/.test(f.srcdoc) && /<td[^>]* bgcolor="/.test(f.srcdoc)), 'the compiled email still carries the dark-mode meta, the wrapper and mirrored attributes');
  await mz.click('#viewSeg [data-w="canvas"]');
  await mz.focus('#foldCompat summary'); await mz.keyboard.press('Enter');
  ok(await mz.$eval('#foldCompat', d => d.open), 'the fold opens from the keyboard');
  await mz.focus('#wrap'); await mz.keyboard.press('Escape');
  ok(await mz.$eval('#foldCompat', d => !d.open && document.activeElement === d.querySelector('summary')), 'Escape closes the fold and hands focus to its summary');
  ok(await mz.$eval('#fontsField', f => getComputedStyle(f).display === 'none'), 'Fallback fonts is hidden in Build');
  await mz.click('#modeSeg [data-m="source"]'); await mz.waitForTimeout(300);
  ok(await mz.$eval('#fontsField', f => getComputedStyle(f).display !== 'none' && !f.closest('details')), 'Fallback fonts shows in Source');
  await mz.click('#modeSeg [data-m="build"]'); await mz.waitForTimeout(300);
  // Claude tab: the brief first, the four connection fields in a fold that is closed while the connection can work and opens when it cannot
  await mz.click('#tabs button[data-t="claude"]');
  ok(await mz.evaluate(() => { const b = document.querySelector('#brief'), f = document.querySelector('#claudeSetup'); return !!(b.compareDocumentPosition(f) & Node.DOCUMENT_POSITION_FOLLOWING) && ['apiKey', 'route', 'proxyToken', 'model'].every(id => f.querySelector('#' + id)); }), 'Claude: the brief comes first; key, route, proxy token and model sit in a fold below it');
  ok(await mz.$eval('#claudeSetup', d => !d.open), 'the fold is closed while the connection can work (a served page uses the proxy route)');
  await mz.$eval('#route', r => { r.value = 'direct'; r.dispatchEvent(new Event('change', { bubbles: true })); });
  ok(await mz.$eval('#claudeSetup', d => d.open), 'Direct with no key: the fold opens by itself');
  await mz.reload({ waitUntil: 'domcontentloaded' }); await mz.waitForTimeout(700);
  ok(await mz.$eval('#claudeSetup', d => d.open), '… and is open on the next visit too');
  await mz.$eval('#route', r => { r.value = 'auto'; r.dispatchEvent(new Event('change', { bubbles: true })); });
  // naming: an inline field, prefilled as the prompt was; Enter saves, Escape cancels, focus goes back to the button
  await mz.$eval('#tpl [data-tpl="newsletter"]', b => b.click()); await mz.waitForTimeout(400);
  await mz.click('#tabs button[data-t="message"]'); await mz.fill('#subject', 'Spring issue');
  await mz.click('#btnSave');
  ok(await mz.evaluate(() => document.querySelector('#popName').dataset.open === 'true' && document.activeElement.id === 'nameInput' && document.activeElement.value === 'Newsletter' && document.querySelector('#nameLabel').textContent === 'Design name'), 'Save opens a name field in the page, prefilled with the design name and focused');
  await mz.keyboard.type('Nope'); await mz.keyboard.press('Escape');
  ok(await mz.evaluate(() => document.querySelector('#popName').dataset.open === 'false' && document.activeElement.id === 'btnSave') && (await stored('designs')) === null, 'Escape cancels: nothing saved, focus back on Save');
  await mz.click('#btnSave'); await mz.keyboard.type('April letter'); await mz.keyboard.press('Enter'); await mz.waitForTimeout(200);
  ok((await toastText()).includes('Saved “April letter”') && await mz.$eval('#savedList', l => l.textContent.includes('April letter')) && JSON.parse(await stored('designs'))[0].name === 'April letter', 'Enter saves the design under the typed name');
  await mz.$eval('.cv-block', b => b.click()); await mz.waitForTimeout(250);
  await mz.click('#btnModule');
  ok(await mz.evaluate(() => document.querySelector('#nameLabel').textContent === 'Module name' && document.activeElement.value === 'Logo header — Pantry'), 'Save as module opens the same field, prefilled with the block and brand');
  await mz.click('#nameSave'); await mz.waitForTimeout(200);
  ok(await mz.$eval('#mods', e => e.textContent.includes('Logo header — Pantry')) && JSON.parse(await stored('modules')).length === 1, 'its Save button saves the module');
  await mz.click('#btnModule'); await mz.click('#nameCancel');
  ok(JSON.parse(await stored('modules')).length === 1 && await mz.evaluate(() => document.activeElement.id === 'btnModule'), 'Cancel saves nothing and hands focus back');
  // ⌘K on canvas text asks for the address in the same field and links the selection
  await mz.evaluate(() => { const ed = [...document.querySelectorAll('#canvas [data-edit][data-rich="1"]')].find(e => e.textContent.includes('The first version')); ed.focus(); const r = document.createRange(), t = document.createTreeWalker(ed, NodeFilter.SHOW_TEXT).nextNode(); r.setStart(t, 0); r.setEnd(t, 2); getSelection().removeAllRanges(); getSelection().addRange(r); });
  await mz.keyboard.press('Control+k');
  ok(await mz.evaluate(() => document.querySelector('#popName').dataset.open === 'true' && document.activeElement.value === 'https://'), '⌘K opens the field for a link address');
  await mz.keyboard.type('https://example.com/notes'); await mz.keyboard.press('Enter'); await mz.waitForTimeout(400);
  ok(/\[Hi\]\(https:\/\/example\.com\/notes\)/.test(await stored('draft')), 'the selected text becomes the link');
  await mz.keyboard.press('Escape'); await mz.waitForTimeout(200);
  // Undo: each of the four actions happens at once, says so, and its Undo puts back exactly what was there
  const draft0 = await draft();
  await mz.$eval('#tpl [data-tpl="launch"]', b => b.click()); await mz.waitForTimeout(300);
  ok((await toastText()).includes('Replaced the canvas with Product launch') && await mz.$eval('#toast button', b => b.textContent) === 'Undo' && (await draft()) !== draft0, 'a template replaces the canvas at once and offers Undo');
  await mz.click('#toast button');
  ok((await draft()) === draft0, 'Undo after a template restores the blocks, name and subject exactly');
  await mz.click('#btnNew'); await mz.waitForTimeout(200);
  ok((await toastText()).includes('Started a new design') && await mz.$$eval('.cv-block', n => n.length) === 0 && await mz.inputValue('#subject') === '', 'New clears the canvas at once and offers Undo');
  await mz.click('#lib .lib-item'); await mz.waitForTimeout(200);       // an edit made after New, before Undo
  await mz.click('#toast button');
  ok((await draft()) === draft0 && await mz.inputValue('#subject') === 'Spring issue', 'Undo after New restores exactly what was there, even after a later edit');
  await mz.click('#btnNew'); await mz.waitForTimeout(200);
  await mz.keyboard.press('Control+z');
  ok((await draft()) === draft0, '⌘Z is the same Undo while the toast is up');
  const designs0 = await stored('designs');
  await mz.click('#savedList [data-rm]'); await mz.waitForTimeout(200);
  ok((await toastText()).includes('Deleted “April letter”') && await stored('designs') === '[]', 'deleting a saved design happens at once and offers Undo');
  await mz.click('#toast button');
  ok(await stored('designs') === designs0 && await mz.$eval('#savedList', l => l.textContent.includes('April letter')), 'Undo puts the saved design back exactly');
  await mz.click('#tabs button[data-t="brand"]');
  const brands0 = await stored('brands'), sel0 = await mz.$eval('#brandSel', s => s.value);
  await mz.click('#brandDel'); await mz.waitForTimeout(200);
  ok((await toastText()).includes('Deleted brand “Pantry”') && JSON.parse(await stored('brands')).length === JSON.parse(brands0).length - 1, 'deleting a brand happens at once and offers Undo');
  await mz.click('#toast button'); await mz.waitForTimeout(200);
  ok(await stored('brands') === brands0 && await mz.$eval('#brandSel', s => s.value) === sel0, 'Undo puts the brand back exactly, selected again');
  ok(mzDialogs.length === 0, 'none of it opened a native dialog (' + mzDialogs.slice(0, 1).join('').slice(0, 60) + ')');
  ok(mzErrs.length === 0, 'ZestMail: no exceptions in the simplified flows (' + mzErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await zctx.close();

  console.log('== Zest MD: custom-skin import ==');
  const md = await ctx.newPage(); await block(md);
  // The sanitizer is the vendored file (zest/vendor/dompurify, served at /vendor/ beside the app as on every surface).
  // It must be byte for byte the npm release tests/package.json pins, the version VENDOR.lock.json and the tag name.
  const PURIFY = fs.readFileSync(require.resolve('dompurify/dist/purify.min.js'));
  const VENDORED = fs.readFileSync(require('path').join(__dirname, '..', 'vendor', 'dompurify', 'purify.min.js'));
  ok(PURIFY.equals(VENDORED), 'the vendored sanitizer is byte for byte the npm release the tests pin');
  const mdErrs = []; md.on('pageerror', e => mdErrs.push(e.message));
  await md.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await md.waitForTimeout(700);
  // the sanitizer tag is pinned by hash. The copy served here is the npm package at the version in package.json,
  // so if it loads, the hash in the page matches that release; a mismatch would block it and fail the checks below.
  ok(await md.$eval('script[src*="dompurify"]', s => /^sha384-[A-Za-z0-9+/]{64}$/.test(s.getAttribute('integrity') || '') && s.getAttribute('crossorigin') === 'anonymous'), 'the sanitizer script tag carries an integrity hash');
  ok(await md.evaluate(() => !!window.DOMPurify && (window.__mdpressMissing || []).length === 0), 'the pinned sanitizer release matches that hash and loads');
  await md.click('[data-act="sample"]'); await md.waitForTimeout(500);
  await md.setInputFiles('#brandFile', { name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf });
  await md.waitForTimeout(500);
  const cssVar = (p, v) => p.evaluate(n => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), v);
  ok(await cssVar(md, '--accent') === '#5f7a0d', 'light accent is the brand primary');
  ok(await cssVar(md, '--paper') === brand.light.paper.toLowerCase(), 'light paper landed');
  ok(await cssVar(md, '--rule') === brand.light.line.toLowerCase(), 'hairline landed as --rule');
  ok(await md.$eval('#custom [data-c="mono"]', e => e.value) === 'geistMono', 'mono font mapped into the typeface picker');
  ok((await md.$eval('.skin[data-skin="custom"] b', e => e.textContent)) === 'Pantry', 'custom skin card carries the brand name');
  ok(await md.$eval('.skin[data-skin="custom"]', e => e.getAttribute('aria-pressed')) === 'true', 'custom skin is active');
  // dark mode uses the brand's EXPLICIT dark palette, not a re-derivation
  await md.$eval('#popRead [data-set="theme"] [data-v="dark"]', b => b.click()); await md.waitForTimeout(300);
  ok(await cssVar(md, '--accent') === expectDarkPrimary, `dark accent is the brand's explicit dark primary (${expectDarkPrimary})`);
  await md.$eval('#popRead [data-set="theme"] [data-v="light"]', b => b.click()); await md.waitForTimeout(200);
  // persistence
  await md.reload({ waitUntil: 'domcontentloaded' }); await md.waitForTimeout(700);
  ok(await cssVar(md, '--accent') === '#5f7a0d', 'imported skin survives reload');
  ok((await md.$eval('.skin[data-skin="custom"] b', e => e.textContent)) === 'Pantry', 'brand name survives reload');
  // hand edit releases the explicit palettes back to four-color derivation
  await md.$eval('#custom [data-c="paper"]', e => { e.value = '#fdf6ec'; e.dispatchEvent(new Event('input', { bubbles: true })); });
  await md.waitForTimeout(300);
  ok((await md.$eval('.skin[data-skin="custom"] b', e => e.textContent)) === 'Custom', 'hand edit releases the brand — card reads Custom again');
  ok(await cssVar(md, '--paper') === '#fdf6ec', 'the edited color applies');
  // a non-brand json is refused honestly
  await md.evaluate(() => { const dt = new DataTransfer(); dt.items.add(new File(['{"x":1}'], 'junk.json', { type: 'application/json' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true })); });
  await md.waitForTimeout(300);
  ok((await md.$eval('#toast', e => e.textContent)).includes('Not a zest-brand.json'), 'non-brand JSON drop is refused honestly');
  // round 1 regression: doc is the READING face — fonts.body, never the display head
  const fm = JSON.parse(JSON.stringify(brand)); fm.name = 'FontMap';
  fm.fonts = { head: 'Bricolage Grotesque', body: 'Geist', mono: 'JetBrains Mono', googleFontsUrl: '', custom: [] };
  await md.setInputFiles('#brandFile', { name: 'f-zest-brand.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(fm)) });
  await md.waitForTimeout(400);
  ok(await md.$eval('#custom [data-c="doc"]', e => e.value) === 'geist', 'Body type takes fonts.body (geist), not the heading face');
  ok(await md.$eval('#custom [data-c="mono"]', e => e.value) === 'jet', 'JetBrains Mono maps to its exact registry key');
  // shared-origin hardening: raw HTML renders, but scripts/handlers never execute
  const PAYLOAD = '# Doc\n\n<img src=x onerror="window.__pwned=1"><em>kept</em>\n\n<iframe srcdoc="x"></iframe>';
  await md.evaluate(t => { const dt = new DataTransfer(); dt.items.add(new File([t], 'evil.md', { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, PAYLOAD);
  await md.waitForTimeout(600);
  ok(await md.evaluate(() => window.__pwned === undefined), 'event handlers in raw HTML never execute');
  ok(await md.$eval('#doc em', e => e.textContent) === 'kept', 'safe raw markup still renders');
  ok(await md.$$eval('#doc [onerror], #doc iframe, #doc script', n => n.length) === 0, 'handlers, frames and scripts are stripped at the sink');
  // the Contents list is a second place document headings land: their ids and text must be inert there too,
  // for a dropped file and for the ?text= deep link (which needs no click at all)
  const TOC_PAYLOAD = '# Doc\n\n<h2 id=\'x"><img src=x onerror="window.__pwned=1">\'>a</h2>\n\n<h2 id=\'y" onmouseover="window.__pwned=2" x="\'>b</h2>\n\n## 2026 plan\n';
  const TOC_HOSTILE = '#toc img, #toc script, #toc iframe, #toc [onerror], #toc [onmouseover]';
  const tocShape = p => p.evaluate(() => ({ links: document.querySelectorAll('#toc a').length, headings: document.querySelectorAll('#doc h1[id], #doc h2[id], #doc h3[id], #doc h4[id]').length, other: [...document.querySelector('#toc').children].filter(c => !['H4', 'A'].includes(c.tagName)).length }));
  await md.evaluate(t => { const dt = new DataTransfer(); dt.items.add(new File([t], 'toc.md', { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, TOC_PAYLOAD);
  await md.waitForTimeout(600);
  ok(await md.evaluate(() => window.__pwned === undefined), 'heading ids never execute through the Contents list (dropped file)');
  ok(await md.$$eval(TOC_HOSTILE, n => n.length) === 0, 'Contents holds no injected elements or handlers (dropped file)');
  let shape = await tocShape(md);
  ok(shape.headings === 4 && shape.links === 4 && shape.other === 0, `Contents is one plain link per heading (${shape.links} links, ${shape.headings} headings)`);
  ok(await md.$eval('#toc a:nth-of-type(2)', a => a.textContent === 'a' && a.getAttribute('href').startsWith('#x"><img')), 'a heading id is kept as an attribute value, never parsed');
  await md.$eval('#toc a:last-of-type', a => a.click()); await md.waitForTimeout(300);   // "2026 plan": an id that starts with a digit
  ok(mdErrs.length === 0, 'a Contents link works for a heading id that starts with a digit');
  await md.goto('http://localhost:8774/?text=' + encodeURIComponent(TOC_PAYLOAD), { waitUntil: 'domcontentloaded' }); await md.waitForTimeout(800);
  ok(await md.evaluate(() => window.__pwned === undefined), 'heading ids never execute through the Contents list (?text= deep link)');
  ok(await md.$$eval(TOC_HOSTILE, n => n.length) === 0, 'Contents holds no injected elements or handlers (?text= deep link)');
  shape = await tocShape(md);
  ok(shape.headings === 4 && shape.links === 4 && shape.other === 0, 'the deep link renders the same four plain links');
  // reader settings come back from storage, which every tool on this origin can write: they are checked on the way in
  await md.evaluate(x => {
    const s = JSON.parse(localStorage.getItem('mdpress:settings'));
    Object.assign(s, { skin: 'custom', font: x, size: '17' + x, lh: x, measure: x });
    s.custom = { paper: '#f2f3f5' + x, sheet: x, ink: x, accent: x, doc: x, ui: x, mono: x, radius: '8' + x, brand: { name: 'n' + x, light: [x], dark: [x] } };
    localStorage.setItem('mdpress:settings', JSON.stringify(s));
  }, X);
  await md.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await md.waitForTimeout(700);
  ok(await md.evaluate(() => window.__pwned === undefined), 'tampered reader settings run nothing at boot');
  ok(await md.$$eval('#popRead img, #popRead script, #popRead [onerror]', n => n.length) === 0 && await md.$$eval('#skins > .skin', n => n.length) === 8, 'the skin list is eight plain buttons');
  ok(await cssVar(md, '--paper') === '#f2f3f5' && await cssVar(md, '--doc-size') === '17px' && await cssVar(md, '--measure') === '70ch' && await cssVar(md, '--radius') === '8px', 'settings the app could not have saved fall back to the defaults');
  await md.evaluate(() => { const dt = new DataTransfer(); dt.items.add(new File(['# Export\n\ntext\n'], 'export.md', { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); });
  await md.waitForTimeout(500);
  const htmlDl = md.waitForEvent('download'); await md.click('#btnExport');
  const exportedHead = fs.readFileSync(await (await htmlDl).path(), 'utf8').split('<article')[0];
  ok(exportedHead.includes('--doc-size:17px;--doc-lh:1.65;--measure:70ch') && !/onerror|<img/i.test(exportedHead), 'the exported file is styled with the checked values only');
  await md.evaluate(x => { const s = JSON.parse(localStorage.getItem('mdpress:settings')); s.theme = 'light' + x; s.skin = 'constructor'; localStorage.setItem('mdpress:settings', JSON.stringify(s)); }, X);
  await md.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await md.waitForTimeout(700);
  ok(await md.evaluate(() => document.documentElement.dataset.theme) === 'auto' && await md.$eval('.skin[data-skin="press"]', e => e.getAttribute('aria-pressed')) === 'true', 'a mode or skin the app does not offer falls back to the default');
  ok(mdErrs.length === 0, 'Zest MD: no exceptions (' + mdErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await md.close();

  console.log('== Zest MD: a simpler bar ==');
  {   // a block of its own, so its names cannot collide with the rest of the suite
  // its own context: clean storage, and clipboard access for Paste
  const barCtx = await browser.newContext({ serviceWorkers: 'block', permissions: ['clipboard-read', 'clipboard-write'] });
  const bar = await barCtx.newPage(); await block(bar);
  const barErrs = []; bar.on('pageerror', e => barErrs.push(e.message));
  await bar.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await bar.waitForTimeout(700);
  // checkVisibility() is false under display:none and inside a closed <details>, where a box can still be measured
  const shown = (p, sel) => p.$$eval(sel, n => n.length > 0 && n.every(e => e.checkVisibility() && e.getBoundingClientRect().width > 0));
  const gone = (p, sel) => p.$$eval(sel, n => n.length > 0 && n.every(e => !e.checkVisibility()));
  const tabCount = () => bar.$$eval('#tabs .tab', n => n.length);
  const dropMd = (name, text) => bar.evaluate(([n, t]) => { const dt = new DataTransfer(); dt.items.add(new File([t], n, { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true })); }, [name, text]);
  const mdFile = (name, text) => ({ name, mimeType: 'text/markdown', buffer: Buffer.from(text) });
  const saved = () => bar.evaluate(() => JSON.parse(localStorage.getItem('mdpress:settings')));
  // Open and Paste: on the empty state while it shows, in the toolbar once a document is open
  ok(await gone(bar, '#btnOpen, #btnPaste') && await shown(bar, '.empty-state [data-act="open"], .empty-state [data-act="paste"]'), 'empty state: Open and Paste are on the page, and the toolbar pair is hidden');
  let chooser = bar.waitForEvent('filechooser'); await bar.keyboard.press('Control+o');
  await (await chooser).setFiles(mdFile('one.md', '# One\n'));
  await bar.waitForFunction(() => document.querySelectorAll('#tabs .tab').length === 1);
  ok(await bar.$eval('#doc h1', h => h.textContent.startsWith('One')), 'empty state: Ctrl/⌘ O still opens a file');
  ok(await shown(bar, '#btnOpen, #btnPaste') && await bar.$$eval('.empty-state', n => n.length) === 0, 'with a document open, the toolbar shows Open and Paste');
  chooser = bar.waitForEvent('filechooser'); await bar.click('#btnOpen');
  await (await chooser).setFiles(mdFile('two.md', '# Two\n'));
  await bar.waitForFunction(() => document.querySelectorAll('#tabs .tab').length === 2);
  chooser = bar.waitForEvent('filechooser'); await bar.keyboard.press('Control+o');
  await (await chooser).setFiles(mdFile('three.md', '# Three\n'));
  await bar.waitForFunction(() => document.querySelectorAll('#tabs .tab').length === 3);
  ok(await bar.$eval('#doc h1', h => h.textContent.startsWith('Three')), 'with a document open, the toolbar Open and Ctrl/⌘ O both open a file');
  await bar.evaluate(() => navigator.clipboard.writeText('# Pasted from the clipboard\n'));
  await bar.click('#btnPaste'); await bar.waitForTimeout(300);
  const viaButton = await tabCount();
  await bar.keyboard.press('Control+v'); await bar.waitForTimeout(300);
  ok(viaButton === 4 && await tabCount() === 5 && await bar.$eval('#doc h1', h => h.textContent.startsWith('Pasted from the clipboard')), 'with a document open, the toolbar Paste and Ctrl/⌘ V on the page each add a tab');
  for (let i = 0; i < 5; i++) await bar.click('#tabs .tab .x');
  ok(await tabCount() === 0 && await gone(bar, '#btnOpen, #btnPaste') && await shown(bar, '.empty-state [data-act="open"], .empty-state [data-act="paste"]'), 'closing the last tab brings the empty state back and hides the toolbar pair again');
  await bar.keyboard.press('Control+v'); await bar.waitForTimeout(300);
  ok(await tabCount() === 1, 'empty state: Ctrl/⌘ V on the page still opens a tab');
  await bar.click('#tabs .tab .x'); await bar.click('.empty-state [data-act="paste"]'); await bar.waitForTimeout(300);
  await dropMd('drop.md', '# Dropped\n\ntext\n'); await bar.waitForTimeout(400);
  ok(await tabCount() === 2 && await bar.$eval('#doc h1', h => h.textContent.startsWith('Dropped')), 'empty state: its Paste button works, and a dropped file opens in either state');

  // Export: one click on the main part is the Ctrl/⌘ S export; the caret part holds the other four exports, and does not repeat it
  const grab = async act => { const d = bar.waitForEvent('download'); await act(); const got = await d; return { name: got.suggestedFilename(), body: fs.readFileSync(await got.path(), 'utf8') }; };
  const byClick = await grab(() => bar.click('#btnExport'));
  ok(await bar.$eval('#popExport', p => p.dataset.open !== 'true') && byClick.name === 'drop.html' && /<h1[^>]*>Dropped<\/h1>/.test(byClick.body), 'Export exports in one click, with no menu in between');
  const byKey = await grab(() => bar.keyboard.press('Control+s'));
  ok(byClick.name === byKey.name && byClick.body === byKey.body, 'the one-click export is the same file Ctrl/⌘ S makes');
  const names = await bar.$$eval('#btnExport, #btnExportMenu', b => b.map(e => (e.getAttribute('aria-label') || e.textContent).trim()));
  ok(names.length === 2 && names.every(Boolean) && names[0] !== names[1], `the two parts have their own names (${names.join(' / ')})`);
  await bar.focus('#btnExportMenu'); await bar.keyboard.press('Enter');
  ok(await bar.$eval('#btnExportMenu', b => b.getAttribute('aria-expanded')) === 'true' && await shown(bar, '#popExport [data-do]')
    && (await bar.$$eval('#popExport [data-do]', b => b.map(e => e.dataset.do).join())) === 'copyhtml,pdf,md,copymd', 'the caret opens the menu by keyboard, with the four other exports and no second HTML download');
  await bar.keyboard.press('Tab');
  const firstItem = await bar.evaluate(() => document.activeElement.dataset.do);
  await bar.keyboard.press('Escape');
  ok(firstItem === 'copyhtml' && await gone(bar, '#popExport [data-do]') && await bar.evaluate(() => document.activeElement.id === 'btnExportMenu' && document.activeElement.getAttribute('aria-expanded') === 'false'), 'Tab reaches the menu, Escape closes it and hands focus back to the caret');

  // Reader settings: the everyday controls on top, the rest behind one disclosure, Markdown handling in its own group
  await bar.click('#btnRead');
  ok(await bar.$eval('#btnRead', b => b.getAttribute('aria-expanded')) === 'true' && await bar.$eval('#moreRead', d => d.open === false)
    && await shown(bar, '#skins .skin, #popRead [data-set="theme"], #popRead [data-set="size"], #moreRead > summary, #cleanLLM, #rawHtml, #btnReset')
    && await gone(bar, '#popRead [data-set="font"], #popRead [data-set="lh"], #popRead [data-set="measure"]'), 'Reader settings opens with the disclosure closed: skin, mode, size and the Markdown group show; typeface, line height and width wait behind it');
  ok(await bar.$$eval('#popRead [data-set], #popRead [data-c], #popRead input[type=checkbox], #popRead button[id]', n => [...new Set(n.map(e => e.dataset.set || e.dataset.c || e.id))].sort().join())
    === 'accent,btnFromSkin,btnImportBrand,btnReset,cleanLLM,doc,font,ink,lh,measure,mono,paper,radius,rawHtml,sheet,size,theme,ui', 'every reader setting is still there');
  await bar.focus('#moreRead > summary'); await bar.keyboard.press('Enter');
  ok(await bar.$eval('#moreRead', d => d.open) && await shown(bar, '#popRead [data-set="font"], #popRead [data-set="lh"], #popRead [data-set="measure"]'), 'the disclosure opens by keyboard');
  const cssVarB = v => bar.evaluate(n => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), v);
  const slide = (k, v) => bar.$eval(`#popRead [data-set="${k}"]`, (e, val) => { e.value = val; e.dispatchEvent(new Event('input', { bubbles: true })); }, v);
  await bar.click('#popRead [data-set="font"] [data-v="serif"]'); await slide('lh', '1.9'); await slide('measure', '90'); await slide('size', '20');
  ok((await cssVarB('--doc-font')).includes('Newsreader') && await cssVarB('--doc-lh') === '1.9' && await cssVarB('--measure') === '90ch' && await cssVarB('--doc-size') === '20px', 'typeface, line height, width and size still take effect from their new places');
  await dropMd('raw.md', 'one\\ntwo\\nthree <em>kept</em>\n'); await bar.waitForTimeout(400);
  const rawOn = await bar.$eval('#doc', d => ({ em: !!d.querySelector('em'), slash: d.textContent.includes('\\n') }));
  await bar.click('#cleanLLM'); await bar.click('#rawHtml'); await bar.waitForTimeout(300);
  const rawOff = await bar.$eval('#doc', d => ({ em: !!d.querySelector('em'), slash: d.textContent.includes('\\n') }));
  ok(rawOn.em && !rawOn.slash && !rawOff.em && rawOff.slash, 'Clean LLM paste and Allow raw HTML still change how the document is read in');
  await bar.keyboard.press('Escape');
  const oneEsc = await bar.evaluate(() => ({ more: document.querySelector('#moreRead').open, pop: document.querySelector('#popRead').dataset.open }));
  ok(oneEsc.more === true && oneEsc.pop === 'false' && await bar.evaluate(() => document.activeElement.id === 'btnRead'), 'Escape outside the disclosure closes the popover and hands focus back to its button');
  await bar.click('#btnRead'); await bar.focus('#popRead [data-set="lh"]'); await bar.keyboard.press('Escape');
  ok(await bar.evaluate(() => !document.querySelector('#moreRead').open && document.querySelector('#popRead').dataset.open === 'true' && document.activeElement.matches('#moreRead > summary')), 'Escape inside the open disclosure closes the disclosure first');
  await bar.reload({ waitUntil: 'domcontentloaded' }); await bar.waitForTimeout(700);
  let st2 = await saved();
  ok(st2.font === 'serif' && st2.lh === 1.9 && st2.measure === 90 && st2.size === 20 && st2.cleanLLM === false && st2.rawHtml === false
    && await bar.$eval('#popRead [data-set="lh"]', e => e.value) === '1.9' && await bar.$eval('#rawHtml', e => e.checked) === false && await bar.$eval('#moreRead', d => d.open === false), 'the moved settings persist across a reload, and the disclosure starts closed again');
  await bar.$eval('#btnReset', b => b.click()); await bar.waitForTimeout(200);
  ok(await cssVarB('--doc-lh') === '1.65' && await cssVarB('--measure') === '70ch' && await cssVarB('--doc-size') === '17px' && await bar.$eval('#popRead [data-set="font"] [data-v="skin"]', b => b.getAttribute('aria-pressed')) === 'true', 'Reset reader settings still restores the defaults');

  // light and dark: the toolbar switch flips between the two, Mode adds Auto; they are one setting and stay in step
  const themeNow = () => bar.evaluate(() => ({ set: document.documentElement.dataset.theme, scheme: document.documentElement.style.colorScheme, mode: document.querySelector('#popRead [data-set="theme"] [aria-pressed="true"]').dataset.v, tip: document.querySelector('#btnTheme').title }));
  const t0 = await themeNow();
  await bar.click('#btnTheme'); const t1 = await themeNow();
  await bar.click('#btnTheme'); const t2 = await themeNow();
  await bar.$eval('#popRead [data-set="theme"] [data-v="auto"]', b => b.click()); const t3 = await themeNow();
  ok(t0.set === 'auto' && t0.mode === 'auto' && t1.scheme !== t0.scheme && t1.set === t1.scheme && t1.mode === t1.set && t2.scheme === t0.scheme && t2.mode === t2.set
    && t3.set === 'auto' && t3.mode === 'auto' && /auto/.test(t3.tip) && t1.tip.includes(t1.set), `the toolbar switch changes the page on its first click (${t0.scheme} → ${t1.scheme}) and Mode follows it; Auto is still offered in Mode`);

  // tab lock: the lock button and the refusal stay; a double-click on the tab no longer locks it
  await dropMd('keep.md', '# Keep\n'); await bar.waitForTimeout(300);
  const keep = '#tabs .tab[aria-selected="true"]';
  await bar.dblclick(keep + ' span'); await bar.waitForTimeout(200);
  const afterDbl = await bar.$eval(keep, t => t.dataset.locked);
  await bar.click(keep + ' .lk'); await bar.waitForTimeout(200);
  const afterLock = await bar.$eval(keep, t => t.dataset.locked);
  const before = await tabCount();
  await bar.$eval(keep + ' .x', b => b.click()); await bar.waitForTimeout(200);   // the close button is hidden on a locked tab; a scripted click still must be refused
  ok(afterDbl === 'false' && afterLock === 'true' && await tabCount() === before && (await bar.$eval('#toast', t => t.textContent)).includes('is locked'), 'a tab locks from its lock button only, and a locked tab still refuses to close and says why');
  await bar.click(keep + ' .lk'); await bar.waitForTimeout(200);
  ok(await bar.$eval(keep, t => t.dataset.locked) === 'false', 'the lock button unlocks it again');
  ok(barErrs.length === 0, 'Zest MD, simpler bar: no exceptions (' + barErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await barCtx.close();
  }

  console.log('== Zest MD without the sanitizer: raw HTML fails closed ==');
  const mdOff = await ctx.newPage();
  await mdOff.route(/^https?:\/\/(?!(localhost|127\.0\.0\.1)[:/])/, r => r.abort());
  await mdOff.route(/\/vendor\/dompurify\//, r => r.abort());   // the sanitizer's own file, refused
  await mdOff.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await mdOff.waitForTimeout(600);
  await mdOff.evaluate(t => { const dt = new DataTransfer(); dt.items.add(new File([t], 'evil.md', { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, PAYLOAD);
  await mdOff.waitForTimeout(600);
  ok(await mdOff.evaluate(() => window.__pwned === undefined), 'no sanitizer → no handler execution either');
  ok(await mdOff.$$eval('#doc img, #doc iframe', n => n.length) === 0, 'no sanitizer → raw HTML is escaped, never parsed (fail closed)');
  await mdOff.evaluate(t => { const dt = new DataTransfer(); dt.items.add(new File([t], 'toc.md', { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, TOC_PAYLOAD);
  await mdOff.waitForTimeout(600);
  ok(await mdOff.evaluate(() => window.__pwned === undefined) && await mdOff.$$eval(TOC_HOSTILE, n => n.length) === 0, 'no sanitizer → the Contents list is still plain links');
  await mdOff.close();

  console.log('== Zest MD: on-demand libraries are pinned by hash, and Mermaid is always configured strict ==');
  const MD_SRC = fs.readFileSync(require('path').join(__dirname, '..', 'apps', 'md', 'index.html'), 'utf8');
  // links that carry text are served from the page the service worker stored, so a fix reaches installed copies only if
  // the worker replaces that page: its version moved on from the one that stored the old page, and visits refresh it
  const MD_SW = fs.readFileSync(require('path').join(__dirname, '..', 'apps', 'md', 'sw.js'), 'utf8');
  ok(/const VERSION = 'mdpress-v(\d+)'/.test(MD_SW) && +MD_SW.match(/const VERSION = 'mdpress-v(\d+)'/)[1] >= 5, 'Zest MD: the service worker version moved on, so installed copies fetch the fixed page');
  ok(/c\.put\(APP_INDEX, shell\)/.test(MD_SW), 'Zest MD: a visit refreshes the stored page that shared links are served from');
  const vendorUrls = MD_SRC.match(/'\.\.\/vendor\/(?:katex|mermaid)\/[^']+'/g) || [];
  const vendorHashed = MD_SRC.match(/'\.\.\/vendor\/(?:katex|mermaid)\/[^']+', 'sha384-[A-Za-z0-9+/]{64}'/g) || [];
  ok(vendorUrls.length === 4 && vendorHashed.length === 4, `every on-demand file is listed with a sha384 (${vendorHashed.length} of ${vendorUrls.length})`);
  ok(!/cdnjs|unpkg|jsdelivr|fonts\.googleapis|fonts\.gstatic/.test(MD_SRC), 'Zest MD names no CDN or font host: every library and face is vendored');
  // A stand-in for the library (the real one is 3.5 MB and not a test dependency). If it runs, it records how the app configures it.
  const STANDIN = 'window.__mermaidLevels=[];window.mermaid={initialize:function(c){window.__mermaidLevels.push(c&&c.securityLevel)},run:async function(){}};';
  const SRI = e => /^sha384-[A-Za-z0-9+/]{64}$/.test(e.integrity) && e.crossOrigin === 'anonymous';
  const dropMd = (p, name, text) => p.evaluate(([n, t]) => { const dt = new DataTransfer(); dt.items.add(new File([t], n, { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, [name, text]);
  const DIAGRAM = '# Diagram\n\n```mermaid\nflowchart LR\n  A[Start] --> B[End]\n```\n';

  // First the loader. The stand-in is served at the app's own Mermaid address: it is not the pinned release, so it must be refused.
  const mdM = await ctx.newPage(); await block(mdM);
  await mdM.route(/\/vendor\/mermaid\/mermaid\.min\.js/, r => r.fulfill({ contentType: 'text/javascript', body: STANDIN }));
  const mdMErrs = []; mdM.on('pageerror', e => mdMErrs.push(e.message));
  await mdM.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await mdM.waitForTimeout(600);
  await dropMd(mdM, 'diagram.md', DIAGRAM); await mdM.waitForTimeout(800);                                  // the fence triggers the on-demand load
  ok(await mdM.$eval('script[src*="mermaid"]', SRI), 'the loader gives the Mermaid tag its integrity hash');
  ok(await mdM.evaluate(() => window.mermaid === undefined && window.__mermaidLevels === undefined), 'a file at the Mermaid address that is not the pinned release does not run');
  ok(await mdM.$$eval('#doc .mermaid', n => n.length) === 0 && await mdM.$$eval('#doc pre[data-lang^="mermaid"]', n => n.length) === 1, 'the diagram stays a plain code block when the library is refused');
  await dropMd(mdM, 'math.md', '# Math\n\n$$x^2$$\n'); await mdM.waitForTimeout(600);                        // same loader, KaTeX (the vendored release, which loads)
  ok(await mdM.$eval('link[href*="katex.min.css"]', SRI) && await mdM.$eval('script[src*="katex.min.js"]', SRI), 'the loader gives the KaTeX stylesheet and script their integrity hashes');
  ok(mdMErrs.length === 0, 'Zest MD with a refused library: no exceptions (' + mdMErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await mdM.close();

  // Then the configuration. The stand-in is defined before the page's own scripts run, as the loaded library would be.
  const mdS = await ctx.newPage(); await block(mdS);
  await mdS.addInitScript(STANDIN);
  const mdSErrs = []; mdS.on('pageerror', e => mdSErrs.push(e.message));
  await mdS.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await mdS.waitForTimeout(600);
  await dropMd(mdS, 'diagram.md', DIAGRAM); await mdS.waitForTimeout(600);
  ok(await mdS.$$eval('#doc pre.mermaid', n => n.length) === 1, 'with the library present the fence is handed to it');
  await mdS.$eval('#popRead [data-set="theme"] [data-v="dark"]', b => b.click()); await mdS.waitForTimeout(300);   // a theme change configures it again
  const levels = await mdS.evaluate(() => window.__mermaidLevels || []);
  ok(levels.length >= 2 && levels.every(l => l === 'strict'), `every Mermaid initialize call asks for securityLevel strict (${levels.join(', ') || 'none recorded'})`);
  ok((MD_SRC.match(/mermaid\.initialize\(/g) || []).length === 1, 'Mermaid is configured in exactly one place');
  ok(!/securityLevel\s*:\s*['"](loose|antiscript)['"]/.test(MD_SRC), 'no code path asks Mermaid for a looser mode');
  ok(mdSErrs.length === 0, 'Zest MD with diagrams: no exceptions (' + mdSErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await mdS.close();

  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
