// ============================================================
// lib/services/firebase_messaging_service.dart
// ============================================================
// Service centralisant TOUT ce qui touche à Firebase Cloud
// Messaging (FCM) : permissions, récupération/rotation du token,
// écoute des messages foreground/background, gestion du tap sur
// une notification.
//
// ⚠️ Ce service ne fait AUCUN appel réseau vers Django lui-même.
// Il expose des callbacks (`onToken`, `onMessageTap`) que
// `main.dart` / `AuthService` branchent sur `DeviceTokenApi`
// (voir device_token_api.dart) — séparation des responsabilités :
// ce fichier ne connaît que Firebase, jamais Dio ni les routes
// Django.
//
// Compatible Android / iOS / Web (Flutter Web utilise le service
// worker `web/firebase-messaging-sw.js`, voir plus bas).
// ============================================================

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Payload minimal transmis lors du clic sur une notification (foreground,
/// background ou app terminée), pour que la couche UI décide de la
/// navigation (ex: aller directement sur `FactureDetailScreen`).
class PushNotificationTapPayload {
  const PushNotificationTapPayload({
    required this.data,
    this.title,
    this.body,
  });

  final Map<String, dynamic> data;
  final String? title;
  final String? body;
}

/// Handler de messages en arrière-plan / app terminée.
///
/// ⚠️ Contrainte Firebase : DOIT être une fonction top-level ou `static`
/// (jamais une méthode d'instance), et annotée `@pragma('vm:entry-point')`
/// pour survivre à la minification/tree-shaking en release.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Remarque : sur Android, ce handler tourne dans un isolate séparé sans
  // état applicatif (pas de Provider, pas de session Dio). On se contente
  // ici de logger — toute action nécessitant l'état de l'app (navigation,
  // mise à jour d'un badge local...) doit être faite dans
  // `onMessageOpenedApp` (déclenché quand l'utilisateur TAPE la
  // notification, à ce moment l'app est réveillée normalement).
  debugPrint(
    '📩 [BG] Notification reçue en arrière-plan : '
    '${message.notification?.title} — ${message.data}',
  );
}

class FirebaseMessagingService {
  FirebaseMessagingService._internal();
  static final FirebaseMessagingService instance =
      FirebaseMessagingService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Appelé à chaque fois qu'un token FCM (initial ou rafraîchi) est
  /// disponible. Branché par `main.dart` sur `DeviceTokenApi.registerToken`.
  void Function(String token)? onToken;

  /// Appelé quand l'utilisateur tape une notification (foreground ou pour
  /// réveiller l'app depuis le background). Branché sur la navigation.
  void Function(PushNotificationTapPayload payload)? onMessageTap;

  /// Appelé pour CHAQUE notification reçue en foreground, avant tout
  /// affichage custom (SnackBar, bannière in-app...). Optionnel.
  void Function(RemoteMessage message)? onForegroundMessage;

  bool _initialized = false;

  /// Point d'entrée unique — à appeler une seule fois dans `main()`,
  /// APRÈS `Firebase.initializeApp()`.
  ///
  /// Ne lève jamais d'exception non gérée : une erreur FCM (permission
  /// refusée, token indisponible sur un émulateur sans Google Play
  /// Services...) ne doit jamais empêcher le reste de l'app de démarrer.
  Future<void> setupFirebaseMessaging({
    void Function(String token)? onToken,
    void Function(PushNotificationTapPayload payload)? onMessageTap,
    void Function(RemoteMessage message)? onForegroundMessage,
  }) async {
    if (_initialized) return;
    _initialized = true;

    this.onToken = onToken;
    this.onMessageTap = onMessageTap;
    this.onForegroundMessage = onForegroundMessage;

    try {
      // Handler background : DOIT être enregistré tôt, avant toute autre
      // interaction avec FirebaseMessaging (ignoré silencieusement sur
      // Web, où le service worker s'en charge — voir plus bas).
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }

      await _requestPermission();

      // Sur iOS/macOS, permet d'afficher alerte/son/badge même quand
      // l'app est au premier plan (sans ça, iOS masque la notif par
      // défaut). Sans effet sur Android/Web.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      await _fetchAndEmitToken();

      // Rotation de token : Firebase peut en émettre un nouveau à tout
      // moment (réinstallation, changement d'app id, expiration...).
      // Sans cet écouteur, le backend Django garderait un token périmé
      // et les push cesseraient silencieusement d'arriver.
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 FCM token rafraîchi : $newToken');
        onToken?.call(newToken);
      });

      // --- Foreground : l'app est ouverte et visible ---
      _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
        debugPrint(
          '📩 [FG] ${message.notification?.title} — ${message.data}',
        );
        onForegroundMessage?.call(message);
      });

      // --- Tap sur la notification pendant que l'app tourne en
      // background (pas terminée) ---
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _emitTap(message);
      });

      // --- App lancée DEPUIS une notification (était totalement
      // terminée) : à vérifier une fois, après le premier frame ---
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _emitTap(initialMessage);
      }
    } catch (e, st) {
      // Filet de sécurité : un environnement sans Google Play Services
      // (émulateur nu) ou une permission refusée ne doit jamais crasher
      // le démarrage de l'app.
      debugPrint('⚠️ Échec initialisation Firebase Messaging : $e\n$st');
    }
  }

  Future<NotificationSettings> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint(
      '🔔 Permission notification : ${settings.authorizationStatus}',
    );
    return settings;
  }

  Future<void> _fetchAndEmitToken() async {
    // Sur Flutter Web, `getToken()` exige la clé VAPID publique du projet
    // Firebase (Console Firebase > Cloud Messaging > Web Push
    // certificates). Sans elle, l'appel échoue silencieusement (retourne
    // null) sur Chrome.
    final token = kIsWeb
        ? await _messaging.getToken(vapidKey: _webVapidKey)
        : await _messaging.getToken();

    if (token == null) {
      debugPrint('⚠️ Aucun token FCM disponible (permission refusée ?).');
      return;
    }

    debugPrint('🔥 FCM TOKEN : $token');
    onToken?.call(token);
  }

  void _emitTap(RemoteMessage message) {
    onMessageTap?.call(
      PushNotificationTapPayload(
        data: message.data,
        title: message.notification?.title,
        body: message.notification?.body,
      ),
    );
  }

  /// Récupère le token FCM actuel à la demande (ex: juste après un login
  /// réussi, pour l'envoyer immédiatement à Django sans attendre un
  /// éventuel `onTokenRefresh`).
  Future<String?> getCurrentToken() {
    return kIsWeb
        ? _messaging.getToken(vapidKey: _webVapidKey)
        : _messaging.getToken();
  }

  /// À appeler au logout : supprime le token côté client Firebase (ne
  /// désenregistre PAS côté Django — c'est le rôle de
  /// `DeviceTokenApi.unregisterToken`, à appeler AVANT ceci pendant que
  /// le token est encore lisible).
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('⚠️ Échec suppression token FCM local : $e');
    }
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _tokenRefreshSub?.cancel();
    _initialized = false;
  }

  // ⚠️ À REMPLACER par ta clé VAPID publique (Console Firebase > Project
  // Settings > Cloud Messaging > Web configuration > Web Push
  // certificates > "Key pair"). Nécessaire UNIQUEMENT pour Flutter Web ;
  // laissée vide, `getToken()` renvoie null sur Web sans planter le reste.
  static const String _webVapidKey = 'REPLACE_WITH_YOUR_VAPID_KEY';
}
