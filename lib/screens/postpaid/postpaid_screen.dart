// ============================================================
// ÉCRAN CLIENT POSTPAYÉ — GESTION DES FACTURES
// ============================================================
// Cahier des charges 5. Écran 3 :
//  - Liste des 12 dernières factures, statut à 3 états
//  - Graphique d'évolution de la consommation (kWh & FCFA)
//  - Bouton "Consulter l'historique ancien" (>12 mois)
//  - Bouton "Signaler une anomalie" par facture
//  - Téléchargement du reçu PDF, initiation du paiement
//
// Branché sur GET /compteurs/<id>/factures/,
// GET /compteurs/<id>/consommation/ et POST /factures/<id>/signaler-anomalie/.
// ============================================================

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/connectivity_gate.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_badge.dart';
import '../payment/payment_screen.dart';

class PostpaidScreen extends StatefulWidget {
  final CompteurModel compteur;
  const PostpaidScreen({super.key, required this.compteur});

  @override
  State<PostpaidScreen> createState() => _PostpaidScreenState();
}

class _PostpaidScreenState extends State<PostpaidScreen> {
  final _repo = EneoRepository();
  bool afficherEnFcfa = false;
  bool historiqueComplet = false;

  int? get _idCompteur => int.tryParse(widget.compteur.id);

  late Future<List<FactureModel>> _factures;
  late Future<List<ConsommationPoint>> _consommation;

  /// `true` si les factures affichées viennent du cache local (§7.6).
  bool horsLigne = false;
  DateTime? derniereSynchro;

  @override
  void initState() {
    super.initState();
    _factures = _chargerFactures();
    _consommation = _idCompteur != null
        ? _repo.getConsommation(_idCompteur!)
        : Future.value(<ConsommationPoint>[]);
  }

  Future<List<FactureModel>> _chargerFactures() async {
    if (_idCompteur == null) return const <FactureModel>[];
    final result = await _repo.getFactures(_idCompteur!, historiqueComplet: historiqueComplet);
    if (mounted) {
      setState(() {
        horsLigne = result.isFromCache;
        derniereSynchro = result.syncedAt;
      });
    }
    return result.data;
  }

  /// Garde-fou connectivité (§7.6) avant d'ouvrir le tunnel de paiement :
  /// pas de graying-out proactif ici (plusieurs points d'entrée "Payer"
  /// dispersés dans la liste), mais une vérification systématique avant
  /// navigation — le filet de sécurité définitif reste de toute façon
  /// `ApiNetworkException` dans `PaymentScreen`.
  Future<bool> _verifierConnexionAvantPaiement() async {
    final connecte = await ConnectivityGate.hasConnection;
    if (!connecte && mounted) {
      _showSnack(
        context,
        'Vous êtes hors connexion. Le paiement d’une facture nécessite une connexion active.',
      );
    }
    return connecte;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mes factures')),
      body: FutureBuilder<List<FactureModel>>(
        future: _factures,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: const [
                ShimmerBox(height: 180, borderRadius: BorderRadius.all(Radius.circular(20))),
                SizedBox(height: 20),
                ShimmerCard(titleWidth: 110),
                SizedBox(height: 12),
                ShimmerCard(titleWidth: 110),
              ],
            );
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Impossible de charger vos factures.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() => _factures = _chargerFactures()),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          final factures = snapshot.data ?? const [];
          final impayees = factures.where((f) => f.statut == StatutFacture.impayee).toList();

          if (factures.isEmpty) return const _AucuneFacture();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Text(widget.compteur.numero, style: AppTextStyles.bodyMuted),
              if (horsLigne) ...[
                const SizedBox(height: 10),
                OfflineBanner(derniereSynchro: derniereSynchro, margin: EdgeInsets.zero),
              ],
              const SizedBox(height: 12),
              if (impayees.isNotEmpty) _buildBanniereImpayee(impayees.first),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Évolution de la consommation'),
              const SizedBox(height: 12),
              _buildGraphique(),
              const SizedBox(height: 24),
              SectionHeader(
                title: historiqueComplet
                    ? 'Historique complet'
                    : 'Historique (12 derniers mois)',
                actionLabel: historiqueComplet ? null : 'Historique ancien',
                onAction: historiqueComplet
                    ? null
                    : () => setState(() {
                          historiqueComplet = true;
                          _factures = _chargerFactures();
                        }),
              ),
              const SizedBox(height: 12),
              ...factures.asMap().entries.map((entry) => FadeSlideIn(
                    index: entry.key,
                    child: _FactureTile(
                      facture: entry.value,
                      onSignaler: () => _signalerAnomalie(context, entry.value),
                      onTelecharger: () => _telechargerRecu(context, entry.value),
                      onPayer: entry.value.statut == StatutFacture.impayee
                          ? () => _payer(entry.value)
                          : null,
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _payer(FactureModel facture) async {
    if (!await _verifierConnexionAvantPaiement()) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          compteur: widget.compteur,
          montantSuggere: facture.montantFcfa,
          factureId: facture.id,
        ),
      ),
    );
  }

