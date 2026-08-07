// Cross-origin isolation for static hosts (GitHub Pages cannot set
// response headers): re-adds COOP/COEP so skwasm gets
// SharedArrayBuffer and renders multithreaded. Registered from
// index.html only when the server did not isolate the page itself.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.cache === 'only-if-cached' && request.mode !== 'same-origin') {
    return;
  }
  event.respondWith(
    fetch(request).then((response) => {
      if (response.status === 0) {
        return response;
      }
      const headers = new Headers(response.headers);
      headers.set('Cross-Origin-Opener-Policy', 'same-origin');
      headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    }),
  );
});
