/* ═══════════════════════════════════════════════════════
   Firebase Cloud Messaging Service Worker
   Handles background push notifications for the PWA
   ═══════════════════════════════════════════════════════ */

importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
    apiKey: 'AIzaSyACyPyqHcgciP31rKqPTuS5jXAtyqpNkdU',
    appId: '1:512074182214:web:351bd07f62180977b92447',
    messagingSenderId: '512074182214',
    projectId: 'diaspora-nearby-a3dac',
    authDomain: 'diaspora-nearby-a3dac.firebaseapp.com',
    storageBucket: 'diaspora-nearby-a3dac.firebasestorage.app',
    measurementId: 'G-0FD7KSDSSD',
});

const messaging = firebase.messaging();

// Handle background messages (when the app tab is not in focus)
messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Background message received:', payload);

    const notificationTitle = payload.notification?.title || payload.data?.title || 'Diaspora Nearby';
    const notificationOptions = {
        body: payload.notification?.body || payload.data?.body || 'You have a new notification',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        data: payload.data || {},
        tag: payload.data?.chatId || payload.messageId || 'default',
        renotify: true,
    };

    return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle notification click — open the app or focus existing tab
self.addEventListener('notificationclick', (event) => {
    console.log('[firebase-messaging-sw.js] Notification clicked:', event);
    event.notification.close();

    const data = event.notification.data || {};
    let targetUrl = '/';

    // Build target route based on notification type
    if (data.type === 'direct_message' || data.type === 'chat_message' || data.type === 'group_mention') {
        if (data.chatId) targetUrl = '/chats/' + data.chatId;
    } else if (data.type === 'relationship_request' && data.fromUserId) {
        targetUrl = '/profile/' + data.fromUserId;
    } else if (data.type === 'points_update' || data.type === 'money_transfer') {
        targetUrl = '/dsp/points';
    }

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
            // If there's already a tab open, focus it
            for (const client of clientList) {
                if ('focus' in client) {
                    client.focus();
                    client.postMessage({ type: 'notification-click', data: data });
                    return;
                }
            }
            // Otherwise open a new tab
            return clients.openWindow(targetUrl);
        })
    );
});
