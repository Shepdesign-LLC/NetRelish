#!/usr/bin/env node
// Zest test runner: builds dist/, serves the apps, runs the three Playwright
// suites and the WCAG contrast sweeps. Exits nonzero if anything fails.
//
//   cd zest/tests && npm ci && npx playwright install chromium && npm test
//
// ZEST_CHROMIUM=/path/to/chromium skips the downloaded browser and launches
// that binary instead (used by sandboxes with a system Chromium).
const { execSync, spawn } = require('child_process');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ZEST = path.join(__dirname, '..');
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.webmanifest': 'application/manifest+json',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.ttf': 'font/ttf', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8',
};

// port → served directory (same map every suite assumes)
const SERVERS = {
  8771: 'apps/zest',   // studio
  8772: 'apps/image',  // ZestImage
  8773: 'apps/mail',   // ZestMail
  8774: 'apps/md',     // Zest MD
  8780: 'dist',        // assembled topology (studio at /, tools at paths, store at /pricing)
};

function serve(port, dir) {
  const root = path.join(ZEST, dir);
  const srv = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p.endsWith('/')) p += 'index.html';
    const file = path.join(root, p);
    if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404); return res.end('not found'); }
    if (fs.statSync(file).isDirectory()) { res.writeHead(301, { location: p + '/' }); return res.end(); }
    res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise(ok => srv.listen(port, '127.0.0.1', () => ok(srv)));
}

// async spawn — a synchronous child wait would block this process's event
// loop, and these servers live in this process
function runNode(args, capture) {
  return new Promise(res => {
    const c = spawn(process.execPath, args, { stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit' });
    let out = '', err = '';
    if (capture) { c.stdout.on('data', d => out += d); c.stderr.on('data', d => err += d); }
    c.on('exit', code => res({ code, out, err }));
  });
}

(async () => {
  console.log('build: assembling dist/ …');
  execSync('bash build.sh', { cwd: ZEST, stdio: 'inherit' });

  const servers = await Promise.all(Object.entries(SERVERS).map(([p, d]) => serve(+p, d)));
  let failed = 0;

  for (const suite of ['test.js', 'handoff2.js', 'topology.js']) {
    console.log(`\n=== ${suite} ===`);
    const r = await runNode([path.join(__dirname, suite)]);
    if (r.code !== 0) failed++;
  }

  // Contrast sweeps. ZestImage is excluded: its body background is a gradient,
  // which the auditor can't composite — it falls back to white and flags the
  // whole page (pre-existing harness limitation, see tests/README.md).
  const SWEEPS = [
    ['http://localhost:8773/', 'dark', 'mail'],
    ['http://localhost:8774/', 'dark', 'md'],
    ['http://localhost:8771/', 'dark', 'studio'],
  ];
  for (const args of SWEEPS) {
    console.log(`\n=== contrast: ${args[2]} (${args[1]}) ===`);
    const r = await runNode([path.join(__dirname, 'contrast-audit.js'), ...args], true);
    if (r.code !== 0) { console.error(r.err || 'contrast audit crashed'); failed++; continue; }
    const report = JSON.parse(r.out);
    if (report.failures.length) {
      failed++;
      console.error(`${report.failures.length} contrast failure(s):`);
      for (const f of report.failures) console.error(`  ${f.path} "${f.text}" ${f.fg} on ${f.bg} = ${f.ratio} (needs ${f.need})`);
    } else {
      console.log('0 failures');
    }
  }

  servers.forEach(s => s.close());
  console.log(failed ? `\nRESULT: ${failed} stage(s) FAILED` : '\nRESULT: all stages green');
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
