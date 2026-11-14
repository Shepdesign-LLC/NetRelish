// Offline gate 2 of 3 (ADR 0015, NN5): the app's copy of the tools, used with no network.
//
// Serves Resources/Zest (bash zest/build.sh --app) on 127.0.0.1 at a free port, opens each tool with every
// request that is not to this server aborted and recorded, works the main flows lightly, and fails on any
// attempted request to another host — page loads, fonts, scripts, fetch/XHR, workers, WebSockets. Resource
// hints open connections without a request the router can see (preconnect, dns-prefetch), so every
// <link rel=preconnect|dns-prefetch|prefetch|prerender|preload|modulepreload> in any frame, static or added
// by script (even if removed again), counts as an attempt too.
//
//   node offline.js [--json report.json]        ZEST_APP_ROOT=<dir> serves another copy (default ../../Resources/Zest)
//
// Each page gets the host's frozen window.netrelish stub in its main frame, as the Zest window injects it, so the
// tools run with their in-app switch on. run.js builds the app's copy into a temp folder and runs this on it;
// CI's app-bundle job runs it on the committed Resources/Zest.
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(process.env.ZEST_APP_ROOT || path.join(__dirname, '..', '..', 'Resources', 'Zest'));
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {};
const jsonAt = process.argv.indexOf('--json');
const JSON_OUT = jsonAt > 0 ? process.argv[jsonAt + 1] : null;
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.txt': 'text/plain',
};
// Resource hints: DNS and TLS happen with no HTTP request, so context.route never sees them. An init script
// in every frame records each hint link as it appears; hintsIn() also reads the ones in the DOM now.
const HINT_SEL = 'link[rel~=preconnect],link[rel~=dns-prefetch],link[rel~=prefetch],link[rel~=prerender],link[rel~=preload],link[rel~=modulepreload]';
const HINT_WATCH = `(() => {
  const SEL = ${JSON.stringify(HINT_SEL)};
  const seen = window.__zestHints = [];
  const note = el => { if (el.matches && el.matches(SEL)) seen.push({ rel: el.rel, href: el.href }); };
  new MutationObserver(ms => { for (const m of ms) {
    if (m.type === 'attributes') note(m.target);
    for (const n of m.addedNodes || []) if (n.nodeType === 1) { note(n); n.querySelectorAll && n.querySelectorAll(SEL).forEach(note); }
  } }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['rel', 'href'] });
})();`;
async function hintsIn(page) {
  const out = [];
  for (const frame of page.frames()) {
    try {
      out.push(...await frame.evaluate(sel => [
        ...(window.__zestHints || []),
        ...[...document.querySelectorAll(sel)].map(l => ({ rel: l.rel, href: l.href })),
      ], HINT_SEL));
    } catch { /* a frame that navigated away mid-read */ }
  }
  return out;
}
const STUB = `if (window.top === window) Object.defineProperty(window, 'netrelish', { value: Object.freeze({ version: '0', host: 'app', network: false }), writable: false, configurable: false });`;
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');

function serve() {
  const srv = http.createServer((req, res) => {
    try {
      let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
      if (p.endsWith('/')) p += 'index.html';
      const file = path.join(ROOT, p);
      if (!file.startsWith(ROOT + path.sep) || !fs.existsSync(file)) { res.writeHead(404); return res.end('not found'); }
      if (fs.statSync(file).isDirectory()) { res.writeHead(301, { location: p + '/' }); return res.end(); }
      res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    } catch { res.writeHead(400); res.end('bad request'); }
  });
  return new Promise(ok => srv.listen(0, '127.0.0.1', () => ok(srv)));
}

// The light flows: the things a person does first in each tool, enough to make it reach for whatever it
// would load. Selectors are the ones sound.js and test.js already hold the tools to.
// Click and wait for the download together, so a click that never lands leaves no wait behind to throw later.
const download = (pg, sel) => Promise.all([pg.waitForEvent('download', { timeout: 8000 }), pg.click(sel)]);
const TOOLS = [
  { name: 'studio', path: '/', steps: [
    ['switch the palette to Dark', pg => pg.click('#mDark')],
    ['Shuffle', pg => pg.click('#bShuffle')],
    ['pick a preset (it sets a type pairing)', pg => pg.click('.pcell:nth-child(3)')],
    ['pick another pairing', pg => pg.click('.pair:nth-child(2)')],
    ['save the brand', pg => pg.click('#bSave')],
    ['export the brand file', pg => download(pg, '#xBrand')],
    ['export the @font-face CSS', pg => download(pg, '#xFontface')],
  ] },
  { name: 'mail', path: '/mail/', steps: [
    ['open the Message tab', pg => pg.click('#tabs button[data-t="message"]')],
    ['add a block', pg => pg.click('#lib .lib-item')],
    ['copy the email HTML', async pg => { await pg.click('#btnExport'); await pg.click('#popExport [data-do="copy"]'); }],
  ] },
  { name: 'md', path: '/md/', steps: [
    ['open the sample (math and a diagram)', pg => pg.click('[data-act="sample"]')],
    ['let KaTeX and Mermaid load', pg => pg.waitForTimeout(1500)],
    ['open Contents', pg => pg.click('#btnToc')],
    ['export HTML in one click', pg => pg.click('#btnExport')],
  ] },
  { name: 'image', path: '/image/', steps: [
    ['switch to Dark', pg => pg.click('#mDark')],
    ['choose a layout', pg => pg.click('#layoutGrid .lcell:nth-child(2)')],
    ['add a photo', pg => pg.setInputFiles('#fPhoto', { name: 'photo.png', mimeType: 'image/png', buffer: PNG })],
    ['write the alt text', pg => pg.fill('#cAlt', 'A title card')],
    ['export the image (embeds the brand fonts)', pg => download(pg, '#bExport')],
  ] },
];

