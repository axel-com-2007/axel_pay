// ============================================================
// AppContainer — conteneur générique du design system
// ============================================================
// Enveloppe standardisée pour les blocs de mise en page qui ne sont pas
// des cartes à ombre (bandeaux, sections de fond coloré, dégradés...),
// afin d'éviter les BoxDecoration écrites en dur dans les écrans.
// ============================================================

import 'package:flutter/material.dart';
import '../../design_system/colors/app_colors.dart';
import '../../design_system/spacing/app_spacing.dart';
import '../../design_system/shadows/app_shadows.dart';

enum AppContainerVariant { plain, tinted, gradient, outlined }

class AppContainer extends StatelessWidget {
  final Widget child;
  final AppContainerVariant variant;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;
  final Gradient? gradient;
  final bool shadow;

  const AppContainer({
    super.key,
    required this.child,
    this.variant = AppContainerVariant.plain,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.borderRadius = AppRadius.card,
    this.color,
    this.gradient,
    this.shadow = false,
  });

  const AppContainer.gradient({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.borderRadius = AppRadius.card,
    this.gradient = AppColors.primaryGradient,
    this.shadow = true,
  })  : variant = AppContainerVariant.gradient,
        color = null;

  const AppContainer.outlined({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.borderRadius = AppRadius.card,
    this.color,
  })  : variant = AppContainerVariant.outlined,
        gradient = null,
        shadow = false;

  @override
  Widget build(BuildContext context) {
    BoxDecoration decoration;
    switch (variant) {
      case AppContainerVariant.gradient:
        decoration = BoxDecoration(
          gradient: gradient ?? AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: shadow ? AppShadows.floating : null,
        );
        break;
      case AppContainerVariant.tinted:
        decoration = BoxDecoration(
          color: color ?? AppColors.greySurface,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: shadow ? AppShadows.soft : null,
        );
        break;
      case AppContainerVariant.outlined:
        decoration = BoxDecoration(
          color: color ?? AppColors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: AppColors.divider),
        );
        break;
      case AppContainerVariant.plain:
        decoration = BoxDecoration(
          color: color ?? AppColors.greyBackground,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: shadow ? AppShadows.soft : null,
        );
        break;
    }

    return Container(
      margin: margin,
      padding: padding,
      decoration: decoration,
      child: child,
    );
  }
}
