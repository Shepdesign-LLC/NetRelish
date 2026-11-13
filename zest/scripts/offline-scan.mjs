#!/usr/bin/env node
// Offline gate 1 of 3 (ADR 0015, NN5): a static scan of the app's copy of the Zest tools.
//
//   node scripts/offline-scan.mjs [dir] [--json report.json]      dir defaults to ../Resources/Zest
//
// Fails on:
//   load    an http(s)/ws(s) URL in a load position: src=, srcset=, href= on link/script/img/iframe/image/use,
//           url(), @import, fetch(, XMLHttpRequest open, new Worker, importScripts, EventSource, WebSocket,
//           import(), sendBeacon, serviceWorker.register, .src/.href/setAttribute('src'|'href') = …
//           No allowlist entry can excuse one of these.
//   url     any other http(s)/ws(s) URL that offline-allowlist.json does not name. A URL kept in a table or
//           a template and loaded later is still a load; this is how those are caught.
//   text    the words "pricing" or "Upgrade" in user-visible text: HTML text, the attributes people read
//           (title, aria-label, placeholder, alt, value, content, label), href values, and string literals in
//           scripts (App Store rule 3.1.1). vendor/ is library code and is not read for text.
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
const urlRules = ALLOW.urls.map(r => ({ ...r, re: new RegExp(r.match), fileRe: r.file ? new RegExp(r.file) : null }));
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
const URL_RE = /(?:https?|wss?):\/\/(?:\$\{|[^\s"'`<>()\\{}]+)/gi;
const HOSTISH = /^(?:\$\{|[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+|localhost|\[[0-9a-f:]+\])/i;
const LOAD_ATTR = /(?:^|[\s"'])(src|srcset|poster|data|background|xlink:href|href|action|formaction|ping|manifest|icon)\s*=\s*\\?["']?$/i;
const LOAD_TAGS = new Set(['link', 'script', 'img', 'iframe', 'frame', 'image', 'use', 'feimage', 'base', 'embed', 'object', 'source', 'track', 'input', 'video', 'audio', 'form', 'button', 'body', 'table', 'td', 'html']);
const LOAD_JS = [
  [/\bfetch\s*\(\s*["'`]$/, 'fetch('],
  [/\bimportScripts\s*\(\s*["'`]$/, 'importScripts('],
  [/\bimport\s*\(\s*["'`]$/, 'import('],
  [/\bsendBeacon\s*\(\s*["'`]$/, 'sendBeacon('],
  [/\bregister\s*\(\s*["'`]$/, 'serviceWorker.register('],
  [/\bnew\s+(?:Shared)?Worker\s*\(\s*["'`]$/, 'new Worker('],
  [/\bnew\s+EventSource\s*\(\s*["'`]$/, 'new EventSource('],
  [/\bnew\s+WebSocket\s*\(\s*["'`]$/, 'new WebSocket('],
  [/\.open\s*\(\s*["'`][A-Za-z]+["'`]\s*,\s*["'`]$/, 'XMLHttpRequest open'],
  [/\.(?:src|href|srcset|action|data|poster)\s*=\s*["'`]$/, '.src/.href ='],
  [/setAttribute(?:NS)?\s*\([^)]*["'](?:src|href|srcset|xlink:href|action|data|poster)["']\s*,\s*["'`]$/, 'setAttribute(src|href)'],
  [/\burl\(\s*["']?$/i, 'url()'],
  [/@import\s+(?:url\(\s*)?["']?$/i, '@import'],
  [/;\s*url=$/i, 'meta refresh'],
];

function enclosingTag(text, off) {
  const lt = text.lastIndexOf('<', off);
  if (lt < 0 || text.lastIndexOf('>', off) > lt) return null;
  const m = text.slice(lt, lt + 40).match(/^<([A-Za-z][\w:-]*)/);
  return m ? m[1].toLowerCase() : null;
}

function classify(text, off) {
  const before = text.slice(Math.max(0, off - 240), off);
  for (const [re, what] of LOAD_JS) if (re.test(before)) return { load: true, what };
  const attr = before.match(LOAD_ATTR);
  if (attr) {
    const name = attr[1].toLowerCase();
    const tag = enclosingTag(text, off);
    if (name === 'href' || name === 'xlink:href') {
      if (tag && LOAD_TAGS.has(tag)) return { load: true, what: `<${tag} ${name}>` };
      return { load: false, what: tag ? `<${tag} href> link` : 'href' };
    }
    return { load: true, what: tag ? `<${tag} ${name}>` : `${name}=` };
  }
  return { load: false, what: '' };
}

function scanUrls(rel, text) {
  for (const m of text.matchAll(URL_RE)) {
    const url = m[0].replace(/[.:]+$/, '');
    const host = url.replace(/^[a-z]+:\/\//i, '');
    if (!HOSTISH.test(host)) continue;   // "https://…", "http://" + x: text, not an address
    const c = classify(text, m.index);
    if (c.load) { add(failures, 'load', rel, text, m.index, url, c.what); continue; }
    const ok = urlRules.find(r => r.re.test(url) && (!r.fileRe || r.fileRe.test(rel)));
    if (!ok) add(failures, 'url', rel, text, m.index, url, c.what || 'a URL kept as a value; loaded later, or not allowlisted');
  }
}

// ---------- visible text ----------
const WORDS = /\b(pricing|upgrade[sd]?)\b/gi;
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
  for (const m of s.matchAll(WORDS)) {
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
}

// ---------- local references (warnings) ----------
function scanLocalRefs(file, rel, text) {
  const html = mask(text, /<script\b[^>]*>[\s\S]*?<\/script>/gi);
  for (const m of html.matchAll(/<(link|script|img|iframe|a)\b[^>]*?\s(?:src|href)=["']([^"'#?]+)[^"']*["']/gi)) {
    const ref = m[2];
    if (/^[a-z][a-z0-9+.-]*:/i.test(ref) || ref.startsWith('//') || ref.includes('${')) continue;
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
    if (ext === '.html') scanLocalRefs(file, rel, text);
  }
}
const budget = ALLOW.budgetBytes;
const mb = b => (b / 1048576).toFixed(2) + ' MB';
if (budget && bytes > budget) failures.push({ kind: 'budget', file: '.', line: 0, what: mb(bytes), detail: `over the ${mb(budget)} budget in offline-allowlist.json` });

console.log(`offline-scan: ${path.relative(process.cwd(), ROOT) || '.'} — ${files.length} files, ${mb(bytes)} (budget ${mb(budget)})`);
const order = { load: 0, url: 1, text: 2, budget: 3 };
failures.sort((a, b) => order[a.kind] - order[b.kind] || (a.file < b.file ? -1 : a.file > b.file ? 1 : a.line - b.line));
for (const f of failures) console.log(`  FAIL ${f.kind.padEnd(6)} ${f.file}:${f.line}  ${f.what.length > 110 ? f.what.slice(0, 107) + '...' : f.what}${f.detail ? '  [' + f.detail + ']' : ''}`);
for (const w of warnings) console.log(`  warn ${w.kind.padEnd(6)} ${w.file}:${w.line}  ${w.what}  [${w.detail}]`);
if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify({ root: ROOT, files: files.length, bytes, budget, failures, warnings }, null, 2) + '\n');
const counts = Object.entries(failures.reduce((o, f) => (o[f.kind] = (o[f.kind] || 0) + 1, o), {})).map(([k, v]) => `${v} ${k}`).join(', ');
console.log(failures.length ? `RESULT: ${failures.length} failure(s) — ${counts}` : 'RESULT: clean — no network address in a load position, nothing unlisted, no pricing or Upgrade text');
process.exit(failures.length ? 1 : 0);
