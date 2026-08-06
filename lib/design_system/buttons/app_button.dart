// ============================================================
// DESIGN SYSTEM — BOUTONS
// ============================================================
// AppButton est le composant canonique utilisé par toute l'application.
// PrimaryButton / SecondaryButton (noms historiques déjà utilisés par
// tous les écrans existants) sont conservés comme fines enveloppes
// autour d'AppButton pour ne rien casser lors du remplacement du
// dossier lib/.
// ============================================================

import 'package:flutter/material.dart';
import '../colors/app_colors.dart';
import '../spacing/app_spacing.dart';
import '../animations/app_animations.dart';

enum AppButtonVariant { primary, secondary, ghost }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? backgroundColor;
  final AppButtonVariant variant;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.backgroundColor,
    this.variant = AppButtonVariant.primary,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.backgroundColor,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  })  : variant = AppButtonVariant.secondary,
        loading = false,
        backgroundColor = null;

  const AppButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  })  : variant = AppButtonVariant.ghost,
        loading = false,
        backgroundColor = null;

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case AppButtonVariant.secondary:
        return _OutlinedAppButton(label: label, onPressed: onPressed, icon: icon);
      case AppButtonVariant.ghost:
        return _GhostAppButton(label: label, onPressed: onPressed, icon: icon);
      case AppButtonVariant.primary:
        return _FilledAppButton(
          label: label,
          onPressed: onPressed,
          loading: loading,
          icon: icon,
          backgroundColor: backgroundColor,
        );
    }
  }
}

class _FilledAppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? backgroundColor;

  const _FilledAppButton({
    required this.label,
    required this.onPressed,
    required this.loading,
    required this.icon,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      scaleDown: 0.98,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor ?? AppColors.primaryBlue,
            foregroundColor: AppColors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
            elevation: 4,
            shadowColor: (backgroundColor ?? AppColors.primaryBlue).withOpacity(0.4),
          ),
          child: loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(label),
                  ],
                ),
        ),
      ),
    );
  }
}

class _OutlinedAppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const _OutlinedAppButton({required this.label, required this.onPressed, required this.icon});

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      scaleDown: 0.98,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textDark,
            side: const BorderSide(color: AppColors.divider),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostAppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const _GhostAppButton({required this.label, required this.onPressed, required this.icon});

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      scaleDown: 0.97,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 6),
            ],
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Alias historiques — utilisés tels quels par tous les écrans
// existants (lib/screens/**). Conservés pour ne rien casser.
// ---------------------------------------------------------------

/// Bouton d'action principal ("Valider", "Continuer", "Payer"...).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? backgroundColor;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onPressed: onPressed,
      loading: loading,
      icon: icon,
      backgroundColor: backgroundColor,
    );
  }
}

/// Bouton secondaire (contour), pour les actions moins importantes
/// à côté d'un [PrimaryButton] (ex: "Annuler").
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return AppButton.secondary(label: label, onPressed: onPressed, icon: icon);
  }
}
