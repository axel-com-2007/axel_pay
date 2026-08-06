// ============================================================
// AppLoader — indicateur de chargement standard
// ============================================================
// Remplace les CircularProgressIndicator "nus" dispersés dans les
// écrans par un indicateur cohérent avec l'identité bleue de l'app,
// avec en option un message et une version plein écran.
// ============================================================

import 'package:flutter/material.dart';
import '../../design_system/colors/app_colors.dart';
import '../../design_system/typography/app_typography.dart';
import '../../design_system/spacing/app_spacing.dart';

class AppLoader extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final Color color;
  final String? message;

  const AppLoader({
    super.key,
    this.size = 32,
    this.strokeWidth = 2.6,
    this.color = AppColors.primaryBlue,
    this.message,
  });

  /// Petit loader inline (ex: à l'intérieur d'un bouton ou d'une ligne).
  const AppLoader.small({super.key, this.color = AppColors.primaryBlue})
      : size = 18,
        strokeWidth = 2.2,
        message = null;

  @override
  Widget build(BuildContext context) {
    final spinner = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth, color: color),
    );

    if (message == null) return Center(child: spinner);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          spinner,
          const SizedBox(height: AppSpacing.md),
          Text(message!, style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  /// Voile plein écran semi-transparent avec loader centré, utilisé
  /// par-dessus un écran déjà affiché pendant une action bloquante
  /// (paiement, envoi de formulaire...).
  static Widget overlay({String? message}) {
    return Container(
      color: AppColors.white.withOpacity(0.7),
      child: AppLoader(message: message),
    );
  }
}
