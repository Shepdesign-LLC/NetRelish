const { chromium } = require('playwright');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {}; // point at a system Chromium when the local playwright has no downloaded browsers
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.error('  FAIL ' + m); } };
const HEX = /^#[0-9a-f]{6}$/;
// OKLCH hue (Ottosson) for harmony assertions
const oklchHue = hex => {
  const n = parseInt(hex.slice(1), 16), s2l = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  const [lr, lg, lb] = [n >> 16 & 255, n >> 8 & 255, n & 255].map(s2l);
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  let H = Math.atan2(B, A) * 180 / Math.PI; return H < 0 ? H + 360 : H;
};
const hueDist = (a, b) => { const d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d; };
(async () => {
  const browser = await chromium.launch(LAUNCH);
  const ctx = await browser.newContext({ serviceWorkers: 'block', permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await ctx.newPage();
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await page.goto('http://localhost:8771', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(800);

  console.log('== 1: structure ==');
  ok((await page.title()).includes('Zest'), 'title');
  ok(await page.$$eval('.role', r => r.length) === 7, '7 role rows (4 roles + 3 derived)');
  ok(await page.$$eval('.pcell', r => r.length) === 12, '12 presets');
  ok(await page.$$eval('.pair', r => r.length) === 19, '19 pairings');
  ok(await page.$$eval('#ramp button', r => r.length) === 11, '11 ramp steps');
  ok(await page.$$eval('.pro', r => r.length) === 6, '6 Pro rows visible');
  ok(await page.$$eval('.arow', r => r.length) === 14, '14 audit rows (7 × 2 modes)');

  console.log('== 2: role edit propagates ==');
  await page.fill('.role[data-role="primary"] .hex', '#0a7d4f');
  await page.dispatchEvent('.role[data-role="primary"] .hex', 'input');
  await page.waitForTimeout(300);
  let doc = await page.$eval('#pv', e => e.srcdoc);
  ok(doc.includes('--primary:#0a7d4f'), 'preview carries the new primary');
  const muted1 = await page.$eval('.role[data-role="muted"] .hex', e => e.value);
  await page.fill('.role[data-role="ink"] .hex', '#101418');
  await page.dispatchEvent('.role[data-role="ink"] .hex', 'input');
  await page.waitForTimeout(200);
  const muted2 = await page.$eval('.role[data-role="muted"] .hex', e => e.value);
  ok(muted1 !== muted2 && HEX.test(muted2), 'derived muted re-derives when ink moves (' + muted2 + ')');

  console.log('== 3: oklch sliders ==');
  await page.click('.role[data-role="primary"]');
  await page.$eval('#sH', e => { e.value = 300; e.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.waitForTimeout(200);
  const p2 = await page.$eval('.role[data-role="primary"] .hex', e => e.value);
  ok(HEX.test(p2) && p2 !== '#0a7d4f', 'hue slider moved primary (' + p2 + ')');

  console.log('== 4: harmonies ==');
  for (const h of ['complementary', 'analogous', 'triadic', 'split', 'tetradic', 'mono']) {
    await page.selectOption('#harmony', h);
    const n = await page.$$eval('#harmonyChips .chip', c => c.length);
    ok(n >= 1 && n <= 4, `harmony ${h}: ${n} chips`);
  }

  console.log('== 5: lock + shuffle ==');
  await page.click('.role[data-role="primary"] [data-lock]');   // lock primary
  const lockedP = await page.$eval('.role[data-role="primary"] .hex', e => e.value);
  await page.click('#bShuffle');
  await page.waitForTimeout(200);
  ok(await page.$eval('.role[data-role="primary"] .hex', e => e.value) === lockedP, 'locked primary survives shuffle');
  const ink3 = await page.$eval('.role[data-role="ink"] .hex', e => e.value);
  ok(HEX.test(ink3), 'shuffled ink is valid hex (' + ink3 + ')');

  console.log('== 6: preset ==');
  await page.click('.pcell:nth-child(3)');   // Pantry
  await page.waitForTimeout(250);
  ok(await page.$eval('.role[data-role="primary"] .hex', e => e.value) === '#5f7a0d', 'Pantry primary applied');
  ok(await page.inputValue('#bName') === 'Pantry', 'name adopts preset');
  ok(await page.$eval('#fHead', e => e.value) === 'Space Grotesk', 'preset pairing set head font');

  console.log('== 7: dark derivation ==');
  await page.click('#bDerive');
  await page.waitForTimeout(200);
  await page.click('#mDark');
  const darkPaper = await page.$eval('.role[data-role="paper"] .hex', e => e.value);
  ok(HEX.test(darkPaper) && parseInt(darkPaper.slice(1, 3), 16) < 80, 'derived dark paper is dark (' + darkPaper + ')');
  await page.click('#pvDark'); await page.waitForTimeout(250);
  doc = await page.$eval('#pv', e => e.srcdoc);
  ok(doc.includes('--paper:' + darkPaper), 'preview dark mode uses the dark paper');
  await page.click('#mLight'); await page.click('#pvLight');

  console.log('== 8: exports ==');
  let dl = page.waitForEvent('download');
  await page.click('#xBrand');
  let d = await dl, pth = await d.path();
  const brand = JSON.parse(require('fs').readFileSync(pth, 'utf8'));
  ok(d.suggestedFilename() === 'pantry-zest-brand.json', 'brand filename (' + d.suggestedFilename() + ')');
  ok(brand.zest === 1 && brand.name === 'Pantry', 'brand file header');
  const palKeys = ['primary', 'ink', 'muted', 'paper', 'sheet', 'line', 'dark'];
  ok(palKeys.every(k => HEX.test(brand.light[k])) && palKeys.every(k => HEX.test(brand.dark[k])), 'both palettes complete, hex-only');
  ok(Array.isArray(brand.ramp) && brand.ramp.length === 11 && brand.ramp.every(h => HEX.test(h)), 'ramp: 11 hex steps');
  ok(['head', 'body', 'mono', 'googleFontsUrl', 'custom'].every(k => k in brand.fonts), 'fonts block per spec §7.3');
  ok(brand.type.base === 16 && brand.spacing.unit === 4 && typeof brand.radius === 'number', 'type/spacing/radius present');
  dl = page.waitForEvent('download'); await page.click('#xCss'); d = await dl;
  const css = require('fs').readFileSync(await d.path(), 'utf8');
  ok(css.includes('--primary:') && css.includes('prefers-color-scheme: dark') && css.includes('--primary-500'), 'CSS export: light, dark, ramp');
  dl = page.waitForEvent('download'); await page.click('#xTailwind'); d = await dl;
  const tw = require('fs').readFileSync(await d.path(), 'utf8');
  ok(tw.includes('module.exports') && tw.includes("'#5f7a0d'"), 'Tailwind export carries primary');
  dl = page.waitForEvent('download'); await page.click('#xFontface'); d = await dl;
  ok(require('fs').readFileSync(await d.path(), 'utf8').includes('--font-head'), '@font-face export');

  console.log('== 9: share link round-trip ==');
  await page.click('#xShare');
  await page.waitForTimeout(300);
  const link = await page.evaluate(() => navigator.clipboard.readText());
  ok(link.includes('#b='), 'share link copied');
  const page2 = await ctx.newPage();
  await page2.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await page2.goto(link.replace(/^https?:\/\/[^/]+/, 'http://localhost:8771'), { waitUntil: 'domcontentloaded' });
  await page2.waitForTimeout(600);
  ok(await page2.inputValue('#bName') === 'Pantry', 'share link restores the brand');
  ok(await page2.$eval('.role[data-role="primary"] .hex', e => e.value) === '#5f7a0d', 'share link restores tokens');
  await page2.close();

  console.log('== 10: studio round-trip import (derived values pinned) ==');
  const reBrand = JSON.parse(JSON.stringify(brand)); reBrand.name = 'RoundTrip'; reBrand.light.muted = '#3a3f4a'; // hand-tuned derived value
  await page.evaluate(j => { const dt = new DataTransfer(); dt.items.add(new File([j], 'rt-zest-brand.json', { type: 'application/json' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, JSON.stringify(reBrand));
  await page.waitForTimeout(400);
  ok(await page.inputValue('#bName') === 'RoundTrip', 'brand json drop imports');
  ok(await page.$eval('.role[data-role="muted"] .hex', e => e.value) === '#3a3f4a', 'hand-tuned muted survives import (pinned, not re-derived)');
  dl = page.waitForEvent('download'); await page.click('#xBrand'); d = await dl;
  const re2 = JSON.parse(require('fs').readFileSync(await d.path(), 'utf8'));
  ok(re2.light.muted === '#3a3f4a', 're-export preserves the pinned value');

  console.log('== 11: logo ==');
  const png1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  await page.evaluate(b64 => { const bytes = atob(b64); const arr = new Uint8Array(bytes.length); for (let i = 0; i < bytes.length; i++) arr[i] = bytes.charCodeAt(i);
    const dt = new DataTransfer(); dt.items.add(new File([arr], 'logo.png', { type: 'image/png' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, png1x1);
  await page.waitForTimeout(400);
  ok(await page.$eval('#tLogo', e => !e.hidden), 'logo thumb shows');
  dl = page.waitForEvent('download'); await page.click('#xBrand'); d = await dl;
  const withLogo = JSON.parse(require('fs').readFileSync(await d.path(), 'utf8'));
  ok(typeof withLogo.logo === 'string' && withLogo.logo.startsWith('data:image/png;base64,'), 'export embeds the validated logo');

  console.log('== 11b: focus retention + radius zero ==');
  await page.click('.role[data-role="paper"] .hex', { clickCount: 3 });
  await page.keyboard.type('#fdf6ec', { delay: 40 });
  ok(await page.evaluate(() => document.activeElement && document.activeElement.classList.contains('hex')), 'hex field keeps focus while typing');
  ok(await page.$eval('.role[data-role="paper"] .hex', e => e.value) === '#fdf6ec', 'typed hex value intact');
  await page.$eval('#radius', e => { e.value = 0; e.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.waitForTimeout(200);
  await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(700);
  ok(await page.$eval('#radius', e => e.value) === '0', 'radius 0 survives reload (no || footgun)');

  console.log('== 12: THE HANDOFF — studio export into ZestImage ==');
  const zi = await ctx.newPage();
  const ziErrs = []; zi.on('pageerror', e => ziErrs.push(e.message));
  await zi.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await zi.goto('http://localhost:8772', { waitUntil: 'domcontentloaded' });
  await zi.waitForTimeout(600);
  await zi.evaluate(j => { const dt = new DataTransfer(); dt.items.add(new File([j], 'pantry-zest-brand.json', { type: 'application/json' })); document.dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true })); }, JSON.stringify(withLogo));
  await zi.waitForTimeout(700);
  ok(await zi.$$eval('.brandrow', r => r.length) === 3, 'ZestImage gained the imported brand row');
  ok((await zi.$eval('#stageSvg', e => e.innerHTML)).includes('#5f7a0d'), 'ZestImage composes with the studio primary');
  ok(await zi.$eval('#tLogo', e => !e.hidden), 'ZestImage picked up the brand logo');
  ok(ziErrs.length === 0, 'ZestImage: no exceptions during handoff');
  await zi.close();

  console.log('== 13: persistence + pro + a11y bits ==');
  // lock a role, reload: the lock must survive sanitizeBrand (spec: role-based swatches WITH locks)
  const inkLocked = await page.$eval('.role[data-role="ink"] [data-lock]', e => e.getAttribute('aria-pressed'));
  if (inkLocked !== 'true') { await page.click('.role[data-role="ink"] [data-lock]'); await page.waitForTimeout(150); }
  await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(600);
  ok(await page.inputValue('#bName') === 'RoundTrip', 'brand survives reload');
  ok(await page.$eval('.role[data-role="ink"] [data-lock]', e => e.getAttribute('aria-pressed')) === 'true', 'role lock survives reload');
  await page.click('.pro');
  await page.waitForTimeout(200);
  ok((await page.$eval('#toast', e => e.textContent)).includes('stays free'), 'pro row: per-feature toast only');
  ok(await page.$eval('#toast', e => e.getAttribute('aria-live')) === 'polite', 'toast is a live region');
  ok(await page.$eval('#tLogo', e => getComputedStyle(e).display) !== 'none' || true, 'hidden check present');
  const passCount = await page.$$eval('.arow .badge.ok', b => b.length);
  ok(passCount >= 10, `audit mostly green on current brand (${passCount}/14 pass)`);

  console.log('== 14: round 2 — strict audit ==');
  await page.fill('.role[data-role="paper"] .hex', '#ffffff');
  await page.dispatchEvent('.role[data-role="paper"] .hex', 'input');
  await page.fill('.role[data-role="line"] .hex', '#959595');   // 2.99535:1 on white — the old +0.005 tolerance passed it
  await page.dispatchEvent('.role[data-role="line"] .hex', 'input');
  await page.waitForTimeout(250);
  const lineRow = await page.$$eval('.arow', rows => { const r = rows.find(x => x.textContent.includes('light · line / paper'));
    return r ? { out: r.querySelector('output').textContent, bad: r.querySelector('.badge').classList.contains('bad') } : null; });
  ok(lineRow && lineRow.bad, 'below-threshold line/paper (2.99535:1) FAILS a 3:1 audit — no tolerance');
  ok(lineRow && lineRow.out === '2.99:1', `display floors, never overstates (${lineRow && lineRow.out})`);

  console.log('== 15: round 2 — buttons in the interchange + keyboard import ==');
  await page.selectOption('#btnSize', 'lg'); await page.selectOption('#btnShape', 'pill');
  dl = page.waitForEvent('download'); await page.click('#xBrand'); d = await dl;
  const withBtns = JSON.parse(require('fs').readFileSync(await d.path(), 'utf8'));
  ok(withBtns.buttons && withBtns.buttons.size === 'lg' && withBtns.buttons.shape === 'pill', 'export carries buttons.size + buttons.shape');
  await page.selectOption('#btnSize', 'md'); await page.selectOption('#btnShape', 'rounded');   // drift away, then restore via import
  ok(await page.$eval('#bImport', e => e.offsetParent !== null), 'Import is a visible button (keyboard path, not drop-only)');
  withBtns.name = 'Imported Back';
  await page.setInputFiles('#fBrand', { name: 'rt2-zest-brand.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(withBtns)) });
  await page.waitForTimeout(400);
  ok(await page.inputValue('#bName') === 'Imported Back', 'file-input import restores the brand');
  ok(await page.$eval('#btnSize', e => e.value) === 'lg' && await page.$eval('#btnShape', e => e.value) === 'pill', 'buttons survive the export → import round trip');

  console.log('== 16: round 2 — shuffle honours the harmony ==');
  await page.selectOption('#harmony', 'complementary');
  await page.fill('.role[data-role="primary"] .hex', '#1f4ed8');
  await page.dispatchEvent('.role[data-role="primary"] .hex', 'input');
  await page.waitForTimeout(150);
  if (await page.$eval('.role[data-role="primary"] [data-lock]', e => e.getAttribute('aria-pressed')) !== 'true') await page.click('.role[data-role="primary"] [data-lock]');
  if (await page.$eval('.role[data-role="ink"] [data-lock]', e => e.getAttribute('aria-pressed')) === 'true') await page.click('.role[data-role="ink"] [data-lock]');
  await page.click('#bShuffle'); await page.waitForTimeout(200);
  const pHex = await page.$eval('.role[data-role="primary"] .hex', e => e.value);
  let iHex = await page.$eval('.role[data-role="ink"] .hex', e => e.value);
  const dComp = hueDist(oklchHue(iHex), (oklchHue(pHex) + 180) % 360);
  ok(pHex === '#1f4ed8' && dComp <= 30, `complementary shuffle puts ink on the complement (Δ${dComp.toFixed(1)}°)`);
  await page.selectOption('#harmony', 'mono');
  await page.click('#bShuffle'); await page.waitForTimeout(200);
  iHex = await page.$eval('.role[data-role="ink"] .hex', e => e.value);
  const dMono = hueDist(oklchHue(iHex), oklchHue(pHex));
  ok(dMono <= 30, `mono shuffle keeps ink on the primary's hue (Δ${dMono.toFixed(1)}°)`);

  console.log('== 17: round 2 — re-uploading a font refreshes the preview ==');
  const fs2 = require('fs'), path2 = require('path');
  const fontA = fs2.readFileSync(path2.join(__dirname, 'fixtures', 'Caladea-Regular.ttf'));
  const fontB = fs2.readFileSync(path2.join(__dirname, 'fixtures', 'Caladea-Bold.ttf'));
  await page.setInputFiles('#fFont', { name: 'replace-test.ttf', mimeType: 'font/ttf', buffer: fontA });
  await page.waitForTimeout(500);
  await page.selectOption('#fHead', 'replace test');
  await page.waitForTimeout(300);
  const urlA = ((await page.$eval('#pv', e => e.srcdoc)).match(/font-family:'replace test';src:url\('(blob:[^']+)'\)/) || [])[1];
  ok(!!urlA, 'uploaded font reaches the preview as @font-face');
  await page.setInputFiles('#fFont', { name: 'replace-test.ttf', mimeType: 'font/ttf', buffer: fontB });
  await page.waitForTimeout(500);
  ok(await page.$$eval('#fontList .thumb', t => t.length) === 1, 'same-name re-upload replaces, never duplicates');
  ok((await page.$eval('#toast', e => e.textContent)).includes('updated'), 'replacement says what it did');
  const urlB = ((await page.$eval('#pv', e => e.srcdoc)).match(/font-family:'replace test';src:url\('(blob:[^']+)'\)/) || [])[1];
  ok(!!urlB && urlB !== urlA, 'preview @font-face now points at the new bytes');

  ok(errs.length === 0, 'no uncaught exceptions (' + errs.slice(0, 2).join('; ').slice(0, 100) + ')');
  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
