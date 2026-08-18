// ============================================================
// COQUILLE PRINCIPALE — NAVIGATION RESPONSIVE
// ============================================================
// Trois modes de navigation selon la taille d'écran :
//   • mobile  (< 600 px)  : NavigationBar en bas (comportement d'origine)
//   • tablet  (600–1023)  : NavigationRail à gauche (compact, sans labels)
//   • desktop (≥ 1024 px) : NavigationRail étendu (avec labels permanents)
//
// Écrans accessibles :
//   1. Accueil     → DashboardScreen
//   2. Contrats    → ContractsScreen
//   3. Paramètres  → SettingsScreen
// ============================================================

import 'package:flutter/material.dart';
import '../../design_system/responsive/responsive_utils.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../contracts/contracts_screen.dart';
import '../settings/settings_screen.dart';
import 'dashboard_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    ContractsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    // ── Destinations partagées ───────────────────────────────
    final List<_NavItem> navItems = [
      _NavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: s.navAccueil,
      ),
      _NavItem(
        icon: Icons.description_outlined,
        selectedIcon: Icons.description,
        label: s.navContrats,
      ),
      _NavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: s.navParametres,
      ),
    ];

    return ResponsiveLayout(
      mobile: _MobileShell(
        screens: _screens,
        currentIndex: currentIndex,
        navItems: navItems,
        onDestinationSelected: (i) => setState(() => currentIndex = i),
      ),
      tablet: _RailShell(
        screens: _screens,
        currentIndex: currentIndex,
        navItems: navItems,
        onDestinationSelected: (i) => setState(() => currentIndex = i),
        extended: false,
      ),
      desktop: _RailShell(
        screens: _screens,
        currentIndex: currentIndex,
        navItems: navItems,
        onDestinationSelected: (i) => setState(() => currentIndex = i),
        extended: true,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Modèle d'item de navigation
// ────────────────────────────────────────────────────────────
class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

// ────────────────────────────────────────────────────────────
// MODE MOBILE — NavigationBar en bas
// ────────────────────────────────────────────────────────────
class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.screens,
    required this.currentIndex,
    required this.navItems,
    required this.onDestinationSelected,
  });

  final List<Widget> screens;
  final int currentIndex;
  final List<_NavItem> navItems;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: AxisSwitcher(index: currentIndex, children: screens)),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.sheet),
            topRight: Radius.circular(AppRadius.sheet),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.sheet),
            topRight: Radius.circular(AppRadius.sheet),
          ),
          child: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: onDestinationSelected,
            backgroundColor: Colors.white,
            elevation: 0,
            indicatorColor: AppColors.primary.withOpacity(0.15),
            destinations: navItems
                .map((item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon, color: AppColors.primary),
                      label: item.label,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// MODE TABLETTE / DESKTOP — NavigationRail à gauche
// ────────────────────────────────────────────────────────────
class _RailShell extends StatelessWidget {
  const _RailShell({
    required this.screens,
    required this.currentIndex,
    required this.navItems,
    required this.onDestinationSelected,
    required this.extended,
  });

  final List<Widget> screens;
  final int currentIndex;
  final List<_NavItem> navItems;
  final ValueChanged<int> onDestinationSelected;

  /// `true` = labels permanents (desktop), `false` = icônes seules (tablette)
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            // ── Rail de navigation ───────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(4, 0),
                  ),
                ],
              ),
              child: NavigationRail(
                extended: extended,
                selectedIndex: currentIndex,
                onDestinationSelected: onDestinationSelected,
                backgroundColor: Colors.white,
                indicatorColor: AppColors.primary.withOpacity(0.14),
                selectedIconTheme:
                    const IconThemeData(color: AppColors.primary),
                unselectedIconTheme:
                    const IconThemeData(color: AppColors.textMuted),
                selectedLabelTextStyle: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                unselectedLabelTextStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
                // Logo AxelPay en tête du rail
                leading: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: extended ? 12 : 0,
                  ),
                  child: extended
                      ? _AxelPayLogo(showLabel: true)
                      : _AxelPayLogo(showLabel: false),
                ),
                destinations: navItems
                    .map((item) => NavigationRailDestination(
                          icon: Icon(item.icon),
                          selectedIcon:
                              Icon(item.selectedIcon, color: AppColors.primary),
                          label: Text(item.label),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                        ))
                    .toList(),
              ),
            ),

            // ── Séparateur fin ───────────────────────────────
            const VerticalDivider(width: 1, thickness: 1),

            // ── Contenu principal ────────────────────────────
            Expanded(
              child: AxisSwitcher(index: currentIndex, children: screens),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Logo AxelPay pour le rail
// ────────────────────────────────────────────────────────────
class _AxelPayLogo extends StatelessWidget {
  const _AxelPayLogo({required this.showLabel});
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    const iconWidget = CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.primaryBlue,
      child: Icon(Icons.bolt, color: Colors.white, size: 20),
    );
    if (!showLabel) return iconWidget;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconWidget,
        const SizedBox(width: 10),
        const Text(
          'AxelPay',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryBlue,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
