#!/usr/bin/env node
// Offline gate 1 of 3 (ADR 0015, NN5): a static scan of the app's copy of the Zest tools.
//
//   node scripts/offline-scan.mjs [dir] [--json report.json]      dir defaults to ../Resources/Zest
//
// Fails on:
//   load    a network address in a load position: src=, every srcset candidate, srcdoc, href= on
//           link/script/img/iframe/image/use, url(), image-set(), @import, fetch(, XMLHttpRequest open,
//           new Worker, importScripts, EventSource, WebSocket, import(), sendBeacon, serviceWorker.register,
//           new URL(…, base), .src/.href/setAttribute('src'|'href') = … A network address is an http(s)/ws(s)
//           URL, written plainly or JSON-escaped (https:\/\/…), or a protocol-relative //host (a network
//           load on the web, a broken one under zest:// in the app). No allowlist entry can excuse a load.
//   url     any other http(s)/ws(s) URL, or a scheme string joined to something ('https:' + '//…'), that
//           offline-allowlist.json does not name. A URL kept in a table or a template and loaded later is
//           still a load; this is how those are caught. No entry passes a URL whose path ends in a resource
//           extension (.png, .js, .css, .woff2, …) unless it names that one exact URL; a protocol-relative
//           <a href> fails here too.
//   text    the words "pricing" or "Upgrade", and the web's plan ("Pro", "Zest account", "Not in this version"),
//           in user-visible text: HTML text, the attributes people read (title, aria-label, placeholder, alt,
//           value, content, label), href values, and string literals in scripts; and a data-pro row in the
//           markup (App Store rules 3.1.1 and 2.1). "Crimson Pro" is a typeface. vendor/ is library code and is
//           not read for text.
//   rtc     a peer connection (RTCPeerConnection, or a stun:/turn: server) in the tools' own files. WebRTC reaches
//           the network over UDP with no URL load, so neither the rule list nor the policy header stops it.
//   budget  the folder is larger than the budget in offline-allowlist.json.
// Warns (does not fail) on a static src/href to a local file that is not in the folder.
//
// No dependencies. Exit 0 when clean, 1 on any failure, 2 on bad usage.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const jsonAt = argv.indexOf('--json');
const jsonOut = jsonAt >= 0 ? argv.splice(jsonAt, 2)[1] : null;
if (argv.length > 1 || (jsonAt >= 0 && !jsonOut)) { console.error('usage: node scripts/offline-scan.mjs [dir] [--json report.json]'); process.exit(2); }
const ROOT = path.resolve(argv[0] || path.join(HERE, '..', '..', 'Resources', 'Zest'));
const ALLOW = JSON.parse(fs.readFileSync(path.join(HERE, 'offline-allowlist.json'), 'utf8'));
// An entry may pass a resource URL (a path ending in .png, .js, …) only by naming that one URL exactly.
const LITERAL = /^\^(?:\\.|[^\\.*+?()[\]{}|^$])*\$$/;
const urlRules = ALLOW.urls.map(r => {
  if (r.allowResourcePath && !LITERAL.test(r.match)) {
    console.error(`offline-allowlist.json: allowResourcePath needs a match that names one exact URL (^…$, no wildcards): ${r.match}`);
    process.exit(2);
  }
  return { ...r, re: new RegExp(r.match), fileRe: r.file ? new RegExp(r.file) : null };
});
const textRules = (ALLOW.text || []).map(r => ({ ...r, re: new RegExp(r.match), fileRe: r.file ? new RegExp(r.file) : null }));

if (!fs.existsSync(ROOT)) { console.error(`offline-scan: ${ROOT} does not exist (run bash zest/build.sh --app)`); process.exit(2); }

const TEXT_EXT = new Set(['.html', '.htm', '.css', '.js', '.mjs', '.svg', '.json', '.webmanifest', '.xml']);
const failures = [];
const warnings = [];
const add = (list, kind, file, text, off, what, detail) => {
  const line = text.slice(0, off).split('\n').length;
  list.push({ kind, file, line, what, detail });
};

