// ============================================================
// DESIGN SYSTEM — TYPOGRAPHIE
// ============================================================
// Hiérarchie typographique professionnelle unique pour toute l'app :
// titres, sous-titres, textes secondaires, montants, infos critiques.
// ============================================================

import 'package:flutter/material.dart';
import '../colors/app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  /// Nom de marque ("AxelPay") en en-tête des écrans d'auth.
  static const TextStyle brand = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: AppColors.primaryBlue,
    letterSpacing: 0.2,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textDark,
    height: 1.2,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.textDark,
    height: 1.25,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textDark,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.textDark,
    height: 1.4,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: 13,
    color: AppColors.textGrey,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.textGreyMuted,
  );

  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textDark,
  );

  /// Montants importants (solde, montant de facture, total à payer...).
  static const TextStyle amountLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
    letterSpacing: -0.5,
  );

  static const TextStyle amountMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
  );

  /// Informations critiques (alertes, soldes négatifs, échecs).
  static const TextStyle critical = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.danger,
  );
}
