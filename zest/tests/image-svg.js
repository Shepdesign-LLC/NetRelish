// SVG logo DoS: exercise the real import, restore, layout and removal paths in Chromium.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {};
const svgURL = src => 'data:image/svg+xml;base64,' + Buffer.from(src).toString('base64');
const brand = logo => ({ zest: 1, name: 'SVG regression', light: { primary: '#123456' }, logo });
// A renderer stuck in synchronous parsing cannot service Playwright's usual page timeouts.
const deadline = setTimeout(() => { console.error('FAIL SVG regression exceeded 45s wall-clock budget'); process.exit(1); }, 45000);
(async () => {
  const browser = await chromium.launch(LAUNCH);
  try {
    const ctx = await browser.newContext({ serviceWorkers: 'block' });
    const pg = await ctx.newPage();
    const errors = []; pg.on('pageerror', e => errors.push(e.message));
    pg.setDefaultTimeout(5000);
    await pg.route(/^https?:\/\/(?!(localhost|127\.0\.0\.1)[:/])/, r => r.abort());
    await pg.goto('http://localhost:8772/');
    const importLogo = async logo => {
      await pg.setInputFiles('#fBrand', { name: 'zest-brand.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(brand(logo))) });
      await pg.waitForFunction(() => JSON.parse(localStorage.getItem('zestimage:brands'))?.[0]?.name === 'SVG regression');
      return pg.evaluate(() => JSON.parse(localStorage.getItem('zestimage:brands'))[0].logo);
    };
    for (const src of [
      '<svg '.repeat(200000),                     // 1 MB decoded, below the 1.5M data URL cap
      '<svg '.repeat(200000) + '>',
      '<svg viewBox="0 0 400 100"><g></svg>',
      '<html/>',
      '<!DOCTYPE svg [<!ENTITY a "400">]><svg width="&a;" height="100"/>',
      '<svg viewBox="0 0 0 100"/>', '<svg viewBox="0 0 400 -1"/>',
      '<svg viewBox="0 0 1e999 100"/>', '<svg viewBox="0 0 400 100 junk"/>',
      '<svg width="NaN" height="100"/>', '<svg width="400" height="0"/>',
      '<svg width="1e999" height="100"/>', '<svg width="400" height="1e-999"/>',
    ]) {
      const url = svgURL(src); assert.ok(url.length <= 1500000);
      const start = Date.now();
      assert.equal(await importLogo(url), null, 'invalid logo must not be persisted');
      assert.ok(Date.now() - start < 5000, 'hostile import finishes within 5s');
    }
    console.log('PASS malformed/DTD/invalid-dimension SVGs (including repeated 1 MB prefixes) are stripped before saving');

    // Simulate a brand saved by the vulnerable build: sanitization must precede rendering on boot.
    await pg.evaluate(b => {
      localStorage.setItem('zestimage:brands', JSON.stringify([b]));
      localStorage.setItem('zestimage:layout', JSON.stringify('kicker'));
    }, brand(svgURL('<svg '.repeat(200000))));
    const start = Date.now();
    await pg.reload({ timeout: 5000 });
    await pg.waitForSelector('#stageSvg svg');
    assert.ok(Date.now() - start < 5000, 'saved active malicious brand boots within 5s');
    assert.equal(await pg.locator('#stageSvg image[data-logo]').count(), 0);
    // The existing Remove control now works without ever rendering the discarded logo.
    await pg.getByRole('button', { name: 'Remove SVG regression', exact: true }).click();
    assert.deepEqual(await pg.evaluate(() => JSON.parse(localStorage.getItem('zestimage:brands'))), []);
    await pg.reload();
    assert.equal(await pg.getByRole('button', { name: 'Remove SVG regression', exact: true }).count(), 0);
    console.log('PASS saved active malformed brand reloads safely and can be removed persistently');

    for (const src of [
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10 -20 4e2 100"><rect width="400" height="100"/></svg>',
      '<svg width="400px" height="100px"/>',
      '<!-- <svg viewBox="0 0 100 400"> --><svg viewBox="0 0 400 100"/>',
      '<svg width="100%" height="100%" viewBox="0,0,400,100"/>',
    ]) {
      const url = svgURL(src);
      assert.equal(await importLogo(url), url, 'valid SVG survives import');
      for (const phase of ['import', 'reload']) {
        if (phase === 'reload') await pg.reload();
        await pg.waitForSelector('#stageSvg image[data-logo]');
        const ratio = await pg.locator('#stageSvg image[data-logo]').first().evaluate(im => +im.getAttribute('width') / +im.getAttribute('height'));
        assert.ok(Math.abs(ratio - 4) < 0.05, `${phase}: SVG uses its real 4:1 aspect (${ratio})`);
      }
    }
    assert.deepEqual(errors, []);
    console.log('PASS viewBox, exponent, px dimensions and misleading comments retain the correct aspect on import and reload; no page errors');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => clearTimeout(deadline));
