// ============================================================
// DESIGN SYSTEM — OMBRES
// ============================================================
// Élévations centralisées pour donner de la profondeur aux cartes et
// boutons sans jamais écrire de BoxShadow "en dur" dans les écrans.
// ============================================================

import 'package:flutter/material.dart';
import '../colors/app_colors.dart';

class AppShadows {
  AppShadows._();

  /// Ombre douce par défaut pour les cartes.
  static List<BoxShadow> get card => [
        BoxShadow(
          color: AppColors.cardShadow,
          blurRadius: 20,
          offset: const Offset(0, 8),
          spreadRadius: -4,
        ),
      ];

  /// Ombre très légère (listes, chips, champs de saisie au focus).
  static List<BoxShadow> get soft => [
        BoxShadow(
          color: AppColors.cardShadow.withOpacity(0.08),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];

  /// Ombre marquée (boutons flottants, carte mise en avant, bottom sheet).
  static List<BoxShadow> get floating => [
        BoxShadow(
          color: AppColors.cardShadow.withOpacity(0.22),
          blurRadius: 28,
          offset: const Offset(0, 12),
          spreadRadius: -6,
        ),
      ];

  /// Halo coloré (états de succès, boutons primaires).
  static List<BoxShadow> glow(Color color, {double opacity = 0.35}) => [
        BoxShadow(
          color: color.withOpacity(opacity),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}
