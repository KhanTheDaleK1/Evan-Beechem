const CACHE_NAME = 'beechem-ops-v1';
const ASSETS_TO_CACHE = [
  '/',
  '/index.html',
  '/projects.html',
  '/outage_map.html',
  '/style.css',
  '/matrix.js',
  '/icons/icon.svg',
  '/manifest.json'
];

// Install Event: Cache core assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[Service Worker] Caching all: app shell and content');
      return cache.addAll(ASSETS_TO_CACHE);
    })
  );
  self.skipWaiting();
});

// Activate Event: Clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keyList) => {
      return Promise.all(keyList.map((key) => {
        if (key !== CACHE_NAME) {
          console.log('[Service Worker] Removing old cache', key);
          return caches.delete(key);
        }
      }));
    })
  );
  self.clients.claim();
});

// Fetch Event: Network First for HTML/JSON, Cache First for others
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Strategy: Network First for HTML and JSON (Data)
  if (url.pathname.endsWith('.html') || url.pathname.endsWith('.json') || url.pathname === '/') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          // Update cache with new version
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
          return response;
        })
        .catch(() => caches.match(event.request)) // Fallback to cache if offline
    );
  } else {
    // Strategy: Cache First for static assets (CSS, JS, Images)
    event.respondWith(
      caches.match(event.request).then((response) => {
        return response || fetch(event.request);
      })
    );
  }
});