function walk(dir, acc = []) {
  for (const name of fs.readdirSync(dir).sort()) {
    const p = path.join(dir, name);
    if (fs.statSync(p).isDirectory()) walk(p, acc); else acc.push(p);
  }
  return acc;
}

// ---------- URLs ----------
// A URL as written in source: plain, or JSON-escaped (https:\/\/host\/path), as minifiers and
// JSON.stringify'd code write it. Matched text is unescaped before it is judged.
const URL_RE = /(?:https?|wss?):\\?\/\\?\/(?:\$\{|(?:\\\/|[^\s"'`<>()\\{}])+)/gi;
// A protocol-relative address: //host.tld… not preceded by a scheme, a word or another slash.
const PROTO_REL_RE = /(?<![\w:\/\\.-])\\?\/\\?\/(?:[A-Za-z0-9-]+\.)+[A-Za-z][A-Za-z0-9-]*(?::\d+)?(?:(?:\\\/|[\/?#])(?:\\\/|[^\s"'`<>()\\{}])*)?/g;
// A scheme string joined to something else: 'https:' + '//host', "http://" + rest.
const CONCAT_RE = /(["'`])((?:https?|wss?):(?:\\?\/){0,2})\1\s*\+/gi;
const HOSTISH = /^(?:\$\{|[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+|localhost|\[[0-9a-f:]+\])/i;
const RESOURCE_EXT = /\.(?:png|jpe?g|gif|webp|avif|svg|ico|css|js|mjs|json|wasm|woff2?|ttf|otf)$/i;
const LOAD_ATTR = /(?:^|[\s"'])(src|srcset|poster|data|background|xlink:href|href|action|formaction|ping|manifest|icon)\s*=\s*\\?["']?$/i;
const LOAD_TAGS = new Set(['link', 'script', 'img', 'iframe', 'frame', 'image', 'use', 'feimage', 'base', 'embed', 'object', 'source', 'track', 'input', 'video', 'audio', 'form', 'button', 'body', 'table', 'td', 'html']);
// Elements an attribute can sit on. A name outside this set after `<` is code (i<n, a<b), not a tag.
const HTML_TAGS = new Set([...LOAD_TAGS, ...(
  'a abbr address area article aside b bdi bdo blockquote br canvas caption center cite code col colgroup data ' +
  'datalist dd del details dfn dialog div dl dt em fieldset figcaption figure font footer h1 h2 h3 h4 h5 h6 head ' +
  'header hgroup hr i ins kbd label legend li main map mark menu meta meter nav noscript ol optgroup option output ' +
  'p param picture pre progress q rp rt ruby s samp section select slot small span strong style sub summary sup ' +
  'tbody template textarea tfoot th thead time title tr u ul var wbr svg g path rect circle ellipse line polyline ' +
  'polygon text tspan textpath defs symbol pattern mask clippath lineargradient radialgradient stop filter ' +
  'foreignobject marker math').split(' ')]);
const LOAD_JS = [
  [/\bfetch\s*\(\s*["'`]$/, 'fetch('],
  [/\bimportScripts\s*\(\s*["'`]$/, 'importScripts('],
  [/\bimport\s*\(\s*["'`]$/, 'import('],
  [/\bsendBeacon\s*\(\s*["'`]$/, 'sendBeacon('],
  [/\bregister\s*\(\s*["'`]$/, 'serviceWorker.register('],
  [/\bnew\s+(?:Shared)?Worker\s*\(\s*["'`]$/, 'new Worker('],
  [/\bnew\s+EventSource\s*\(\s*["'`]$/, 'new EventSource('],
  [/\bnew\s+WebSocket\s*\(\s*["'`]$/, 'new WebSocket('],
  [/\bnew\s+URL\s*\([^()]*,\s*["'`]$/, 'new URL(…, base)'],
  [/\.open\s*\(\s*["'`][A-Za-z]+["'`]\s*,\s*["'`]$/, 'XMLHttpRequest open'],
  [/\.(?:src|href|srcset|action|data|poster)\s*=\s*["'`]$/, '.src/.href ='],
  [/setAttribute(?:NS)?\s*\([^)]*["'](?:src|href|srcset|xlink:href|action|data|poster)["']\s*,\s*["'`]$/, 'setAttribute(src|href)'],
  [/\burl\(\s*["']?$/i, 'url()'],
  [/@import\s+(?:url\(\s*)?["']?$/i, '@import'],
  [/;\s*url=$/i, 'meta refresh'],
];

// The element whose attribute list `off` sits in, or null. The text between `<name` and `off` must parse as
// attributes (name, name=value, ${…}), so a JS variable `data = '…'` or `i<n; src = '…'` is not mistaken for one.
const TAG_ATTRS = /^<([A-Za-z][\w:-]*)(?:\s+(?:\$\{[^}]*\}|[^\s"'<>=\/`]+(?:\s*=\s*(?:\\?"[^"]*?\\?"|\\?'[^']*?\\?'|\$\{[^}]*\}|[^\s"'<>=`]+))?))*\s+[^\s"'<>=\/`]+\s*=\s*\\?["']?$/;
function enclosingTag(text, off) {
  const lt = text.lastIndexOf('<', off);
  if (lt < 0 || off - lt > 4000 || text.lastIndexOf('>', off) > lt) return null;
  const m = text.slice(lt, off).match(TAG_ATTRS);
  return m && HTML_TAGS.has(m[1].toLowerCase()) ? m[1].toLowerCase() : null;
}

const SRCDOC_OPEN = /\bsrcdoc\s*=\s*\\?(["'])(?:(?!\1)[^])*$/i;
function classify(text, off) {
  const before = text.slice(Math.max(0, off - 240), off);
  for (const [re, what] of LOAD_JS) if (re.test(before)) return { load: true, what };
  if (/\bsrcset\s*=\s*\\?["'][^"'<>]*$/i.test(before)) return { load: true, what: 'srcset candidate' };
  if (/image-set\(\s*[^;{}]*$/i.test(before)) return { load: true, what: 'image-set()' };
  if (SRCDOC_OPEN.test(text.slice(Math.max(0, off - 20000), off))) return { load: true, what: 'inside srcdoc (a document the frame loads)' };
  const attr = before.match(LOAD_ATTR);
  const tag = attr && enclosingTag(text, off);
  if (tag) {
    const name = attr[1].toLowerCase();
    if (name === 'href' || name === 'xlink:href') {
      if (LOAD_TAGS.has(tag)) return { load: true, what: `<${tag} ${name}>` };
      return { load: false, what: `<${tag} href> link` };
    }
    // src, srcset and ping load from any element; data, poster, background, action and the rest only on
    // the elements that fetch them (object, video, body/table/td, form/button/input, html).
    if (name === 'src' || name === 'srcset' || name === 'ping' || LOAD_TAGS.has(tag)) return { load: true, what: `<${tag} ${name}>` };
    return { load: false, what: `<${tag} ${name}>` };
  }
  return { load: false, what: '' };
}

const resourcePath = url => {
  try { return RESOURCE_EXT.test(new URL(url.replace(/^ws(s?):/i, 'http$1:')).pathname); }
  catch { return RESOURCE_EXT.test(url.split(/[?#]/)[0]); }
};
const reported = new Set();   // "file@offset" of every load already failed, so two scanners never report one twice
function judge(rel, text, off, url, key = url) {
  const c = classify(text, off);
  if (c.load) { reported.add(`${rel}@${off}`); add(failures, 'load', rel, text, off, url, c.what); return; }
  const ok = urlRules.find(r => r.re.test(key) && (!r.fileRe || r.fileRe.test(rel)) && (r.allowResourcePath || !resourcePath(key)));
  if (ok) return;
  const why = resourcePath(key) ? 'a resource address kept as a value: no allowlist entry passes one unless it names it exactly'
    : c.what || 'a URL kept as a value; loaded later, or not allowlisted';
  add(failures, 'url', rel, text, off, url, why);
}

function scanUrls(rel, text) {
  for (const m of text.matchAll(URL_RE)) {
    const url = m[0].replace(/\\\//g, '/').replace(/&(?:quot|apos|#34|#39);[^]*$/i, '').replace(/[.:]+$/, '');
    const host = url.replace(/^[a-z]+:\/\//i, '');
    if (!HOSTISH.test(host)) continue;   // "https://…", a regex like /^http:\/\//: text, not an address
    judge(rel, text, m.index, url);
  }
  for (const m of text.matchAll(PROTO_REL_RE)) {
    const c = classify(text, m.index);
    if (!c.load) continue;   // //host outside a load position is a comment or prose
    reported.add(`${rel}@${m.index}`);
    add(failures, 'load', rel, text, m.index, m[0].replace(/\\\//g, '/'), `${c.what}, protocol-relative`);
  }
  for (const m of text.matchAll(CONCAT_RE)) {
    const scheme = m[2].replace(/\\\//g, '/').replace(/:\/*$/, '').toLowerCase();
    judge(rel, text, m.index + 1, `${m[1]}${m[2]}${m[1]} + …`, `${scheme}://+`);
  }
}

// ---------- visible text ----------
const WORDS = /\b(pricing|upgrade[sd]?)\b/gi;
const PLAN_WORDS = /(?<!Crimson )\bPro\b|\bZest accounts?\b|\bNot in this version\b/g;   // the web's plan; the app has none
const VISIBLE_ATTR = /\s(title|aria-label|placeholder|alt|value|content|label|href)\s*=\s*(?:"([^"]*)"|'([^']*)')/gi;
const mask = (s, re) => s.replace(re, x => x.replace(/[^\n]/g, ' '));   // keep offsets and line numbers

// String literals and template-literal text from JS source, with their offsets. Comments and regex
// literals are skipped; code inside ${…} is read as code (its strings are collected too).
function jsStrings(code, base) {
  const out = [];
  const stack = [];          // one entry per open ${: the brace depth inside it
  let i = 0, last = '', word = '';
  const n = code.length;
  const regexOK = () => !last || /[(,=:[!&|?{};+\-*%<>~^]$/.test(last) ||
    /^(return|typeof|case|do|else|in|of|new|delete|void|throw|instanceof|yield|await)$/.test(last);
  function template(start) {   // reads template text from start; returns index after ` or after ${
    let j = start, buf = '', from = start;
    while (j < n) {
      const ch = code[j];
      if (ch === '\\') { buf += code.slice(j, j + 2); j += 2; continue; }
      if (ch === '`') { out.push({ s: buf, off: base + from }); last = 'a'; return j + 1; }
      if (ch === '$' && code[j + 1] === '{') { out.push({ s: buf, off: base + from }); stack.push(0); last = '{'; return j + 2; }
      buf += ch; j++;
    }
    out.push({ s: buf, off: base + from });
    return n;
  }
  while (i < n) {
    const c = code[i];
    if (c === '/' && code[i + 1] === '/') { const e = code.indexOf('\n', i); i = e < 0 ? n : e; continue; }
    if (c === '/' && code[i + 1] === '*') { const e = code.indexOf('*/', i + 2); i = e < 0 ? n : e + 2; continue; }
    if (c === '"' || c === "'") {
      let j = i + 1, buf = '';
      while (j < n && code[j] !== c && code[j] !== '\n') { if (code[j] === '\\') { buf += code.slice(j, j + 2); j += 2; } else buf += code[j++]; }
      out.push({ s: buf, off: base + i + 1 });
      i = j + 1; last = 'a'; word = ''; continue;
    }
    if (c === '`') { i = template(i + 1); word = ''; continue; }
    if (c === '/' && regexOK()) {
      let j = i + 1, cls = false;
      while (j < n && code[j] !== '\n') {
        if (code[j] === '\\') { j += 2; continue; }
        if (code[j] === '[') cls = true; else if (code[j] === ']') cls = false;
        else if (code[j] === '/' && !cls) break;
        j++;
      }
      i = j + 1;
      while (i < n && /[a-z]/i.test(code[i])) i++;
      last = 'a'; word = ''; continue;
    }
    if (c === '{' && stack.length) stack[stack.length - 1]++;
    if (c === '}' && stack.length) {
      if (stack[stack.length - 1] === 0) { stack.pop(); i = template(i + 1); word = ''; continue; }
      stack[stack.length - 1]--;
    }
    if (/[\w$]/.test(c)) { word += c; last = word; }
    else { word = ''; if (!/\s/.test(c)) last = c; }
    i++;
  }
  return out;
}

function visibleBits(fragment) {   // text and readable attribute values of an HTML fragment, with offsets
  const bits = [];
  for (const m of fragment.matchAll(VISIBLE_ATTR)) bits.push({ s: m[2] ?? m[3] ?? '', off: m.index, where: m[1].toLowerCase() });
  const noTags = fragment.replace(/<[^>]*>/g, x => ' '.repeat(x.length));
  bits.push({ s: noTags, off: 0, where: 'text' });
  return bits;
}

function scanWords(rel, text, s, off, where) {
  for (const m of [...s.matchAll(WORDS), ...s.matchAll(PLAN_WORDS)]) {
    const at = off + m.index;
    const excerpt = s.slice(Math.max(0, m.index - 40), m.index + 40).replace(/\s+/g, ' ').trim();
    if (textRules.some(r => r.re.test(excerpt) && (!r.fileRe || r.fileRe.test(rel)))) continue;
    add(failures, 'text', rel, text, at, `"${m[0]}"`, `${where}: …${excerpt}…`);
  }
}

function scanText(rel, text, ext) {
  if (ext === '.js' || ext === '.mjs') {
    for (const lit of jsStrings(text, 0)) for (const b of visibleBits(lit.s)) scanWords(rel, text, b.s, lit.off + b.off, `string (${b.where})`);
    return;
  }
  if (ext !== '.html' && ext !== '.htm' && ext !== '.svg') return;
  for (const m of text.matchAll(/(<script\b[^>]*>)([\s\S]*?)<\/script>/gi)) {
    if (/\btype=["'](?!text\/javascript|module)[^"']+["']/i.test(m[1])) continue;   // JSON, templates
    const base = m.index + m[1].length;
    for (const lit of jsStrings(m[2], base)) for (const b of visibleBits(lit.s)) scanWords(rel, text, b.s, lit.off + b.off, `script string (${b.where})`);
  }
  let html = mask(text, /<script\b[^>]*>[\s\S]*?<\/script>/gi);
  html = mask(html, /<style\b[^>]*>[\s\S]*?<\/style>/gi);
  html = mask(html, /<!--[\s\S]*?-->/g);
  for (const b of visibleBits(html)) scanWords(rel, text, b.s, b.off, b.where === 'text' ? 'page text' : `attribute ${b.where}`);
  for (const m of html.matchAll(/\sdata-pro\b/g)) add(failures, 'text', rel, text, m.index + 1, 'data-pro', 'a Pro row in the markup');
}

// ---------- WebRTC ----------
const RTC = /\b(?:webkit)?RTC(?:PeerConnection|DataChannel|IceCandidate)\b|\b(?:stun|turns?):(?=[\w[\/])/g;
function scanRtc(rel, text) {
  for (const m of text.matchAll(RTC)) add(failures, 'rtc', rel, text, m.index, m[0], 'a peer connection reaches the network past the rule list and the policy');
}

// ---------- local references (warnings) ----------
function scanLocalRefs(file, rel, text) {
  const html = mask(text, /<script\b[^>]*>[\s\S]*?<\/script>/gi);
  for (const m of html.matchAll(/<(link|script|img|iframe|a)\b[^>]*?\s(?:src|href)=(["'])([^"'#?]*)[^"']*\2/gi)) {
    const ref = m[3];
    const at = m[0].match(/\s(?:src|href)=["']/);
    const off = m.index + at.index + at[0].length;   // where the value starts
    if (ref.startsWith('//')) {   // protocol-relative: a network address on the web, a broken one in the app
      if (!reported.has(`${rel}@${off}`)) {
        const tag = m[1].toLowerCase();
        add(failures, tag === 'a' ? 'url' : 'load', rel, text, off, ref, `<${tag}> protocol-relative: a network address on the web, broken under zest://`);
      }
      continue;
    }
    if (!ref || /^[a-z][a-z0-9+.-]*:/i.test(ref) || ref.includes('${')) continue;
    let target = path.resolve(path.dirname(file), ref);
    if (ref.endsWith('/')) target = path.join(target, 'index.html');
    if (!target.startsWith(ROOT + path.sep) && target !== ROOT) { add(warnings, 'ref', rel, text, m.index, ref, 'points outside the folder'); continue; }
    if (!fs.existsSync(target)) add(warnings, 'ref', rel, text, m.index, ref, `<${m[1].toLowerCase()}> names a file that is not in the folder`);
  }
}

// ---------- run ----------
const files = walk(ROOT);
let bytes = 0;
for (const file of files) {
  const rel = path.relative(ROOT, file).split(path.sep).join('/');
  bytes += fs.statSync(file).size;
  const ext = path.extname(file).toLowerCase();
  if (!TEXT_EXT.has(ext)) continue;
  const text = fs.readFileSync(file, 'utf8');
  scanUrls(rel, text);
  if (!rel.startsWith('vendor/')) {
    scanText(rel, text, ext);
    scanRtc(rel, text);
    if (ext === '.html') scanLocalRefs(file, rel, text);
  }
}
const budget = ALLOW.budgetBytes;
const mb = b => (b / 1048576).toFixed(2) + ' MB';
if (budget && bytes > budget) failures.push({ kind: 'budget', file: '.', line: 0, what: mb(bytes), detail: `over the ${mb(budget)} budget in offline-allowlist.json` });

console.log(`offline-scan: ${path.relative(process.cwd(), ROOT) || '.'} — ${files.length} files, ${mb(bytes)} (budget ${mb(budget)})`);
const order = { load: 0, rtc: 1, url: 2, text: 3, budget: 4 };
failures.sort((a, b) => order[a.kind] - order[b.kind] || (a.file < b.file ? -1 : a.file > b.file ? 1 : a.line - b.line));
for (const f of failures) console.log(`  FAIL ${f.kind.padEnd(6)} ${f.file}:${f.line}  ${f.what.length > 110 ? f.what.slice(0, 107) + '...' : f.what}${f.detail ? '  [' + f.detail + ']' : ''}`);
for (const w of warnings) console.log(`  warn ${w.kind.padEnd(6)} ${w.file}:${w.line}  ${w.what}  [${w.detail}]`);
if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify({ root: ROOT, files: files.length, bytes, budget, failures, warnings }, null, 2) + '\n');
const counts = Object.entries(failures.reduce((o, f) => (o[f.kind] = (o[f.kind] || 0) + 1, o), {})).map(([k, v]) => `${v} ${k}`).join(', ');
console.log(failures.length ? `RESULT: ${failures.length} failure(s) — ${counts}` : 'RESULT: clean — no network address in a load position, no peer connection, nothing unlisted, no pricing, Upgrade or Pro text');
process.exit(failures.length ? 1 : 0);
