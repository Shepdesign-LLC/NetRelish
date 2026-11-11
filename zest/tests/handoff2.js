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
  const block = p => p.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort()); // no live CDN: every run sees the same page state, with or without egress

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
  ml.on('dialog', d => d.accept());
  await ml.goto('http://localhost:8773', { waitUntil: 'domcontentloaded' }); await ml.waitForTimeout(700);
  const brandCount0 = await ml.$$eval('#brandSel option', o => o.length);
  ok(await ml.$eval('#brandImport', b => b.offsetParent !== null || !!b.closest('.panel')), 'Import zest-brand.json button exists in the Brand panel');
  await ml.setInputFiles('#brandFile', { name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf });
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
  await ml.setInputFiles('#brandFile', { name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf });
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
  await ml.setInputFiles('#brandFile', { name: 'i-zest-brand.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(inj)) });
  await ml.waitForTimeout(400);
  const injStack = await ml.$eval('[data-bk="font"]', e => e.value);
  ok(!/[&#;:(){}"]/.test(injStack), `numeric char refs cannot reach style attributes (${injStack.slice(0, 48)})`);
  const news = JSON.parse(JSON.stringify(brand)); news.name = 'Serif Brand';
  news.fonts = { head: 'Fraunces', body: 'Newsreader', mono: 'Geist Mono', googleFontsUrl: '', custom: [] };
  await ml.setInputFiles('#brandFile', { name: 'n-zest-brand.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(news)) });
  await ml.waitForTimeout(400);
  ok(/Newsreader.*Georgia/.test(await ml.$eval('[data-bk="font"]', e => e.value)), 'Newsreader classifies as serif (Georgia fallback)');
  await ml.click('#btnNew'); await ml.waitForTimeout(300);        // empty canvas: run() skips persist()
  await ml.setInputFiles('#brandFile', { name: 'pantry-zest-brand.json', mimeType: 'application/json', buffer: brandBuf });
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
  await ml.close();

  console.log('== Zest MD: custom-skin import ==');
  const md = await ctx.newPage(); await block(md);
  // serve the pinned DOMPurify from node_modules (package.json pins the same version the app's cdnjs tag loads) so the
  // sanitized-raw-HTML path is under test and the suite works offline; registered after block(),
  // so this more specific route wins while the rest of cdnjs stays aborted
  const PURIFY = fs.readFileSync(require.resolve('dompurify/dist/purify.min.js'));   // raw bytes: the script tag checks them against its integrity hash
  const CORS = { 'access-control-allow-origin': '*' };                                // the tag is crossorigin="anonymous", as cdnjs itself answers
  await md.route(/cdnjs\.cloudflare\.com.*dompurify/i, r => r.fulfill({ contentType: 'text/javascript', headers: CORS, body: PURIFY }));
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
  const htmlDl = md.waitForEvent('download'); await md.$eval('#popExport [data-do="html"]', b => b.click());
  const exportedHead = fs.readFileSync(await (await htmlDl).path(), 'utf8').split('<article')[0];
  ok(exportedHead.includes('--doc-size:17px;--doc-lh:1.65;--measure:70ch') && !/onerror|<img/i.test(exportedHead), 'the exported file is styled with the checked values only');
  await md.evaluate(x => { const s = JSON.parse(localStorage.getItem('mdpress:settings')); s.theme = 'light' + x; s.skin = 'constructor'; localStorage.setItem('mdpress:settings', JSON.stringify(s)); }, X);
  await md.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await md.waitForTimeout(700);
  ok(await md.evaluate(() => document.documentElement.dataset.theme) === 'auto' && await md.$eval('.skin[data-skin="press"]', e => e.getAttribute('aria-pressed')) === 'true', 'a mode or skin the app does not offer falls back to the default');
  ok(mdErrs.length === 0, 'Zest MD: no exceptions (' + mdErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await md.close();

  console.log('== Zest MD without the sanitizer: raw HTML fails closed ==');
  const mdOff = await ctx.newPage();
  await mdOff.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
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
  const vendorUrls = MD_SRC.match(/'https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/(?:KaTeX|mermaid)\/[^']+'/g) || [];
  const vendorHashed = MD_SRC.match(/'https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/(?:KaTeX|mermaid)\/[^']+', 'sha384-[A-Za-z0-9+/]{64}'/g) || [];
  ok(vendorUrls.length === 4 && vendorHashed.length === 4, `every on-demand file is listed with a sha384 (${vendorHashed.length} of ${vendorUrls.length})`);
  // A stand-in for the library (the real one is 3.5 MB and not a test dependency). If it runs, it records how the app configures it.
  const STANDIN = 'window.__mermaidLevels=[];window.mermaid={initialize:function(c){window.__mermaidLevels.push(c&&c.securityLevel)},run:async function(){}};';
  const SRI = e => /^sha384-[A-Za-z0-9+/]{64}$/.test(e.integrity) && e.crossOrigin === 'anonymous';
  const dropMd = (p, name, text) => p.evaluate(([n, t]) => { const dt = new DataTransfer(); dt.items.add(new File([t], n, { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, [name, text]);
  const DIAGRAM = '# Diagram\n\n```mermaid\nflowchart LR\n  A[Start] --> B[End]\n```\n';

  // First the loader. The stand-in is served at the app's own Mermaid address: it is not the pinned release, so it must be refused.
  const mdM = await ctx.newPage(); await block(mdM);
  await mdM.route(/cdnjs\.cloudflare\.com.*dompurify/i, r => r.fulfill({ contentType: 'text/javascript', headers: CORS, body: PURIFY }));
  await mdM.route(/cdnjs\.cloudflare\.com.*mermaid/i, r => r.fulfill({ contentType: 'text/javascript', headers: CORS, body: STANDIN }));
  const mdMErrs = []; mdM.on('pageerror', e => mdMErrs.push(e.message));
  await mdM.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await mdM.waitForTimeout(600);
  await dropMd(mdM, 'diagram.md', DIAGRAM); await mdM.waitForTimeout(800);                                  // the fence triggers the on-demand load
  ok(await mdM.$eval('script[src*="mermaid"]', SRI), 'the loader gives the Mermaid tag its integrity hash');
  ok(await mdM.evaluate(() => window.mermaid === undefined && window.__mermaidLevels === undefined), 'a file at the Mermaid address that is not the pinned release does not run');
  ok(await mdM.$$eval('#doc .mermaid', n => n.length) === 0 && await mdM.$$eval('#doc pre[data-lang^="mermaid"]', n => n.length) === 1, 'the diagram stays a plain code block when the library is refused');
  await dropMd(mdM, 'math.md', '# Math\n\n$$x^2$$\n'); await mdM.waitForTimeout(600);                        // same loader, KaTeX (its address is blocked like the rest of the CDN)
  ok(await mdM.$eval('link[href*="katex.min.css"]', SRI) && await mdM.$eval('script[src*="katex.min.js"]', SRI), 'the loader gives the KaTeX stylesheet and script their integrity hashes');
  ok(mdMErrs.length === 0, 'Zest MD with a refused library: no exceptions (' + mdMErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await mdM.close();

  // Then the configuration. The stand-in is defined before the page's own scripts run, as the loaded library would be.
  const mdS = await ctx.newPage(); await block(mdS);
  await mdS.route(/cdnjs\.cloudflare\.com.*dompurify/i, r => r.fulfill({ contentType: 'text/javascript', headers: CORS, body: PURIFY }));
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