  Widget _buildBanniereImpayee(FactureModel facture) {
    return AppCard(
      color: AppColors.danger.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatFcfa(facture.montantFcfa)} impayés',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Échéance : ${_formatDate(facture.dateLimite)}',
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _payer(facture),
            child: const Text('Payer'),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphique() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _MetricToggleButton(
                label: 'kWh',
                selected: !afficherEnFcfa,
                onTap: () => setState(() => afficherEnFcfa = false),
              ),
              const SizedBox(width: 8),
              _MetricToggleButton(
                label: 'FCFA',
                selected: afficherEnFcfa,
                onTap: () => setState(() => afficherEnFcfa = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: FutureBuilder<List<ConsommationPoint>>(
              future: _consommation,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LottieLoader(size: 64);
                }
                final points = snapshot.data ?? const [];
                if (points.isEmpty) {
                  return const Center(
                    child: Text('Pas encore assez de données', style: AppTextStyles.bodyMuted),
                  );
                }
                return BarChart(
                  BarChartData(
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= points.length) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(points[i].moisLabel, style: AppTextStyles.caption),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(points.length, (i) {
                      final point = points[i];
                      final value = afficherEnFcfa ? point.fcfa / 100 : point.kwh;
                      return BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: value,
                          color: AppColors.primary,
                          width: 18,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ]);
                    }),
                  ),
                );
              },
            ),
          ),
          if (afficherEnFcfa)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Échelle réduite (÷100) pour la lisibilité du graphique',
                  style: AppTextStyles.caption),
            ),
        ],
      ),
    );
  }

  void _signalerAnomalie(BuildContext context, FactureModel facture) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) {
        final controller = TextEditingController();
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Signaler une anomalie — ${facture.moisFacturation}',
                  style: AppTextStyles.h3),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Décrivez le problème rencontré (montant incorrect, index erroné...)',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final description = controller.text.trim();
                    Navigator.pop(ctx);
                    try {
                      await _repo.signalerAnomalie(facture.id, description);
                      if (!mounted) return;
                      _showSnack(context, 'Signalement transmis au support technique');
                    } on ApiException catch (e) {
                      if (!mounted) return;
                      _showSnack(context, e.message);
                    }
                  },
                  child: const Text('Envoyer au support'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _telechargerRecu(BuildContext context, FactureModel facture) async {
    // ⚠️ `FactureReçuPDFView` ne génère pas encore de vrai PDF côté serveur
    // (cf. commentaire "TODO INTEGRATION : générer le PDF... et le
    // retourner en FileResponse" dans views.py) : il renvoie pour l'instant
    // les données brutes du reçu en JSON. On informe honnêtement l'usager
    // plutôt que de simuler un téléchargement qui n'existe pas.
    _showSnack(context, 'Préparation du reçu…');
    try {
      await _repo.getFactureRecu(facture.id);
      if (!mounted) return;
      _showSnack(
        context,
        'Le reçu a été retrouvé côté serveur, mais la génération du PDF '
        'télécharger n’est pas encore disponible dans cette version.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(context, e.message);
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FactureTile extends StatelessWidget {
  final FactureModel facture;
  final VoidCallback onSignaler;
  final VoidCallback onTelecharger;
  final VoidCallback? onPayer;

  const _FactureTile({
    required this.facture,
    required this.onSignaler,
    required this.onTelecharger,
    this.onPayer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(facture.moisFacturation, style: AppTextStyles.h3),
                StatusBadge(label: facture.statutLabel),
              ],
            ),
            const SizedBox(height: 8),
            Text(formatFcfa(facture.montantFcfa), style: AppTextStyles.h3),
            const SizedBox(height: 2),
            Text('Index : ${facture.indexConsommation.toStringAsFixed(0)} kWh',
                style: AppTextStyles.caption),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onTelecharger,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Reçu PDF'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onSignaler,
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Anomalie'),
                  ),
                ),
              ],
            ),
            if (onPayer != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onPayer,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Payer cette facture'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MetricToggleButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? AppColors.primary : AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AucuneFacture extends StatelessWidget {
  const _AucuneFacture();

  @override
  Widget build(BuildContext context) {
    return const EmptyStateLottie(
      asset: LottieAssets.search,
      title: 'Aucune facture disponible',
      subtitle: 'Ce compteur vient d’être enregistré. Vos futures factures apparaîtront ici.',
    );
  }
}

String _formatDate(DateTime date) {
  const mois = [
    'jan',
    'fév',
    'mar',
    'avr',
    'mai',
    'juin',
    'juil',
    'août',
    'sep',
    'oct',
    'nov',
    'déc',
  ];
  return '${date.day} ${mois[date.month - 1]} ${date.year}';
}
