#!/usr/bin/env node
// Vendors the libraries and fonts the Zest tools load, from npm, pinned (ADR 0015, "Pinned and generated").
//
//   node scripts/vendor.mjs                    fetch every tarball in vendor.config.json, verify it against the
//                                              registry's sha512, rewrite zest/vendor/ and VENDOR.lock.json
//   node scripts/vendor.mjs --check            CI: fetch again and fail on any difference between npm, the lock,
//                                              and the files on disk; then the checks below
//   node scripts/vendor.mjs --check --offline  no network: the files on disk against the lock; then the checks below
//
// Both check modes also check the copy the app ships: every file under Resources/Zest/vendor/ against the
// lock's SHA-256 (nothing missing, nothing extra), and Resources/Zest/NOTICE byte for byte against the root
// NOTICE. They do not check the tools' HTML in Resources/Zest against apps/; CI's rebuild-and-diff does.
//
// Both check modes also fail when Zest MD's DOMPurify <script> tag names a different version than the lock
// (or names none), when an integrity hash in apps/md/index.html is not the sha384 of the vendored file it
// stands for, when zest/tests pins a different DOMPurify than the lock, when the root NOTICE does not
// name every vendored npm release, and when code inlined in a tool (vendor.config.json "inline": Zest MD's
// renderer) no longer hashes to the SHA-256 pinned there, in apps/ or in Resources/Zest.
//
// No dependencies: Node 20+ (global fetch, zlib). Output is deterministic: sorted paths, no timestamps.
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ZEST = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const VENDOR = path.join(ZEST, 'vendor');
const LOCK = path.join(VENDOR, 'VENDOR.lock.json');
const BUNDLE = path.join(ZEST, '..', 'Resources', 'Zest');   // the copy NetRelish.app ships (build.sh --app)
const CONFIG = JSON.parse(fs.readFileSync(path.join(ZEST, 'scripts', 'vendor.config.json'), 'utf8'));
const REGISTRY = 'https://registry.npmjs.org';

const args = new Set(process.argv.slice(2));
const CHECK = args.has('--check');
const OFFLINE = args.has('--offline');
if ([...args].some(a => !['--check', '--offline'].includes(a)) || (OFFLINE && !CHECK)) {
  console.error('usage: node scripts/vendor.mjs [--check [--offline]]');
  process.exit(2);
}

const sha256 = buf => createHash('sha256').update(buf).digest('hex');
const sri384 = buf => 'sha384-' + createHash('sha384').update(buf).digest('base64');
const rel = p => path.relative(ZEST, p).split(path.sep).join('/');
const problems = [];
const fail = msg => problems.push(msg);

// ---------- npm: packument, tarball, integrity, a minimal tar reader ----------
async function getBuf(url) {
  for (let attempt = 1; ; attempt++) {
    try {
      const r = await fetch(url);
      if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
      return Buffer.from(await r.arrayBuffer());
    } catch (e) {
      if (attempt >= 3) throw new Error(`GET ${url}: ${e.message}`);
      await new Promise(ok => setTimeout(ok, 1000 * attempt));
    }
  }
}

