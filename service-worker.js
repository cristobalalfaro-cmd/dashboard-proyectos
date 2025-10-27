const CACHE_NAME = 'dash-v3'; // súbele la versión para forzar actualización

self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (e) => self.clients.claim());

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Nunca cachear data.json ni cache-bust.txt
  if (url.pathname.endsWith('/data.json') || url.pathname.endsWith('/cache-bust.txt')) {
    event.respondWith(fetch(event.request, { cache: 'no-store' }));
    return;
  }

  // Estrategia normal para el resto (cache-first con fallback)
  event.respondWith(
    caches.open(CACHE_NAME).then(async cache => {
      const cached = await cache.match(event.request);
      if (cached) return cached;
      const resp = await fetch(event.request);
      // Puedes filtrar qué guardar en caché si quieres
      cache.put(event.request, resp.clone());
      return resp;
    })
  );
});
