// Finance Tracker service worker — notifications only (no fetch caching, so the
// app always loads fresh and updates immediately).
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

// Future: real background push (needs a push backend sending these messages).
self.addEventListener('push', (e) => {
  let d = { title: 'Finance Tracker', body: '' };
  try { d = e.data.json(); } catch (_) { if (e.data) d.body = e.data.text(); }
  e.waitUntil(self.registration.showNotification(d.title || 'Finance Tracker', {
    body: d.body || '',
    icon: '/finance-tracker/icon-512-v6.png',
    badge: '/finance-tracker/icon-192-v6.png',
    tag: d.tag || undefined,
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((cs) => {
      for (const c of cs) { if ('focus' in c) return c.focus(); }
      if (self.clients.openWindow) return self.clients.openWindow('/finance-tracker/');
    })
  );
});
