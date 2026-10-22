/* MD Press service worker — app shell offline, CDN extras cached on first use */
const VERSION = 'mdpress-v3';   // v3: only successful responses are cached (shell and CDN)
const SHELL = ['/', '/index.html', '/manifest.webmanifest', '/icons/icon-192.png', '/icons/icon-512.png', '/icons/favicon.svg'];
const RUNTIME_HOSTS = ['cdnjs.cloudflare.com', 'fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('mdpress-') && k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  // App shell: network first (so deploys land), cache fallback (so offline works)
  if (url.origin === location.origin) {
    // Share-target navigations (manifest share_target, method GET) carry the
    // shared title/text in the query string. Never send that URL to the
    // network — "Nothing is uploaded" — serve the cached shell and let the
    // page read its own location. Fail closed if the shell isn't cached.
    if (e.request.mode === 'navigate' && (url.searchParams.has('title') || url.searchParams.has('text'))) {
      e.respondWith(caches.open(VERSION).then(c => c.match('/index.html')).then(r => r || Response.error()));
      return;
    }
    // Lookups are scoped to THIS app's cache — a global caches.match() could serve another Zest app's shell on a shared origin.
    e.respondWith(fetch(e.request).then(r => { if (r.ok) { const copy = r.clone(); caches.open(VERSION).then(c => c.put(e.request, copy)); } return r; })
      .catch(() => caches.open(VERSION).then(c => c.match(e.request).then(r => r || c.match('/index.html')))));
    return;
  }
  // Fonts, KaTeX, Mermaid: cache first, fill on first use
  if (RUNTIME_HOSTS.includes(url.hostname)) {
    e.respondWith(caches.open(VERSION).then(c => c.match(e.request).then(hit => hit || fetch(e.request).then(r => { if (r.ok) { const copy = r.clone(); c.put(e.request, copy); } return r; }))));
  }
});
