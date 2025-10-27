/* ===== Dashboard Service Worker =====
 * Estrategias:
 * - data.json / cache-bust.txt: NETWORK-FIRST (sin cache)
 * - Estáticos (HTML, CSS, JS, icons): CACHE-FIRST con precache básico
 * - Limpieza de caches antiguos en activate
 */

const CACHE_VERSION = 'v3-2025-10-27';
const STATIC_CACHE = `dashboard-static-${CACHE_VERSION}`;

// Archivos que podemos precachear (ajusta a lo que uses realmente)
const PRECACHE_URLS = [
  '/',                // si sirves desde raíz; si es GH Pages, considera '/dashboard-proyectos/'
  '/index.html',
  '/styles.css',
  '/settings.json',
  '/service-worker.js',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  // agrega aquí otros JS/CSS propios si los tienes (p.ej. /scripts/ui.js)
];

// Utilidad: detecta si la request es de datos (no cachear)
function isDataRequest(url) {
  return url.pathname.endsWith('/data.json') || url.pathname.endsWith('/cache-bust.txt');
}

// ========== INSTALL ==========
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE)
      .then((cache) => cache.addAll(PRECACHE_URLS).catch(() => null))
      .then(() => self.skipWaiting())
  );
});

// ========== ACTIVATE ==========
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Elimina caches viejos
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((k) => k.startsWith('dashboard-static-') && k !== STATIC_CACHE)
        .map((k) => caches.delete(k))
    );
    await self.clients.claim();
  })());
});

// ========== FETCH ==========
self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Siempre BYPASS cache para data.json y cache-bust.txt
  if (isDataRequest(url)) {
    event.respondWith(
      fetch(new Request(req, { cache: 'no-store' }))
        .catch(() => {
          // si falla red, intenta alguna respuesta mínima
          return new Response('[]', { headers: { 'Content-Type': 'application/json' } });
        })
    );
    return;
  }

  // Para navegación (document) — Network-first con fallback al cache
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req);
        // Opcional: guarda la última versión de index.html
        const cache = await caches.open(STATIC_CACHE);
        cache.put(req, fresh.clone());
        return fresh;
      } catch {
        const cache = await caches.open(STATIC_CACHE);
        const cached = await cache.match('/index.html');
        return cached || new Response('Offline', { status: 503, statusText: 'Offline' });
      }
    })());
    return;
  }

  // Para estáticos: Cache-first con actualización en background (SWr)
  if (req.destination === 'style' || req.destination === 'script' || req.destination === 'image' || req.destination === 'font') {
    event.respondWith((async () => {
      const cache = await caches.open(STATIC_CACHE);
      const cached = await cache.match(req);
      const networkPromise = fetch(req).then((resp) => {
        cache.put(req, resp.clone());
        return resp;
      }).catch(() => null);

      // Responde primero con cache si hay; si no, espera la red
      return cached || networkPromise || fetch(req);
    })());
    return;
  }

  // Resto: intenta cache y si no, red
  event.respondWith((async () => {
    const cache = await caches.open(STATIC_CACHE);
    const cached = await cache.match(req);
    if (cached) return cached;
    const resp = await fetch(req).catch(() => null);
    return resp || new Response('Offline', { status: 503, statusText: 'Offline' });
  })());
});

// ========== Mensajes opcionales desde la página ==========
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});
