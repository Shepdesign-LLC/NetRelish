// Sound suite: the zest-sound kit inlined in all four tools, each tool's Sound toggle, and its wiring.
// Web Audio is replaced with a counting stand-in before each page loads, so the suite hears nothing and
// counts everything: contexts made, oscillators started, the loudest gain, the longest note.
// Serve: studio :8771, image :8772, mail :8773, md :8774, dist :8780 (run.js hosts all five).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const LAUNCH = process.env.ZEST_CHROMIUM ? { executablePath: process.env.ZEST_CHROMIUM } : {}; // point at a system Chromium when the local playwright has no downloaded browsers
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  PASS ' + m); } else { fail++; console.error('  FAIL ' + m); } };

const APPS = path.join(__dirname, '..', 'apps');
const KEY = 'zest.sound';
const KIT = /\/\* zest-sound:start v\d+ \*\/[\s\S]*?\/\* zest-sound:end \*\//g;
const LOCAL = /^(https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?\/|data:|blob:|about:)/;
const KNOWN_HOSTS = /^https:\/\/(fonts\.googleapis\.com|fonts\.gstatic\.com|cdnjs\.cloudflare\.com)\//;   // fonts and Zest MD's pinned libraries: there before sound, aborted here like every suite does
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');

// Each step is a real click or key press, and the sound it must make.
const TOOLS = [
  { name: 'studio', dir: 'zest', url: 'http://localhost:8771/', toggle: '#bSound', steps: [
    ['switching the palette to Dark', 'tap', pg => pg.click('#mDark')],
    ['Shuffle', 'pop', pg => pg.click('#bShuffle')],
    ['saving the brand', 'done', pg => pg.click('#bSave')],
    ['removing a saved brand', 'drop', pg => pg.click('#savedList .bdel')],
    ['a Pro row', 'nope', pg => pg.click('.pro')],
  ] },
  { name: 'image', dir: 'image', url: 'http://localhost:8772/', toggle: '#bSound', steps: [
    ['switching to Dark', 'tap', pg => pg.click('#mDark')],
    ['choosing a layout', 'tap', pg => pg.click('#layoutGrid .lcell:nth-child(2)')],
    ['adding a photo', 'pop', pg => pg.setInputFiles('#fPhoto', { name: 'photo.png', mimeType: 'image/png', buffer: PNG })],
    ['removing the photo', 'drop', pg => pg.click('#tPhoto button')],
    ['copying the OG snippet', 'done', pg => pg.click('#bOg')],
    ['a Pro row', 'nope', pg => pg.click('.pro')],
  ] },
  { name: 'mail', dir: 'mail', url: 'http://localhost:8773/', toggle: '#btnSound', steps: [
    ['switching to the Message tab', 'tap', pg => pg.click('#tabs button[data-t="message"]')],
    ['exporting an empty canvas', 'nope', async pg => { await pg.click('#btnExport'); await pg.click('#popExport [data-do="copy"]'); }],
    ['adding a block', 'pop', pg => pg.click('#lib .lib-item')],
    ['copying the email HTML', 'done', async pg => { await pg.click('#btnExport'); await pg.click('#popExport [data-do="copy"]'); }],
    ['removing the block', 'drop', pg => pg.click('.cv-block[aria-selected="true"] [data-act="del"]')],
  ] },
  { name: 'md', dir: 'md', url: 'http://localhost:8774/', toggle: '#btnSound', steps: [
    ['exporting with nothing open', 'nope', async pg => { await pg.click('#btnExportMenu'); await pg.click('#popExport [data-do="copymd"]'); }],
    ['opening the sample', 'pop', pg => pg.click('[data-act="sample"]')],
    ['opening Contents', 'tap', pg => pg.click('#btnToc')],
    ['copying the Markdown', 'done', async pg => { await pg.click('#btnExportMenu'); await pg.click('#popExport [data-do="copymd"]'); }],
    ['exporting in one click', 'done', pg => pg.click('#btnExport')],
    ['closing the tab', 'drop', pg => pg.click('#tabs .tab .x')],
  ] },
];

