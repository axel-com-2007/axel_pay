import 'dart:async';
import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'token_storage.dart';

/// Point d'entrée unique vers le backend Django (`axel_pay_backend`).
///
/// Responsabilités :
///  1. Construire les requêtes HTTP (base URL, headers JSON).
///  2. Attacher automatiquement `Authorization: Bearer <access>` (cf.
///     `SIMPLE_JWT["AUTH_HEADER_TYPES"] = ("Bearer",)` dans settings.py),
///     sauf sur les routes publiques (`permissions.AllowAny` côté Django :
///     register, login, verify-otp, password-reset, refresh, webhook...).
///  3. Rafraîchir automatiquement le token d'accès sur un 401, rejouer la
///     requête originale, et ne le faire qu'UNE fois en cas de requêtes
///     concurrentes (verrou `_refreshCompleter`).
///  4. Mapper chaque réponse d'erreur DRF vers une [ApiException] typée pour
///     que le reste de l'app Flutter n'ait jamais à parser du JSON d'erreur.
///
/// Usage recommandé : instancier UNE SEULE FOIS (singleton `ApiClient.instance`)
/// et injecter cette instance dans les services métier (voir
/// `eneo_api_service.dart`), plutôt que de créer des `Dio()` un peu partout.
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        // On gère nous-mêmes le statut pour pouvoir mapper les erreurs DRF.
        validateStatus: (_) => true,
      ),
    );
    _dio.interceptors.add(_authInterceptor());
  }

  static final ApiClient instance = ApiClient._internal();

  late final Dio _dio;
  final TokenStorage _tokenStorage = TokenStorage.instance;

  /// Callback déclenché quand la session ne peut plus être maintenue
  /// (refresh token expiré/invalide/blacklisté). Branche ceci sur ta
  /// navigation Flutter pour rediriger vers l'écran de login, ex :
  ///   ApiClient.instance.onSessionExpired = () => router.go('/login');
  void Function()? onSessionExpired;

  /// Routes qui ne doivent JAMAIS recevoir de header Authorization, en miroir
  /// exact de `permission_classes = [permissions.AllowAny]` dans views.py.
  static const List<String> _publicPaths = [
    '/auth/register/',
    '/auth/verify-otp/',
    '/auth/login/',
    '/auth/refresh/',
    '/auth/password-reset/',
    '/auth/password-reset/confirm/',
    '/paiements/webhook/', // authentifié par signature HMAC, pas par JWT
  ];

  bool _isPublicPath(String path) =>
      _publicPaths.any((p) => path.startsWith(p) || path.startsWith('/api$p'));

  Completer<bool>? _refreshCompleter;

  Interceptor _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (!_isPublicPath(options.path)) {
          final token = await _tokenStorage.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
    );
  }

  /// Tente un rafraîchissement du token d'accès. Retourne `true` en cas de
  /// succès. Les appels concurrents attendent le même [Completer] au lieu de
  /// déclencher chacun leur propre appel réseau vers `/auth/refresh/`.
  Future<bool> _refreshAccessToken() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final refresh = await _tokenStorage.refreshToken;
      if (refresh == null) {
        completer.complete(false);
        return false;
      }

      // Appel brut (pas via `request()`) pour éviter toute récursion sur
      // l'intercepteur 401 ci-dessous.
      final response = await _dio.post('/auth/refresh/', data: {'refresh': refresh});

      if (response.statusCode == 200 && response.data['access'] != null) {
        await _tokenStorage.updateAccessToken(response.data['access'] as String);
        completer.complete(true);
        return true;
      }
      completer.complete(false);
      return false;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Cœur de l'exécution d'une requête : envoie, gère le 401 → refresh →
  /// retry, puis mappe toute erreur restante vers une [ApiException].
  ///
  /// ⚠️ CORRECTIF (audit Flutter↔Django) : l'ancienne version ne convertissait
  /// en [ApiNetworkException] que 3 des 8 [DioExceptionType] possibles
  /// (connectionTimeout/receiveTimeout/connectionError) et faisait `rethrow`
  /// pour tous les autres (badResponse, badCertificate, cancel, sendTimeout,
  /// unknown). Un `DioException` brut n'est PAS une [ApiException] : tout
  /// écran qui ne catche que `on ApiException catch (e)` (le cas standard
  /// dans ce projet) laissait alors filer une exception non gérée — freeze
  /// silencieux de l'UI (bouton qui "ne fait rien"), déjà observé en
  /// production sur une simple faute de frappe dans `ApiConfig.baseUrl`.
  /// Le switch ci-dessous est volontairement EXHAUSTIF : quoi qu'il arrive
  /// côté réseau/Dio, l'appelant reçoit toujours une [ApiException].
  Future<T> _send<T>(
    Future<Response> Function() call, {
    required T Function(Response response) onSuccess,
    bool isRetry = false,
  }) async {
    late Response response;
    try {
      response = await call();
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.transformTimeout:
          throw ApiNetworkException(
              'Impossible de joindre le serveur. Vérifie ta connexion et l\'adresse configurée dans ApiConfig.baseUrl.');
        case DioExceptionType.badCertificate:
          throw ApiNetworkException('Certificat du serveur invalide.');
        case DioExceptionType.cancel:
          // Requête annulée volontairement (CancelToken, cf. verbes HTTP
          // ci-dessous) — typiquement un écran fermé pendant un appel en
          // vol. Ce n'est pas une vraie "erreur" ; on le distingue quand
          // même comme ApiException pour que l'appelant puisse l'ignorer
          // explicitement (`on ApiCancelledException { /* no-op */ }`)
          // sans avoir à parser une chaîne de message.
          throw ApiCancelledException();
        case DioExceptionType.badResponse:
          // Ne devrait pas arriver (validateStatus renvoie toujours true
          // ci-dessous) — sécurité si Dio lève quand même côté transport.
          throw ApiServerException('Réponse serveur invalide.',
              statusCode: e.response?.statusCode);
        case DioExceptionType.unknown:
          // Cas typique : URL malformée, hôte/DNS introuvable, socket
          // fermé... (c'est ici qu'atterrissait le bug historique de
          // faute de frappe dans ApiConfig.baseUrl).
          throw ApiNetworkException(
              'Impossible de joindre le serveur (${e.message ?? "erreur réseau"}). Vérifie ApiConfig.baseUrl.');
      }
    } catch (e) {
      // Filet de sécurité final : quoi qu'il arrive (y compris une erreur
      // qui ne vient même pas de Dio), l'appelant reçoit toujours une
      // [ApiException] qu'il sait catcher — jamais une erreur brute qui
      // disparaît silencieusement dans un Future non observé.
      if (e is ApiException) rethrow;
      throw ApiException('Erreur inattendue : $e');
    }

    final status = response.statusCode ?? 0;

    if (status == 401 && !isRetry) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        return _send(call, onSuccess: onSuccess, isRetry: true);
      }
      await _tokenStorage.clear();
      onSessionExpired?.call();
      throw ApiAuthException(_extractDetail(response) ?? 'Session expirée, reconnecte-toi.');
    }

    if (status >= 200 && status < 300) {
      return onSuccess(response);
    }

    throw _mapError(status, response);
  }

  ApiException _mapError(int status, Response response) {
    final detail = _extractDetail(response);
    switch (status) {
      case 400:
        return ApiValidationException(
          detail ?? 'Requête invalide.',
          fieldErrors: _extractFieldErrors(response.data),
          rawBody: response.data,
        );
      case 401:
        return ApiAuthException(detail ?? 'Non authentifié.', rawBody: response.data);
      case 403:
        return ApiPermissionException(detail ?? 'Action non autorisée.', rawBody: response.data);
      case 404:
        return ApiNotFoundException(detail ?? 'Ressource introuvable.', rawBody: response.data);
      case 409:
        return ApiConflictException(detail ?? 'Conflit détecté.', rawBody: response.data);
      default:
        if (status >= 500) {
          return ApiServerException('Erreur serveur ($status).', statusCode: status, rawBody: response.data);
        }
        return ApiException(detail ?? 'Erreur inattendue ($status).', statusCode: status, rawBody: response.data);
    }
  }

  /// DRF renvoie parfois `{"detail": "..."}`, parfois directement
  /// `{"champ": "message"}` ou `{"champ": ["message"]}` (cf. `ValidationError`
  /// levées dans views.py, ex: `ValidationError({"telephone": "..."})`).
  String? _extractDetail(Response response) {
    final data = response.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (data is Map && data.isNotEmpty) {
      final firstValue = data.values.first;
      if (firstValue is List && firstValue.isNotEmpty) return firstValue.first.toString();
      return firstValue.toString();
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  Map<String, List<String>> _extractFieldErrors(dynamic data) {
    final result = <String, List<String>>{};
    if (data is Map) {
      data.forEach((key, value) {
        if (key == 'detail') return;
        if (value is List) {
          result[key.toString()] = value.map((e) => e.toString()).toList();
        } else {
          result[key.toString()] = [value.toString()];
        }
      });
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Verbes HTTP génériques — utilisés par les services métier (module par
  // module) plutôt que d'exposer Dio directement en dehors de ce fichier.
  //
  // `cancelToken` (optionnel, cf. https://pub.dev/documentation/dio/latest/dio/CancelToken-class.html) :
  // passe un `CancelToken` créé dans `initState()`/le provider d'un écran,
  // et appelle `token.cancel()` dans `dispose()`. Sans ça, un appel encore
  // en vol quand l'utilisateur quitte l'écran continue de tourner en
  // arrière-plan : dans le meilleur cas c'est du réseau gaspillé, dans le
  // pire cas une réponse tardive vient écraser un état plus récent
  // (race condition classique "out of order response") ou provoque un
  // `setState() called after dispose()` si le résultat est utilisé
  // directement dans un `FutureBuilder`/callback sans vérifier `mounted`.
  // ---------------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, dynamic>? query, CancelToken? cancelToken}) {
    return _send(
      () => _dio.get(path, queryParameters: query, cancelToken: cancelToken),
      onSuccess: (r) => r.data,
    );
  }

  Future<dynamic> post(String path, {dynamic data, CancelToken? cancelToken}) {
    return _send(
      () => _dio.post(path, data: data, cancelToken: cancelToken),
      onSuccess: (r) => r.data,
    );
  }

  Future<dynamic> patch(String path, {dynamic data, CancelToken? cancelToken}) {
    return _send(
      () => _dio.patch(path, data: data, cancelToken: cancelToken),
      onSuccess: (r) => r.data,
    );
  }

  Future<dynamic> put(String path, {dynamic data, CancelToken? cancelToken}) {
    return _send(
      () => _dio.put(path, data: data, cancelToken: cancelToken),
      onSuccess: (r) => r.data,
    );
  }

  Future<dynamic> delete(String path, {dynamic data, CancelToken? cancelToken}) {
    return _send(
      () => _dio.delete(path, data: data, cancelToken: cancelToken),
      onSuccess: (r) => r.data,
    );
  }
}
