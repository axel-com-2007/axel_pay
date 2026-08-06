// ============================================================
// BANDEAU "MODE HORS CONNEXION" — partagé entre tous les écrans
// offline-critiques
// ============================================================
// Affiché dès qu'AU MOINS une donnée visible à l'écran provient du cache
// local plutôt que du réseau. Complète (sans le remplacer) l'indicateur
// de fraîcheur déjà présent sur certaines cartes.
// ============================================================

import 'package:flutter/material.dart';
import '../../design_system/colors/app_colors.dart';
import '../../design_system/typography/app_typography.dart';

/// "à l'instant" / "il y a 12 min" / "il y a 3 h" / "il y a 2 j".
String formatSyncLabel(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'à l’instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  return 'il y a ${diff.inDays} j';
}

class OfflineBanner extends StatelessWidget {
  final DateTime? derniereSynchro;
  final EdgeInsetsGeometry margin;

  const OfflineBanner({
    super.key,
    required this.derniereSynchro,
    this.margin = const EdgeInsets.fromLTRB(20, 8, 20, 0),
  });

  @override
  Widget build(BuildContext context) {
    final synchro = derniereSynchro;
    final label = synchro != null
        ? 'Dernière synchronisation : ${formatSyncLabel(synchro)}'
        : 'Aucune synchronisation récente';
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mode hors connexion',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                Text(label, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau utilisé côté écran de paiement : aucune opération financière
/// n'est autorisée sans connexion active. Volontairement distinct
/// d'[OfflineBanner] : il n'indique pas une fraîcheur de donnée mais
/// bloque une ACTION, donc un ton et une icône différents (danger
/// plutôt que warning), sans date de synchronisation.
class OfflineActionBlockedBanner extends StatelessWidget {
  final String message;

  const OfflineActionBlockedBanner({
    super.key,
    this.message =
        'Vous êtes hors connexion. Les paiements et recharges nécessitent une connexion active — réessayez une fois reconnecté.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off, size: 18, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
