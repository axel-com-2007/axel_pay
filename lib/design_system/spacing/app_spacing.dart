// ============================================================
// DESIGN SYSTEM — ESPACEMENTS & RAYONS
// ============================================================
// Échelle d'espacement cohérente (multiples de 4) + rayons de bordure
// centralisés. Évite les "magic numbers" dispersés dans les écrans.
// ============================================================

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class AppRadius {
  AppRadius._();

  static const double card = 22;
  static const double field = 14;
  static const double chip = 30;
  static const double sheet = 24;
  static const double banner = 28;
  static const double button = 16;
}
