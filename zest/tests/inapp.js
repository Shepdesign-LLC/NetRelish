// In-app suite (ADR 0015; App Review 3.1.1 and 2.5.2; NN5): the four tools as NetRelish.app runs them.
//
// Part 1 serves the app's copy (Resources/Zest, or ZEST_APP_ROOT) on 127.0.0.1 at a free port and injects the
// host's frozen window.netrelish stub before any page script, in the main frame only, as the Zest window does.
// For each tool it checks that
//   - the in-app switch is on (html.in-app);
//   - nothing sells: no pricing link or text, no Upgrade, no Pro badge, no drafting with a model, and none of
//     those words or the model host anywhere in the shipped page;
//   - no service worker is registered (register is never even called);
//   - the web's plan is not in the app at all: no Pro row, no data-pro, no line about a Zest account (3.1.1, 2.1);
//   - nothing copies or links a zest: URL, which nothing outside the Zest window can open;
//   - the defaults are placeholders, not the maker's own name, company or address;
//   - an image at a web address shows as a placeholder that says why, and the export keeps the real <img>;
//   - the studio gets its desktop layout at the Zest window's default size (1180 wide);
//   - the type is the vendored faces, loaded from vendor/ on this origin (the UI's own faces, the studio's
//     preview frame, ZestImage's brand faces), and Zest MD's sanitizer and math load from there too;
//   - exports carry their fonts inside the file: no font host, no vendor/ path that breaks once saved;
//   - no request leaves 127.0.0.1, and no page throws.
//   - every file is served with the host's own headers (the Content-Security-Policy, nosniff and the table of
//     content types in Sources/Zest/ZestFiles.swift), and nothing in any frame is refused by that policy;
// Part 2 opens the web sources (run.js's ports 8771-8774) with the same stub: the run-time switch alone, before
// build.sh --app strips anything, hides the same parts.
//
//   node inapp.js [--shots <dir>]     also saves a 1180x820 screenshot of each tool in the app's copy
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(process.env.ZEST_APP_ROOT || path.join(__dirname, '..', '..', 'Resources', 'Zest'));
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {};
const shotsAt = process.argv.indexOf('--shots');
const SHOTS = shotsAt > 0 ? path.resolve(process.argv[shotsAt + 1]) : null;
// The host's response headers, read from the Swift source so this suite and the app can't drift apart.
const SWIFT = fs.readFileSync(path.join(__dirname, '..', '..', 'Sources', 'Zest', 'ZestFiles.swift'), 'utf8');
const CSP = (((SWIFT.match(/static let contentSecurityPolicy = \[([\s\S]*?)\]\.joined\(separator: "; "\)/) || [])[1] || '')
  .match(/"[^"]*"/g) || []).map(d => d.slice(1, -1)).join('; ');
const APP_TYPES = Object.fromEntries([...(((SWIFT.match(/static let mimeTypes: \[String: String\] = \[([\s\S]*?)\n    \]/) || [])[1]) || '')
  .matchAll(/"([a-z0-9]+)": "([^"]+)"/g)].map(m => ['.' + m[1], m[2]]));
const HOST_HEADERS = file => ({ 'content-type': APP_TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream',
  'content-security-policy': CSP, 'x-content-type-options': 'nosniff', 'cache-control': 'no-cache' });
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.error('  FAIL ' + m); } };

// The host's stub (Sources/Zest): frozen, main frame only. The recorder notes any service-worker registration.
const STUB = `(() => {
  if (window.top === window) Object.defineProperty(window, 'netrelish', { value: Object.freeze({ version: '0', host: 'app', network: false }), writable: false, configurable: false });
  window.__swCalls = 0;
  try { const sw = navigator.serviceWorker; if (sw) { const reg = sw.register.bind(sw); sw.register = (...a) => { window.__swCalls++; return reg(...a); }; } } catch {}
})();`;
// Every refusal by the policy, in any frame (the srcdoc previews too), kept on the top page.
const POLICY_WATCH = `(() => {
  let top; try { top = window.top; void top.document; } catch { top = window; }
  top.__refused = top.__refused || [];
  document.addEventListener('securitypolicyviolation', e => top.__refused.push(e.violatedDirective + ' ' + (e.blockedURI || 'inline')));
})();`;
// Words that sell, and the model host. "Crimson Pro" is a typeface, not a tier.
const SELLS = /pricing|upgrade|\bpro\b|draft with|claude|anthropic/i;
const visibleText = () => document.body.innerText.replace(/Crimson Pro/g, '');

