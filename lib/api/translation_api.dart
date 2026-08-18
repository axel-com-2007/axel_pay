// ============================================================
// CLIENT API — /i18n/traduire/ (traduction FR->EN via DeepL, côté serveur)
// ============================================================
// Ne fait qu'un seul travail : envoyer un lot de textes français à
// `TraduireTextesView` (api/views.py) et renvoyer les traductions dans le
// même ordre. Toute la logique de cache/lots vit dans
// `l10n/translation_controller.dart` — cette classe reste un simple client
// HTTP, sur le même modèle que les autres fichiers de `lib/api/`.
//
// Sécurité : la clé DeepL n'existe QUE côté Django (settings.DEEPL_API_KEY).
// Ce client n'en a jamais connaissance — il parle à notre propre backend,
// jamais à `api.deepl.com` directement.
// ============================================================

import 'api_client.dart';

class TranslationApi {
  TranslationApi._internal();
  static final TranslationApi instance = TranslationApi._internal();

  /// Traduit [textes] (français) vers [cible] ("EN" par défaut). Renvoie
  /// la liste des traductions dans le MÊME ORDRE — l'appelant est
  /// responsable de réassocier chaque traduction à sa clé d'origine.
  ///
  /// Laisse remonter [ApiException] (réseau, 503 DeepL indisponible, etc.) :
  /// c'est à l'appelant (`TranslationController`) de décider de retomber
  /// silencieusement sur le français en cas d'échec, pas à ce client.
  Future<List<String>> traduireLot(List<String> textes, {String cible = 'EN'}) async {
    if (textes.isEmpty) return const [];
    final data = await ApiClient.instance.post(
      '/i18n/traduire/',
      data: {'textes': textes, 'cible': cible},
    );
    final traductions = (data as Map<String, dynamic>)['traductions'] as List;
    return traductions.map((e) => e as String).toList();
  }
}
