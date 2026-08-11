import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'device_token_api.dart';
import 'eneo_api_service.dart';
import 'token_storage.dart';
import 'models/user_model.dart';
import '../data/local_cache.dart';
import '../services/firebase_messaging_service.dart';

/// État d'authentification exposé à l'UI.
///
/// `unknown`        : au tout premier lancement, avant que [AuthService.initialize]
///                     ait déterminé si une session valide existe déjà.
/// `authenticated`   : utilisateur connecté, [AuthService.currentUser] est renseigné.
/// `unauthenticated` : pas de session (jamais connecté, déconnecté, ou session expirée).
enum AuthStatus { unknown, authenticated, unauthenticated }

/// Service d'authentification — couche métier au-dessus d'[EneoApiService]
/// dédiée au Module 1 (`auth/*`, `profile/*`) de `urls.py`.
///
/// [NOTIFICATIONS PUSH] Ce service enregistre/désenregistre également le
/// token FCM du terminal auprès de Django (Module 6, `devices/*`) à chaque
/// changement de session — c'est le point central le plus fiable pour ça :
/// on est sûr d'avoir un JWT valide en main (nécessaire, `/devices/` exige
/// `IsAuthenticated`), et ça couvre tous les chemins d'entrée/sortie de
/// session (login, logout volontaire, logout forcé, relance de l'app).
class AuthService extends ChangeNotifier {
  AuthService({EneoApiService? apiService})
      : _api = apiService ?? EneoApiService() {
    // Déclenché par ApiClient quand un refresh échoue (refresh token
    // expiré/invalide/blacklisté) — cf. `_send()` dans api_client.dart.
    // On synchronise alors l'état local SANS rappeler /auth/logout/ (le
    // token est déjà mort côté serveur, l'appel échouerait de toute façon).
    ApiClient.instance.onSessionExpired = _handleForcedLogout;
  }

  final EneoApiService _api;
  final TokenStorage _tokenStorage = TokenStorage.instance;

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _currentUser;
  String? _lastError;
  bool _isLoading = false;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  String? get lastError => _lastError;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(ApiException e) {
    _lastError = e is ApiValidationException ? e.firstMessage : e.message;
  }

  // ===========================================================================
  // Notifications push (FCM) — voir note de classe ci-dessus
  // ===========================================================================

  /// Enregistre le token FCM courant auprès de Django. Volontairement
  /// "fire-and-forget" (non attendu par les appelants) : un échec ici ne
  /// doit jamais retarder ni faire échouer un login par ailleurs réussi
  /// (voir aussi le try/catch absorbant dans [DeviceTokenApi]).
  void _registerCurrentDeviceToken() {
    unawaited(() async {
      final token = await FirebaseMessagingService.instance.getCurrentToken();
      if (token == null) return;
      await DeviceTokenApi.instance.registerToken(
        fcmToken: token,
        deviceType: kIsWeb ? 'web' : 'android',
      );
    }());
  }

  /// Désenregistre le token FCM AVANT que la session ne soit nettoyée
  /// (l'appel a besoin du JWT encore valide pour passer l'auth Django).
  Future<void> _unregisterCurrentDeviceToken() async {
    try {
      final token = await FirebaseMessagingService.instance.getCurrentToken();
      if (token != null) {
        await DeviceTokenApi.instance.unregisterToken(token);
      }
    } catch (_) {
      // Absorbé : ne doit jamais bloquer un logout.
    }
  }

  // ===========================================================================
  // Démarrage de l'app
  // ===========================================================================

  /// À appeler une fois au démarrage de l'app (ex. `main()` ou écran splash).
  ///
  /// S'il existe un refresh token en stockage sécurisé, on tente de récupérer
  /// le profil (`GET /profile/`) pour (a) valider que la session est toujours
  /// utilisable et (b) peupler [currentUser]. `ApiClient` rafraîchit
  /// automatiquement l'access token si besoin ; si le refresh échoue,
  /// [_handleForcedLogout] est appelé automatiquement via `onSessionExpired`.
  Future<void> initialize() async {
    final hasSession = await _tokenStorage.hasSession;
    if (!hasSession) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      final data = await _api.getProfile();
      _currentUser = UserModel.fromJson(data);
      _status = AuthStatus.authenticated;
    } on ApiException {
      // Session invalide malgré la présence d'un refresh token (ex. compte
      // désactivé entre-temps) : on nettoie et on repart propre.
      await _tokenStorage.clear();
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();

    if (_status == AuthStatus.authenticated) {
      // Filet de sécurité pour le consentement RGPD : si l'appel tenté juste
      // après l'inscription (voir otp_screen.dart) avait échoué (réseau,
      // serveur down...), on retente ici à CHAQUE démarrage de l'app tant
      // qu'aucun GRANTED n'est retrouvé côté serveur. Volontairement non
      // "awaited" : ça ne doit jamais retarder l'affichage du premier écran.
      unawaited(_ensureConsentRecorded());

      // Session déjà valide au relancement de l'app (ex. token FCM ayant
      // tourné pendant que l'app était fermée) : on (ré)enregistre pour
      // être sûr que Django a la dernière valeur.
      _registerCurrentDeviceToken();
    }
  }

