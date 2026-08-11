// ============================================================
// lib/api/device_token_api.dart
// ============================================================
// Façade Dio dédiée aux routes Django `devices/*` (Module 6 —
// Notifications, cf. api/urls.py backend).
//
// S'appuie sur `ApiClient.instance` déjà existant du projet
// (singleton Dio + intercepteur JWT + refresh automatique) — PAS
// de nouvelle instance Dio créée ici, conformément au reste du
// codebase (voir eneo_api_service.dart).
// ============================================================

import 'api_client.dart';
import 'api_exception.dart';

class DeviceTokenApi {
  DeviceTokenApi._internal();
  static final DeviceTokenApi instance = DeviceTokenApi._internal();

  final ApiClient _client = ApiClient.instance;

  /// Enregistre (ou met à jour, cf. upsert côté Django sur `fcm_token`
  /// unique) le token FCM du terminal courant.
  ///
  /// À appeler :
  ///  - juste après un [AuthService.login] réussi ;
  ///  - à chaque `onTokenRefresh` émis par [FirebaseMessagingService].
  ///
  /// `deviceType` doit être l'une des valeurs attendues côté Django
  /// (`android` | `ios` | `web`).
  Future<void> registerToken({
    required String fcmToken,
    required String deviceType,
  }) async {
    try {
      await _client.post(
        '/devices/',
        data: {
          'fcm_token': fcmToken,
          'type_appareil': deviceType,
        },
      );
    } on ApiException catch (e) {
      // Volontairement absorbé : un échec d'enregistrement du token ne
      // doit jamais bloquer le login ni planter l'app — au pire,
      // l'utilisateur ne reçoit pas de push tant que le prochain
      // `onTokenRefresh` ou le prochain login ne réessaie.
      // ignore: avoid_print
      print('⚠️ Échec enregistrement token FCM : ${e.message}');
    }
  }

  /// Désenregistre le token FCM du terminal courant (déconnexion,
  /// désinstallation). Appelle `DELETE /devices/desenregistrer/` avec le
  /// token en corps de requête plutôt que par `id_device` (le client
  /// Flutter ne connaît jamais cet identifiant serveur — voir
  /// `DeviceUnregisterByTokenView` côté Django).
  ///
  /// À appeler AVANT [FirebaseMessagingService.deleteToken] (pendant que
  /// le token est encore lisible) et AVANT que [AuthService.logout]
  /// n'efface les tokens JWT (sinon la requête part sans
  /// `Authorization`).
  Future<void> unregisterToken(String fcmToken) async {
    try {
      await _client.delete(
        '/devices/desenregistrer/',
        data: {'fcm_token': fcmToken},
      );
    } on ApiException catch (e) {
      // Même logique : ne bloque jamais le logout. Le pire cas est un
      // device marqué "Actif" un peu plus longtemps côté Django — sans
      // conséquence grâce au nettoyage automatique des tokens invalides
      // (voir notifications/firebase.py côté backend).
      // ignore: avoid_print
      print('⚠️ Échec désenregistrement token FCM : ${e.message}');
    }
  }
}
