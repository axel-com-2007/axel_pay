// ============================================================
// PERSISTANCE DU CACHE DE TRADUCTION (hors-ligne, réutilisable sans DeepL)
// ============================================================
// Stocke sur disque, en JSON simple (pas chiffré : ce ne sont que des
// libellés d'interface déjà publics dans le binaire de l'app, pas des
// données personnelles — inutile de payer le coût de SQLCipher ici comme
// le fait `LocalCache`), le résultat des traductions DeepL déjà obtenues.
//
// Volontairement un fichier séparé de `LocalCache` (data/local_cache.dart)
// et de `LocaleController` (l10n/app_locale_controller.dart), pour la même
// raison que celle documentée dans `app_locale_controller.dart` : le cache
// offline métier (`LocalCache`) est intégralement purgé à la déconnexion
// (`LocalCache.clear()`), ce qui ferait perdre TOUTES les traductions déjà
// payées à DeepL à chaque logout — donc un nouvel appel réseau au prochain
// login, uniquement pour ré-afficher les mêmes libellés d'interface.
//
// Format sur disque : { "<clé>": {"fr": "<texte source>", "en": "<traduit>"} }
// Le champ "fr" sert à invalider le cache automatiquement si le texte
// source change un jour (ajout d'un mot, correction...) sans avoir à gérer
// de version de schéma manuelle.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CachedTranslation {
  final String fr;
  final String en;
  const CachedTranslation({required this.fr, required this.en});

  factory CachedTranslation.fromJson(Map<String, dynamic> json) =>
      CachedTranslation(fr: json['fr'] as String, en: json['en'] as String);

  Map<String, dynamic> toJson() => {'fr': fr, 'en': en};
}

class TranslationCacheStore {
  TranslationCacheStore._internal();
  static final TranslationCacheStore instance = TranslationCacheStore._internal();

  // "v1" : à incrémenter si le format JSON ci-dessus change un jour, pour
  // repartir d'un cache vide plutôt que de planter sur un ancien format.
  static const _fileName = 'axelpay_i18n_cache_en_v1.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Lit le cache persisté. Ne lève jamais d'exception : un fichier
  /// absent, corrompu, ou illisible (permissions...) donne simplement un
  /// cache vide — l'app doit toujours démarrer, même dans ce cas.
  Future<Map<String, CachedTranslation>> lire() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return raw.map(
        (key, value) => MapEntry(key, CachedTranslation.fromJson(value as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  /// Écrit l'intégralité du cache sur disque (écrasement complet — le
  /// volume attendu, quelques centaines de chaînes d'interface tout au
  /// plus, rend un stockage clé/valeur incrémental inutilement complexe).
  /// Échec silencieux (stockage plein...) : non bloquant, le cache reste
  /// simplement en mémoire pour le reste de la session.
  Future<void> ecrire(Map<String, CachedTranslation> cache) async {
    try {
      final f = await _file();
      final raw = cache.map((key, value) => MapEntry(key, value.toJson()));
      await f.writeAsString(jsonEncode(raw));
    } catch (_) {
      // Non bloquant, voir commentaire ci-dessus.
    }
  }
}
