// Deploy topology (§8/§11.5): one origin — studio at /, tools at /mail /md /image,
// store at /pricing. Serve: `bash zest/build.sh` then dist/ on :8780.
const { chromium } = require('playwright');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {}; // point at a system Chromium when the local playwright has no downloaded browsers
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.error('  FAIL ' + m); } };
const ORIGIN = 'http://localhost:8780';
(async () => {
  const browser = await chromium.launch(LAUNCH);
  const ctx = await browser.newContext({ serviceWorkers: 'block' });
  const block = p => p.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());

  console.log('== structure: every path serves its app ==');
  const get = async p => { const r = await fetch(ORIGIN + p, { redirect: 'manual' }); return r; };
  ok((await get('/')).status === 200, '/ serves');
  const redir = await get('/mail');
  ok([301, 308].includes(redir.status) && /\/mail\/$/.test(redir.headers.get('location') || ''), '/mail redirects to /mail/ (trailing slash — relative assets depend on it)');
  for (const [p, marker] of [['/mail/', 'ZestMail'], ['/md/', 'Zest MD'], ['/image/', 'ZestImage'], ['/pricing/', 'Zest']]) {
    const r = await get(p); const t = await r.text();
    ok(r.status === 200 && t.includes(marker), `${p} serves its app (${marker})`);
  }
  for (const p of ['/sw.js', '/md/sw.js', '/image/sw.js', '/icons/favicon.svg', '/mail/icons/favicon.svg', '/md/icons/favicon.svg', '/image/icons/favicon.svg', '/zest.json', '/mail/zest.json']) {
    ok((await get(p)).status === 200, `${p} present`);
  }
  const swText = await (await get('/sw.js')).text();
  ok(swText.includes('siblingPath'), 'studio sw keeps its sibling-path guard (never serves its shell for /mail /md /image)');
  ok(/mail\|md\|image\|api\|pricing\|account\|changelog/.test(swText), 'the guard covers the store paths this topology creates (/pricing + future /account /changelog)');
  ok((await get('/mail/api/claude.js')).status === 404 || (await get('/mail/api/claude.js')).status === 301, 'the api source is not published as a static file under /mail');

  console.log('== the home page: studio + §11.5 tools row ==');
  const st = await ctx.newPage(); await block(st);
  const errs = []; st.on('pageerror', e => errs.push(e.message));
  await st.goto(ORIGIN + '/', { waitUntil: 'domcontentloaded' }); await st.waitForTimeout(700);
  ok((await st.title()).includes('Zest'), 'studio is the home page');
  ok(await st.$$eval('.role', r => r.length) === 7, 'the palette tool is working, no signup (§11.5)');
  ok(await st.$eval('#tools', e => !!e), 'tools row exists');
  const links = await st.$$eval('#tools .tool', a => a.map(x => x.getAttribute('href')));
  ok(JSON.stringify(links) === JSON.stringify(['mail/', 'md/', 'image/']), `tools row carries the three tools (${links.join(' ')})`);
  ok(await st.$eval('#tools .lab a[href="pricing/"]', e => !!e), 'pricing is a link on the label row — not passed off as a tool');
  ok(await st.$eval('header a[href="#tools"]', e => !!e), 'header Tools is an in-page anchor now');
  ok(await st.$$eval('#tools .tool img', i => i.every(x => x.complete && x.naturalWidth > 0)), 'tool marks load (each app’s own favicon)');

  console.log('== the handoff still works same-origin ==');
  await st.click('.pcell:nth-child(3)'); await st.waitForTimeout(300);     // Pantry
  const dl = st.waitForEvent('download'); await st.click('#xBrand');
  const brand = require('fs').readFileSync(await (await dl).path(), 'utf8');
  const zi = await ctx.newPage(); await block(zi);
  const ziErrs = []; zi.on('pageerror', e => ziErrs.push(e.message));
  await zi.goto(ORIGIN + '/image/', { waitUntil: 'domcontentloaded' }); await zi.waitForTimeout(600);
  await zi.evaluate(j => { const dt = new DataTransfer(); dt.items.add(new File([j], 'pantry-zest-brand.json', { type: 'application/json' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, brand);
  await zi.waitForTimeout(700);
  ok((await zi.$eval('#stageSvg', e => e.innerHTML)).includes('#5f7a0d'), 'brand exported at / re-skins /image/ on the same origin');
  ok(ziErrs.length === 0 && errs.length === 0, 'no exceptions on either page');
  await zi.close(); await st.close();

  console.log('== the other pages boot clean under their paths ==');
  for (const p of ['/mail/', '/md/', '/pricing/']) {
    const pg = await ctx.newPage(); await block(pg);
    const es = []; pg.on('pageerror', e => es.push(e.message));
    await pg.goto(ORIGIN + p, { waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(600);
    ok(es.length === 0, `${p} boots with no exceptions (${es.slice(0, 1).join('').slice(0, 60)})`);
    await pg.close();
  }
  const store = await ctx.newPage(); await block(store);
  await store.goto(ORIGIN + '/pricing/', { waitUntil: 'domcontentloaded' });
  ok(await store.$eval('nav a[href="/"]', e => e.textContent === 'Studio'), 'store nav links back to the studio home');
  await store.close();

  console.log('== PWA identity under the topology (round 1 regressions) ==');
  const live = await browser.newContext();                     // real service workers this time
  for (const [p, scopeEnd] of [['/', '/'], ['/md/', '/md/'], ['/image/', '/image/']]) {
    const pg = await live.newPage();
    await pg.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort()); // live SWs, but still no live CDN
    await pg.goto(ORIGIN + p, { waitUntil: 'domcontentloaded' });
    const scope = await pg.evaluate(() => Promise.race([
      navigator.serviceWorker.ready.then(r => r.scope),
      new Promise(res => setTimeout(() => res('TIMEOUT'), 8000)),
    ]));
    ok(scope === ORIGIN + scopeEnd, `${p} registers ITS OWN worker at ITS scope (${scope})`);
    await pg.close();
  }
  await live.close();
  for (const p of ['/md/', '/image/']) {
    const m = await (await get(p + 'manifest.webmanifest')).json();
    ok(m.start_url === './' && m.scope === './' && m.id === './' && m.icons.every(i => !i.src.startsWith('/')), `${p}manifest installs as its own app (scope-relative identity)`);
  }
  const mdManifest = await (await get('/md/manifest.webmanifest')).json();
  ok(mdManifest.file_handlers[0].action === './' && mdManifest.share_target.action === './', 'md file-handler and share-target actions stay inside /md/');
  const mdHead = await (await get('/md/')).text();
  ok(mdHead.includes('href="manifest.webmanifest"') && !mdHead.includes('href="/manifest.webmanifest"'), 'md head links are app-relative');

  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
