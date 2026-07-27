import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'animations/animations.dart';

/// Carte blanche standard avec ombre légère, utilisée comme conteneur
/// visuel principal sur la quasi-totalité des écrans (dashboard, factures,
/// compteurs, paramètres...).
///
/// Micro-interaction : quand [onTap] est fourni, la carte réduit
/// légèrement de taille au toucher (effet ressort), pour donner une
/// sensation d'app vivante sur toute l'application. [heroTag] permet en
/// plus une transition "Hero" fluide vers un écran de détail (ex :
/// vignette de facture -> header de la page de détail).
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
    Widget card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );

    if (heroTag != null) {
      card = Hero(
        tag: heroTag!,
        child: Material(color: Colors.transparent, child: card),
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
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

/// Ligne icône + titre + sous-titre + chevron, inspirée de la page
/// "Paramètres Windows" fournie en référence visuelle (grille d'options
/// avec icône colorée). Utilisée dans l'écran Paramètres & Support.
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
    this.iconColor = AppColors.primary,
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
