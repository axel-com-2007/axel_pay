// ============================================================
// ÉCRAN CLIENT PRÉPAYÉ — SUIVI & ACHAT DE CRÉDIT
// ============================================================
// Cahier des charges 5. Écran 4 :
//  - Jauge visuelle du solde (kWh & FCFA simultanés)
//  - Estimation d'autonomie (jours restants)
//  - Formulaire d'achat rapide avec conversion FCFA -> kWh en direct
//    selon la grille tarifaire (RG-07 : prix figé à l'achat)
//  - Dernier jeton à 20 chiffres, consultable hors-ligne
//
// `widget.compteur` arrive déjà enrichi (solde, dernier jeton) depuis
// `DashboardScreen`, qui l'a construit via `EneoRepository.getCompteurs()`.
// Cet écran charge en plus l'historique des recharges
// (`GET /compteurs/<id>/tokens/`).
// ============================================================

import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/connectivity_gate.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../shared/widgets/meter_gauge.dart';
import '../payment/payment_screen.dart';

/// Grille tarifaire simplifiée pour la conversion en direct côté frontend
/// PENDANT LA SAISIE. La valeur réellement appliquée à la transaction est
/// de toute façon figée côté serveur au moment du paiement (RG-07) — ce
/// n'est qu'un indicatif d'aide à la saisie.
const double _prixKwhIndicatif = 300;

class PrepaidScreen extends StatefulWidget {
  final CompteurModel compteur;
  const PrepaidScreen({super.key, required this.compteur});

  @override
  State<PrepaidScreen> createState() => _PrepaidScreenState();
}

class _PrepaidScreenState extends State<PrepaidScreen> {
  final _repo = EneoRepository();
  final montantController = TextEditingController(text: '5000');

  late Future<List<TransactionPrepaieeModel>> _transactions;

  /// `true` si l'historique affiché vient du cache local plutôt que du
  /// réseau (§7.6) — pilote le bandeau "Mode hors connexion" de cet
  /// écran, au même titre que sur l'accueil.
  bool horsLigne = false;
  DateTime? derniereSynchro;

  double get montant => double.tryParse(montantController.text) ?? 0;
  double get kwhEstime => montant / _prixKwhIndicatif;

  @override
  void initState() {
    super.initState();
    final idCompteur = int.tryParse(widget.compteur.id);
    _transactions = idCompteur != null
        ? _chargerTransactions(idCompteur)
        : Future.value(<TransactionPrepaieeModel>[]);
  }

  Future<List<TransactionPrepaieeModel>> _chargerTransactions(int idCompteur) async {
    final result = await _repo.getTransactions(idCompteur);
    if (mounted) {
      setState(() {
        horsLigne = result.isFromCache;
        derniereSynchro = result.syncedAt;
      });
    }
    return result.data;
  }

