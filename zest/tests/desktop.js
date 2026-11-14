// Desktop suite: ZestMail's canvas and previews at laptop and desktop sizes (1280x800, 1920x1080, 2560x1440).
// Guards the canvas size: the email is never drawn below 100% on a laptop, grows to use a wide screen, shares one zoom with
// the previews, and the zoom never reaches the exported email. Serve: mail :8773.
const { chromium } = require('playwright');
const fs = require('fs');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {};
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.error('  FAIL ' + m); } };
(async () => {
  const browser = await chromium.launch(LAUNCH);
  const exports = {};
  for (const [w, h] of [[1280, 800], [1920, 1080], [2560, 1440]]) {
    console.log(`== mail at ${w}x${h} ==`);
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, serviceWorkers: 'block', acceptDownloads: true });
    const pg = await ctx.newPage();
    const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
    await pg.goto('http://localhost:8773/', { waitUntil: 'domcontentloaded' }); await pg.evaluate(() => localStorage.clear()); await pg.reload({ waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(500);
    await pg.click('#tpl [data-tpl="newsletter"]'); await pg.waitForTimeout(400);
    const m = () => pg.evaluate(() => {
      const wrap = document.querySelector('#canvasWrap'), z = +wrap.style.zoom || 1, st = document.querySelector('#stage');
      return { z, email: document.querySelector('#canvas').getBoundingClientRect().width, mat: wrap.getBoundingClientRect().width, stage: st.clientWidth,
        matRight: wrap.getBoundingClientRect().right, stageRight: st.getBoundingClientRect().right - parseFloat(getComputedStyle(st).paddingRight) - (st.offsetWidth - st.clientWidth) };
    });
    const c = await m();
    if (w === 1280) ok(c.email >= 600 - 0.5, `1280: the email draws at 100% or more (${Math.round(c.email)}px, was 578)`);
    else if (w === 1920) ok(c.mat >= c.stage * 0.55, `1920: in Fit the email fills the stage (${Math.round(c.mat)} of ${c.stage}px, was 652)`);
    else ok(Math.abs(c.z - 1.25) < 0.001, `${w}: Fit grows the email to its 125% cap on a wide screen (was 100%)`);
    ok(c.matRight <= c.stageRight + 1, `${w}: in Fit the mat stays inside the stage`);
    ok(await pg.evaluate(() => Math.abs(document.querySelector('.pane.center > .pane-head').getBoundingClientRect().width - document.querySelector('.pane.center').getBoundingClientRect().width) < 1), `${w}: the canvas header spans its pane (was a 374px floating strip)`);
    ok(await pg.evaluate(() => /^\d+%$/.test(document.querySelector('#zoomVal').textContent) && document.querySelector('#zoomSeg [data-z="fit"]').getAttribute('aria-pressed') === 'true'), `${w}: Fit is on and shows its percentage`);
    // editing chrome stays UI size at any zoom
    await pg.click('.cv-block:nth-child(3) h2'); await pg.waitForTimeout(200);
    const tool = () => pg.evaluate(() => Math.round(document.querySelector('.cv-block[aria-selected="true"] .tools button').getBoundingClientRect().height));
    const t1 = await tool();
    await pg.click('#zoomSeg [data-z="1.5"]'); await pg.waitForTimeout(200);
    ok(Math.abs((await m()).z - 1.5) < 0.001 && await tool() === t1, `${w}: 150% scales the email but not the block tools (${t1}px)`);
    // the Desktop preview renders the desktop email at the canvas's scale, and is as tall as the email
    await pg.click('#viewSeg [data-w="600"]'); await pg.waitForTimeout(700);
    const pv = await pg.evaluate(() => { const f = document.querySelector('#frame'), d = f.contentDocument; return { container: d.querySelector('.container').getBoundingClientRect().width, inner: d.documentElement.scrollHeight, frameH: f.clientHeight, zoom: +f.style.zoom || 1 }; });
    ok(pv.container === 600, `${w}: the Desktop preview shows the 600px desktop email, not its phone layout (${pv.container}px, was 576)`);
    ok(Math.abs(pv.zoom - 1.5) < 0.001, `${w}: the Desktop preview takes the same zoom as the canvas`);
    ok(pv.inner <= pv.frameH + 1, `${w}: the preview frame is as tall as the email, so the stage scrolls it (${pv.frameH} for ${pv.inner})`);
    await pg.click('#viewSeg [data-w="outlook"]'); await pg.waitForTimeout(700);
    ok(await pg.evaluate(() => document.querySelector('#frame').contentDocument.querySelector('.container').getBoundingClientRect().width === 600), `${w}: the Outlook preview keeps the 600px email (the Word engine reads the mso table width)`);
    // the export is the same at every zoom: a 600px email
    const dl = async () => { await pg.click('#btnExport'); const d = pg.waitForEvent('download'); await pg.click('#popExport [data-do="download"]'); return fs.readFileSync(await (await d).path(), 'utf8'); };
    const at150 = await dl();
    await pg.click('#viewSeg [data-w="canvas"]'); await pg.click('#zoomSeg [data-z="fit"]'); await pg.waitForTimeout(200);
    const atFit = await dl();
    ok(at150 === atFit && /max-width:600px/.test(atFit) && /width="600"/.test(atFit), `${w}: the exported HTML is the same at Fit and 150%, a 600px email`);
    exports[w] = atFit;
    // the choice is remembered
    await pg.click('#zoomSeg [data-z="1.25"]'); await pg.reload({ waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(500);
    ok(await pg.evaluate(() => document.querySelector('#zoomSeg [data-z="1.25"]').getAttribute('aria-pressed') === 'true' && Math.abs((+document.querySelector('#canvasWrap').style.zoom || 1) - 1.25) < 0.001), `${w}: the zoom choice survives a reload`);
    ok(!errs.length, `${w}: no exceptions (${errs.slice(0, 1).join('').slice(0, 80)})`);
    await ctx.close();
  }
  ok(exports[1280] === exports[1920] && exports[1920] === exports[2560], 'the exported HTML is the same at every window size');
  // no storage at all: the zoom control still works
  const nctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, serviceWorkers: 'block' });
  await nctx.addInitScript(() => { Object.defineProperty(window, 'localStorage', { get() { throw new Error('blocked'); } }); });
  const np = await nctx.newPage(); const nerrs = []; np.on('pageerror', e => nerrs.push(e.message));
  await np.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
  await np.goto('http://localhost:8773/', { waitUntil: 'domcontentloaded' }); await np.waitForTimeout(500);
  await np.click('#zoomSeg [data-z="1.5"]'); await np.waitForTimeout(200);
  ok(!nerrs.length && await np.evaluate(() => +document.querySelector('#canvasWrap').style.zoom === 1.5), 'with storage blocked the zoom still works');
  await nctx.close();
  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
