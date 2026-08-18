// ============================================================
// THÈME CENTRAL DE L'APPLICATION — COMPATIBILITÉ
// ============================================================
// Ce fichier reste à son emplacement historique (lib/theme/app_theme.dart)
// pour qu'AUCUN écran existant n'ait à changer son import
// (`import '../../theme/app_theme.dart';`).
//
// Toute la source de vérité (couleurs, typographie, espacements, ombres,
// boutons, cartes, animations) vit désormais dans lib/design_system/.
// Ce fichier se contente de la ré-exporter et de construire le
// ThemeData Material global à partir de ces tokens.
// ============================================================

import 'package:flutter/material.dart';
import '../design_system/design_system.dart';

export '../design_system/design_system.dart';
// responsive_utils est déjà réexporté via design_system.dart

class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        primary: AppColors.primaryBlue,
        secondary: AppColors.secondaryGreen,
        // Forcer surface = blanc pur pour que Material3 n'invente pas
        // une teinte bleu-grisée à partir du seedColor bleu.
        surface: AppColors.white,
        // surfaceContainerLowest/Low/High… sont aussi générés bleutés
        // par fromSeed. On les ramène tous au blanc ou au gris neutre.
        surfaceContainerLowest: AppColors.white,
        surfaceContainerLow: AppColors.white,
        surfaceContainer: AppColors.greyBackground,
        surfaceContainerHigh: AppColors.greyBackground,
        surfaceContainerHighest: AppColors.greyBackground,
      ),
      // Neutralise le surfaceTintColor automatique de Material3 pour les
      // widgets Card natifs (CardTheme) — idem que pour AppCard custom.
      // Neutralise le surfaceTintColor automatique de Material3 pour les
      // widgets Card natifs (CardTheme) — idem que pour AppCard custom.
      cardTheme: CardThemeData(                          // ← CardThemeData (pas CardTheme)
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        centerTitle: false,
        titleTextStyle: AppTextStyles.h2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          elevation: 4,
          shadowColor: AppColors.primaryBlue.withOpacity(0.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: AppColors.primaryBlue.withOpacity(0.14),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primaryBlue : AppColors.textMuted,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
    );
  }
}
