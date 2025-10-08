// service-worker.js
const CACHE_NAME = "dashboard-cache-v3";
const ASSETS = [
  "./",
  "./index.html",
  // agrega aquí tus archivos estáticos si existen:
  // "./styles.css",
  // "./app.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png"
  // IMPORTANTE: NO incluir "./data.json" en el precache
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((c) => c.addAll(ASSETS)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.map((k) => (k !== CACHE_NAME ? caches.delete(k) : null)))
    )
  );
});

// data.json: network-first (si no hay red, usa lo último en caché)
// resto de assets: cache-first
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Manejo especial para data.json
  if (url.pathname.endsWith("/data.json")) {
    event.respondWith(
      fetch(event.request)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(event.request, copy));
          return res;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Por defecto: cache-first
  event.respondWith(
    caches.match(event.request).then((cached) =>
      cached ||
      fetch(event.request).then((res) => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then((c) => c.put(event.request, copy));
        return res;
      })
    )
  );
});