function untar(tgz) {
  const tar = gunzipSync(tgz);
  const files = new Map();
  let off = 0, longName = null, pax = {};
  const str = (o, n) => tar.subarray(o, o + n).toString('utf8').replace(/\0[\s\S]*$/, '');
  while (off + 512 <= tar.length) {
    const h = tar.subarray(off, off + 512);
    if (h.every(b => b === 0)) break;
    const size = parseInt(str(off + 124, 12).trim() || '0', 8);
    const type = String.fromCharCode(h[156] || 48);
    const prefix = str(off + 345, 155);
    let name = (prefix ? prefix + '/' : '') + str(off, 100);
    const body = tar.subarray(off + 512, off + 512 + size);
    off += 512 + Math.ceil(size / 512) * 512;
    if (type === 'L') { longName = body.toString('utf8').replace(/\0+$/, ''); continue; }
    if (type === 'x') {
      pax = {};
      for (const line of body.toString('utf8').split('\n')) {
        const m = line.match(/^\d+ ([^=]+)=(.*)$/);
        if (m) pax[m[1]] = m[2];
      }
      continue;
    }
    if (type === 'g') continue;
    if (longName) { name = longName; longName = null; }
    if (pax.path) name = pax.path;
    pax = {};
    if (type === '0' || type === '\0' || type === '7') files.set(name.replace(/^[^/]+\//, ''), Buffer.from(body));   // strip "package/"
  }
  return files;
}

const tarballs = new Map();   // "name@version" -> { name, version, tarball, integrity, files }
async function pkg(name, version) {
  const key = `${name}@${version}`;
  if (tarballs.has(key)) return tarballs.get(key);
  const meta = JSON.parse((await getBuf(`${REGISTRY}/${name.replace('/', '%2F')}/${version}`)).toString('utf8'));
  const { tarball, integrity } = meta.dist;
  if (!/^sha512-/.test(integrity || '')) throw new Error(`${key}: the registry gives no sha512 integrity`);
  const tgz = await getBuf(tarball);
  const got = 'sha512-' + createHash('sha512').update(tgz).digest('base64');
  if (got !== integrity) throw new Error(`${key}: tarball sha512 ${got} does not match the registry's ${integrity}`);
  const entry = { name, version, tarball, integrity, license: meta.license || '', files: untar(tgz) };
  tarballs.set(key, entry);
  process.stderr.write(`  fetched ${key}\n`);
  return entry;
}
const need = (p, file) => {
  const b = p.files.get(file);
  if (!b) throw new Error(`${p.name}@${p.version} has no ${file}`);
  return b;
};

// ---------- build the whole vendor tree in memory ----------
async function build() {
  const out = new Map();        // vendor-relative path -> { buf, rec }
  const packages = {};
  const put = (dest, buf, rec) => {
    if (out.has(dest)) throw new Error(`two sources for vendor/${dest}`);
    out.set(dest, { buf, rec: { path: dest, ...rec, bytes: buf.length, sha256: sha256(buf) } });
  };
  const note = p => { packages[`${p.name}@${p.version}`] = { name: p.name, version: p.version, tarball: p.tarball, integrity: p.integrity, license: p.license }; };

  for (const lib of CONFIG.libraries) {
    const p = await pkg(lib.name, lib.version);
    note(p);
    const from = { ...lib.files };
    if (lib.cssFonts) {   // the font files the stylesheet names, in the one format WebKit and Chromium pick first
      const css = need(p, lib.cssFonts.css).toString('utf8');
      const dir = path.posix.dirname(lib.cssFonts.css);
      const re = new RegExp(`url\\((?:"|')?([^)"']+\\.${lib.cssFonts.format})(?:"|')?\\)`, 'g');
      for (const [, u] of css.matchAll(re)) from[path.posix.join(dir, u)] = path.posix.join(lib.cssFonts.into, u);
    }
    for (const [src, dest] of Object.entries(from)) {
      const buf = need(p, src);
      const rec = { package: `${p.name}@${p.version}`, from: src, license: lib.license };
      if ((lib.sri || []).includes(src)) rec.sri = sri384(buf);
      put(dest, buf, rec);
    }
  }

  const F = CONFIG.fonts;
  const faces = [];
  const manifest = {};
  for (const fam of F.families) {
    const p = await pkg(fam.pkg, fam.version || F.version);
    note(p);
    const meta = JSON.parse(need(p, 'metadata.json').toString('utf8'));
    if (meta.family !== fam.family) throw new Error(`${fam.pkg}: family is "${meta.family}", config says "${fam.family}"`);
    const latin = JSON.parse(need(p, 'unicode.json').toString('utf8')).latin;
    if (!latin) throw new Error(`${fam.pkg}: no latin subset`);
    const lic = (meta.license && meta.license.type) || p.license;
    const id = meta.id;
    const famFaces = [];
    for (const style of fam.styles) {
      if (!meta.styles.includes(style)) throw new Error(`${fam.pkg}: no ${style} style`);
      if (fam.axis) {
        const v = meta.variable && meta.variable[fam.axis];
        if (!v) throw new Error(`${fam.pkg}: no ${fam.axis} axis`);
        const w = meta.variable.wght;
        const weight = w ? `${w.min} ${w.max}` : String(meta.weights[0]);
        const src = `files/${id}-latin-${fam.axis}-${style}.woff2`;
        const dest = `fonts/${id}/${id}-latin-${fam.axis}-${style}.woff2`;
        put(dest, need(p, src), { package: `${p.name}@${p.version}`, from: src, license: lic });
        famFaces.push({ style, weight, file: dest.slice('fonts/'.length), variable: fam.axis === 'opsz' ? ['opsz', 'wght'] : ['wght'] });
      } else {
        for (const wt of fam.weights) {
          if (!meta.weights.includes(wt)) throw new Error(`${fam.pkg}: no weight ${wt}`);
          const src = `files/${id}-latin-${wt}-${style}.woff2`;
          const dest = `fonts/${id}/${id}-latin-${wt}-${style}.woff2`;
          put(dest, need(p, src), { package: `${p.name}@${p.version}`, from: src, license: lic });
          famFaces.push({ style, weight: String(wt), file: dest.slice('fonts/'.length) });
        }
      }
    }
    put(`fonts/${id}/LICENSE`, need(p, 'LICENSE'), { package: `${p.name}@${p.version}`, from: 'LICENSE', license: lic });
    for (const f of famFaces) faces.push({ family: fam.family, unicodeRange: latin, ...f });
    manifest[fam.family] = {
      id, category: meta.category, license: lic, attribution: (meta.license && meta.license.attribution) || '',
      package: `${p.name}@${p.version}`, usedBy: fam.usedBy,
      faces: famFaces.map(f => ({ style: f.style, weight: f.weight, file: f.file, ...(f.variable ? { axes: f.variable } : {}) })),
    };
  }

  const css = [
    '/* Generated by zest/scripts/vendor.mjs from scripts/vendor.config.json. Do not edit.',
    '   Latin-subset woff2 from the @fontsource and @fontsource-variable npm packages; versions,',
    '   SHA-256 and licenses in VENDOR.lock.json, license texts beside each family. */',
    ...faces.map(f => [
      `@font-face {`,
      `  font-family: '${f.family}';`,
      `  font-style: ${f.style};`,
      `  font-weight: ${f.weight};`,
      `  font-display: swap;`,
      `  src: url(${f.file}) format('woff2');`,
      `  unicode-range: ${f.unicodeRange};`,
      `}`,
    ].join('\n')),
  ].join('\n') + '\n';
  put('fonts/fonts.css', Buffer.from(css), { generated: 'scripts/vendor.mjs', license: 'MIT (generated; the fonts it names keep their own licenses)' });
  const json = JSON.stringify({ about: 'Generated by zest/scripts/vendor.mjs. Every family the tools offer, the faces vendored for it (paths relative to this file), and its license.', families: manifest }, null, 2) + '\n';
  put('fonts/fonts.json', Buffer.from(json), { generated: 'scripts/vendor.mjs', license: 'MIT (generated)' });

  const files = [...out.values()].map(e => e.rec).sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  const sortedPkgs = Object.fromEntries(Object.keys(packages).sort().map(k => [k, packages[k]]));
  const lock = {
    about: 'Generated by zest/scripts/vendor.mjs from scripts/vendor.config.json. Do not edit. Every file under zest/vendor/ with the npm release it comes from, the path inside that tarball, its SHA-256 and its license. `node scripts/vendor.mjs --check` fetches every tarball again and fails on any difference.',
    registry: REGISTRY,
    packages: sortedPkgs,
    files,
  };
  return { out, lock };
}

// ---------- the files on disk ----------
function walk(dir, base = dir, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const name of fs.readdirSync(dir).sort()) {
    const p = path.join(dir, name);
    if (fs.statSync(p).isDirectory()) walk(p, base, acc);
    else acc.push(path.relative(base, p).split(path.sep).join('/'));
  }
  return acc;
}

// The files under `dir` against the lock: same set of paths, same SHA-256. `label` names the folder in messages.
function checkDiskAgainstLock(lock, dir = VENDOR, label = 'vendor') {
  const listed = new Map(lock.files.map(f => [f.path, f]));
  const onDisk = walk(dir).filter(p => !(dir === VENDOR && p === 'VENDOR.lock.json'));
  for (const p of onDisk) {
    const rec = listed.get(p);
    if (!rec) { fail(`${label}/${p} is on disk but not in VENDOR.lock.json`); continue; }
    const got = sha256(fs.readFileSync(path.join(dir, p)));
    if (got !== rec.sha256) fail(`${label}/${p}: SHA-256 ${got} on disk, ${rec.sha256} in the lock`);
  }
  const have = new Set(onDisk);
  for (const p of listed.keys()) if (!have.has(p)) fail(`${label}/${p} is in VENDOR.lock.json but missing on disk`);
}

// The copy the app ships: its vendor/ against the lock, its NOTICE against the root NOTICE.
function checkBundle(lock) {
  const label = 'Resources/Zest';
  if (!fs.existsSync(path.join(BUNDLE, 'index.html'))) { fail(`${label} is missing: run bash zest/build.sh --app`); return; }
  checkDiskAgainstLock(lock, path.join(BUNDLE, 'vendor'), `${label}/vendor`);
  const notice = path.join(ZEST, '..', 'NOTICE');
  const shipped = path.join(BUNDLE, 'NOTICE');
  if (!fs.existsSync(shipped)) fail(`${label}/NOTICE is missing: run bash zest/build.sh --app`);
  else if (fs.existsSync(notice) && !fs.readFileSync(shipped).equals(fs.readFileSync(notice))) fail(`${label}/NOTICE differs from the root NOTICE: run bash zest/build.sh --app`);
}

// Zest MD's tags name the files the app vendors: same versions, same bytes (by their sha384).
function checkMdTags(lock) {
  const file = path.join(ZEST, 'apps', 'md', 'index.html');
  const html = fs.readFileSync(file, 'utf8');
  const byBase = new Map(lock.files.filter(f => f.sri).map(f => [path.posix.basename(f.path), f]));
  const versionOf = name => Object.values(lock.packages).find(p => p.name === name)?.version;

  const tags = [...html.matchAll(/<script\b[^>]*\bsrc=["']([^"']*purify(?:\.min)?\.js[^"']*)["'][^>]*>/g)];
  if (tags.length !== 1) fail(`apps/md/index.html: expected one DOMPurify <script> tag, found ${tags.length}`);
  for (const [tag, src] of tags) {
    const want = versionOf('dompurify');
    const named = (src.match(/dompurify[@/](\d+\.\d+\.\d+)/) || tag.match(/\bdata-version=["'](\d+\.\d+\.\d+)["']/) || [])[1];
    if (!named) fail(`apps/md/index.html: the DOMPurify tag names no version (put it in the URL or in data-version="${want}")`);
    else if (named !== want) fail(`apps/md/index.html: the DOMPurify tag loads ${named}, VENDOR.lock.json pins ${want}`);
    const integrity = (tag.match(/\bintegrity=["']([^"']+)["']/) || [])[1];
    const rec = byBase.get('purify.min.js');
    if (!integrity) fail('apps/md/index.html: the DOMPurify tag has no integrity hash');
    else if (rec && integrity !== rec.sri) fail(`apps/md/index.html: the DOMPurify tag's integrity ${integrity} is not the vendored file's ${rec.sri}`);
  }

  // The on-demand table: ['<url>', 'sha384-…'] pairs.
  const pairs = [...html.matchAll(/\[\s*'([^']+\.(?:css|js))'\s*,\s*'(sha384-[^']+)'\s*\]/g)];
  const seen = new Set();
  for (const [, url, hash] of pairs) {
    const rec = byBase.get(path.posix.basename(url.split('?')[0]));
    if (!rec) { fail(`apps/md/index.html: ${url} is hashed but not vendored`); continue; }
    seen.add(rec.path);
    const name = rec.package.replace(/@[^@]+$/, '');
    const m = url.match(/\/(\d+\.\d+\.\d+)\//);
    if (m && m[1] !== versionOf(name)) fail(`apps/md/index.html: ${url} is ${name} ${m[1]}, VENDOR.lock.json pins ${versionOf(name)}`);
    if (hash !== rec.sri) fail(`apps/md/index.html: ${url} carries ${hash}, the vendored file is ${rec.sri}`);
  }
  for (const f of lock.files.filter(f => f.sri && !f.path.startsWith('dompurify/'))) {
    if (!seen.has(f.path)) fail(`apps/md/index.html: no hashed entry loads vendor/${f.path}`);
  }

  const testsPkg = JSON.parse(fs.readFileSync(path.join(ZEST, 'tests', 'package.json'), 'utf8'));
  const pinned = (testsPkg.devDependencies || {}).dompurify;
  if (pinned !== versionOf('dompurify')) fail(`tests/package.json pins dompurify ${pinned}, VENDOR.lock.json pins ${versionOf('dompurify')}`);
}

// Code a tool carries inline, not fetched from npm: the <script> block whose text starts with the entry's mark
// hashes to the SHA-256 pinned in vendor.config.json, in the tool's source and in the copy the app ships.
function checkInline() {
  for (const e of CONFIG.inline || []) {
    for (const [label, file] of [[e.file, path.join(ZEST, e.file)],
      [`Resources/Zest/${e.file.replace(/^apps\/(zest\/)?/, '')}`, path.join(BUNDLE, e.file.replace(/^apps\/(zest\/)?/, ''))]]) {
      if (!fs.existsSync(file)) { fail(`${label} is missing (inline "${e.block}")`); continue; }
      const blocks = [...fs.readFileSync(file, 'utf8').matchAll(/<script>(\/\* ([^*]+?) \*\/[\s\S]*?)<\/script>/g)].filter(m => m[2] === e.block);
      if (blocks.length !== 1) { fail(`${label}: expected one <script> block marked "${e.block}", found ${blocks.length}`); continue; }
      const got = sha256(Buffer.from(blocks[0][1], 'utf8'));
      if (got !== e.sha256) fail(`${label}: the "${e.block}" block hashes to ${got}; vendor.config.json pins ${e.sha256} (${e.names}). Update the pin and NOTICE section 3 together`);
    }
  }
}

// The root NOTICE names every vendored release as name@version, so a bump can't leave it behind.
function checkNotice(lock) {
  const file = path.join(ZEST, '..', 'NOTICE');
  if (!fs.existsSync(file)) { fail('the root NOTICE is missing'); return; }
  const notice = fs.readFileSync(file, 'utf8');
  for (const key of Object.keys(lock.packages)) if (!notice.includes(key)) fail(`NOTICE does not name ${key}`);
}

// ---------- main ----------
try {
  if (!CHECK) {
    const { out, lock } = await build();
    fs.rmSync(VENDOR, { recursive: true, force: true });
    for (const [dest, { buf }] of out) {
      fs.mkdirSync(path.dirname(path.join(VENDOR, dest)), { recursive: true });
      fs.writeFileSync(path.join(VENDOR, dest), buf);
    }
    fs.writeFileSync(LOCK, JSON.stringify(lock, null, 2) + '\n');
    const total = lock.files.reduce((n, f) => n + f.bytes, 0);
    console.log(`vendor/: ${lock.files.length} files, ${(total / 1048576).toFixed(2)} MB, from ${Object.keys(lock.packages).length} npm releases`);
  } else {
    if (!fs.existsSync(LOCK)) { fail('vendor/VENDOR.lock.json is missing: run node scripts/vendor.mjs'); throw null; }
    const lock = JSON.parse(fs.readFileSync(LOCK, 'utf8'));
    checkDiskAgainstLock(lock);
    if (!OFFLINE) {
      const fresh = (await build()).lock;
      const a = JSON.stringify(fresh, null, 2) + '\n';
      const b = fs.readFileSync(LOCK, 'utf8');
      if (a !== b) {
        const old = new Map(lock.files.map(f => [f.path, f]));
        for (const f of fresh.files) {
          const o = old.get(f.path);
          if (!o) fail(`npm would add vendor/${f.path}`);
          else if (o.sha256 !== f.sha256) fail(`vendor/${f.path}: npm gives ${f.sha256}, the lock says ${o.sha256}`);
          old.delete(f.path);
        }
        for (const p of old.keys()) fail(`vendor/${p} is in the lock but not in what vendor.config.json fetches`);
        for (const [k, p] of Object.entries(fresh.packages)) {
          const o = lock.packages[k];
          if (!o) fail(`npm release ${k} is fetched but not in the lock`);
          else if (o.integrity !== p.integrity || o.tarball !== p.tarball) fail(`${k}: the registry now gives ${p.tarball} ${p.integrity}, the lock says ${o.tarball} ${o.integrity}`);
        }
        if (!problems.length) fail('VENDOR.lock.json differs from a fresh build (formatting or metadata): run node scripts/vendor.mjs');
      }
    }
    checkBundle(lock);
    checkMdTags(lock);
    checkInline();
    checkNotice(lock);
    if (!problems.length) console.log(`vendor check: ${lock.files.length} files in vendor/ and Resources/Zest/vendor/ match VENDOR.lock.json${OFFLINE ? ' (offline: disk against the lock)' : ' and npm'}; Resources/Zest/NOTICE is the root NOTICE; Zest MD's tags name the vendored versions, and its inline renderer matches its pin`);
  }
} catch (e) {
  if (e) fail(e.message || String(e));
}
if (problems.length) {
  console.error(`vendor ${CHECK ? 'check' : ''} FAILED:`);
  for (const p of problems) console.error('  - ' + p);
  process.exit(1);
}