// Runs before the page's own scripts: a stand-in AudioContext that makes no sound and keeps count.
function fakeAudio() {
  const seen = window.__zs = { contexts: 0, starts: 0, peak: 0, longest: 0, names: [] };
  const param = onValue => ({ value: 0,
    setValueAtTime(v) { onValue && onValue(v); return this; },
    exponentialRampToValueAtTime(v) { onValue && onValue(v); return this; },
    linearRampToValueAtTime(v) { onValue && onValue(v); return this; } });
  class FakeAudioContext {
    constructor() { seen.contexts++; this.state = 'running'; this.currentTime = 0; this.destination = {}; }
    createOscillator() { let at = 0; return { type: 'sine', frequency: param(), connect() {},
      start(t) { seen.starts++; at = t || 0; }, stop(t) { seen.longest = Math.max(seen.longest, (t || 0) - at); } }; }
    createGain() { return { gain: param(v => { seen.peak = Math.max(seen.peak, v); }), connect() {} }; }
    resume() { this.state = 'running'; return Promise.resolve(); }
    suspend() { this.state = 'suspended'; return Promise.resolve(); }
  }
  window.AudioContext = window.webkitAudioContext = FakeAudioContext;
}
const noAudio = () => { delete window.AudioContext; delete window.webkitAudioContext; };
const noStorage = () => { Object.defineProperty(window, 'localStorage', { get() { throw new DOMException('denied', 'SecurityError'); } }); };

