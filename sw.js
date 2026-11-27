// App Locale – V05 – service worker: riceve le notifiche push e apre l'app al tocco
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data && e.data.text() }; }
  e.waitUntil((async () => {
    await self.registration.showNotification(d.title || 'App Locale', {
      body: d.body || 'Nuovo avviso',
      tag: d.tag,
      icon: 'icon-192.png',
      badge: 'icon-192.png',
      data: { url: d.url || './' }
    });
    if (typeof d.badge === 'number' && self.navigator.setAppBadge) {
      try { await self.navigator.setAppBadge(d.badge); } catch (_) {}
    }
  })());
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope).href;
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of all) {
      if (c.url.startsWith(self.registration.scope)) {
        await c.focus();
        c.postMessage({ type: 'open', url });
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
