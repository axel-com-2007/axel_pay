// ============================================================
// ÉCRAN DES FACTURES AGRÉGÉES PAR CONTRAT
// ============================================================
// REFONTE : un contrat peut avoir plusieurs compteurs, mais un seul est
// ACTIF à la fois (RG métier) — afficher/filtrer par compteur au sein
// d'un même contrat n'apporte donc plus rien : cet écran affiche
// directement, sans étape intermédiaire, toutes les factures du contrat
// (le plus récent d'abord, voir `ContratFacturesListView.get_queryset`),
// avec un seul filtre — le statut — plus le bouton "historique ancien"
// (RG-14). L'écran ne dépend plus d'une liste de compteurs fournie par
// l'appelant : il navigue directement depuis la liste des contrats
// (`ContractsScreen`), sans passer par un écran intermédiaire listant les
// compteurs.
//
// Branché sur GET /contrats/<id>/factures/?statut=&historique_complet=
// via `EneoRepository.getContratFactures`, et GET /contrats/<id>/compteurs/
// (en tâche de fond, pour résoudre `id_compteur -> numéro` et retrouver le
// compteur actif nécessaire à `PaymentScreen`).
//
// Si le contrat n'a AUCUN compteur postpayé, la liste renvoyée par le
// serveur est simplement vide (les compteurs prépayés n'ont pas de ligne
// dans `factures_postpayees`) — pas une erreur, on affiche l'état vide.
// ============================================================

import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_badge.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../design_system/buttons/app_button.dart';
import '../payment/payment_screen.dart';
import '../postpaid/facture_detail_screen.dart';
import 'contracts_screen.dart';

class ContratFacturesScreen extends StatefulWidget {
  final ContratModel contrat;

  const ContratFacturesScreen({
    super.key,
    required this.contrat,
  });

  @override
  State<ContratFacturesScreen> createState() => _ContratFacturesScreenState();
}

class _ContratFacturesScreenState extends State<ContratFacturesScreen> {
  final _repo = EneoRepository();

  // `null` = "Tous".
  String? _statutFiltre;
  bool _historiqueComplet = false;

  late Future<List<FactureModel>> _factures;

  /// Nom du client, requis par `FactureDetailPage` (affiché sur la
  /// facture imprimable) — chargé en tâche de fond une seule fois, comme
  /// dans `PostpaidScreen`.
  String _nomClient = '';

  /// Compteurs du contrat, chargés en tâche de fond (jamais affichés —
  /// un contrat n'a qu'un compteur actif à la fois) : uniquement utile
  /// pour résoudre le libellé du compteur d'une facture et retrouver le
  /// `CompteurModel` nécessaire à `PaymentScreen` au moment de payer.
  List<CompteurModel> _compteurs = [];

  int get _idContrat => int.tryParse(widget.contrat.id) ?? 0;

  @override
  void initState() {
    super.initState();
    _factures = _charger();
    _chargerProfil();
  }

  Future<void> _chargerProfil() async {
    try {
      final result = await _repo.getProfile();
      if (mounted) setState(() => _nomClient = result.data.nomComplet);
    } on ApiException {
      // Non bloquant : `FactureDetailPage` retombe sur 'Client' si le nom
      // n'a pas pu être chargé (même parti pris que `PostpaidScreen`).
    }
  }

  Future<List<FactureModel>> _charger() async {
    // `getContratFactures` n'est PAS mis en cache (agrégation par contrat,
    // hors périmètre §7.6 — voir le commentaire en tête de fichier), donc
    // uniquement `getContratCompteurs` (résolution du libellé, en tâche de
    // fond) renvoie un `CachedResult`.
    final facturesFuture = _repo.getContratFactures(
      _idContrat,
      statut: _statutFiltre,
      historiqueComplet: _historiqueComplet,
    );
    final compteursFuture =
        _repo.getContratCompteurs(_idContrat, numeroContrat: widget.contrat.numeroContrat);
    final raw = await facturesFuture;
    final compteursResult = await compteursFuture;
    _compteurs = compteursResult.data;
    final numeroParId = {
      for (final c in _compteurs) int.tryParse(c.id) ?? -1: c.numero,
    };
    return raw
        .map((f) => f.copyWith(compteurNumero: numeroParId[f.idCompteur]))
        .toList();
  }