(async () => {
  console.log('== the kit: one block, four identical copies ==');
  const blocks = TOOLS.map(t => (fs.readFileSync(path.join(APPS, t.dir, 'index.html'), 'utf8').match(KIT) || []));
  TOOLS.forEach((t, i) => ok(blocks[i].length === 1, `${t.name}: the kit block is present, once`));
  ok(blocks.every(b => b.length === 1 && b[0] === blocks[0][0]), 'the four kit blocks are byte-identical');
  const kit = (blocks[0] && blocks[0][0]) || '';
  ok(kit.length > 0 && kit.split('\n').length <= 120, `the kit stays small (${kit.split('\n').length} lines)`);
  ok(!/https?:|\/\/[a-z0-9-]+\.[a-z]|fetch\s*\(|XMLHttpRequest|sendBeacon|WebSocket|EventSource|new Audio|<audio|import\s*\(|\.src\s*=/i.test(kit), 'the kit names no address, no audio file and no way to make a request');

  const browser = await chromium.launch(LAUNCH);
  // one context per tool: every tool here is its own origin (port), so each starts with clean storage
  const open = async (url, { init = fakeAudio, extra } = {}) => {
    const ctx = await browser.newContext({ serviceWorkers: 'block', permissions: ['clipboard-read', 'clipboard-write'] });
    await ctx.addInitScript(init);
    if (extra) await ctx.addInitScript(extra);
    const pg = await ctx.newPage();
    const errs = [], reqs = [];
    pg.on('pageerror', e => errs.push(e.message));
    pg.on('request', r => reqs.push(r.url()));
    await pg.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
    await pg.goto(url, { waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(600);
    return { ctx, pg, errs, reqs };
  };
  const seen = pg => pg.evaluate(() => Object.assign({}, window.__zs, { names: window.__zs.names.slice() }));
  const reset = pg => pg.evaluate(() => Object.assign(window.__zs, { starts: 0, peak: 0, longest: 0, names: [] }));
  // record which sound each call asked for, without changing what the kit does
  const listen = pg => pg.evaluate(() => { const play = window.ZestSound.play; window.ZestSound.play = n => { window.__zs.names.push(n); return play(n); }; });
  const toggle = (pg, sel) => pg.$eval(sel, (b, key) => ({ tag: b.tagName, name: (b.getAttribute('aria-label') || b.textContent || '').trim(), pressed: b.getAttribute('aria-pressed'),
    shown: b.getBoundingClientRect().width > 0, title: b.title, stored: localStorage.getItem(key), muted: window.ZestSound.muted }), KEY);

  for (const t of TOOLS) {
    console.log(`== ${t.name} ==`);
    const { ctx, pg, errs, reqs } = await open(t.url);

    // nothing on load
    let s = await seen(pg);
    ok(s.contexts === 0 && s.starts === 0, `${t.name}: nothing plays on load, and no audio context is made`);
    await pg.evaluate(() => { for (const n of ['tap', 'pop', 'drop', 'done', 'nope']) window.ZestSound.play(n); });
    s = await seen(pg);
    ok(s.contexts === 0 && s.starts === 0, `${t.name}: a script cannot make it play before the first real gesture`);
    ok(await pg.evaluate(() => typeof window.ZestSound.play === 'function' && typeof window.ZestSound.setMuted === 'function' && window.ZestSound.muted === false), `${t.name}: window.ZestSound = { play, muted, setMuted }, on by default`);

    // the toggle
    let tg = await toggle(pg, t.toggle);
    ok(tg.tag === 'BUTTON' && tg.shown, `${t.name}: the Sound toggle is a button, on screen`);
    ok(tg.name === 'Sound', `${t.name}: its accessible name is "Sound" (got "${tg.name}")`);
    ok(tg.pressed === 'true' && tg.title.length > 0, `${t.name}: aria-pressed="true" by default, with a tooltip`);
    ok(await pg.$$eval('[data-zest-sound]', b => b.length) === 1, `${t.name}: one toggle, no more`);

    // unmuted: each wired interaction makes its sound
    await listen(pg);
    for (const [what, name, act] of t.steps) {
      await reset(pg); await act(pg); await pg.waitForTimeout(250);
      s = await seen(pg);
      ok(s.starts >= 1 && s.names.includes(name), `${t.name}: ${what} plays "${name}" (${s.starts} oscillator${s.starts === 1 ? '' : 's'} started; asked for ${s.names.join(', ') || 'nothing'})`);
      ok(s.peak > 0 && s.peak <= 0.08 && s.longest <= 0.2, `${t.name}: … quietly and briefly (peak gain ${s.peak}, ${Math.round(s.longest * 1000)} ms)`);
    }
    ok((await seen(pg)).contexts === 1, `${t.name}: one audio context for the whole session`);

    // mute by keyboard; it persists
    await pg.focus(t.toggle); await pg.keyboard.press('Space'); await pg.waitForTimeout(100);
    tg = await toggle(pg, t.toggle);
    ok(tg.pressed === 'false' && tg.muted === true && tg.stored === 'off', `${t.name}: Space on the toggle mutes — aria-pressed="false", ${KEY}=off`);
    await reset(pg);
    await pg.evaluate(() => { for (const n of ['tap', 'pop', 'drop', 'done', 'nope']) window.ZestSound.play(n); });
    ok((await seen(pg)).starts === 0, `${t.name}: muted, no oscillator starts`);

    // muted survives a reload, and the wired interactions stay silent
    await pg.reload({ waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(600);
    tg = await toggle(pg, t.toggle);
    ok(tg.pressed === 'false' && tg.muted === true && tg.stored === 'off', `${t.name}: muted survives a reload`);
    await listen(pg);
    for (const [, , act] of t.steps.slice(0, 3)) { await act(pg).catch(() => {}); await pg.waitForTimeout(150); }
    s = await seen(pg);
    ok(s.names.length >= 2 && s.starts === 0 && s.contexts === 0, `${t.name}: muted, the same interactions start no oscillator and make no audio context (${s.names.length} sounds asked for)`);

    // unmute by click: it answers with a tap, and persists
    await reset(pg); await pg.click(t.toggle); await pg.waitForTimeout(150);
    tg = await toggle(pg, t.toggle); s = await seen(pg);
    ok(tg.pressed === 'true' && tg.muted === false && tg.stored === 'on', `${t.name}: a click turns sound back on — aria-pressed="true", ${KEY}=on`);
    ok(s.starts >= 1, `${t.name}: turning sound on answers with a tap`);
    await pg.reload({ waitUntil: 'domcontentloaded' }); await pg.waitForTimeout(600);
    tg = await toggle(pg, t.toggle);
    ok(tg.pressed === 'true' && tg.stored === 'on', `${t.name}: on survives a reload`);

    // nothing left the machine: every request is local, or one of the hosts the tools already used (aborted above)
    const away = [...new Set(reqs.filter(u => !LOCAL.test(u)))];
    ok(away.every(u => KNOWN_HOSTS.test(u)), `${t.name}: no request to a new host (${away.filter(u => !KNOWN_HOSTS.test(u)).join(', ') || 'none'})`);
    ok(!reqs.some(u => /\.(mp3|wav|ogg|m4a|aac|flac|opus)(\?|$)/i.test(u)), `${t.name}: no audio file is requested`);
    ok(errs.length === 0, `${t.name}: no uncaught exceptions${errs.length ? ' — ' + errs.join(' | ') : ''}`);
    await ctx.close();

    // no Web Audio at all: the tool works, the toggle works, nothing throws
    const bare = await open(t.url, { init: noAudio });
    await t.steps[0][2](bare.pg).catch(() => {}); await bare.pg.click(t.toggle); await bare.pg.click(t.toggle); await bare.pg.waitForTimeout(150);
    ok(bare.errs.length === 0 && await bare.pg.$eval(t.toggle, b => b.getAttribute('aria-pressed')) === 'true', `${t.name}: without Web Audio nothing throws and the toggle still works${bare.errs.length ? ' — ' + bare.errs.join(' | ') : ''}`);
    await bare.ctx.close();

    // no localStorage: on by default, nothing throws, the toggle still mutes for this visit
    const locked = await open(t.url, { extra: noStorage });
    const before = await locked.pg.$eval(t.toggle, b => b.getAttribute('aria-pressed'));
    await locked.pg.click(t.toggle); await locked.pg.waitForTimeout(100);
    const after = await locked.pg.$eval(t.toggle, b => b.getAttribute('aria-pressed'));
    ok(before === 'true' && after === 'false' && locked.errs.length === 0, `${t.name}: without localStorage sound is on by default and nothing throws${locked.errs.length ? ' — ' + locked.errs.join(' | ') : ''}`);
    await locked.ctx.close();
  }

  console.log('== one key for all four tools (dist: one origin) ==');
  const one = await open('http://localhost:8780/');
  await one.pg.click('#bSound'); await one.pg.waitForTimeout(100);
  ok(await one.pg.evaluate(k => localStorage.getItem(k), KEY) === 'off', 'muting in the studio writes the shared key');
  for (const [p, sel] of [['/mail/', '#btnSound'], ['/md/', '#btnSound'], ['/image/', '#bSound']]) {
    await one.pg.goto('http://localhost:8780' + p, { waitUntil: 'domcontentloaded' }); await one.pg.waitForTimeout(500);
    ok(await one.pg.$eval(sel, b => b.getAttribute('aria-pressed')) === 'false' && await one.pg.evaluate(() => window.ZestSound.muted), `${p} opens muted — same key, same choice`);
  }
  // a second tab on the same origin follows the change without a reload
  const second = await one.ctx.newPage();
  await second.route(/fonts\.(googleapis|gstatic)\.com|cdnjs\.cloudflare\.com/, r => r.abort());
  await second.goto('http://localhost:8780/', { waitUntil: 'domcontentloaded' }); await second.waitForTimeout(500);
  await one.pg.click('#bSound'); await second.waitForTimeout(300);   // one.pg is on /image/: turn sound back on there
  ok(await second.$eval('#bSound', b => b.getAttribute('aria-pressed')) === 'true', 'an open studio tab follows a change made in another tool');
  ok(one.errs.length === 0, `no uncaught exceptions across the origin${one.errs.length ? ' — ' + one.errs.join(' | ') : ''}`);
  await one.ctx.close();

  await browser.close();
  console.log(`\nTALLY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
