// ============================================================
// CONTRÔLEUR DE TRADUCTION — moteur dynamique derrière `S` (app_strings.dart)
// ============================================================
// Remplace l'ancienne approche de `app_strings.dart` (paires FR/EN écrites
// à la main dans le code) par des traductions générées par DeepL et mises
// en cache sur l'appareil (voir `translation_cache_store.dart`) :
//   - Le FRANÇAIS reste la seule "vérité" écrite dans le code Dart (chaque
//     écran ne fournit qu'un texte français à `S`, comme avant).
//   - L'ANGLAIS est demandé à DeepL (via `TranslationApi` -> backend Django
///    -> DeepL) LA PREMIÈRE FOIS qu'une chaîne est affichée en anglais,
//     puis réutilisé indéfiniment depuis le cache disque, y compris hors
//     connexion, sans nouvel appel réseau.
//
// Fonctionnement (voir `translate()`) :
//   1. Si la traduction de `cle` est déjà en cache ET que le texte source
//      français n'a pas changé depuis -> on la retourne directement.
//   2. Sinon -> on retombe TEMPORAIREMENT sur le texte français fourni (pas
//      de null, pas de clé technique affichée à l'écran) et on met la
//      chaîne en file d'attente pour un appel groupé.
//   3. Toutes les chaînes mises en file d'attente pendant le MÊME frame
//      Flutter (donc potentiellement plusieurs dizaines de `Text(...)`
//      construits par le même écran) sont envoyées en UN SEUL appel réseau
//      groupé juste après ce frame (`addPostFrameCallback`), jamais un
//      appel par widget — indispensable pour rester dans la limite de
//      débit `DEFAULT_THROTTLE_RATES["traduction"]` côté Django et éviter
//      un flash visuel écran par écran.
//   4. Dès que le lot revient, le cache est mis à jour, persisté sur disque,
//      et `notifyListeners()` reconstruit les écrans concernés (via
//      `S.of(context)` qui fait `context.watch<TranslationController>()`)
//      — l'anglais apparaît alors sans action de l'utilisateur.
// ============================================================

import 'package:flutter/widgets.dart';

import '../api/translation_api.dart';
import 'translation_cache_store.dart';

class TranslationController extends ChangeNotifier {
  final Map<String, CachedTranslation> _cache = {};
  final Map<String, String> _enAttente = {}; // clé -> texte français
  bool _envoiPlanifie = false;
  bool _chargementInitialFait = false;

  /// Charge le cache persisté — à appeler une fois au démarrage (voir
  /// `main.dart`), avant `runApp` idéalement, comme `LocaleController.charger()`.
  Future<void> charger() async {
    final donnees = await TranslationCacheStore.instance.lire();
    _cache.addAll(donnees);
    _chargementInitialFait = true;
  }

  /// Traduit [texteFr] (identifié par [cle], stable et unique dans toute
  /// l'app — voir convention dans `app_strings.dart`) vers l'anglais.
  ///
  /// Toujours synchrone (nécessaire : appelée depuis `build()`). Ne
  /// bloque JAMAIS l'affichage : retombe sur [texteFr] tant que la
  /// traduction n'est pas encore en cache, et se corrige toute seule dès
  /// qu'elle arrive (voir `notifyListeners()` dans `_envoyerLot`).
  String translate(String cle, String texteFr) {
    final entree = _cache[cle];
    if (entree != null && entree.fr == texteFr) {
      return entree.en;
    }
    // Pas encore traduit, ou texte source français modifié depuis la
    // dernière traduction (cache invalidé automatiquement dans ce cas).
    _enAttente[cle] = texteFr;
    _planifierEnvoi();
    return texteFr;
  }

  void _planifierEnvoi() {
    if (_envoiPlanifie) return;
    _envoiPlanifie = true;
    // `addPostFrameCallback` plutôt qu'un `Future.microtask` : on veut
    // laisser TOUS les widgets du frame en cours (donc de l'écran entier)
    // ajouter leurs clés manquantes à `_enAttente` avant de partir en un
    // seul appel réseau — un microtask pourrait se déclencher entre deux
    // `build()` du même frame selon l'ordonnancement.
    WidgetsBinding.instance.addPostFrameCallback((_) => _envoyerLot());
  }

  Future<void> _envoyerLot() async {
    _envoiPlanifie = false;
    if (_enAttente.isEmpty) return;

    final lot = Map<String, String>.of(_enAttente);
    _enAttente.clear();

    try {
      final traductions = await TranslationApi.instance.traduireLot(lot.values.toList());
      final cles = lot.keys.toList();
      for (var i = 0; i < cles.length; i++) {
        _cache[cles[i]] = CachedTranslation(fr: lot[cles[i]]!, en: traductions[i]);
      }
      await TranslationCacheStore.instance.ecrire(_cache);
      notifyListeners();
    } catch (e) {
      // Hors ligne, DeepL indisponible, ou limite de débit atteinte : on
      // reste silencieusement en français pour ce lot. Les clés
      // redeviendront candidates au prochain accès (ex: changement
      // d'écran) — pas d'erreur visible pour l'utilisateur, un écran
      // traduit "en retard" est un compromis très préférable à un écran
      // qui plante.
      debugPrint('TranslationController: échec de traduction (non bloquant) : $e');
    }
  }

  bool get chargementInitialFait => _chargementInitialFait;
}