function serve() {
  const srv = http.createServer((req, res) => {
    try {
      let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
      if (p.endsWith('/')) p += 'index.html';
      const file = path.join(ROOT, p);
      if (!file.startsWith(ROOT + path.sep) || !fs.existsSync(file)) { res.writeHead(404); return res.end('not found'); }
      if (fs.statSync(file).isDirectory()) { res.writeHead(301, { location: p + '/' }); return res.end(); }
      res.writeHead(200, HOST_HEADERS(file));
      fs.createReadStream(file).pipe(res);
    } catch { res.writeHead(400); res.end('bad request'); }
  });
  return new Promise(r => srv.listen(0, '127.0.0.1', () => r(srv)));
}

// Which faces loaded, and from where.
const fontsState = () => document.fonts.ready.then(() => ({
  loaded: [...document.fonts].filter(f => f.status === 'loaded').map(f => f.family.replace(/["']/g, '')),
  files: performance.getEntriesByType('resource').map(e => e.name).filter(n => /\.woff2$/.test(n)),
}));
// What is left of the web's plan: Pro rows and their fold, and any line about a Zest account.
const planLeft = () => {
  const rows = [...document.querySelectorAll('.pro, [data-pro], #cloudNote, #proFold, #proList')];
  const notes = [...document.querySelectorAll('.hint, p, small')].filter(h => h.checkVisibility() && /Zest account|Not in this version/.test(h.textContent));
  return { rows: rows.length, shown: rows.filter(e => e.checkVisibility()).length, notes: notes.length };
};
// Visible controls that would hand out a zest: URL (a link, or the studio's Share link).
const zestLinks = () => [...document.querySelectorAll('a[href], #xShare')].filter(e => e.checkVisibility() && (e.id === 'xShare' || /^zest:/i.test(e.getAttribute('href')))).length;

const TOOLS = [
  { name: 'studio', path: '/', ui: ['Geist', 'Bricolage Grotesque'] },
  { name: 'mail', path: '/mail/', ui: ['Geist'] },
  { name: 'md', path: '/md/', ui: ['Geist'] },
  { name: 'image', path: '/image/', ui: ['Geist', 'Bricolage Grotesque'] },
];

(async () => {
  if (!fs.existsSync(path.join(ROOT, 'index.html'))) { console.error(`inapp: ${ROOT} is not built (bash zest/build.sh --app)`); process.exit(2); }
  ok(/^default-src /.test(CSP) && /script-src [^;]*'unsafe-inline'/.test(CSP) && !/unsafe-eval/.test(CSP) && APP_TYPES['.woff2'] === 'font/woff2' && APP_TYPES['.js'],
    `the host's policy and content types are read from ZestFiles.swift (${CSP.split('; ').length} directives, ${Object.keys(APP_TYPES).length} types)`);
  const shipped = [...new Set(fs.readdirSync(ROOT, { recursive: true }).filter(f => fs.statSync(path.join(ROOT, f)).isFile() && path.extname(f)).map(f => path.extname(f).toLowerCase()))];
  ok(shipped.every(e => APP_TYPES[e]), `the host has a content type for every extension in the app's copy (${shipped.sort().join(' ')})`);
  if (SHOTS) fs.mkdirSync(SHOTS, { recursive: true });
  const srv = await serve();
  const origin = `http://127.0.0.1:${srv.address().port}`;
  const browser = await chromium.launch(LAUNCH);

  for (const t of TOOLS) {
    console.log(`== app copy: ${t.name} (${t.path}) ==`);
    const ctx = await browser.newContext({ viewport: { width: 1180, height: 820 }, acceptDownloads: true });   // service workers allowed: one would register if asked
    const away = [];
    await ctx.route('**/*', r => { const u = r.request().url(); if (u.startsWith(origin + '/') || /^(data|blob):/.test(u)) return r.continue(); away.push(u); return r.abort('blockedbyclient'); });
    await ctx.addInitScript(STUB);
    await ctx.addInitScript(POLICY_WATCH);
    const pg = await ctx.newPage();
    const errs = []; pg.on('pageerror', e => errs.push(e.message));
    const refusedLog = []; pg.on('console', m => { if (/Content Security Policy|Refused to/i.test(m.text())) refusedLog.push(m.text()); });
    await pg.goto(origin + t.path, { waitUntil: 'load' }); await pg.waitForTimeout(900);

    ok(await pg.evaluate(() => document.documentElement.classList.contains('in-app') && window.ZEST_IN_APP === true), `${t.name}: the in-app switch is on`);
    const src = fs.readFileSync(path.join(ROOT, t.path, 'index.html'), 'utf8');
    ok(!/pricing|\bupgrade[sd]?\b|api\.anthropic\.com|api\/claude|serviceWorker\.register|manifest\.webmanifest|<em>PRO<\/em>/i.test(src), `${t.name}: the shipped page holds no pricing, Upgrade, Pro badge, model call, service worker or install manifest`);
    const text = await pg.evaluate(visibleText);
    ok(!SELLS.test(text), `${t.name}: nothing on screen sells or drafts with a model (${(text.match(SELLS) || ['none'])[0]})`);
    ok(await pg.$$eval('a[href]', as => as.every(a => !/pricing|zest\.netrelish\.com|^https?:/i.test(a.getAttribute('href')))), `${t.name}: no link to pricing or to the web`);
    ok(await pg.evaluate(() => window.__swCalls) === 0 && (await pg.evaluate(() => navigator.serviceWorker ? navigator.serviceWorker.getRegistrations().then(r => r.length) : 0)) === 0, `${t.name}: no service worker is registered`);
    const plan = await pg.evaluate(planLeft);
    ok(plan.rows === 0 && plan.notes === 0, `${t.name}: the web's plan is not in the app: no Pro row, no data-pro, no line about a Zest account (${plan.rows} row(s), ${plan.notes} line(s))`);
    ok(!/data-pro|Zest account|Not in this version|id="cloudNote"/.test(src), `${t.name}: the shipped page holds no Pro row or account line`);
    ok(await pg.evaluate(zestLinks) === 0, `${t.name}: no visible control links or copies a zest: URL`);
    ok(!/Ryan|Shepherd|Phoenix|Shepdesign LLC/.test(await pg.evaluate(() => [...document.querySelectorAll('input, textarea')].map(i => i.value).join(' ') + document.body.innerText)), `${t.name}: the defaults are placeholders, not the maker's own details`);
    if (t.name === 'mail') {
      ok(await pg.$$eval('[data-t="claude"], #panelClaude, #btnDraft, #apiKey', n => n.length) === 0, 'mail: no drafting tab, panel, button or key field');
      ok(await pg.$eval('#brandPill', e => e.textContent) === 'Your brand', 'mail: the first brand is a placeholder');
      const WEB = 'https://example.com/hero.png';
      await pg.evaluate(u => localStorage.setItem('mailpress:draft', JSON.stringify({ blocks: [{ id: 'webimg', type: 'image', props: { src: u, alt: 'Product hero', link: '', width: 'full', align: 'center', bg: 'brand.sheet', pad: 0 } }] })), WEB);
      await pg.reload({ waitUntil: 'load' }); await pg.waitForTimeout(700);
      const onCanvas = await pg.evaluate(() => { const p = document.querySelector('#canvas .web-img'); return p ? { h: Math.round(p.getBoundingClientRect().height), seen: p.checkVisibility(), text: p.textContent, imgs: document.querySelectorAll('#canvas img[src^="http"]').length } : null; });
      ok(onCanvas && onCanvas.seen && onCanvas.h > 0 && onCanvas.imgs === 0 && /doesn’t load images from the web/.test(onCanvas.text), `mail: an image at a web address is a placeholder on the canvas that says why (${onCanvas ? onCanvas.h + 'px' : 'none'})`);
      await pg.click('#viewSeg button[data-w="600"]'); await pg.waitForTimeout(700);
      const inPreview = await pg.evaluate(() => { const d = document.querySelector('#frame').contentDocument, p = d && d.querySelector('.web-img'); return p ? { h: Math.round(p.getBoundingClientRect().height), imgs: d.querySelectorAll('img[src^="http"]').length } : null; });
      ok(inPreview && inPreview.h > 0 && inPreview.imgs === 0, `mail: and in the Desktop preview (${inPreview ? inPreview.h + 'px' : 'none'})`);
      await pg.click('#btnExport'); await pg.waitForTimeout(150);
      const [dl] = await Promise.all([pg.waitForEvent('download'), pg.click('#popExport [data-do="download"]')]);
      const html = fs.readFileSync(await dl.path(), 'utf8');
      ok(html.includes(`src="${WEB}"`) && !/web-img|doesn’t load images/.test(html), 'mail: the exported email keeps the real <img>');
      // Comments are preserved by compilation, but must never be scanned as image tags.
      // The old regex repeatedly scanned this suffix (quadratic), blocking Source's UI.
      const prefixes = '<img '.repeat(64000);
      const comment = `<!--${prefixes}-->`;
      const hidden = `<!--[if mso]><img src="${WEB}" width="200"><![endif]-->`;
      const inline = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
      await pg.click('#modeSeg [data-m="source"]');
      const started = Date.now();
      await pg.fill('#src', `<div>${comment}${hidden}<p>Placeholder regression</p><img src='${WEB}?a=1&amp;b=&quot;safe&quot;' width='200'><img src="${inline}" width="1"></div>`);
      await pg.waitForFunction(() => document.querySelector('#frame').contentDocument?.body?.textContent.includes('Placeholder regression'), null, { timeout: 5000 });
      const elapsed = Date.now() - started;
      ok(elapsed < 5000, `mail: Source previews 64,000 incomplete image prefixes without hanging (${elapsed}ms including debounce)`);
      for (const view of ['600', '375', 'outlook']) {
        await pg.click(`#viewSeg [data-w="${view}"]`);
        await pg.waitForTimeout(400);
        const preview = await pg.evaluate(() => {
          const d = document.querySelector('#frame').contentDocument;
          const comments = [], walk = d.createTreeWalker(d, NodeFilter.SHOW_COMMENT);
          while (walk.nextNode()) comments.push(walk.currentNode.data);
          const p = d.querySelector('.web-img');
          return { comments, title: p?.title, width: p?.style.width, height: p?.style.height,
            placeholders: d.querySelectorAll('.web-img').length, imgs: [...d.images].map(i => i.getAttribute('src')),
            document: d.compatMode === 'CSS1Compat' && !!d.head.querySelector('meta[name="viewport"]') };
        });
        ok(preview.comments.includes(prefixes) && preview.comments.includes(hidden.slice(4, -3)), `mail: ${view} leaves large and conditional comments untouched`);
        ok(preview.placeholders === 1 && preview.title === `${WEB}?a=1&b="safe"` && preview.width === '200px' && preview.height === '100px', `mail: ${view} replaces only the actual web image, keeping its dimensions and escaped URL`);
        ok(preview.imgs.length === 1 && preview.imgs[0] === inline && preview.document, `mail: ${view} keeps inline images, document head and standards mode`);
      }
      await pg.click('#btnExport');
      const [sourceDownload] = await Promise.all([pg.waitForEvent('download'), pg.click('#popExport [data-do="download"]')]);
      const sourceHTML = fs.readFileSync(await sourceDownload.path(), 'utf8');
      ok(sourceHTML.includes(comment) && sourceHTML.includes(hidden) && sourceHTML.includes(`src="${WEB}?a=1&amp;b=&quot;safe&quot;"`) && !sourceHTML.includes('web-img'), 'mail: Source export retains comments and real images, never placeholders');
    }

    const fonts = await pg.evaluate(fontsState);
    for (const fam of t.ui) ok(fonts.loaded.includes(fam), `${t.name}: ${fam} loads`);
    ok(fonts.files.length > 0 && fonts.files.every(u => u.startsWith(origin + '/vendor/fonts/')), `${t.name}: every face comes from vendor/fonts on this origin (${fonts.files.length} file(s))`);

    if (t.name === 'studio') {
      const cols = await pg.evaluate(() => getComputedStyle(document.querySelector('.app')).gridTemplateColumns.split(' ').length);
      ok(cols === 3, `studio: at the Zest window's default 1180 wide, the studio has its three columns (${cols})`);
      ok(await pg.$$eval('#xShare', n => n.length) === 0 && await pg.$eval('#xFontface', b => b.checkVisibility() && b.getBoundingClientRect().width > 200), 'studio: no Share link; @font-face takes the row');
      const frame = pg.frames().find(f => f !== pg.mainFrame());
      const pf = frame ? await frame.evaluate(fontsState) : { loaded: [] };
      ok(pf.loaded.includes('Bricolage Grotesque') && pf.loaded.includes('Geist'), `studio: the preview frame sets the brand in its own faces (${[...new Set(pf.loaded)].join(', ')})`);
      const [dl] = await Promise.all([pg.waitForEvent('download'), pg.click('#xFontface')]);
      const css = fs.readFileSync(await dl.path(), 'utf8');
      ok(/@font-face\{font-family:'Bricolage Grotesque'[^}]*data:font\/woff2;base64,/.test(css) && /font-family:'Geist'/.test(css) && !/@import|url\(\s*['"]?(https?:|\/\/)/.test(css), `studio: the @font-face export embeds the brand's faces and loads from no host (${Math.round(css.length / 1024)} KB)`);
      const [db] = await Promise.all([pg.waitForEvent('download'), pg.click('#xBrand')]);
      const brand = JSON.parse(fs.readFileSync(await db.path(), 'utf8'));
      ok(brand.fonts && brand.fonts.googleFontsUrl === '' && !/https?:/.test(JSON.stringify(brand.fonts)), 'studio: the brand file names no font host');
    }
    if (t.name === 'image') {
      const im = await pg.evaluate(() => ({ byline: document.querySelector('#cByline').value, count: document.querySelector('#brandCount').textContent }));
      ok(im.byline === 'Your name · your-site.example' && !/ of \d/.test(im.count), `image: the byline is a placeholder and saved brands have no cap (${im.byline}; "${im.count}")`);
      await pg.waitForFunction(() => document.querySelector('#stageSvg text[data-role="title"]'), null, { timeout: 5000 }).catch(() => {});
      const st = await pg.evaluate(() => ({ fam: (document.querySelector('#stageSvg text[data-role="title"]') || { getAttribute: () => '' }).getAttribute('font-family'), note: document.querySelector('#fontNote').hidden }));
      ok(/^'[^']+'/.test(st.fam || '') && st.note, `image: the card is set in the brand's own face, read from vendor/ (${(st.fam || '').split(',')[0]})`);
    }
    if (t.name === 'md') {
      ok(await pg.evaluate(() => !!window.DOMPurify && (window.__mdpressMissing || []).length === 0), 'md: the sanitizer loads from vendor/ and matches its hash');
      await pg.click('[data-act="sample"]');
      await pg.waitForFunction(() => document.querySelector('#doc .katex') && document.querySelector('#doc .diagram svg'), null, { timeout: 10000 }).catch(() => {});
      ok(await pg.$$eval('#doc .katex', n => n.length) > 0, 'md: math renders (KaTeX from vendor/)');
      ok(await pg.$$eval('#doc .diagram svg', n => n.length) > 0, 'md: the diagram renders (Mermaid from vendor/)');
      const dg = await pg.evaluate(() => ({ diagrams: document.querySelectorAll('#doc .diagram').length, inPre: document.querySelectorAll('#doc pre .diagram').length, copies: [...document.querySelectorAll('#doc .diagram')].map(d => d.querySelectorAll('.copy').length) }));
      ok(dg.diagrams === 1 && dg.inPre === 0 && dg.copies.every(c => c === 1), `md: a diagram has one frame and one Copy (${JSON.stringify(dg)})`);
      ok(!/browser tab|in this tab/.test(await pg.evaluate(() => document.body.innerText)), 'md: the sample says nothing about a browser tab');
      const kf = await pg.evaluate(fontsState);
      ok(kf.loaded.some(f => /^KaTeX_/.test(f)), 'md: KaTeX sets math in its own faces');
      const [dl] = await Promise.all([pg.waitForEvent('download'), pg.click('#btnExport')]);
      const html = fs.readFileSync(await dl.path(), 'utf8');
      ok(/@font-face\{font-family:'Geist'[^}]*data:font\/woff2;base64,/.test(html) && /@font-face\{font-family:KaTeX_Main[^}]*data:font\/woff2;base64,/.test(html), `md: the exported page embeds its text and math faces (${Math.round(html.length / 1024)} KB)`);
      ok(!/vendor\/|fonts\.googleapis|cdnjs|<link[^>]+stylesheet/.test(html), 'md: the exported page loads nothing: no vendor/ path, no font host, no stylesheet link');
      // a web image and sans-serif math
      const WEB = 'https://example.com/photo.jpg';
      await pg.setInputFiles('#file', { name: 'web.md', mimeType: 'text/markdown', buffer: Buffer.from(`# Web image\n\n![A photo](${WEB})\n\nSans math: $\\mathsf{A} + \\textsf{b}$\n`) });
      await pg.waitForFunction(() => document.querySelector('#doc .web-img') && document.querySelector('#doc .katex'), null, { timeout: 8000 }).catch(() => {});
      const wi = await pg.evaluate(() => { const p = document.querySelector('#doc .web-img'); return p ? { h: Math.round(p.getBoundingClientRect().height), seen: p.checkVisibility(), text: p.textContent, imgs: document.querySelectorAll('#doc img[src^="http"]').length } : null; });
      ok(wi && wi.seen && wi.h > 0 && wi.imgs === 0 && /doesn’t load images from the web/.test(wi.text), `md: an image at a web address is a placeholder that says why (${wi ? wi.h + 'px' : 'none'})`);
      const [dw] = await Promise.all([pg.waitForEvent('download'), pg.click('#btnExport')]);
      const page = fs.readFileSync(await dw.path(), 'utf8');
      ok(page.includes(`src="${WEB}"`) && !/web-img|data-web-src/.test(page), 'md: the exported page keeps the real <img>');
      ok(/@font-face\{font-family:"?KaTeX_SansSerif"?[^}]*data:font\/woff2;base64,/.test(page), 'md: sans-serif math keeps its KaTeX_SansSerif face in the export');
    }
    if (SHOTS) await pg.screenshot({ path: path.join(SHOTS, `${t.name}.png`) });
    const refused = [...await pg.evaluate(() => window.__refused || []), ...refusedLog];
    ok(refused.length === 0, `${t.name}: the host's Content-Security-Policy refuses nothing, in any frame${refused.length ? ' — ' + [...new Set(refused)].slice(0, 3).join(' | ') : ''}`);
    ok(away.length === 0, `${t.name}: no request left 127.0.0.1${away.length ? ' — ' + [...new Set(away)].slice(0, 3).join(', ') : ''}`);
    ok(errs.length === 0, `${t.name}: no page errors${errs.length ? ' — ' + errs.slice(0, 2).join(' | ') : ''}`);
    await ctx.close();
  }

  // Part 2: the web sources, unstripped, with the stub. Served by run.js on fixed ports.
  const WEB = [['studio', 'http://localhost:8771/', true], ['image', 'http://localhost:8772/', true], ['mail', 'http://localhost:8773/', false], ['md', 'http://localhost:8774/', false]];
  for (const [name, url, pro] of WEB) {
    console.log(`== web source with the stub: ${name} ==`);
    const ctx = await browser.newContext({ viewport: { width: 1180, height: 820 } });
    await ctx.route(/^https?:\/\/(?!(localhost|127\.0\.0\.1)[:/])/, r => r.abort());
    await ctx.addInitScript(STUB);
    const pg = await ctx.newPage();
    const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.goto(url, { waitUntil: 'load' }); await pg.waitForTimeout(700);
    const text = await pg.evaluate(visibleText);
    ok(!SELLS.test(text), `${name}: the switch alone hides everything that sells (${(text.match(SELLS) || ['none'])[0]})`);
    ok(await pg.$$eval('a[href]', as => as.filter(a => a.checkVisibility()).every(a => !/pricing|^https?:/i.test(a.getAttribute('href')))), `${name}: no visible link to pricing or to the web`);
    ok(await pg.evaluate(() => window.__swCalls) === 0, `${name}: register is never called`);
    if (pro) { const g = await pg.evaluate(planLeft); ok(g.rows > 0 && g.shown === 0 && g.notes === 0, `${name}: the switch alone hides the ${g.rows} Pro element(s), and no line mentions an account`); }
    ok(await pg.evaluate(zestLinks) === 0, `${name}: no visible control links or copies a zest: URL`);
    if (name === 'mail') ok(await pg.$$eval('[data-t="claude"], #panelClaude', n => n.length) === 0, 'mail: the drafting tab and panel are gone');
    ok(errs.length === 0, `${name}: no page errors${errs.length ? ' — ' + errs.slice(0, 2).join(' | ') : ''}`);
    await ctx.close();
  }
  // and without the stub, the web keeps what the web has
  {
    const ctx = await browser.newContext();
    await ctx.route(/^https?:\/\/(?!(localhost|127\.0\.0\.1)[:/])/, r => r.abort());
    const pg = await ctx.newPage();
    await pg.goto('http://localhost:8771/', { waitUntil: 'load' }); await pg.waitForTimeout(400);
    ok(await pg.evaluate(() => !document.documentElement.classList.contains('in-app')) && await pg.$eval('a[href="pricing/"]', a => a.checkVisibility()), 'web, no stub: the switch is off and the studio keeps its pricing link');
    const ml = await ctx.newPage();
    await ml.goto('http://localhost:8773/', { waitUntil: 'load' }); await ml.waitForTimeout(400);
    ok(await ml.$eval('[data-t="claude"]', b => b.checkVisibility()), 'web, no stub: ZestMail keeps its drafting tab');
    await ctx.close();
  }

  await browser.close();
  srv.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
