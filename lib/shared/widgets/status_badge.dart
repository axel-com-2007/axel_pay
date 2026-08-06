import 'package:flutter/material.dart';
import '../../design_system/colors/app_colors.dart';
import '../../design_system/spacing/app_spacing.dart';
import '../../design_system/animations/app_animations.dart';

/// Petite pastille colorée affichant un statut métier (facture, compteur,
/// transaction). La couleur est déduite automatiquement du libellé via
/// [statusColor] pour éviter toute incohérence entre écrans.
///
/// Effet lumineux : un léger halo pulse en boucle autour des statuts
/// urgents (impayée, suspendu, échoué) pour attirer l'œil sans être
/// intrusif — désactivable via [pulse].
class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final bool? pulse;

  const StatusBadge({super.key, required this.label, this.color, this.pulse});

  bool get _isUrgent {
    final l = label.toLowerCase();
    return l.contains('impayé') || l.contains('suspendu') || l.contains('échoué') || l.contains('echoue');
  }

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? statusColor(label);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final shouldPulse = pulse ?? _isUrgent;
    if (!shouldPulse) return badge;
    return GlowPulse(
      color: c,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: badge,
    );
  }
}
