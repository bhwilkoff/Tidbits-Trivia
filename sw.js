// Tidbits service worker — offline app shell + cached corpus.
const CACHE = 'tidbits-v1';
const SHELL = [
  './', 'index.html', 'css/styles.css',
  'js/app.js', 'js/api.js', 'js/engine.js', 'js/store.js',
  'assets/corpus.json', 'manifest.json',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  // Never cache the live Wikipedia API.
  if (url.hostname.endsWith('wikipedia.org')) return;
  // Cache-first for app shell + corpus; network-first fallback otherwise.
  e.respondWith(
    caches.match(e.request).then((hit) => hit || fetch(e.request).then((resp) => {
      if (resp.ok && url.origin === location.origin) {
        const copy = resp.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
      }
      return resp;
    }).catch(() => caches.match('index.html')))
  );
});