(async () => {
  if (!fs.existsSync(path.join(ROOT, 'index.html'))) { console.error(`offline: ${ROOT} is not built (bash zest/build.sh --app)`); process.exit(2); }
  const srv = await serve();
  const origin = `http://127.0.0.1:${srv.address().port}`;
  const isLocal = u => u.startsWith(origin + '/') || u === origin || /^(data|blob|about):/.test(u);
  const browser = await chromium.launch(LAUNCH);
  const report = [];
  let blockedTotal = 0, flowFails = 0;

  for (const tool of TOOLS) {
    const blocked = [];
    let step = 'page load';
    const context = await browser.newContext({ serviceWorkers: 'block', acceptDownloads: true });
    await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin });
    await context.route('**/*', route => {
      const req = route.request();
      if (isLocal(req.url())) return route.continue();
      blocked.push({ url: req.url(), type: req.resourceType(), step });
      return route.abort('blockedbyclient');
    });
    await context.routeWebSocket(/.*/, ws => { blocked.push({ url: ws.url(), type: 'websocket', step }); ws.close(); });
    await context.addInitScript(STUB);
    await context.addInitScript(HINT_WATCH);
    const page = await context.newPage();
    const hintsSeen = new Set();
    const checkHints = async () => {
      for (const h of await hintsIn(page)) {
        if (!h.href || isLocal(h.href) || hintsSeen.has(h.href)) continue;
        hintsSeen.add(h.href);
        blocked.push({ url: h.href, type: `hint:${h.rel.split(/\s+/)[0]}`, step });
      }
    };
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    console.log(`\n=== ${tool.name} (${tool.path}) ===`);
    await page.goto(origin + tool.path, { waitUntil: 'load' });
    await page.waitForTimeout(800);   // first-paint work: deferred font links, on-load handlers
    await checkHints();
    const flows = [];
    for (const [name, run] of tool.steps) {
      step = name;
      try {
        await Promise.race([run(page), new Promise((_, no) => setTimeout(() => no(new Error('timed out after 8s')), 8000))]);
        await page.waitForTimeout(300);
        await checkHints();
        flows.push({ step: name, ok: true });
      } catch (e) {
        flowFails++;
        flows.push({ step: name, ok: false, error: e.message.split('\n')[0] });
        console.error(`  FLOW ${name}: ${e.message.split('\n')[0]}`);
      }
    }
    step = 'settle';
    await page.waitForTimeout(500);
    await checkHints();
    await context.close();

    const seen = new Map();
    for (const b of blocked) { const k = `${b.type.startsWith('hint:') ? 'hint ' : ''}${b.url}`; if (!seen.has(k)) seen.set(k, { ...b, count: 0 }); seen.get(k).count++; }
    const unique = [...seen.values()];
    blockedTotal += unique.length;
    if (unique.length) for (const b of unique) console.error(`  FAIL ${b.type.padEnd(10)} ${b.url.length > 120 ? b.url.slice(0, 117) + '...' : b.url}  [during: ${b.step}${b.count > 1 ? `, ×${b.count}` : ''}]`);
    else console.log('  PASS no request left 127.0.0.1');
    const okSteps = flows.filter(f => f.ok).length;
    console.log(`  ${okSteps}/${flows.length} steps ran${errors.length ? `; ${errors.length} page error(s): ${errors.slice(0, 2).join(' | ')}` : ''}`);
    report.push({ tool: tool.name, path: tool.path, blocked: unique, flows, pageErrors: errors });
  }

  await browser.close();
  srv.close();
  if (JSON_OUT) fs.writeFileSync(JSON_OUT, JSON.stringify({ root: ROOT, tools: report }, null, 2) + '\n');
  const hosts = [...new Set(report.flatMap(r => r.blocked.map(b => { try { return new URL(b.url).host; } catch { return b.url; } })))].sort();
  if (blockedTotal || flowFails) {
    console.error(`\nRESULT: ${blockedTotal} address(es) outside 127.0.0.1 attempted${hosts.length ? ' (' + hosts.join(', ') + ')' : ''}; ${flowFails} step(s) did not run`);
    process.exit(1);
  }
  console.log('\nRESULT: every tool ran its flows with no request outside 127.0.0.1');
})().catch(e => { console.error(e); process.exit(1); });
