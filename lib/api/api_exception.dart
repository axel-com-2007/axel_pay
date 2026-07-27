/// Exceptions typées mappées sur les réponses d'erreur de Django REST
/// Framework, telles qu'observées dans `views.py` :
///   - `ValidationError({"champ": "message"})` → 400
///   - `PermissionDenied("message")`           → 403
///   - `NotFound` (get_object_or_404)          → 404
///   - conflits métier (webhook, écart montant)→ 409
///   - non authentifié / token expiré          → 401
///
/// Toutes héritent de [ApiException] pour permettre un `catch (ApiException e)`
/// générique côté UI Flutter, tout en gardant la possibilité de distinguer
/// les cas (ex: afficher un formulaire d'erreurs de champ pour une
/// [ApiValidationException], ou rediriger vers le login pour une
/// [ApiAuthException]).
library;

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  /// Corps brut de la réponse d'erreur, si disponible (utile pour debug/log).
  final dynamic rawBody;

  ApiException(this.message, {this.statusCode, this.rawBody});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 400 — erreurs de validation DRF. `fieldErrors` reprend le mapping
/// champ → liste de messages, ex: {"telephone": ["Ce numéro est déjà utilisé."]}
/// pour pouvoir les afficher directement sous les champs d'un formulaire.
class ApiValidationException extends ApiException {
  final Map<String, List<String>> fieldErrors;

  ApiValidationException(
    super.message, {
    required this.fieldErrors,
    super.statusCode = 400,
    super.rawBody,
  });

  /// Premier message d'erreur toutes catégories confondues, pratique pour un
  /// simple SnackBar quand on ne veut pas détailler champ par champ.
  String get firstMessage {
    if (fieldErrors.isEmpty) return message;
    return fieldErrors.values.first.first;
  }
}

/// 401 — non authentifié, session expirée, refresh token invalide/blacklisté.
/// Le client déclenche automatiquement [ApiClient.onSessionExpired] dans ce cas.
class ApiAuthException extends ApiException {
  ApiAuthException(super.message, {super.statusCode = 401, super.rawBody});
}

/// 403 — authentifié mais rôle/droit insuffisant (ex: IsAdminFinancier,
/// IsAdminTechnicien, RG-02/RG-03/RG-05 dans views.py).
class ApiPermissionException extends ApiException {
  ApiPermissionException(super.message, {super.statusCode = 403, super.rawBody});
}

/// 404 — ressource introuvable (get_object_or_404 côté Django).
class ApiNotFoundException extends ApiException {
  ApiNotFoundException(super.message, {super.statusCode = 404, super.rawBody});
}

/// 409 — conflit métier : écart de montant webhook (RG-08), etc.
class ApiConflictException extends ApiException {
  ApiConflictException(super.message, {super.statusCode = 409, super.rawBody});
}

/// 5xx — erreur serveur.
class ApiServerException extends ApiException {
  ApiServerException(super.message, {super.statusCode, super.rawBody});
}

/// Pas de réponse du serveur (timeout, pas de réseau, DNS...).
class ApiNetworkException extends ApiException {
  ApiNetworkException(super.message) : super(statusCode: null);
}

/// Requête annulée volontairement via un [CancelToken] (écran fermé pendant
/// un appel en vol). À catcher séparément pour l'ignorer silencieusement :
/// ```dart
/// } on ApiCancelledException {
///   // no-op : l'écran qui a lancé l'appel n'existe déjà plus.
/// } on ApiException catch (e) {
///   _showSnack(e.message);
/// }
/// ```
class ApiCancelledException extends ApiException {
  ApiCancelledException() : super('Requête annulée.', statusCode: null);
}
