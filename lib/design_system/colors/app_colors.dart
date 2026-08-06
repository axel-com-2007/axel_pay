// ============================================================
// DESIGN SYSTEM — COULEURS
// ============================================================
// Source unique de vérité pour toutes les couleurs de l'application.
// Palette obligatoire :
//   - Couleurs principales  : Bleu / Blanc
//   - Couleurs secondaires  : Vert / Gris
// Aucune couleur ne doit être écrite "en dur" (Color(0xFF...)) dans les
// écrans : tout passe par AppColors.
//
// Rétro-compatibilité : les anciens noms (primary, secondary, background,
// surface, textPrimary...) sont conservés comme alias vers les nouveaux
// tokens ci-dessous, afin qu'aucun écran existant n'ait à être modifié
// pour continuer à compiler et à s'afficher correctement.
// ============================================================

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ---------------------------------------------------------
  // Couleurs principales — Bleu & Blanc
  // ---------------------------------------------------------
  static const Color primaryBlue = Color(0xFF0A5FFF);
  static const Color primaryBlueDark = Color(0xFF0A46BF);
  static const Color primaryBlueLight = Color(0xFFEAF1FF);
  static const Color white = Color(0xFFFFFFFF);

  // ---------------------------------------------------------
  // Couleurs secondaires — Vert & Gris
  // ---------------------------------------------------------
  static const Color secondaryGreen = Color(0xFF16A34A);
  static const Color secondaryGreenDark = Color(0xFF0F7C38);
  static const Color secondaryGreenLight = Color(0xFFE6F7EC);

  static const Color greyBackground = Color(0xFFF4F6F9);
  static const Color greySurface = Color(0xFFEFF4FF); // blanc légèrement teinté bleu
  static const Color greyMedium = Color(0xFFE3E7ED);
  static const Color greyDark = Color(0xFFF4F6F9);

  static const Color textDark = Color(0xFF10182B);
  static const Color textGrey = Color(0xFF5B6472);
  static const Color textGreyMuted = Color(0xFF9AA3AF);

  // ---------------------------------------------------------
  // Statuts fonctionnels (factures, compteurs, transactions)
  // ---------------------------------------------------------
  static const Color success = secondaryGreen; // Payée / Actif / Réussi
  static const Color warning = Color(0xFFE0A106); // En cours de traitement
  static const Color danger = Color(0xFFE0453C); // Impayée / Suspendu / Échoué
  static const Color info = primaryBlue;

  static const Color divider = Color(0x1F10182B);
  static const Color cardShadow = Color(0x1A0B1B2B);

  // Dégradé de fond doux (écrans de connexion / inscription)
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [white, greyBackground],
  );

  // Dégradé bleu (bandeaux, avatar, éléments de marque)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), primaryBlue],
  );

  // Dégradé vert (accents secondaires, succès, carte de mise en avant)
  static const LinearGradient secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22C55E), secondaryGreen],
  );

  // ---------------------------------------------------------
  // Alias rétro-compatibles — NE PAS SUPPRIMER
  // Utilisés tels quels par les écrans existants (lib/screens/**).
  // Conservés pour ne rien casser lors du remplacement du dossier lib/.
  // ---------------------------------------------------------
  static const Color primary = primaryBlue;
  static const Color primaryDark = primaryBlueDark;
  static const Color primaryLight = primaryBlueLight;
  static const Color secondary = secondaryGreen;
  static const Color background = white;
  static const Color surface = white;
  static const Color surfaceWhite = white;

  static const Color textPrimary = textDark;
  static const Color textSecondary = textGrey;
  static const Color textMuted = textGreyMuted;
}

/// Renvoie une couleur de statut cohérente pour tous les écrans
/// (factures, compteurs, transactions) à partir d'un libellé métier.
Color statusColor(String statut) {
  switch (statut.toLowerCase()) {
    case 'payée':
    case 'payee':
    case 'actif':
    case 'réussi':
    case 'reussi':
    case 'confirmé':
      return AppColors.success;
    case 'en cours':
    case 'en cours de traitement':
    case 'en attente':
      return AppColors.warning;
    case 'impayée':
    case 'impayee':
    case 'suspendu':
    case 'échoué':
    case 'echoue':
    case 'annulé':
      return AppColors.danger;
    default:
      return AppColors.info;
  }
}