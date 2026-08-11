// ============================================================
// web/firebase-messaging-sw.js
// ============================================================
// Service worker requis par firebase_messaging sur Flutter Web
// pour recevoir les notifications quand l'onglet n'a PAS le
// focus (équivalent web du handler background Android/iOS).
//
// ⚠️ Placement obligatoire : à la RACINE du dossier `web/` (au
// même niveau que `web/index.html`), jamais dans un
// sous-dossier — Chrome n'enregistre un service worker qu'à
// l'intérieur de son propre scope.
//
// ⚠️ Versions des SDK : gardées alignées avec firebase_core /
// firebase_messaging du pubspec.yaml (firebase_core ^4.0.0,
// firebase_messaging ^16.0.0). Si tu montes ces packages, monte
// aussi ces URLs (les SDK JS compat de Firebase suivent leur
// propre numérotation, indépendante des packages Dart).
// ============================================================

importScripts('https://www.gstatic.com/firebasejs/10.13.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.1/firebase-messaging-compat.js');

// ⚠️ Doit être IDENTIQUE à la config de lib/firebase_options.dart
// (section web). Copie exacte des valeurs générées par `flutterfire
// configure` — ne pas inventer de valeurs ici.
firebase.initializeApp({
  apiKey: 'REPLACE_WITH_FIREBASE_OPTIONS_WEB_APIKEY',
  authDomain: 'REPLACE_WITH_FIREBASE_OPTIONS_WEB_AUTHDOMAIN',
  projectId: 'REPLACE_WITH_FIREBASE_OPTIONS_WEB_PROJECTID',
  storageBucket: 'REPLACE_WITH_FIREBASE_OPTIONS_WEB_STORAGEBUCKET',
  messagingSenderId: 'REPLACE_WITH_FIREBASE_OPTIONS_WEB_MESSAGINGSENDERID',
  appId: 'REPLACE_WITH_FIREBASE_OPTIONS_WEB_APPID',
});

const messaging = firebase.messaging();

// Notification reçue alors que l'onglet AxelPay n'est pas actif —
// Firebase affiche déjà une notification native par défaut si le
// payload contient un bloc `notification` ; ce handler ne sert qu'à
// personnaliser cet affichage (icône, actions...).
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Message reçu en arrière-plan :', payload);

  const title = payload.notification?.title || 'AxelPay';
  const options = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png', // adapte au chemin réel de ton icône web
    data: payload.data || {},
  };

  self.registration.showNotification(title, options);
});

// Clic sur la notification affichée ci-dessus : ramène l'onglet AxelPay
// au premier plan (ou en ouvre un nouveau s'il n'y en a aucun).
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if ('focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});
