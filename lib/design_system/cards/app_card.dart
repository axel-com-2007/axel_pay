// ============================================================
// DESIGN SYSTEM — CARTES
// ============================================================

import 'package:flutter/material.dart';
import '../colors/app_colors.dart';
import '../typography/app_typography.dart';
import '../spacing/app_spacing.dart';
import '../shadows/app_shadows.dart';
import '../animations/app_animations.dart';

/// Carte blanche standard avec ombre légère, utilisée comme conteneur
/// visuel principal sur la quasi-totalité des écrans (accueil, factures,
/// compteurs, paramètres...).
///
/// Micro-interaction : quand [onTap] est fourni, la carte réduit
/// légèrement de taille au toucher (effet ressort). [heroTag] permet en
/// plus une transition "Hero" fluide vers un écran de détail.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final Object? heroTag;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.onTap,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Material(
      color: color ?? AppColors.white,
      // En Material 3, Flutter applique automatiquement un tint coloré
      // (dérivé de colorScheme.primary) par-dessus la couleur de fond,
      // même à elevation: 0. Résultat : toutes les cartes "blanches"
      // prennent une teinte bleu-gris. On neutralise ce comportement en
      // forçant surfaceTintColor à transparent.
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.card),
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card,
        ),
        child: child,
      ),
    );

    if (heroTag != null) {
      card = Hero(
        tag: heroTag!,
        child: card,
      );
    }

    if (onTap == null) return card;
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: card,
    );
  }
}

/// Titre de section avec un éventuel lien d'action à droite
/// (ex: "Dernières factures" — "Voir tout").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTextStyles.h3),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(
                color: AppColors.secondaryGreen,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

/// Ligne icône + titre + sous-titre + chevron, utilisée dans les listes
/// d'options (ex: écran Paramètres & Support).
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = AppColors.primaryBlue,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.label),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right,
                    color: AppColors.textMuted, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Formate un montant en francs CFA, ex: 18500 -> "18 500 FCFA".
String formatFcfa(num montant) {
  final buffer = StringBuffer();
  final str = montant.round().toString();
  for (int i = 0; i < str.length; i++) {
    final posFromEnd = str.length - i;
    buffer.write(str[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write(' ');
  }
  return '${buffer.toString()} FCFA';
}