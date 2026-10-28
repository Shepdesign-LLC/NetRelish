/* ZestImage service worker — app shell offline, fonts cached on first use */
const VERSION = 'zimage-v2';   // v2: scope-relative shell — the app serves at / standalone and at /image under the one-origin topology (§8)
const APP_ROOT = new URL('./', self.location).pathname;   // '/' standalone, '/image/' mounted
const APP_INDEX = `${APP_ROOT}index.html`;
const SHELL = [APP_ROOT, APP_INDEX, `${APP_ROOT}manifest.webmanifest`, `${APP_ROOT}icons/icon-192.png`, `${APP_ROOT}icons/icon-512.png`, `${APP_ROOT}icons/favicon.svg`];
const RUNTIME_HOSTS = ['fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('zimage-') && k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  // App shell: network first (so deploys land), cache fallback (so offline works); only successful responses are cached.
  // Lookups are scoped to THIS app's cache — a global caches.match() could serve another Zest app's shell on a shared origin.
  if (url.origin === location.origin) {
    e.respondWith(fetch(e.request).then(r => { if (r.ok) { const copy = r.clone(); caches.open(VERSION).then(c => c.put(e.request, copy)); } return r; })
      .catch(() => caches.open(VERSION).then(c => c.match(e.request).then(r => r || c.match(APP_INDEX)))));
    return;
  }
  // Brand fonts: cache first, fill on first successful use
  if (RUNTIME_HOSTS.includes(url.hostname)) {
    e.respondWith(caches.open(VERSION).then(c => c.match(e.request).then(hit => hit || fetch(e.request).then(r => { if (r.ok) { const copy = r.clone(); c.put(e.request, copy); } return r; }))));
  }
});
