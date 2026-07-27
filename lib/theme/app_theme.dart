// ============================================================
// THÈME CENTRAL DE L'APPLICATION AXELPAY
// ============================================================
// REFONTE — palette alignée sur les 3 maquettes fournies :
//   - Turquoise (titre "AxelPay", boutons, onglet actif) : #17BFB8
//   - Jaune doré (carte d'accueil "Compteurs / Factures / Statistiques") : #F6C453
//   - Fond clair neutre (au lieu du dégradé beige précédent)
// On regroupe ici toutes les couleurs et tous les styles pour ne
// jamais avoir de valeurs "en dur" éparpillées dans les écrans.
// ============================================================

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Couleurs de marque (maquettes : connexion / création de compte / accueil)
  static const Color primary = Color(0xFF17BFB8); // Turquoise — "AxelPay", boutons, onglet actif
  static const Color primaryDark = Color(0xFF0FA39D);
  static const Color primaryLight = Color(0xFFE6F8F7);
  static const Color secondary = Color(0xFF0099FF); // Liens (mot de passe oublié, etc.)
  static const Color gold = Color(0xFFF6C453); // Jaune doré — carte d'accueil
  static const Color goldDark = Color(0xFFE0A82C);

  static const Color background = Color(0xFFFAFAF7); // Fond général clair
  static const Color surface = Color(0xFFEFFBFA); // Cartes claires teintées turquoise
  static const Color surfaceWhite = Colors.white;

  // Texte
  static const Color textPrimary = Color(0xDE0B1B2B); // quasi-noir bleuté
  static const Color textSecondary = Color(0x991B2A41);
  static const Color textMuted = Color(0x611B2A41);

  // Statuts fonctionnels (factures, compteurs, transactions)
  static const Color success = Color(0xFF2E9E5B); // Payée / Actif / Réussi
  static const Color warning = Color(0xFFE0A106); // En cours de traitement
  static const Color danger = Color(0xFFE0453C); // Impayée / Suspendu / Échoué
  static const Color info = Color(0xFF3D7BF0);

  // Neutres pour les listes / séparateurs
  static const Color divider = Color(0x1F1B2A41);
  static const Color cardShadow = Color(0x1A0B1B2B);

  // Dégradé de fond doux (écrans de connexion / inscription)
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFEFFBFA)],
  );

  // Dégradé turquoise (bandeaux, avatar, éléments de marque)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1FD1C9), primary],
  );
}

class AppRadius {
  AppRadius._();
  static const double card = 22;
  static const double field = 14;
  static const double chip = 30;
  static const double sheet = 24;
  static const double banner = 28;
}

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle brand = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: AppColors.primary,
    letterSpacing: 0.2,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: 13,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.textMuted,
  );

  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.gold,
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
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          elevation: 4,
          shadowColor: AppColors.primary.withOpacity(0.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withOpacity(0.14),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textMuted,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
    );
  }
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
