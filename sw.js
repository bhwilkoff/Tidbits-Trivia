// Tidbits service worker — offline app shell + corpus, with fresh updates.
// Bump CACHE on every deploy that changes shell/code so the SW re-installs.
const CACHE = 'tidbits-v7';
const SHELL = [
  './', 'index.html', 'css/styles.css',
  'js/app.js', 'js/api.js', 'js/engine.js', 'js/store.js',
  'assets/corpus.json', 'manifest.json',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys()
    .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (url.hostname.endsWith('wikipedia.org')) return;   // never cache the live API

  // Network-first for the corpus + app code/shell so content and logic
  // updates always propagate; cache is the offline fallback. (Stale SW +
  // IndexedDB caching is why corpus changes weren't showing up.)
  const p = url.pathname;
  const dynamic = p.endsWith('corpus.json') || p.endsWith('.js') || p.endsWith('.css')
    || p.endsWith('index.html') || p.endsWith('manifest.json') || p.endsWith('/');
  if (dynamic && url.origin === location.origin) {
    e.respondWith(
      fetch(e.request).then((resp) => {
        const copy = resp.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
        return resp;
      }).catch(() => caches.match(e.request).then((hit) => hit || caches.match('index.html')))
    );
    return;
  }
  // Cache-first for everything else (icons, etc.).
  e.respondWith(caches.match(e.request).then((hit) => hit || fetch(e.request)));
});
