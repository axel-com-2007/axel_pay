// ============================================================
// COQUILLE PRINCIPALE DE L'APPLICATION
// ============================================================
// Regroupe les 3 grandes zones accessibles en permanence après
// connexion, via une barre de navigation basse :
//   1. Accueil  -> DashboardScreen (hub multi-compteurs)
//   2. Contrats -> ContractsScreen (REFONTE v1.5 : nouvelle racine du
//      graphe de propriété — un contrat regroupe un ou plusieurs
//      compteurs ; c'est désormais depuis cet onglet que l'on rattache un
//      compteur et que l'on gère les délégations, par compteur ou par
//      contrat entier). L'ancien écran "Mes compteurs" (`MetersScreen`)
//      reste accessible en vue transverse depuis cet onglet.
//   3. Paramètres -> SettingsScreen (préférences & support)
// Les écrans Postpayé / Prépayé / Paiement sont ouverts en
// navigation empilée (push) depuis le Dashboard, car ce sont des
// parcours contextuels à un compteur précis, pas des onglets
// permanents.
// ============================================================

import 'package:flutter/material.dart';
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: AxisSwitcher(index: currentIndex, children: _screens)),
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
            onDestinationSelected: (i) => setState(() => currentIndex = i),
            backgroundColor: Colors.white,
            elevation: 0,
            indicatorColor: AppColors.primary.withOpacity(0.15),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: AppColors.primary),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description, color: AppColors.primary),
                label: 'Contrats',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: AppColors.primary),
                label: 'Paramètres',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
