/// <reference lib="webworker" />
import { precacheAndRoute, cleanupOutdatedCaches } from 'workbox-precaching';

declare let self: ServiceWorkerGlobalScope;

cleanupOutdatedCaches();
precacheAndRoute(self.__WB_MANIFEST);

// ─── Push notifications ───────────────────────────────────────────────────

self.addEventListener('push', (event) => {
  if (!event.data) return;

  let payload: { title?: string; body?: string; order_id?: string; type?: string };
  try {
    payload = event.data.json();
  } catch {
    payload = { title: 'Dastak', body: event.data.text() };
  }

  const title = payload.title || 'Dastak';
  const options: NotificationOptions & { vibrate?: number[]; renotify?: boolean } = {
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
  const data = (event.notification.data as { order_id?: string }) || {};
  let url = '/';
  if (data.order_id) url = `/orders/${data.order_id}`;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          (client as WindowClient).navigate(url);
          return (client as WindowClient).focus();
        }
      }
      return self.clients.openWindow(url);
    })
  );
});
