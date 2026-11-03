const CACHE_VERSION = '__PWA_CACHE_VERSION__';
const PRECACHE = __PWA_PRECACHE_FILES__;

const LEGACY_FLUTTER_CACHES = new Set([
  'flutter-app-cache',
  'flutter-temp-cache',
  'flutter-app-manifest',
]);

const NETWORK_FIRST_PATHS = new Set([
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/pwa_platform_bridge.js',
  '/pwa_ocr_bridge.js',
  '/version.json',
  '/manifest.json',
]);

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_VERSION);
    for (const url of PRECACHE) {
      const response = await fetch(url, {cache: 'reload'});
      if (!response.ok) {
        throw new Error('Failed to precache ' + url + ': ' + response.status);
      }
      await cache.put(url, response);
    }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) =>
          (key.startsWith('adventurers-guild-pwa-') &&
              key !== CACHE_VERSION) ||
          LEGACY_FLUTTER_CACHES.has(key))
        .map((key) => caches.delete(key)),
    );
    await self.clients.claim();
  })());
});

async function networkFirst(request, cache) {
  try {
    const response = await fetch(request, {cache: 'no-cache'});
    if (response.ok) {
      await cache.put(request, response.clone());
    }
    return response;
  } catch (_) {
    return (await cache.match(request, {ignoreSearch: true})) ||
        Response.error();
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_VERSION);

    if (request.mode === 'navigate' ||
        NETWORK_FIRST_PATHS.has(url.pathname)) {
      return networkFirst(request, cache);
    }

    const cached = await cache.match(request);
    if (cached) return cached;

    try {
      const response = await fetch(request);
      if (response.ok) {
        await cache.put(request, response.clone());
      }
      return response;
    } catch (_) {
      return Response.error();
    }
  })());
});
