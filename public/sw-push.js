// Custom push handler — imported by the PWA service worker via importScripts.
// This file lives in /public so vite-plugin-pwa can reference it.

self.addEventListener('push', (event) => {
  if (!event.data) return;

  let payload;
  try {
    payload = event.data.json();
  } catch {
    payload = { title: 'Dastak', body: event.data.text() };
  }

  const title = payload.title || 'Dastak';
  const options = {
    body: payload.body || '',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    data: { order_id: payload.order_id, type: payload.type },
    vibrate: [200, 100, 200],
    tag: payload.order_id ? `order-${payload.order_id}` : undefined,
    renotify: !!payload.order_id,
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  let url = '/';
  if (data.order_id) {
    url = `/orders/${data.order_id}`;
  }

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.navigate(url);
          return client.focus();
        }
      }
      return self.clients.openWindow(url);
    })
  );
});
