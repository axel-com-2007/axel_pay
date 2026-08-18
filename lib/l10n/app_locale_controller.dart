// ============================================================
// CONTRÔLEUR DE LANGUE — sélecteur "Langue" de SettingsScreen
// ============================================================
// Le sélecteur existait déjà dans `settings_screen.dart` (bottom sheet
// Français/English) mais ne faisait que modifier une variable locale
// `langue`, sans aucun effet sur l'app : ce fichier fournit l'état
// PARTAGÉ (via `provider`, déjà utilisé ailleurs dans l'app — cf.
// `AuthService` dans `main.dart`) qui pilote réellement la locale de
// `MaterialApp` et de [S] (`app_strings.dart`).
//
// Persistance via `flutter_secure_storage` : déjà une dépendance du
// projet (cf. `token_storage.dart`), réutilisée ici plutôt que
// d'introduire `shared_preferences` pour une seule préférence. Le choix
// de langue n'est PAS une donnée sensible, mais éviter une dépendance
// supplémentaire pour un seul champ est un compromis raisonnable — à
// migrer vers `shared_preferences` si d'autres préférences non
// sensibles doivent être persistées un jour.
//
// ⚠️ Volontairement indépendant de `LocalCache` (le cache hors-ligne
// §7.6) : ce dernier est intégralement purgé à la déconnexion
// (`LocalCache.clear()`), ce qui ferait perdre la langue choisie à
// chaque logout — un mauvais comportement pour une préférence
// d'affichage qui n'a rien à voir avec les données de compte.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocaleController extends ChangeNotifier {
  static const _kStorageKey = 'eneo_langue_choisie';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Langues supportées par l'app. `Locale('fr')` reste la langue par
  /// défaut tant qu'aucun choix n'a été persisté (comportement identique
  /// à avant ce correctif — l'app démarrait déjà en français).
  static const supported = [Locale('fr'), Locale('en')];

  Locale _locale = const Locale('fr');
  Locale get locale => _locale;

  /// Charge la langue précédemment choisie (si l'utilisateur en a déjà
  /// sélectionné une) — à appeler une fois au démarrage, avant
  /// `runApp` idéalement, ou juste après (voir `main.dart`).
  Future<void> charger() async {
    final code = await _storage.read(key: _kStorageKey);
    if (code != null && supported.any((l) => l.languageCode == code)) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

  Future<void> definirLangue(Locale nouvelle) async {
    if (nouvelle.languageCode == _locale.languageCode) return;
    _locale = nouvelle;
    notifyListeners();
    await _storage.write(key: _kStorageKey, value: nouvelle.languageCode);
  }
}
