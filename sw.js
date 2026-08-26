// Tidbits service worker — offline app shell + corpus, with fresh updates.
// Bump CACHE on every deploy that changes shell/code so the SW re-installs.
const CACHE = 'tidbits-v65';
const SHELL = [
  './', 'index.html', 'css/styles.css',
  'js/app.js',
  'js/quiz.js',
  'js/quizstore.js', 'js/api.js', 'js/engine.js', 'js/store.js', 'js/identity.js',
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

// --- Web Push (docs/PUSH-CONTRACT.md) ---
// The cron sends {title, body, url}; anything unparseable still shows the appointment
// rather than nothing, because a push that arrives and displays nothing is worse than a
// generic one — the browser will surface a default notification anyway on a userVisibleOnly
// subscription, and it says less than this does.
self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data && e.data.text() }; }
  const title = d.title || 'Tidbits Trivia';
  e.waitUntil(self.registration.showNotification(title, {
    body: d.body || 'Your Daily is ready.',
    icon: 'assets/icon.png',
    badge: 'assets/icon.png',
    tag: d.tag || 'tidbits-daily',
    data: { url: d.url || './#/daily' },
  }));
});

// Focus an open tab rather than piling up new ones.
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const target = (e.notification.data && e.notification.data.url) || './#/daily';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) {
      if (c.url.includes(self.registration.scope) && 'focus' in c) { c.navigate(target); return c.focus(); }
    }
    return self.clients.openWindow(target);
  }));
});
