// ============================================================
// SÉLECTION EXTERNE DE CONTRAT (PAGE CONTRATS -> ACCUEIL)
// ============================================================
// Quand l'utilisateur clique sur un contrat depuis la page "Contrats",
// ce contrat doit remplacer celui affiché sur l'accueil, et le sélecteur
// du haut doit alors montrer "le contrat actuel + les 2 contrats les
// plus proches en date" plutôt que les 3 contrats les plus récents.
//
// `DashboardScreen` (via `AxisSwitcher`/`AnimatedSwitcher` dans
// `MainShell`) est entièrement recréé à chaque retour sur l'onglet
// Accueil — il n'existe donc pas d'instance à notifier "en direct".
// Cette petite classe statique sert de boîte aux lettres, lue une seule
// fois par `DashboardScreen._charger()` puis vidée aussitôt consommée.
// ============================================================

import '../models/models.dart';

class ContratSelectionExterne {
  ContratSelectionExterne._();

  /// Contrat choisi sur un autre écran, en attente d'être appliqué au
  /// prochain chargement de l'accueil. `null` si aucune sélection en
  /// attente.
  static ContratModel? enAttente;
}
