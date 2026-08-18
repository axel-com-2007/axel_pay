// ============================================================
// DESIGN SYSTEM — RESPONSIVE UTILS
// ============================================================
// Système complet d'adaptation aux tailles d'écran.
//
// Breakpoints :
//   • mobile  : largeur < 600 px   (téléphones)
//   • tablet  : 600 ≤ largeur < 1 024 px (tablettes, grands téléphones)
//   • desktop : largeur ≥ 1 024 px (PC, TV, écrans larges)
//
// Usage :
//   context.isMobile  → bool
//   context.isTablet  → bool
//   context.isDesktop → bool
//   context.screenWidth → double
//   context.sw(0.5)   → 50 % de la largeur d'écran
//   context.sh(0.3)   → 30 % de la hauteur d'écran
//
//   Responsive.value(context, mobile: 12, tablet: 16, desktop: 20)
//   Responsive.builder(context, mobile: widget1, tablet: widget2)
//   ResponsiveLayout(mobile: ...)  → choisit automatiquement
//
//   AppResponsiveSpacing.pagePadding(context) → EdgeInsets adapté
//   AppResponsiveText.scale(context, 14)     → fontSize adapté
// ============================================================

import 'package:flutter/material.dart';

// ────────────────────────────────────────────────────────────
// 1. BREAKPOINTS
// ────────────────────────────────────────────────────────────
class AppBreakpoints {
  AppBreakpoints._();

  /// Limite mobile → tablette
  static const double tablet = 600;

  /// Limite tablette → desktop
  static const double desktop = 1024;

  /// Largeur max du contenu sur desktop (évite les lignes trop larges)
  static const double maxContentWidth = 1200;

  /// Largeur max d'une colonne de formulaire (login, register…)
  static const double maxFormWidth = 480;

  /// Largeur max d'une carte dans une grille
  static const double maxCardWidth = 540;
}

// ────────────────────────────────────────────────────────────
// 2. EXTENSIONS BuildContext — accès rapide
// ────────────────────────────────────────────────────────────
extension ResponsiveContext on BuildContext {
  /// Largeur actuelle de l'écran
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Hauteur actuelle de l'écran
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// % de largeur (ex: sw(0.5) = 50 % de la largeur)
  double sw(double fraction) => screenWidth * fraction;

  /// % de hauteur
  double sh(double fraction) => screenHeight * fraction;

  /// Pixel ratio de l'écran
  double get devicePixelRatio => MediaQuery.devicePixelRatioOf(this);

  bool get isMobile => screenWidth < AppBreakpoints.tablet;
  bool get isTablet =>
      screenWidth >= AppBreakpoints.tablet && screenWidth < AppBreakpoints.desktop;
  bool get isDesktop => screenWidth >= AppBreakpoints.desktop;

  /// Catégorie courante
  ScreenType get screenType {
    if (isDesktop) return ScreenType.desktop;
    if (isTablet) return ScreenType.tablet;
    return ScreenType.mobile;
  }

  /// Padding horizontal de page standard (16 mobile / 32 tablette / 0 desktop
  /// — le contenu est centré par maxContentWidth plutôt que paddé)
  double get pageHPadding {
    if (isDesktop) return 0;
    if (isTablet) return 32;
    return 16;
  }

  /// Padding vertical de page standard
  double get pageVPadding {
    if (isDesktop) return 32;
    if (isTablet) return 24;
    return 16;
  }

  EdgeInsets get pagePadding => EdgeInsets.symmetric(
        horizontal: pageHPadding,
        vertical: pageVPadding,
      );

  /// Nombre de colonnes de grille recommandé
  int get gridColumns {
    if (isDesktop) return 3;
    if (isTablet) return 2;
    return 1;
  }

  /// Espacement de grille recommandé
  double get gridSpacing {
    if (isDesktop) return 24;
    if (isTablet) return 16;
    return 12;
  }
}

// ────────────────────────────────────────────────────────────
// 3. ENUM TYPE D'ÉCRAN
// ────────────────────────────────────────────────────────────
enum ScreenType { mobile, tablet, desktop }

// ────────────────────────────────────────────────────────────
// 4. CLASSE UTILITAIRE — valeurs responsive
// ────────────────────────────────────────────────────────────
class Responsive {
  Responsive._();

  /// Retourne la valeur adaptée au breakpoint courant.
  /// [tablet] et [desktop] sont optionnels : si absent, [mobile] est utilisé.
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= AppBreakpoints.desktop && desktop != null) return desktop;
    if (w >= AppBreakpoints.tablet && tablet != null) return tablet;
    return mobile;
  }

  /// Retourne le widget adapté au breakpoint courant.
  static Widget builder(
    BuildContext context, {
    required Widget mobile,
    Widget? tablet,
    Widget? desktop,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= AppBreakpoints.desktop && desktop != null) return desktop;
    if (w >= AppBreakpoints.tablet && tablet != null) return tablet;
    return mobile;
  }
}