  void _relancer() => setState(() => _factures = _charger());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Factures — ${widget.contrat.numeroContrat}'),
        actions: [
          IconButton(
            tooltip: 'Gérer ce contrat',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ContratDetailScreen(contrat: widget.contrat),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFiltres(),
            Expanded(
              child: FutureBuilder<List<FactureModel>>(
                future: _factures,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: const [
                        ShimmerCard(titleWidth: 100),
                        SizedBox(height: 12),
                        ShimmerCard(titleWidth: 100),
                        SizedBox(height: 12),
                        ShimmerCard(titleWidth: 100),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Impossible de charger les factures de ce contrat.';
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(message,
                                textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _relancer,
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final factures = snapshot.data ?? const [];
                  if (factures.isEmpty) return const _AucuneFactureContrat();

                  return RefreshIndicator(
                    onRefresh: () async => _relancer(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        SectionHeader(
                          title: _historiqueComplet
                              ? 'Historique complet'
                              : 'Historique (12 derniers mois)',
                          actionLabel: _historiqueComplet ? null : 'Historique ancien',
                          onAction: _historiqueComplet
                              ? null
                              : () => setState(() {
                                    _historiqueComplet = true;
                                    _factures = _charger();
                                  }),
                        ),
                        const SizedBox(height: 12),
                        ...factures.asMap().entries.map((entry) => FadeSlideIn(
                              index: entry.key,
                              child: _FactureContratTile(
                                facture: entry.value,
                                onTap: () => _ouvrirDetail(entry.value),
                                onSignaler: () => _signalerAnomalie(entry.value),
                                onTelecharger: () => _ouvrirDetail(entry.value),
                                onPayer: entry.value.statut == StatutFacture.impayee
                                    ? () => _payer(entry.value)
                                    : null,
                              ),
                            )),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltres() {
    // Filtre statut uniquement : un contrat n'a qu'un seul compteur actif
    // à la fois (RG métier), donc plus de filtre par compteur ici.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FiltreChip(
                  label: 'Tous',
                  selected: _statutFiltre == null,
                  onTap: () => setState(() {
                    _statutFiltre = null;
                    _factures = _charger();
                  }),
                ),
                const SizedBox(width: 8),
                _FiltreChip(
                  label: 'Payée',
                  selected: _statutFiltre == 'Payée',
                  onTap: () => setState(() {
                    _statutFiltre = 'Payée';
                    _factures = _charger();
                  }),
                ),
                const SizedBox(width: 8),
                _FiltreChip(
                  // Le libellé affiché ('En cours', avec un espace) reste du
                  // texte français lisible ; seule la VALEUR envoyée à
                  // l'API doit correspondre exactement au littéral de
                  // l'ENUM PostgreSQL enum_statut_facture ('En_cours', avec
                  // un underscore) — cf. correctif du 21/07/2026 :
                  // l'ancien code envoyait 'En cours' (espace), ce qui
                  // provoquait un DataError PostgreSQL non catché (500)
                  // côté ContratFacturesListView.
                  label: 'En cours',
                  selected: _statutFiltre == 'En_cours',
                  onTap: () => setState(() {
                    _statutFiltre = 'En_cours';
                    _factures = _charger();
                  }),
                ),
                const SizedBox(width: 8),
                _FiltreChip(
                  label: 'Impayée',
                  selected: _statutFiltre == 'Impayée',
                  onTap: () => setState(() {
                    _statutFiltre = 'Impayée';
                    _factures = _charger();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _payer(FactureModel facture) {
    final compteur = _compteurs.firstWhere(
      (c) => c.id == facture.idCompteur.toString(),
      orElse: () => _compteurs.first,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          compteur: compteur,
          montantSuggere: facture.montantFcfa,
          factureId: facture.id,
        ),
      ),
    );
  }

  void _signalerAnomalie(FactureModel facture) {
    final controller = TextEditingController();
    AppBottomSheet.show(
      context: context,
      title: 'Signaler une anomalie — ${facture.moisFacturation}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: controller,
            maxLines: 3,
            hintText: 'Décrivez le problème rencontré (montant incorrect, index erroné...)',
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Envoyer au support',
            onPressed: () async {
              final description = controller.text.trim();
              Navigator.pop(context);
              try {
                await _repo.signalerAnomalie(facture.id, description);
                if (!mounted) return;
                _showSnack('Signalement transmis au support technique');
              } on ApiException catch (e) {
                if (!mounted) return;
                _showSnack(e.message);
              }
            },
          ),
        ],
      ),
    );
  }

  void _ouvrirDetail(FactureModel facture) {
    if (_compteurs.isEmpty) {
      _showSnack('Détail indisponible : aucun compteur résolu pour ce contrat.');
      return;
    }
    final compteur = _compteurs.firstWhere(
      (c) => c.id == facture.idCompteur.toString(),
      orElse: () => _compteurs.first,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FactureDetailPage(
          facture: facture,
          compteur: compteur,
          nomClient: _nomClient.isNotEmpty ? _nomClient : 'Client',
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FiltreChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool outline;
  final VoidCallback onTap;

  const _FiltreChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.outline = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (outline ? AppColors.secondary : AppColors.primary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected
                ? (outline ? AppColors.secondary : AppColors.primary)
                : AppColors.divider,
          ),
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

/// Comme `_FactureTile` de `postpaid_screen.dart` — un contrat n'ayant
/// qu'un seul compteur actif à la fois, plus besoin d'indiquer de quel
/// compteur vient chaque facture.
class _FactureContratTile extends StatelessWidget {
  final FactureModel facture;
  final VoidCallback onTap;
  final VoidCallback onSignaler;
  final VoidCallback onTelecharger;
  final VoidCallback? onPayer;

  const _FactureContratTile({
    required this.facture,
    required this.onTap,
    required this.onSignaler,
    required this.onTelecharger,
    this.onPayer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(facture.moisFacturation, style: AppTextStyles.h3),
                  ),
                  Row(children: [
                    StatusBadge(label: facture.statutLabel),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                  ]),
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
      ),
    );
  }
}

class _AucuneFactureContrat extends StatelessWidget {
  const _AucuneFactureContrat();

  @override
  Widget build(BuildContext context) {
    return const EmptyStateLottie(
      asset: LottieAssets.search,
      title: 'Aucune facture disponible',
      subtitle: 'Aucune facture ne correspond à ces filtres, ou ce contrat ne '
          'compte que des compteurs prépayés (pas de facturation mensuelle).',
    );
  }
}