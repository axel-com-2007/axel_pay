// ============================================================
// AppDialog — boîte de dialogue standard de l'application
// ============================================================
// Point d'entrée unique pour les confirmations et alertes, avec une
// apparence cohérente (coins arrondis, titre, boutons AppButton).
// ============================================================

import 'package:flutter/material.dart';
import '../../design_system/colors/app_colors.dart';
import '../../design_system/typography/app_typography.dart';
import '../../design_system/spacing/app_spacing.dart';
import '../../design_system/buttons/app_button.dart';

class AppDialog {
  AppDialog._();

  /// Dialogue de confirmation générique (ex: "Supprimer ce compteur ?").
  /// Renvoie `true` si l'utilisateur confirme, `false`/`null` sinon.
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirmer',
    String cancelLabel = 'Annuler',
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Text(title, style: AppTextStyles.h3),
        content: Text(message, style: AppTextStyles.body),
        actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        actions: [
          Expanded(
            child: AppButton.secondary(
              label: cancelLabel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppButton(
              label: confirmLabel,
              backgroundColor: danger ? AppColors.danger : null,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    );
  }

  /// Alerte simple à un seul bouton ("OK").
  static Future<void> alert({
    required BuildContext context,
    required String title,
    required String message,
    String buttonLabel = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: Text(title, style: AppTextStyles.h3),
        content: Text(message, style: AppTextStyles.body),
        actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        actions: [
          Expanded(
            child: AppButton(label: buttonLabel, onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}