// ────────────────────────────────────────────────────────────
// 5. WIDGET ResponsiveLayout — sélecteur déclaratif
// ────────────────────────────────────────────────────────────
/// Widget qui reconstruit son enfant à chaque changement de breakpoint.
/// Si [tablet] ou [desktop] sont omis, [mobile] est utilisé à la place.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    return Responsive.builder(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
}

// ────────────────────────────────────────────────────────────
// 6. WIDGET ResponsiveCenter — centre le contenu avec maxWidth
// ────────────────────────────────────────────────────────────
/// Centre le contenu horizontalement et limite sa largeur à [maxWidth].
/// Sur mobile, désactive le centrage (pleine largeur).
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.maxContentWidth,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);
    if (isMobile) return content;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: content,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 7. WIDGET ResponsiveFormCard — carte de formulaire centrée
// ────────────────────────────────────────────────────────────
/// Enveloppe un formulaire dans une carte blanche centrée sur
/// tablette/desktop ; sur mobile, affiche directement sans cadre.
class ResponsiveFormCard extends StatelessWidget {
  const ResponsiveFormCard({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.maxFormWidth,
    this.padding = const EdgeInsets.all(32),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Colors.black.withOpacity(0.06),
              width: 1,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 8. ESPACEMENTS RESPONSIVES
// ────────────────────────────────────────────────────────────
class AppResponsiveSpacing {
  AppResponsiveSpacing._();

  /// Padding horizontal de page
  static EdgeInsets pagePadding(BuildContext context) =>
      context.pagePadding;

  /// Padding intérieur d'une section / carte
  static EdgeInsets cardPadding(BuildContext context) {
    if (context.isDesktop) return const EdgeInsets.all(28);
    if (context.isTablet) return const EdgeInsets.all(22);
    return const EdgeInsets.all(16);
  }

  /// Espacement vertical entre deux sections
  static double sectionGap(BuildContext context) {
    if (context.isDesktop) return 32;
    if (context.isTablet) return 24;
    return 16;
  }

  /// Espacement vertical entre deux éléments d'un formulaire
  static double fieldGap(BuildContext context) {
    if (context.isDesktop) return 24;
    if (context.isTablet) return 20;
    return 16;
  }
}

// ────────────────────────────────────────────────────────────
// 9. TAILLES DE TEXTE RESPONSIVES
// ────────────────────────────────────────────────────────────
class AppResponsiveText {
  AppResponsiveText._();

  static const double _tabletFactor = 1.10;
  static const double _desktopFactor = 1.20;

  /// Applique un facteur d'échelle à une taille de police de base.
  static double scale(BuildContext context, double baseFontSize) {
    if (context.isDesktop) return baseFontSize * _desktopFactor;
    if (context.isTablet) return baseFontSize * _tabletFactor;
    return baseFontSize;
  }

  /// TextStyle brand scalé
  static TextStyle brand(BuildContext context) => TextStyle(
        fontSize: scale(context, 34),
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      );

  static TextStyle h1(BuildContext context) => TextStyle(
        fontSize: scale(context, 28),
        fontWeight: FontWeight.bold,
        height: 1.2,
      );

  static TextStyle h2(BuildContext context) => TextStyle(
        fontSize: scale(context, 20),
        fontWeight: FontWeight.bold,
        height: 1.25,
      );

  static TextStyle h3(BuildContext context) => TextStyle(
        fontSize: scale(context, 16),
        fontWeight: FontWeight.w700,
      );

  static TextStyle body(BuildContext context) => TextStyle(
        fontSize: scale(context, 14),
        height: 1.4,
      );

  static TextStyle caption(BuildContext context) => TextStyle(
        fontSize: scale(context, 12),
      );
}

// ────────────────────────────────────────────────────────────
// 10. WIDGET ConstrainedPageBody
// ────────────────────────────────────────────────────────────
/// Wrapper pour le body d'un Scaffold : centre + contraint + padding.
/// Remplace `Padding(padding: EdgeInsets.all(16), child: ...)` dans les
/// écrans pour obtenir automatiquement le bon comportement responsive.
class ConstrainedPageBody extends StatelessWidget {
  const ConstrainedPageBody({
    super.key,
    required this.child,
    this.scrollable = false,
    this.maxWidth = AppBreakpoints.maxContentWidth,
  });

  final Widget child;
  final bool scrollable;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: context.pagePadding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
    if (scrollable) return SingleChildScrollView(child: padded);
    return padded;
  }
}

// ────────────────────────────────────────────────────────────
// 11. WIDGET ResponsiveGrid
// ────────────────────────────────────────────────────────────
/// Grille responsive : 1 col mobile, 2 tablette, 3 desktop.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
    this.spacing,
  });

  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final cols = Responsive.value(
      context,
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
    );
    final gap = spacing ?? context.gridSpacing;
    return LayoutBuilder(
      builder: (_, constraints) {
        final itemWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: children
              .map((c) => SizedBox(width: itemWidth, child: c))
              .toList(),
        );
      },
    );
  }
}