  @override
  void dispose() {
    montantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.compteur;
    final soldeMax = 100.0; // borne haute indicative pour la jauge visuelle

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mon crédit prépayé')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(c.numero, style: AppTextStyles.bodyMuted),
          if (horsLigne) ...[
            const SizedBox(height: 12),
            OfflineBanner(derniereSynchro: derniereSynchro, margin: EdgeInsets.zero),
          ],
          const SizedBox(height: 16),

          AppCard(
            child: Column(
              children: [
                MeterGaugeWidget(
                  value: c.soldeKwh ?? 0,
                  maxValue: soldeMax,
                  unitLabel: 'kWh restants',
                  subLabel: c.soldeFcfaEquivalent != null
                      ? '≈ ${formatFcfa(c.soldeFcfaEquivalent!)}'
                      : '≈ non disponible',
                ),
                const Divider(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _InfoStat(
                      icon: Icons.hourglass_bottom,
                      label: 'Autonomie estimée',
                      value: c.joursAutonomieEstimes != null
                          ? '${c.joursAutonomieEstimes} jours'
                          : 'Non disponible',
                    ),
                    _InfoStat(
                      icon: Icons.access_time,
                      label: 'Mise à jour',
                      value: c.freshnessLabel(DateTime.now()).replaceFirst(
                          'Dernière mise à jour : ', ''),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'Acheter du crédit'),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Montant (FCFA)', style: AppTextStyles.label),
                const SizedBox(height: 8),
                TextField(
                  controller: montantController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'ex: 5000'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [2000, 5000, 10000, 20000].map((m) {
                    return ActionChip(
                      label: Text(formatFcfa(m)),
                      onPressed: () => setState(() => montantController.text = '$m'),
                      backgroundColor: AppColors.surface,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Équivalent estimé', style: AppTextStyles.bodyMuted),
                      Text(
                        '${kwhEstime.toStringAsFixed(1)} kWh',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Garde-fou connectivité (§7.6) : le bouton se désactive
                // proactivement hors-ligne, plutôt que de laisser
                // l'utilisateur ouvrir tout le tunnel de paiement pour
                // échouer à la fin. `ConnectivityGate` ne garantit pas un
                // accès Internet réel — le filet de sécurité définitif
                // reste `ApiNetworkException` dans `PaymentScreen`.
                StreamBuilder<bool>(
                  stream: ConnectivityGate.onChange,
                  initialData: true,
                  builder: (context, snapshot) {
                    final connecte = snapshot.data ?? true;
                    return Column(
                      children: [
                        if (!connecte) ...[
                          const OfflineActionBlockedBanner(
                            message: 'Vous êtes hors connexion. La recharge de crédit '
                                'nécessite une connexion active.',
                          ),
                          const SizedBox(height: 10),
                        ],
                        PrimaryButton(
                          label: 'Recharger mon crédit',
                          onPressed: montant > 0 && connecte
                              ? () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PaymentScreen(
                                        compteur: c,
                                        montantSuggere: montant,
                                      ),
                                    ),
                                  )
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'Dernier jeton généré'),
          const SizedBox(height: 12),
          _TokenCard(compteur: c),
          const SizedBox(height: 24),

          const SectionHeader(title: 'Historique des recharges'),
          const SizedBox(height: 12),
          FutureBuilder<List<TransactionPrepaieeModel>>(
            future: _transactions,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Column(
                  children: [
                    ShimmerCard(titleWidth: 100),
                    SizedBox(height: 10),
                    ShimmerCard(titleWidth: 100),
                  ],
                );
              }
              if (snapshot.hasError) {
                final message = snapshot.error is ApiException
                    ? (snapshot.error as ApiException).message
                    : 'Impossible de charger l’historique.';
                return AppCard(child: Text(message, style: AppTextStyles.bodyMuted));
              }
              final transactions = snapshot.data ?? const [];
              if (transactions.isEmpty) {
                return const AppCard(
                  child: EmptyStateLottie(
                    asset: LottieAssets.search,
                    title: 'Aucune recharge pour le moment.',
                    size: 100,
                  ),
                );
              }
              return Column(
                children: transactions
                    .asMap()
                    .entries
                    .map((entry) => FadeSlideIn(index: entry.key, child: _TransactionTile(transaction: entry.value)))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoStat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

class _TokenCard extends StatelessWidget {
  final CompteurModel compteur;
  const _TokenCard({required this.compteur});

  @override
  Widget build(BuildContext context) {
    final token = compteur.dernierToken;
    if (token == null) {
      return const AppCard(
        child: EmptyStateLottie(
          asset: LottieAssets.search,
          title: 'Aucun jeton généré pour le moment.',
          size: 100,
        ),
      );
    }
    return AppCard(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.confirmation_number_outlined, color: AppColors.primaryDark),
              SizedBox(width: 8),
              Text('Jeton STS', style: AppTextStyles.label),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            token,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Consultable hors-ligne — saisissez ce code directement sur votre compteur. '
            'Génération de test tant que le raccordement à l’API/IoT Eneo n’est pas '
            'finalisé : le code n’active donc pas encore un vrai compteur.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Jeton copié')));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copier'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionPrepaieeModel transaction;
  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final reussi = transaction.statut == StatutTransaction.reussi;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (reussi ? AppColors.success : AppColors.warning).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.bolt, color: reussi ? AppColors.success : AppColors.warning, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatFcfa(transaction.montantFcfa), style: AppTextStyles.label),
                  Text(
                    '${transaction.valeurKwh.toStringAsFixed(1)} kWh · ${_formatDateCourt(transaction.date)}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            Icon(
              reussi ? Icons.check_circle : Icons.hourglass_bottom,
              color: reussi ? AppColors.success : AppColors.warning,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateCourt(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}