  /// Vérifie qu'un consentement `GRANTED` existe déjà côté serveur
  /// (`GET /profile/consent/`) ; sinon, tente de l'enregistrer. Échec
  /// absorbé en silence — c'est justement le rôle de ce filet de
  /// sécurité de retenter plus tard sans jamais bloquer l'utilisateur.
  Future<void> _ensureConsentRecorded() async {
    try {
      final consents = await _api.listConsents();
      final dejaAccepte = consents
          .whereType<Map>()
          .any((c) => c['action'] == 'GRANTED');
      if (!dejaAccepte) {
        await recordConsent(action: 'GRANTED');
      }
    } on ApiException {
      // Nouvelle tentative au prochain lancement de l'app.
    }
  }

  // ===========================================================================
  // Inscription + vérification OTP
  // ===========================================================================

  /// Crée le compte (`POST /auth/register/`). Ne connecte PAS automatiquement
  /// l'utilisateur : enchaîne normalement sur un écran de saisie OTP puis un
  /// appel explicite à [login] (le compte est déjà utilisable pour se
  /// connecter dès la création côté backend actuel — voir le commentaire
  /// `statut_compte="Actif"` dans `RegisterView` — mais l'UX attendue reste
  /// inscription → OTP → login).
  ///
  /// Lance [ApiValidationException] si téléphone/e-mail déjà pris ou champ
  /// manquant (`fieldErrors` prêt à afficher sous les champs du formulaire).
  Future<UserModel> register({
    required String nom,
    required String prenom,
    required String telephone,
    required String email,
    required String motDePasse,
    String? situationMatrimoniale,
    String? quartier,
  }) async {
    _lastError = null;
    _setLoading(true);
    try {
      final data = await _api.register(
        nom: nom,
        prenom: prenom,
        telephone: telephone,
        email: email,
        motDePasse: motDePasse,
        situationMatrimoniale: situationMatrimoniale,
        quartier: quartier,
      );
      return UserModel.fromJson(data);
    } on ApiException catch (e) {
      _setError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Vérifie le code OTP à 6 chiffres envoyé au `telephone` (inscription ou
  /// changement de numéro). Ne modifie pas [status] : la connexion reste un
  /// appel séparé à [login].
  Future<void> verifyOtp({required String telephone, required String otp}) async {
    _lastError = null;
    _setLoading(true);
    try {
      await _api.verifyOtp(telephone: telephone, otp: otp);
    } on ApiException catch (e) {
      _setError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ===========================================================================
  // Connexion / déconnexion
  // ===========================================================================

  /// Connexion par téléphone OU e-mail (`identifiant`). En cas de succès,
  /// stocke les tokens (fait par [EneoApiService.login]), peuple
  /// [currentUser] et passe [status] à `authenticated`.
  ///
  /// Erreurs à gérer côté UI :
  ///  - [ApiValidationException] (400) : identifiants invalides.
  ///  - [ApiPermissionException] (403) : compte verrouillé (5 tentatives
  ///    échouées → verrouillage 1h côté `LoginView`).
  Future<UserModel> login({
    required String identifiant,
    required String motDePasse,
  }) async {
    _lastError = null;
    _setLoading(true);
    try {
      final data = await _api.login(identifiant: identifiant, motDePasse: motDePasse);
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      _currentUser = user;
      _status = AuthStatus.authenticated;

      // [NOTIFICATIONS PUSH] Le JWT vient d'être stocké par
      // EneoApiService.login() : on peut maintenant enregistrer le token
      // FCM auprès de Django en toute sécurité.
      _registerCurrentDeviceToken();

      return user;
    } on ApiException catch (e) {
      _setError(e);
      rethrow;
    } catch (e) {
      // Filet de sécurité : si la réponse du serveur a une forme inattendue
      // (champ manquant, type différent...), on ne doit jamais rester
      // bloqué silencieusement sur l'écran de connexion. On affiche
      // l'erreur réelle pour pouvoir la corriger.
      debugPrint('Erreur inattendue pendant le login : $e');
      _lastError = 'Erreur inattendue : $e';
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Déconnexion volontaire : blackliste le refresh token côté serveur
  /// (`POST /auth/logout/`) puis nettoie l'état local, que l'appel réseau
  /// réussisse ou non (déjà géré par [EneoApiService.logout]).
  Future<void> logout() async {
    _setLoading(true);
    try {
      // [NOTIFICATIONS PUSH] Désenregistrer AVANT l'appel logout : le
      // token FCM doit disparaître de Django tant que le JWT est encore
      // valide, sinon la requête part sans Authorization et échoue (sans
      // gravité — juste un device qui reste "Actif" un peu plus
      // longtemps, voir _unregisterCurrentDeviceToken).
      await _unregisterCurrentDeviceToken();
      await _api.logout();
    } finally {
      // §7.6 : purge du cache local hors-ligne au logout, que l'appel
      // réseau ait réussi ou non — même logique que le nettoyage du
      // TokenStorage dans EneoApiService.logout().
      await LocalCache.instance.clear();
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _setLoading(false);
    }
  }

  /// Déconnexion forcée (refresh token expiré/invalide/blacklisté), appelée
  /// automatiquement par [ApiClient.onSessionExpired]. Ne fait AUCUN appel
  /// réseau : le stockage est déjà nettoyé par `ApiClient._send()` avant que
  /// ce callback soit invoqué.
  ///
  /// [NOTIFICATIONS PUSH] Pas de désenregistrement du token ici : le JWT
  /// est déjà mort côté serveur, l'appel `/devices/desenregistrer/`
  /// échouerait de toute façon (401). Le device restera "Actif" jusqu'au
  /// nettoyage automatique des tokens invalides côté Django (voir
  /// `notifications/firebase.py` : un push qui échoue avec
  /// `UNREGISTERED`/`InvalidRegistration` désactive le device
  /// correspondant).
  void _handleForcedLogout() {
    // §7.6 : purge du cache local hors-ligne, ici aussi (pas seulement au
    // logout volontaire) — le token est déjà nettoyé par ApiClient._send()
    // avant cet appel, mais le cache offline (solde, factures, jetons...)
    // ne l'était pas encore. `onSessionExpired` est un callback synchrone
    // (`void Function()?`), donc on ne peut pas l'attendre ici ; c'est sans
    // risque puisque `LocalCache.clear()` est déjà silencieux sur erreur.
    unawaited(LocalCache.instance.clear());
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    _lastError = 'Session expirée, merci de te reconnecter.';
    notifyListeners();
  }

  // ===========================================================================
  // Mot de passe oublié
  // ===========================================================================

  /// Réponse volontairement neutre côté backend (ne révèle pas si le compte
  /// existe) — inutile d'interpréter le résultat, juste afficher un message
  /// de confirmation générique à l'utilisateur.
  Future<void> requestPasswordReset({required String identifiant}) async {
    _lastError = null;
    _setLoading(true);
    try {
      await _api.passwordResetRequest(identifiant: identifiant);
    } on ApiException catch (e) {
      _setError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> confirmPasswordReset({
    required String token,
    required String nouveauMotDePasse,
  }) async {
    _lastError = null;
    _setLoading(true);
    try {
      await _api.passwordResetConfirm(token: token, nouveauMotDePasse: nouveauMotDePasse);
    } on ApiException catch (e) {
      _setError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ===========================================================================
  // Consentement RGPD (CDC 5.1 / 11.3)
  // ===========================================================================

  /// Version des CGU actuellement en vigueur — un seul endroit à modifier
  /// quand les CGU changent. Utilisée par [recordConsent].
  static const String cguVersion = '1.0';

  /// Enregistre une décision de consentement (`POST /profile/consent/`,
  /// `UserConsentView`). Nécessite une session active (`IsAuthenticated`
  /// côté backend) — à appeler après [login], jamais après [register] seul
  /// (voir le commentaire dans `RegisterScreen`/`OtpScreen`).
  ///
  /// `UserConsentLogs` est Append-Only (RG-12) : chaque appel crée une
  /// nouvelle ligne opposable, il n'y a jamais de mise à jour.
  Future<void> recordConsent({
    String canal = 'App',
    String versionCgu = cguVersion,
    required String action, // GRANTED | REVOKED
  }) async {
    // Volontairement silencieux côté [status]/[lastError] : un échec ici ne
    // doit jamais bloquer une connexion par ailleurs réussie. L'appelant
    // décide comment réagir (log, retry silencieux, etc.).
    await _api.recordConsent(canal: canal, versionCgu: versionCgu, action: action);
  }

  // ===========================================================================
  // Profil connecté (téléphone, infos générales)
  // ===========================================================================

  /// Changement de numéro : nécessite le mot de passe courant en confirmation
  /// (`ChangePhoneNumberView.update` — protection contre le détournement de
  /// compte). Met à jour [currentUser] en cas de succès.
  Future<UserModel> changePhoneNumber({
    required String nouveauTelephone,
    required String motDePasseConfirmation,
  }) async {
    _lastError = null;
    _setLoading(true);
    try {
      final data = await _api.changePhoneNumber(
        nouveauTelephone: nouveauTelephone,
        motDePasseConfirmation: motDePasseConfirmation,
      );
      final user = UserModel.fromJson(data);
      _currentUser = user;
      return user;
    } on ApiException catch (e) {
      _setError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Recharge le profil depuis le serveur (ex. après un `pull-to-refresh` sur
  /// un écran "Mon compte") et met à jour [currentUser].
  Future<void> refreshProfile() async {
    if (_status != AuthStatus.authenticated) return;
    try {
      final data = await _api.getProfile();
      _currentUser = UserModel.fromJson(data);
      notifyListeners();
    } on ApiException catch (e) {
      _setError(e);
      // On ne déconnecte pas ici : un 401 déclenche déjà _handleForcedLogout
      // via ApiClient ; les autres erreurs (réseau, 5xx) ne doivent pas tuer
      // une session par ailleurs valide.
    }
  }
}
