// ============================================================
// GARDE-FOU CONNECTIVITÉ — opérations financières (cahier des charges §7.6)
// ============================================================
// "Lecture seule en mode hors-ligne : aucune opération financière
// (paiement, achat de crédit) n'est autorisée sans connexion active, afin
// de ne jamais dupliquer ou corrompre une transaction."
//
// Volontairement minimal : ce helper ne fait qu'exposer un booléen "y
// a-t-il une interface réseau active ?" pour DÉSACTIVER PROACTIVEMENT les
// boutons de paiement/recharge dans l'UI (meilleure expérience que de
// laisser l'utilisateur cliquer puis échouer). Ce n'est PAS le filet de
// sécurité définitif : la vraie garantie reste `ApiNetworkException` côté
// `ApiClient`/`EneoRepository` si la connectivité change entre l'instant
// où le bouton est activé et l'appel réel (ex: bascule Wi-Fi -> rien
// pendant la frappe du montant) — ce cas continue d'être géré par le
// catch existant sur `ApiException` dans les écrans de paiement.
//
// Ajoute au pubspec.yaml : connectivity_plus: ^6.0.0
// ============================================================

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityGate {
  ConnectivityGate._();

  /// `true` si au moins une interface réseau est active. Une interface
  /// active ne garantit pas un accès Internet réel (portail captif,
  /// Wi-Fi sans Internet...) mais c'est un signal suffisant pour éviter
  /// de proposer un paiement à un utilisateur manifestement hors-ligne
  /// (mode avion, aucune barre réseau) — le cas résiduel (interface
  /// active mais serveur injoignable) reste couvert par
  /// `ApiNetworkException` au moment de l'appel réel.
  static Future<bool> get hasConnection async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  /// Flux réactif, pratique pour désactiver/réactiver un bouton en direct
  /// (`StreamBuilder<bool>`) sans avoir à re-vérifier manuellement à
  /// chaque frame.
  static Stream<bool> get onChange => Connectivity()
      .onConnectivityChanged
      .map((results) => !results.contains(ConnectivityResult.none));
}
