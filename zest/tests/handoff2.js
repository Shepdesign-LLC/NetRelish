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
  const block = p => p.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());

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
  ok(mlErrs.length === 0, 'ZestMail: no exceptions (' + mlErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await ml.close();

  console.log('== Zest MD: custom-skin import ==');
  const md = await ctx.newPage(); await block(md);
  // the proxy blocks cdnjs here — serve the pinned DOMPurify locally so the sanitized-raw-HTML path is the one under test
  const PURIFY = fs.readFileSync(require.resolve('dompurify/dist/purify.min.js'), 'utf8');
  await md.route(/cdnjs\.cloudflare\.com.*dompurify/i, r => r.fulfill({ contentType: 'text/javascript', body: PURIFY }));
  const mdErrs = []; md.on('pageerror', e => mdErrs.push(e.message));
  await md.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await md.waitForTimeout(700);
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
  ok(mdErrs.length === 0, 'Zest MD: no exceptions (' + mdErrs.slice(0, 1).join('').slice(0, 80) + ')');
  await md.close();

  console.log('== Zest MD without the sanitizer: raw HTML fails closed ==');
  const mdOff = await ctx.newPage();
  await mdOff.route(/fonts\.(googleapis|gstatic)\.com|dompurify/, r => r.abort());
  await mdOff.goto('http://localhost:8774', { waitUntil: 'domcontentloaded' }); await mdOff.waitForTimeout(600);
  await mdOff.evaluate(t => { const dt = new DataTransfer(); dt.items.add(new File([t], 'evil.md', { type: 'text/markdown' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, PAYLOAD);
  await mdOff.waitForTimeout(600);
  ok(await mdOff.evaluate(() => window.__pwned === undefined), 'no sanitizer → no handler execution either');
  ok(await mdOff.$$eval('#doc img, #doc iframe', n => n.length) === 0, 'no sanitizer → raw HTML is escaped, never parsed (fail closed)');
  await mdOff.close();

  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
