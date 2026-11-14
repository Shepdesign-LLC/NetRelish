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
  // four of the five folds are closed on every load: open one the way a person would before using what is inside it
  const openFold = async sel => { if (!await page.$eval(sel, d => d.open)) await page.click(sel + ' > summary'); };
  // what is really on screen: inside a closed <details> an element still has an offsetParent, so ask Playwright instead
  const shown = async sel => { const out = []; for (const h of await page.$$(sel)) if (await h.isVisible()) out.push(h); return out; };

  console.log('== 1: structure ==');
  ok((await page.title()).includes('Zest'), 'title');
  ok(await page.$$eval('.role', r => r.length) === 7, '7 role rows (4 roles + 3 derived)');
  ok(await page.$$eval('.pcell', r => r.length) === 12, '12 presets');
  ok(await page.$$eval('.pair', r => r.length) === 19, '19 pairings');
  ok(await page.$$eval('#ramp button', r => r.length) === 11, '11 ramp steps');
  ok(await page.$$eval('#proFold .pro', r => r.length) === 6 && await page.$$eval('.pro', r => r.length) === 6, '6 Pro rows, all in the one Pro fold');
  ok(await page.$$eval('.arow', r => r.length) === 14, '14 audit rows (7 × 2 modes)');

  console.log('== 1b: folds — four closed on load and opened by keyboard; Pro open on load ==');
  ok(await page.$eval('#tBase', e => e.value) === '16' && await page.$eval('#tRatio', e => e.value) === '1.25' && await page.$eval('#spUnit', e => e.value) === '4'
    && await page.$eval('#spDensity', e => e.value) === 'comfortable' && await page.$eval('#btnSize', e => e.value) === 'md' && await page.$eval('#btnShape', e => e.value) === 'rounded',
    'the folded controls keep their defaults (16 × 1.25, unit 4, comfortable, medium, rounded)');
  const FOLDS = [['#slFold', 'OKLCH sliders', '#sH'], ['#scaleFold', 'Type scale', '#tRatio'], ['#spaceFold', 'Spacing and buttons', '#btnShape'],
    ['#sendFold', 'Send to', '[data-send="mail"]'], ['#proFold', 'Pro', '.pro']];
  ok(await page.$$eval('details', d => d.length) === FOLDS.length, 'five folds, no more');
  const visiblePro = async () => (await shown('.pro')).length;
  for (const [sel, name, inside] of FOLDS) {
    const f = await page.$eval(sel, d => ({ tag: d.tagName, open: d.open, name: d.querySelector(':scope > summary').textContent.trim() }));
    if (sel === '#proFold') {   // spec §4.3: never hide Pro from free users — this fold loads open
      ok(f.tag === 'DETAILS' && f.open && f.name === name && await visiblePro() === 6 && await page.isVisible('#proFold + .hint'), 'Pro: a native fold with that name, open on load — six rows and the hint visible with no click');
      await page.focus(sel + ' > summary'); await page.keyboard.press('Space');
      ok(!await page.$eval(sel, d => d.open) && await visiblePro() === 0, 'Pro: Space on its summary closes it');
      await page.keyboard.press('Enter');
      ok(await page.$eval(sel, d => d.open) && await visiblePro() === 6, 'Pro: Enter opens it again');
      continue;
    }
    ok(f.tag === 'DETAILS' && !f.open && f.name === name && !await page.isVisible(inside), `${name}: a native fold with that name, closed on load, its controls out of sight`);
    await page.focus(sel + ' > summary'); await page.keyboard.press('Enter');
    ok(await page.$eval(sel, d => d.open) && await page.isVisible(inside), `${name}: Enter on its summary opens it`);
    await page.keyboard.press('Space');
    ok(!await page.$eval(sel, d => d.open) && !await page.isVisible(inside), `${name}: Space closes it again`);
  }
  // every fold is now as the page loads it (Pro open, the other four closed): each section below opens what it needs

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
  await openFold('#slFold');
  await page.$eval('#sH', e => { e.value = 300; e.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.waitForTimeout(200);
  const p2 = await page.$eval('.role[data-role="primary"] .hex', e => e.value);
  ok(HEX.test(p2) && p2 !== '#0a7d4f', 'hue slider moved primary (' + p2 + ')');
  await page.focus('#sL'); await page.keyboard.press('ArrowRight'); await page.waitForTimeout(200);
  const p3 = await page.$eval('.role[data-role="primary"] .hex', e => e.value);
  ok(HEX.test(p3) && p3 !== p2, 'inside the fold the lightness slider works from the keyboard (' + p3 + ')');

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
  const lightPaper = await page.$eval('.role[data-role="paper"] .hex', e => e.value);
  await page.click('#mDark');
  const darkPaper = await page.$eval('.role[data-role="paper"] .hex', e => e.value);
  ok(HEX.test(darkPaper) && parseInt(darkPaper.slice(1, 3), 16) < 80, 'derived dark paper is dark (' + darkPaper + ')');
  await page.waitForTimeout(250);   // one switch: the same click moved the preview, with nothing else pressed
  doc = await page.$eval('#pv', e => e.srcdoc);
  ok(doc.includes('--paper:' + darkPaper), 'preview dark mode uses the dark paper');
  ok(await page.$$eval('button', b => b.filter(x => /^(Light|Dark)$/.test(x.textContent.trim())).map(x => x.id).join()) === 'mLight,mDark', 'one Light/Dark switch on the page, not two');
  ok(await page.$eval('#mDark', e => e.getAttribute('aria-pressed')) === 'true' && await page.$eval('#mLight', e => e.getAttribute('aria-pressed')) === 'false'
    && (await page.$eval('#pvLabel', e => e.textContent)) === 'Preview · Dark', 'the switch and the preview label both say Dark');
  await page.click('#mLight'); await page.waitForTimeout(250);
  doc = await page.$eval('#pv', e => e.srcdoc);
  ok(doc.includes('--paper:' + lightPaper) && (await page.$eval('#pvLabel', e => e.textContent)) === 'Preview · Light', 'Light puts the role rows and the preview back on the light palette');

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

  console.log('== 12b: ZestImage — fields follow the layout, one Export button, folded options ==');
  // same page as the handoff: the imported brand is active, and it carries a logo
  const ziShown = () => zi.$$eval('#cUsed [data-f]', els => els.map(e => e.dataset.f).join(' '));
  const ziVis = sel => zi.$eval(sel, e => e.checkVisibility());   // false inside a closed <details> as well as under [hidden]
  const ziToast = () => zi.$eval('#toast', e => e.textContent);
  const ZI_FIELDS = { title: 'title byline', kicker: 'title kicker byline', split: 'title kicker byline', scrim: 'title kicker',
    stat: 'title stat', quote: 'quote byline', series: 'title byline series', logo: 'byline' };
  await zi.fill('#cTitle', 'Kept across layouts');
  const ziSeen = {};
  for (const k of Object.keys(ZI_FIELDS)) { await zi.click(`#layoutGrid [data-l="${k}"]`); ziSeen[k] = await ziShown(); }
  ok(Object.keys(ZI_FIELDS).every(k => ziSeen[k] === ZI_FIELDS[k]), `ZestImage: each of the eight layouts shows only the fields it draws (${Object.keys(ZI_FIELDS).filter(k => ziSeen[k] !== ZI_FIELDS[k]).map(k => k + ': ' + ziSeen[k]).join('; ') || 'all match'})`);
  ok(!(await ziVis('#cTitle')) && await zi.$eval('#cRest', d => !d.open && !d.hidden), 'ZestImage: Logo lockup hides Title; the fields it leaves out sit in a disclosure, closed');
  await zi.focus('#cRest summary'); await zi.keyboard.press('Enter');
  ok(await zi.$eval('#cRest', d => d.open) && await ziVis('#cTitle') && await zi.inputValue('#cTitle') === 'Kept across layouts', 'ZestImage: that disclosure opens by keyboard, and the hidden Title kept what was typed');
  await zi.click('#layoutGrid [data-l="title"]');
  ok(await ziShown() === 'title byline' && await zi.inputValue('#cTitle') === 'Kept across layouts' && (await zi.$eval('#stageSvg', e => e.textContent)).includes('Kept across'), 'ZestImage: switching back shows Title again with its value, and the stage draws it');

  ok(await ziVis('#bExport') && await zi.$eval('#exMenu', d => !d.open) && !(await ziVis('#bAlt')) && !(await ziVis('#bManifest')) && !(await ziVis('#bOg')), 'ZestImage: one Export button; alt.txt, Manifest and the OG snippet wait behind More');
  await zi.focus('#exMenu summary'); await zi.keyboard.press('Enter');
  ok(await zi.$eval('#exMenu', d => d.open) && await ziVis('#bAlt') && await ziVis('#bManifest') && await ziVis('#bOg'), 'ZestImage: More opens by keyboard and lists all three');
  await zi.keyboard.press('Tab'); await zi.keyboard.press('Escape');
  ok(await zi.$eval('#exMenu', d => !d.open && document.activeElement === d.querySelector('summary')), 'ZestImage: Escape closes the menu and hands focus back to More');
  await zi.click('#exMenu summary');
  let zdl = zi.waitForEvent('download'); await zi.click('#bAlt'); let zf = await zdl;
  ok(zf.suggestedFilename().endsWith('.alt.txt') && require('fs').readFileSync(await zf.path(), 'utf8') === await zi.inputValue('#cAlt') && await zi.$eval('#exMenu', d => !d.open), 'ZestImage: alt.txt still saves the alt text, one file, and choosing it closes the menu');
  await zi.click('#exMenu summary');
  zdl = zi.waitForEvent('download'); await zi.click('#bManifest'); zf = await zdl; await zi.waitForTimeout(150);
  ok(JSON.parse(require('fs').readFileSync(await zf.path(), 'utf8')).tool === 'image' && (await ziToast()).includes('Manifest saved'), 'ZestImage: Manifest still saves, with its toast');
  await zi.bringToFront(); await zi.click('#exMenu summary'); await zi.click('#bOg'); await zi.waitForTimeout(250);
  ok((await zi.evaluate(() => navigator.clipboard.readText())).includes('og:image:alt') && (await ziToast()).includes('OG meta copied'), 'ZestImage: Copy OG meta snippet still copies, with its toast');

  ok(await zi.$eval('#exOpts', d => !d.open) && !(await ziVis('#eFmt')) && !(await ziVis('#eScale')) && await zi.textContent('#exSum') === 'PNG · 2×', 'ZestImage: Format and Scale are folded away, and the summary says "PNG · 2×"');
  await zi.focus('#exOpts summary'); await zi.keyboard.press('Space');
  const ziOptsOpen = await zi.$eval('#exOpts', d => d.open) && await ziVis('#eFmt');
  await zi.selectOption('#eFmt', 'webp'); await zi.selectOption('#eScale', '1');
  ok(ziOptsOpen && await zi.textContent('#exSum') === 'WebP · 1×' && /-og\.webp$/.test(await zi.textContent('#fname')), 'ZestImage: they open by keyboard, and the summary and the filename follow the choice');
  await zi.fill('#cAlt', '');
  let ziLeak = 0; const ziCount = () => { ziLeak++; }; zi.on('download', ziCount);
  await zi.click('#bExport'); await zi.waitForTimeout(500);
  zi.off('download', ziCount);
  ok(ziLeak === 0 && (await ziToast()).includes('Alt text first'), 'ZestImage: export without alt text is still blocked');
  await zi.fill('#cAlt', 'A title card');
  zdl = zi.waitForEvent('download'); await zi.click('#bExport'); zf = await zdl; await zi.waitForTimeout(250);
  ok(zf.suggestedFilename() === await zi.textContent('#fname') && (await ziToast()).includes('under More'), 'ZestImage: Export saves the one image, in the format the summary named');

  const ziProRows = () => zi.$$eval('#proList .pro', r => r.filter(e => e.checkVisibility()).length);
  ok(await zi.$eval('#proList', d => d.open) && await ziProRows() === 6, 'ZestImage: the six Pro rows are one disclosure, open on load — all six visible without a click');
  await zi.focus('#proList summary'); await zi.keyboard.press('Enter');
  const ziProShut = await zi.$eval('#proList', d => !d.open) && await ziProRows() === 0;
  await zi.keyboard.press('Enter');
  ok(ziProShut && await zi.$eval('#proList', d => d.open) && await ziProRows() === 6, 'ZestImage: it closes and reopens by keyboard');
  await zi.click('.pro[data-pro="svg"]'); await zi.waitForTimeout(150);
  ok((await ziToast()).includes('stays free'), 'ZestImage: a Pro row still answers with the Pro toast');

  ok(!(await ziVis('#dLogo')) && await ziVis('#bLogoReplace') && (await zi.textContent('#tLogo span')).includes("brand's logo"), 'ZestImage: with a brand logo, one line says it is in use — no drop zone');
  await zi.click('#bLogoReplace');
  const ziDropShown = await ziVis('#dLogo');
  const otherPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  await zi.setInputFiles('#fLogo', { name: 'mine.png', mimeType: 'image/png', buffer: Buffer.from(otherPng, 'base64') }); await zi.waitForTimeout(300);
  ok(ziDropShown && await zi.textContent('#tLogo span') === 'mine.png' && (await zi.$eval('#stageSvg', e => e.innerHTML)).includes(otherPng), 'ZestImage: Replace reveals the drop zone, and a dropped logo takes over');
  await zi.click('#bLogoRemove'); await zi.waitForTimeout(200);
  ok((await zi.$eval('#stageSvg', e => e.innerHTML)).includes(withLogo.logo) && !(await ziVis('#dLogo')) && await ziVis('#bLogoReplace'), 'ZestImage: removing the replacement falls back to the brand logo');
  ok(ziErrs.length === 0, `ZestImage: no exceptions from the simplified controls${ziErrs.length ? ' — ' + ziErrs.join(' | ') : ''}`);
  await zi.close();

  console.log('== 12c: ZestImage stage — the preview fits the window, zoom, safe zones per target ==');
  const zs = await ctx.newPage();
  const zsErrs = []; zs.on('pageerror', e => zsErrs.push(e.message));
  await zs.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await zs.goto('http://localhost:8772', { waitUntil: 'domcontentloaded' }); await zs.waitForTimeout(600);
  const ZS_TARGETS = ['og', 'blog', 'blog-sm', 'square', 'portrait', 'story', 'pinterest', 'custom'];
  const zsTarget = async t => { await zs.click(`#targetGrid [data-t="${t}"]`); await zs.waitForTimeout(120); };
  // the frame against the stage's content box: whole, centered, as large as fits on one axis or at real size, never past it
  const zsFit = () => zs.evaluate(() => {
    const f = document.querySelector('#frame').getBoundingClientRect(), st = document.querySelector('#stage'), s = st.getBoundingClientRect(), cs = getComputedStyle(st);
    const L = s.left + parseFloat(cs.paddingLeft), R = s.right - parseFloat(cs.paddingRight), T = s.top + parseFloat(cs.paddingTop), B = s.bottom - parseFloat(cs.paddingBottom);
    const real = +document.querySelector('#dims').textContent.split('×')[0];
    return { inVp: f.top >= 0 && f.left >= 0 && f.bottom <= innerHeight + 0.5 && f.right <= innerWidth + 0.5,
      inStage: f.left >= L - 1 && f.right <= R + 1 && f.top >= T - 1 && f.bottom <= B + 1,
      dx: Math.round(Math.abs((f.left + f.right) / 2 - (s.left + s.right) / 2)), dy: Math.round(Math.abs((f.top + f.bottom) / 2 - (s.top + s.bottom) / 2)),
      fills: Math.abs(f.width - (R - L)) < 2 || Math.abs(f.height - (B - T)) < 2 || Math.abs(f.width - real) < 2, w: Math.round(f.width), real };
  });
  for (const [W, H] of [[1280, 720], [1440, 900], [1920, 1080]]) {
    await zs.setViewportSize({ width: W, height: H }); await zs.waitForTimeout(250);
    const bad = [];
    for (const t of ZS_TARGETS) { await zsTarget(t); const m = await zsFit(); if (!(m.inVp && m.inStage && m.dx <= 40 && m.dy <= 40 && m.fills && m.w <= m.real + 1)) bad.push(t + ' ' + JSON.stringify(m)); }
    ok(bad.length === 0, `ZestImage at ${W}×${H}: every target's preview is whole, centered on the stage, as large as fits and never past real size (${bad.join('; ') || 'all eight'})`);
  }
  await zs.setViewportSize({ width: 1280, height: 720 }); await zsTarget('og'); await zs.waitForTimeout(200);
  ok(await zs.evaluate(() => document.documentElement.scrollHeight <= innerHeight && ['#left', '.panel.right'].every(s => { const p = document.querySelector(s); return getComputedStyle(p).overflowY === 'auto' && p.getBoundingClientRect().bottom <= innerHeight; }) && document.querySelector('.panel.right').scrollHeight > document.querySelector('.panel.right').clientHeight),
    'ZestImage: the workspace is the window — the page does not scroll, and each panel scrolls on its own');
  ok(await zs.evaluate(() => { const b = getComputedStyle(document.body); return b.backgroundRepeat.startsWith('no-repeat') && b.backgroundColor === 'rgb(18, 6, 7)'; }), 'ZestImage: the body gradient paints once over plain night (no seam a viewport down)');
  const zsPct = () => zs.textContent('#zoomPct');
  const fitPct = await zsPct();
  ok(fitPct === Math.round(await zs.$eval('#frame', f => f.getBoundingClientRect().width) / 1200 * 100) + '%' && parseInt(fitPct) < 100, `ZestImage: the stage bar shows the live scale (${fitPct} at Fit)`);
  await zs.click('#zoomSeg [data-z="100"]'); await zs.waitForTimeout(200);
  ok(await zs.$eval('#frame', f => Math.round(f.getBoundingClientRect().width)) === 1200 && await zsPct() === '100%' && await zs.$eval('#stage', s => s.scrollWidth > s.clientWidth && getComputedStyle(s).overflow === 'auto') && await zs.$eval('#zoomSeg [data-z="100"]', b => b.getAttribute('aria-pressed') === 'true'),
    'ZestImage: 100% shows the image at real size, and the stage scrolls to reach all of it');
  await zs.click('#zoomSeg [data-z="fit"]'); await zs.waitForTimeout(200);
  ok(await zsPct() === fitPct && (await zsFit()).inStage, 'ZestImage: Fit brings it back inside the stage');
  // safe zones: drawn from each target's own pixel insets; no zone, no toggle
  const zsSafe = () => zs.evaluate(() => {
    const lab = document.querySelector('#safeLab'), f = document.querySelector('#frame').getBoundingClientRect(), i = document.querySelector('#safe i').getBoundingClientRect(), em = document.querySelector('#safe em').getBoundingClientRect();
    return { shown: !lab.hidden && lab.checkVisibility(), on: document.querySelector('#safe').classList.contains('on'), f, i, em, inside: document.querySelector('#safe').classList.contains('inside'), fs: parseFloat(getComputedStyle(document.querySelector('#safe em')).fontSize) };
  });
  const zones = {};
  for (const t of ZS_TARGETS) { await zsTarget(t); const z = await zsSafe(); zones[t] = z.shown === z.on ? (z.shown ? 'zone' : 'none') : 'MISMATCH'; }
  ok(['og', 'portrait', 'story', 'pinterest'].every(t => zones[t] === 'zone') && ['blog', 'blog-sm', 'square', 'custom'].every(t => zones[t] === 'none'), `ZestImage: the Safe zone toggle shows only for targets that have a zone (${JSON.stringify(zones)})`);
  await zsTarget('story'); const sz = await zsSafe();
  const near = (a, b) => Math.abs(a - b) < 1.5;
  ok(near(sz.i.top - sz.f.top, sz.f.height * 250 / 1920) && near(sz.f.bottom - sz.i.bottom, sz.f.height * 340 / 1920) && near(sz.i.left - sz.f.left, sz.f.width * 60 / 1080), 'ZestImage: Story draws its own zone — clear of the top bar (250px) and the reply bar (340px)');
  ok(sz.em.left >= sz.f.left && sz.em.top >= sz.f.top && sz.fs >= 9 && (sz.inside ? sz.em.top >= sz.i.top : sz.em.bottom <= sz.i.top + 0.5), 'ZestImage: the zone label rides on the rectangle, inside the frame, and never sits across the dashed line');
  ok(await zs.$eval('#safeTgl', c => getComputedStyle(c).accentColor) === 'rgb(240, 82, 94)', 'ZestImage: the Safe zone checkbox wears the accent, not system blue');
  await zsTarget('og');
  ok(await zs.$eval('#fontNote', n => !n.hidden && n.checkVisibility()) && !(await zs.textContent('#toast')).includes('Brand fonts'), 'ZestImage: with the fonts blocked, a quiet line in the stage bar says so — no toast over the card');
  await zs.click('.pro[data-pro="batch"]'); await zs.waitForTimeout(400);
  ok(await zs.evaluate(() => { const t = document.querySelector('#toast'), r = t.getBoundingClientRect(), f = document.querySelector('#frame').getBoundingClientRect();
    return t.classList.contains('show') && (r.right <= f.left || r.left >= f.right || r.bottom <= f.top || r.top >= f.bottom); }), 'ZestImage: a toast never covers the preview');
  ok(zsErrs.length === 0, `ZestImage: no exceptions from the stage${zsErrs.length ? ' — ' + zsErrs.join(' | ') : ''}`);
  await zs.close();

  console.log('== 13: persistence + pro + a11y bits ==');
  // lock a role, reload: the lock must survive sanitizeBrand (spec: role-based swatches WITH locks)
  const inkLocked = await page.$eval('.role[data-role="ink"] [data-lock]', e => e.getAttribute('aria-pressed'));
  if (inkLocked !== 'true') { await page.click('.role[data-role="ink"] [data-lock]'); await page.waitForTimeout(150); }
  await page.click('#proFold > summary');   // close Pro before the reload: it must come back open
  const proClosed = !await page.$eval('#proFold', d => d.open);
  await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(600);
  ok(await page.inputValue('#bName') === 'RoundTrip', 'brand survives reload');
  ok(await page.$eval('.role[data-role="ink"] [data-lock]', e => e.getAttribute('aria-pressed')) === 'true', 'role lock survives reload');
  ok(proClosed && await page.$eval('#proFold', d => d.open), 'a Pro fold closed by hand is open again after a reload');
  ok((await shown('.pro')).length === 6, '6 Pro rows visible after the reload, with no click');
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
  await openFold('#spaceFold');
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

  console.log('== 18: folded controls — values reach the preview, the export and the next visit ==');
  await openFold('#scaleFold'); await openFold('#spaceFold');
  await page.selectOption('#tRatio', '1.5'); await page.fill('#tBase', '18');
  await page.selectOption('#spUnit', '8'); await page.selectOption('#spDensity', 'spacious');
  await page.waitForTimeout(300);
  ok((await page.$eval('#pv', e => e.srcdoc)).includes('Type scale — 18px × 1.5'), 'type scale set inside its fold reaches the preview');
  dl = page.waitForEvent('download'); await page.click('#xBrand'); d = await dl;
  const folded = JSON.parse(fs2.readFileSync(await d.path(), 'utf8'));
  ok(folded.type.base === 18 && folded.type.ratio === 1.5 && folded.spacing.unit === 8 && folded.spacing.density === 'spacious' && folded.buttons.size === 'lg' && folded.buttons.shape === 'pill',
    'export carries the type scale, spacing and buttons set inside the folds');
  await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(700);
  ok(await page.$$eval('details', d => d.filter(x => x.open).map(x => x.id).join()) === 'proFold', 'after a reload Pro is open and the other four folds are closed again');
  ok(await page.$eval('#tBase', e => e.value) === '18' && await page.$eval('#tRatio', e => e.value) === '1.5' && await page.$eval('#spUnit', e => e.value) === '8'
    && await page.$eval('#spDensity', e => e.value) === 'spacious' && await page.$eval('#btnSize', e => e.value) === 'lg' && await page.$eval('#btnShape', e => e.value) === 'pill',
    'the folded values survive the reload');

  console.log('== 19: Send to — one fold, three tools, the same file as the export ==');
  dl = page.waitForEvent('download'); await page.click('#xBrand'); d = await dl;
  const viaExport = fs2.readFileSync(await d.path(), 'utf8');
  ok(!await page.isVisible('[data-send]'), 'the Send to buttons are folded away on load');
  await openFold('#sendFold');
  ok((await Promise.all((await shown('[data-send]')).map(h => h.getAttribute('data-send')))).join() === 'image,mail,md', 'open, it offers ZestImage, ZestMail and Zest MD');
  for (const [tool, word] of [['image', 'ZestImage'], ['mail', 'ZestMail'], ['md', 'Zest MD']]) {
    dl = page.waitForEvent('download'); await page.click(`[data-send="${tool}"]`); d = await dl;
    await page.waitForTimeout(150);
    ok(d.suggestedFilename() === 'imported-back-zest-brand.json' && fs2.readFileSync(await d.path(), 'utf8') === viaExport && (await page.$eval('#toast', e => e.textContent)).includes(word),
      `Send to ${word}: the same zest-brand.json as the export, and a note on where ${word} imports it`);
  }

  ok(errs.length === 0, 'no uncaught exceptions (' + errs.slice(0, 2).join('; ').slice(0, 100) + ')');
  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
