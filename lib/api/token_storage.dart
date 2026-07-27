import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage des tokens JWT émis par `LoginView` / `RefreshTokenView`.
///
/// - `access` (SIMPLE_JWT.ACCESS_TOKEN_LIFETIME = 20 min côté settings.py)
/// - `refresh` (SIMPLE_JWT.REFRESH_TOKEN_LIFETIME = 30 jours)
///
/// Utilise `flutter_secure_storage` (Keychain iOS / Keystore Android) plutôt
/// que `SharedPreferences` : un JWT donne un accès complet au compte, il ne
/// doit jamais atterrir en clair dans un stockage non chiffré.
///
/// Ajoute au pubspec.yaml :
///   flutter_secure_storage: ^9.0.0
class TokenStorage {
  TokenStorage._internal();
  static final TokenStorage instance = TokenStorage._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kAccessKey = 'eneo_access_token';
  static const _kRefreshKey = 'eneo_refresh_token';

  Future<void> saveTokens({required String access, required String refresh}) async {
    await Future.wait([
      _storage.write(key: _kAccessKey, value: access),
      _storage.write(key: _kRefreshKey, value: refresh),
    ]);
  }

  /// Met à jour uniquement le token d'accès (cas du refresh classique, cf.
  /// `RefreshTokenView` qui ne renvoie que `{"access": ...}` — le backend ne
  /// fait PAS de rotation du refresh token malgré `ROTATE_REFRESH_TOKENS =
  /// True` dans settings.py, qui ne s'applique qu'au TokenRefreshView natif
  /// de simplejwt, non utilisé ici).
  Future<void> updateAccessToken(String access) async {
    await _storage.write(key: _kAccessKey, value: access);
  }

  Future<String?> get accessToken => _storage.read(key: _kAccessKey);
  Future<String?> get refreshToken => _storage.read(key: _kRefreshKey);

  Future<bool> get hasSession async => (await refreshToken) != null;

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kAccessKey),
      _storage.delete(key: _kRefreshKey),
    ]);
  }
}
