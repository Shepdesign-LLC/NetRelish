// Merge-tag DoS regressions: bounded scanner checks, then real imports and draft restoration.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { chromium } = require('playwright');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {};
const source = fs.readFileSync(path.join(__dirname, '../apps/mail/index.html'), 'utf8');
const scanner = source.slice(source.indexOf('  function tagMatches('), source.indexOf('  function chipTags('));
const context = vm.createContext({ assert });
vm.runInContext(scanner + String.raw`
  const own = ['*|FNAME|*', '%recipient.first%', '[a+b?]', 'abcde', 'abc'];
  const old = /\{\{[^}]+\}\}|\*\|FNAME\|\*|%recipient\.first%|\[a\+b\?\]|abcde|abc/g;
  function check(text) {
    const expected = [...text.matchAll(old)].map(m => [m.index, m.index + m[0].length]);
    assert.deepEqual(tagMatches(text, own), expected, text);
  }
  ['{{}}', '{{{}}', '{{x}', '{{x} {{ok}}', '{{a{{b}}c}}',
   'Hi {{ visitor.first_name }} *|FNAME|* [a+b?] %recipient.first% abcde abc',
   '{{*|FNAME|*}', '{{x}*|FNAME|*', '{{\nname\n}}'].forEach(check);
  let seed = 417;
  for (let n = 0; n < 10000; n++) {
    let text = '';
    for (let j = 0; j < 60; j++) { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; text += '{}abc '[seed % 6]; }
    check(text);
  }
  for (const text of ['{'.repeat(200000), '{'.repeat(199999) + '}', '{'.repeat(199998) + '}}']) {
    tagMatches(text, own);
  }
`, context, { timeout: 2000 });
console.log('PASS scanner matches legacy semantics on edge cases and 10,000 deterministic samples; 200,000-character adversarial scans finish within a 2s total budget');

(async () => {
  const browser = await chromium.launch(LAUNCH);
  try {
    const ctx = await browser.newContext({ acceptDownloads: true, serviceWorkers: 'block' });
    const pg = await ctx.newPage();
    const errors = []; pg.on('pageerror', e => errors.push(e.message));
    pg.setDefaultTimeout(5000);
    await pg.route(/^https?:\/\/(?!(localhost|127\.0\.0\.1)[:/])/, r => r.abort());
    await pg.goto('http://localhost:8773/');
    for (const [name, body] of [
      ['unmatched', '{'.repeat(200000)],
      ['invalid close', '{'.repeat(199980) + '} {{good}}'],
      ['nested', '{'.repeat(199998) + '}}'],
      ['normal', 'Hi {{ visitor.first_name }} and {{ subject }}.'],
    ]) {
      const design = { name, blocks: [{ type: 'text', props: { body } }] };
      const start = Date.now();
      await pg.setInputFiles('#jsonFile', { name: 'tags.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(design)) });
      await pg.waitForFunction(name => JSON.parse(localStorage.getItem('mailpress:draft'))?.designName === name, name);
      for (const phase of ['import', 'reload']) {
        if (phase === 'reload') await pg.reload({ waitUntil: 'load', timeout: 5000 });
        const actual = await pg.$eval('#canvas [data-edit="body"]', el => {
          const copy = el.cloneNode(true);
          copy.querySelectorAll('.mtag').forEach(c => c.replaceWith(document.createTextNode(c.dataset.tag)));
          return copy.textContent;
        });
        assert.equal(actual, body, `${name}: exact text after ${phase}`);
        assert.equal(await pg.evaluate(() => JSON.parse(localStorage.getItem('mailpress:draft')).blocks[0].props.body), body);
      }
      await pg.click('#btnExport');
      const download = pg.waitForEvent('download');
      await pg.click('#popExport [data-do="json"]');
      const exported = JSON.parse(fs.readFileSync(await (await download).path(), 'utf8'));
      assert.equal(exported.blocks[0].props.body, body);
      console.log(`PASS ${name}: import, reload and JSON export preserve text (${Date.now() - start}ms)`);
    }
    // Confirmed recovery must clear before the first draft read, not render and then clear it.
    await pg.evaluate(() => { localStorage.setItem('mailpress:designs', '[]'); localStorage.setItem('mailpress:modules', '[]'); });
    const kept = await pg.evaluate(() => ['brands', 'designs', 'modules'].map(k => localStorage.getItem('mailpress:' + k)));
    await pg.addInitScript(() => {
      const get = Storage.prototype.getItem, set = Storage.prototype.setItem;
      window.draftEvents = [];
      Storage.prototype.getItem = function(k) { if (k === 'mailpress:draft') window.draftEvents.push('read'); return get.call(this, k); };
      Storage.prototype.setItem = function(k, v) { if (k === 'mailpress:draft' && v === 'null') window.draftEvents.push('clear'); return set.call(this, k, v); };
    });
    pg.once('dialog', d => d.accept());
    await pg.goto('http://localhost:8773/?recover-draft');
    assert.deepEqual(await pg.evaluate(() => window.draftEvents.slice(0, 2)), ['clear', 'read']);
    assert.equal(await pg.locator('#canvas .cv-block').count(), 0);
    assert.deepEqual(await pg.evaluate(() => ['brands', 'designs', 'modules'].map(k => localStorage.getItem('mailpress:' + k))), kept);
    assert.equal(new URL(pg.url()).search, '');
    console.log('PASS recovery clears before draft access and keeps saved designs, brands and modules');
    await pg.evaluate(() => localStorage.setItem('mailpress:draft', JSON.stringify({ designName: 'Keep me', blocks: [{ type: 'text', props: { body: 'Keep {{ subject }}' } }] })));
    pg.once('dialog', d => d.dismiss());
    await pg.goto('http://localhost:8773/?recover-draft');
    assert.equal(await pg.locator('#canvas .mtag').getAttribute('data-tag'), '{{ subject }}');
    assert.equal(await pg.evaluate(() => JSON.parse(localStorage.getItem('mailpress:draft')).designName), 'Keep me');
    assert.ok(await pg.evaluate(() => window.draftEvents.length > 0 && window.draftEvents.every(e => e === 'read')));
    assert.equal(new URL(pg.url()).search, '');
    assert.deepEqual(errors, []);
    console.log('PASS cancelling recovery keeps and restores the draft; no page errors');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
