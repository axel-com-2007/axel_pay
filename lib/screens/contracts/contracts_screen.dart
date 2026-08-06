// ============================================================
// ÉCRAN DES CONTRATS — NOUVELLE RACINE DU GRAPHE DE PROPRIÉTÉ
// ============================================================
// REFONTE v1.5 (backend) : Users (1—N) Contrats (1—N) Compteurs (1—N)
// Factures. Ce que faisait auparavant l'écran "Mes compteurs" (rattacher
// un compteur, déléguer l'accès) part maintenant d'un contrat précis :
// un compteur DOIT être rattaché à un contrat existant (FK NOT NULL côté
// SQL), et une délégation peut désormais porter soit sur un compteur,
// soit sur le contrat entier.
//
// Branché sur GET /contrats/, POST /contrats/, GET /contrats/<id>/compteurs/,
// GET /contrats/<id>/factures/, POST /compteurs/, POST /delegations/,
// POST /delegations/<id>/revoquer/.
// ============================================================

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../api/api_exception.dart';
import '../../data/contrat_selection.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_badge.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_loader.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../design_system/buttons/app_button.dart';
import '../meters/meters_screen.dart';
import 'contrat_factures_screen.dart';

// ============================================================
// TRI DES CONTRATS — filtre de la barre de recherche
// ============================================================
// Deux familles de tri : date d'ancienneté, ou montant (croissant /
// décroissant). Le bottom sheet est partagé entre l'icône "filtre"
// (Icons.tune_rounded) de la barre de recherche d'accueil et l'écran
// Contrats lui-même, mais le tri est TOUJOURS appliqué et affiché sur
// cet écran (voir cahier des charges).
// ============================================================

enum ContratSortOption {
  anciennetePlusRecent,
  anciennetePlusAncien,
  montantCroissant,
  montantDecroissant,
}

extension ContratSortOptionX on ContratSortOption {
  String get label {
    switch (this) {
      case ContratSortOption.anciennetePlusRecent:
        return 'Ancienneté : plus récent d’abord';
      case ContratSortOption.anciennetePlusAncien:
        return 'Ancienneté : plus ancien d’abord';
      case ContratSortOption.montantCroissant:
        return 'Montant croissant';
      case ContratSortOption.montantDecroissant:
        return 'Montant décroissant';
    }
  }

  bool get parMontant =>
      this == ContratSortOption.montantCroissant || this == ContratSortOption.montantDecroissant;

  IconData get icon => parMontant ? Icons.payments_outlined : Icons.event_outlined;
}

class ContratSortSheet {
  ContratSortSheet._();

  static Future<ContratSortOption?> choose(BuildContext context) {
    return AppBottomSheet.show<ContratSortOption>(
      context: context,
      title: 'Trier les contrats',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Par date d’ancienneté', style: AppTextStyles.label),
          _SortTile(
            option: ContratSortOption.anciennetePlusRecent,
            label: 'Du plus récent au plus ancien',
          ),
          _SortTile(
            option: ContratSortOption.anciennetePlusAncien,
            label: 'Du plus ancien au plus récent',
          ),
          SizedBox(height: AppSpacing.lg),
          Text('Par montant', style: AppTextStyles.label),
          _SortTile(
            option: ContratSortOption.montantCroissant,
            label: 'Montant croissant',
          ),
          _SortTile(
            option: ContratSortOption.montantDecroissant,
            label: 'Montant décroissant',
          ),
        ],
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  final ContratSortOption option;
  final String label;
  const _SortTile({required this.option, required this.label});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(option.icon, color: AppColors.primaryDark),
      title: Text(label, style: AppTextStyles.body),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: () => Navigator.of(context).pop(option),
    );
  }
}

class ContractsScreen extends StatefulWidget {
  /// Tri à appliquer dès l'ouverture — utilisé quand on arrive depuis
  /// l'icône "filtre" de la barre de recherche d'accueil, qui propose
  /// déjà le choix avant de naviguer ici.
  final ContratSortOption? initialSort;

  const ContractsScreen({super.key, this.initialSort});

  @override
  State<ContractsScreen> createState() => _ContractsScreenState();
}

class _ContractsScreenState extends State<ContractsScreen> {
  final _repo = EneoRepository();

  late Future<void> _chargement;
  List<ContratModel> _contratsOriginal = [];
  List<ContratModel> contrats = [];
  String? erreur;

  ContratSortOption? _sort;
  final Map<String, double> _montantsParContrat = {};
  bool _chargementMontants = false;

  @override
  void initState() {
    super.initState();
    _chargement = _charger();
  }

  Future<void> _charger() async {
    setState(() => erreur = null);
    try {
      final c = await _repo.getAllContrats();
      setState(() {
        _contratsOriginal = c;
        contrats = List.of(c);
      });
      // Après un pull-to-refresh, on conserve le tri en cours ; à la
      // première ouverture, on applique celui reçu depuis l'accueil.
      final sortAReappliquer = _sort ?? widget.initialSort;
      if (sortAReappliquer != null) {
        _montantsParContrat.clear();
        await _appliquerTri(sortAReappliquer);
      }
    } on ApiException catch (e) {
      setState(() => erreur = e.message);
    } catch (_) {
      setState(() => erreur = 'Une erreur est survenue. Vérifiez votre connexion.');
    }
  }

  Future<void> _choisirTri() async {
    final choix = await ContratSortSheet.choose(context);
    if (choix != null) {
      await _appliquerTri(choix);
    }
  }

  Future<void> _appliquerTri(ContratSortOption option) async {
    if (option.parMontant && _montantsParContrat.length < _contratsOriginal.length) {
      setState(() => _chargementMontants = true);
      await Future.wait(_contratsOriginal.map((contrat) async {
        if (_montantsParContrat.containsKey(contrat.id)) return;
        try {
          final idContrat = int.tryParse(contrat.id);
          if (idContrat == null) {
            _montantsParContrat[contrat.id] = 0;
            return;
          }
          // Montant dû = somme des factures impayées du contrat, tous
          // compteurs confondus (cohérent avec "Montant dû sur les
          // factures impayées" affiché à l'accueil).
          final factures = await _repo.getContratFactures(idContrat, statut: 'Impayée');
          _montantsParContrat[contrat.id] =
              factures.fold<double>(0, (total, f) => total + f.montantFcfa);
        } catch (_) {
          _montantsParContrat[contrat.id] = 0;
        }
      }));
      if (!mounted) return;
      setState(() => _chargementMontants = false);
    }

    final trie = List<ContratModel>.of(_contratsOriginal);
    switch (option) {
      case ContratSortOption.anciennetePlusRecent:
        trie.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
        break;
      case ContratSortOption.anciennetePlusAncien:
        trie.sort((a, b) => a.dateCreation.compareTo(b.dateCreation));
        break;
      case ContratSortOption.montantCroissant:
        trie.sort((a, b) => (_montantsParContrat[a.id] ?? 0)
            .compareTo(_montantsParContrat[b.id] ?? 0));
        break;
      case ContratSortOption.montantDecroissant:
        trie.sort((a, b) => (_montantsParContrat[b.id] ?? 0)
            .compareTo(_montantsParContrat[a.id] ?? 0));
        break;
    }
    if (!mounted) return;
    setState(() {
      _sort = option;
      contrats = trie;
    });
  }

  void _reinitialiserTri() {
    setState(() {
      _sort = null;
      contrats = List.of(_contratsOriginal);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _chargement,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: const [
              ShimmerBox(width: 140, height: 22),
              SizedBox(height: 20),
              ShimmerCard(titleWidth: 120),
              SizedBox(height: 12),
              ShimmerCard(titleWidth: 120),
              SizedBox(height: 12),
              ShimmerCard(titleWidth: 120),
            ],
          );
        }
        if (erreur != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(erreur!, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _chargement = _charger()),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _chargement = _charger()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Mes contrats', style: AppTextStyles.h2),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Trier les contrats',
                        icon: _chargementMontants
                            ? const AppLoader.small()
                            : Icon(Icons.tune_rounded,
                                color: _sort != null
                                    ? AppColors.primary
                                    : AppColors.primaryDark),
                        onPressed: _chargementMontants ? null : _choisirTri,
                      ),
                      IconButton(
                        tooltip: 'Voir tous mes compteurs',
                        icon: const Icon(Icons.speed_outlined, color: AppColors.primaryDark),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MetersScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Un contrat regroupe un ou plusieurs compteurs. Rattachez vos '
                'compteurs à un contrat pour en gérer l’accès et les factures.',
                style: AppTextStyles.bodyMuted,
              ),
              if (_sort != null) ...[
                const SizedBox(height: 12),
                InputChip(
                  avatar: Icon(_sort!.icon, size: 18, color: AppColors.primaryDark),
                  label: Text(_sort!.label, style: AppTextStyles.caption),
                  onDeleted: _reinitialiserTri,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  backgroundColor: AppColors.primary.withOpacity(0.08),
                  side: BorderSide.none,
                ),
              ],
              const SizedBox(height: 20),
              if (contrats.isEmpty)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Lottie.asset(LottieAssets.girlSayHi, width: 48, height: 48, repeat: true),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Aucun contrat pour le moment.', style: AppTextStyles.bodyMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _ouvrirCreationContrat,
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter un contrat'),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                ...contrats.asMap().entries.map((entry) => FadeSlideIn(
                      index: entry.key,
                      child: _ContratTile(
                        contrat: entry.value,
                        onTap: () => _ouvrirFactures(entry.value),
                      ),
                    )),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _ouvrirCreationContrat,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter un contrat'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Un contrat = ses compteurs actifs : plus besoin de montrer la liste
  /// des compteurs avant les factures. Cliquer sur un contrat mène donc
  /// directement à ses factures ; la gestion des compteurs/délégations
  /// (`ContratDetailScreen`) reste accessible depuis l'icône "Gérer ce
  /// contrat" de cet écran de factures.
  ///
  /// REFONTE — ce contrat devient aussi celui affiché sur l'accueil : on
  /// le dépose dans `ContratSelectionExterne` (voir ce fichier pour le
  /// pourquoi), l'accueil le lira à son prochain chargement et
  /// affichera "ce contrat + les 2 plus proches en date" en haut de la
  /// barre de recherche à la place de l'aperçu habituel.
  void _ouvrirFactures(ContratModel contrat) {
    ContratSelectionExterne.enAttente = contrat;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContratFacturesScreen(contrat: contrat)),
    );
  }

  void _ouvrirCreationContrat() {
    final numeroController = TextEditingController();
    bool envoi = false;
    String? erreurLocale;

    AppBottomSheet.show(
      context: context,
      title: 'Ajouter un contrat',
      child: StatefulBuilder(
        builder: (ctx, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Renseignez le numéro du contrat Eneo (visible sur votre '
              'contrat papier ou communiqué par une agence Eneo).',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Numéro de contrat',
              controller: numeroController,
              hintText: 'ex: CTR-2026-000123',
            ),
            if (erreurLocale != null) ...[
              const SizedBox(height: 12),
              Text(erreurLocale!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 16),
            AppButton(
              label: envoi ? 'Enregistrement…' : 'Ajouter ce contrat',
              loading: envoi,
              onPressed: envoi
                  ? null
                  : () async {
                      final numero = numeroController.text.trim();
                      if (numero.isEmpty) {
                        setModalState(() => erreurLocale = 'Le numéro de contrat est requis.');
                        return;
                      }
                      setModalState(() {
                        envoi = true;
                        erreurLocale = null;
                      });
                      try {
                        final nouveau = await _repo.createContrat(numeroContrat: numero);
                        if (!mounted) return;
                        Navigator.pop(context);
                        setState(() => contrats = [...contrats, nouveau]);
                        _showSnack('Contrat ${nouveau.numeroContrat} ajouté.');
                      } on ApiValidationException catch (e) {
                        setModalState(() {
                          envoi = false;
                          erreurLocale = e.firstMessage;
                        });
                      } on ApiException catch (e) {
                        setModalState(() {
                          envoi = false;
                          erreurLocale = e.message;
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ContratTile extends StatelessWidget {
  final ContratModel contrat;
  final VoidCallback onTap;

  const _ContratTile({required this.contrat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.description_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contrat.numeroContrat, style: AppTextStyles.label),
                  Text(
                    contrat.nombreCompteurs != null
                        ? '${contrat.nombreCompteurs} compteur${contrat.nombreCompteurs! > 1 ? 's' : ''}'
                        : 'Compteurs : —',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            StatusBadge(label: contrat.statutLabel),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.background),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DÉTAIL D'UN CONTRAT — compteurs, ajout, délégation "tout le contrat"
// ============================================================

class ContratDetailScreen extends StatefulWidget {
  final ContratModel contrat;
  const ContratDetailScreen({super.key, required this.contrat});

  @override
  State<ContratDetailScreen> createState() => _ContratDetailScreenState();
}

class _ContratDetailScreenState extends State<ContratDetailScreen> {
  final _repo = EneoRepository();

  late Future<void> _chargement;
  List<CompteurModel> compteurs = [];
  List<DelegationModel> delegationsContrat = [];
  String? erreur;
  bool _modifie = false;

  /// `true` si les compteurs du contrat viennent du cache local (§7.6).
  bool horsLigne = false;
  DateTime? derniereSynchro;

  int get _idContrat => int.tryParse(widget.contrat.id) ?? 0;

  @override
  void initState() {
    super.initState();
    _chargement = _charger();
  }

  Future<void> _charger() async {
    setState(() => erreur = null);
    try {
      final compteursFuture =
          _repo.getContratCompteurs(_idContrat, numeroContrat: widget.contrat.numeroContrat);
      final delegationsFuture = _repo.getDelegations();
      final compteursResult = await compteursFuture;
      final listeDelegations = await delegationsFuture;
      setState(() {
        compteurs = compteursResult.data;
        horsLigne = compteursResult.isFromCache;
        derniereSynchro = compteursResult.syncedAt;
        delegationsContrat = listeDelegations
            .where((d) => d.portee == PorteeDelegation.contrat && d.idContrat == _idContrat)
            .toList();
      });
    } on ApiException catch (e) {
      setState(() => erreur = e.message);
    } catch (_) {
      setState(() => erreur = 'Une erreur est survenue. Vérifiez votre connexion.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_modifie);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          title: Text(widget.contrat.numeroContrat),
          actions: [
            IconButton(
              tooltip: 'Factures du contrat',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ContratFacturesScreen(contrat: widget.contrat),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: FutureBuilder<void>(
            future: _chargement,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LottieLoader();
              }
              if (erreur != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(erreur!, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() => _chargement = _charger()),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => setState(() => _chargement = _charger()),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    if (horsLigne) ...[
                      OfflineBanner(derniereSynchro: derniereSynchro, margin: EdgeInsets.zero),
                      const SizedBox(height: 12),
                    ],
                    AppCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.contrat.numeroContrat, style: AppTextStyles.h3),
                              const SizedBox(height: 4),
                              Text(
                                'Créé le ${_formatDate(widget.contrat.dateCreation)}',
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                          StatusBadge(label: widget.contrat.statutLabel),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: 'Compteurs (${compteurs.length})',
                      actionLabel: 'Ajouter',
                      onAction: _ouvrirAjoutCompteur,
                    ),
                    const SizedBox(height: 12),
                    if (compteurs.isEmpty)
                      const AppCard(
                        child: EmptyStateLottie(
                          asset: LottieAssets.search,
                          title: 'Aucun compteur rattaché à ce contrat pour le moment.',
                          size: 100,
                        ),
                      )
                    else
                      ...compteurs.map((c) => _CompteurDeContratTile(compteur: c)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ContratFacturesScreen(contrat: widget.contrat),
                          ),
                        ),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('Voir les factures du contrat'),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SectionHeader(title: 'Délégation sur tout le contrat'),
                    const SizedBox(height: 8),
                    const Text(
                      'Un tiers ainsi désigné accède à tous les compteurs actuels et '
                      'futurs de ce contrat.',
                      style: AppTextStyles.bodyMuted,
                    ),
                    const SizedBox(height: 12),
                    if (delegationsContrat.isEmpty)
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Lottie.asset(LottieAssets.search, width: 44, height: 44, repeat: true),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text('Aucune délégation sur ce contrat.',
                                      style: AppTextStyles.bodyMuted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _ouvrirDelegationContrat,
                                icon: const Icon(Icons.person_add_alt, size: 18),
                                label: const Text('Déléguer tout le contrat'),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      ...delegationsContrat.map((d) => _DelegationContratTile(
                            delegation: d,
                            onRevoke: () => _revoquerDelegation(d),
                          )),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _ouvrirDelegationContrat,
                          icon: const Icon(Icons.person_add_alt, size: 18),
                          label: const Text('Déléguer à un autre tiers'),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _revoquerDelegation(DelegationModel d) async {
    final confirme = await AppDialog.confirm(
      context: context,
      title: 'Révoquer cet accès ?',
      message: '${d.nomTiers} perdra immédiatement l’accès à tout le contrat.',
      confirmLabel: 'Révoquer',
      danger: true,
    );
    if (confirme != true) return;
    try {
      await _repo.revokeDelegation(d.id);
      setState(() {
        delegationsContrat.remove(d);
        _modifie = true;
      });
    } on ApiException catch (e) {
      _showSnack(e.message);
    }
  }

  void _ouvrirAjoutCompteur() {
    final numeroController = TextEditingController();
    final villeController = TextEditingController();
    final communeController = TextEditingController();
    final quartierController = TextEditingController();
    TypeCompteur type = TypeCompteur.prepaye;
    bool envoi = false;
    String? erreurLocale;

    AppBottomSheet.show(
      context: context,
      title: 'Ajouter un compteur — ${widget.contrat.numeroContrat}',
      child: StatefulBuilder(
        builder: (ctx, setModalState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ce compteur sera rattaché à ce contrat. Renseignez son numéro '
                'et son adresse d’installation.',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Numéro de compteur unique',
                controller: numeroController,
                hintText: 'ex: CM-2026-004821',
              ),
              const SizedBox(height: 14),
              const Text('Type', style: AppTextStyles.label),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<TypeCompteur>(
                      contentPadding: EdgeInsets.zero,
                      value: TypeCompteur.prepaye,
                      groupValue: type,
                      title: const Text('Prépayé'),
                      onChanged: (v) => setModalState(() => type = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<TypeCompteur>(
                      contentPadding: EdgeInsets.zero,
                      value: TypeCompteur.postpaye,
                      groupValue: type,
                      title: const Text('Postpayé'),
                      onChanged: (v) => setModalState(() => type = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: 'Adresse d’installation',
                controller: villeController,
                hintText: 'Ville',
              ),
              const SizedBox(height: 8),
              AppTextField(controller: communeController, hintText: 'Commune'),
              const SizedBox(height: 8),
              AppTextField(controller: quartierController, hintText: 'Quartier'),
              if (erreurLocale != null) ...[
                const SizedBox(height: 12),
                Text(erreurLocale!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              AppButton(
                label: envoi ? 'Enregistrement…' : 'Ajouter ce compteur',
                loading: envoi,
                onPressed: envoi
                    ? null
                    : () async {
                        if (numeroController.text.trim().isEmpty ||
                            villeController.text.trim().isEmpty) {
                          setModalState(() => erreurLocale = 'Numéro et ville sont requis.');
                          return;
                        }
                        setModalState(() {
                          envoi = true;
                          erreurLocale = null;
                        });
                        try {
                          final nouveau = await _repo.rattacherCompteur(
                            idContrat: _idContrat,
                            numero: numeroController.text.trim(),
                            typeApi: type == TypeCompteur.prepaye ? 'PREPAYE' : 'POSTPAYE',
                            ville: villeController.text.trim(),
                            commune: communeController.text.trim(),
                            quartier: quartierController.text.trim(),
                            proprietaireLegal: '',
                          );
                          if (!mounted) return;
                          Navigator.pop(context);
                          setState(() {
                            compteurs = [...compteurs, nouveau];
                            _modifie = true;
                          });
                          _showSnack('Compteur ${nouveau.numero} ajouté au contrat.');
                        } on ApiValidationException catch (e) {
                          setModalState(() {
                            envoi = false;
                            erreurLocale = e.firstMessage;
                          });
                        } on ApiException catch (e) {
                          setModalState(() {
                            envoi = false;
                            erreurLocale = e.message;
                          });
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _ouvrirDelegationContrat() {
    final phoneController = TextEditingController();
    DroitDelegation droit = DroitDelegation.lecture;

    // Même flux que `_ouvrirDelegation` dans `meters_screen.dart`, à ceci
    // près que la délégation porte ici sur `idContrat` (tous les compteurs
    // actuels ET futurs du contrat) plutôt que sur un `idCompteur` précis.
    UtilisateurRechercheModel? resultat;
    bool rechercheEnCours = false;
    bool envoiEnCours = false;
    String? erreurLocale;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> rechercher() async {
            final telephone = phoneController.text.trim();
            if (telephone.isEmpty) {
              setModalState(() => erreurLocale = 'Saisissez un numéro de téléphone.');
              return;
            }
            setModalState(() {
              rechercheEnCours = true;
              erreurLocale = null;
              resultat = null;
            });
            try {
              final trouve = await _repo.rechercherUtilisateurParTelephone(telephone);
              setModalState(() {
                rechercheEnCours = false;
                if (trouve == null) {
                  erreurLocale = 'Aucun utilisateur inscrit avec ce numéro.';
                } else {
                  resultat = trouve;
                }
              });
            } on ApiException catch (e) {
              setModalState(() {
                rechercheEnCours = false;
                erreurLocale = e.message;
              });
            } catch (_) {
              setModalState(() {
                rechercheEnCours = false;
                erreurLocale = 'Une erreur est survenue. Vérifiez votre connexion.';
              });
            }
          }

          Future<void> confirmer() async {
            final trouve = resultat;
            final idContrat = int.tryParse(widget.contrat.id);
            if (trouve == null || idContrat == null) return;
            setModalState(() {
              envoiEnCours = true;
              erreurLocale = null;
            });
            try {
              await _repo.createDelegation(
                idUserTiers: trouve.idUser,
                idContrat: idContrat,
                droit: droit,
                cibleLabel: widget.contrat.numeroContrat,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _showSnack('Délégation accordée à ${trouve.nom} ${trouve.prenomMasque}.');
              _modifie = true;
              setState(() => _chargement = _charger());
            } on ApiException catch (e) {
              setModalState(() {
                envoiEnCours = false;
                erreurLocale = e.message;
              });
            } catch (_) {
              setModalState(() {
                envoiEnCours = false;
                erreurLocale = 'Une erreur est survenue. Vérifiez votre connexion.';
              });
            }
          }

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
                Text('Déléguer tout le contrat — ${widget.contrat.numeroContrat}',
                    style: AppTextStyles.h3),
                const SizedBox(height: 6),
                const Text(
                  'Le tiers désigné accédera à tous les compteurs actuels ET '
                  'futurs de ce contrat.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 14),
                const Text('Numéro de téléphone du tiers', style: AppTextStyles.label),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        enabled: resultat == null && !envoiEnCours,
                        decoration: const InputDecoration(hintText: '+237 6XX XXX XXX'),
                        onSubmitted: (_) => rechercher(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (resultat == null)
                      ElevatedButton(
                        onPressed: rechercheEnCours ? null : rechercher,
                        child: rechercheEnCours
                            ? const AppLoader.small(color: AppColors.white)
                            : const Text('Rechercher'),
                      ),
                  ],
                ),
                if (resultat != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tiers trouvé : ${resultat!.nom} ${resultat!.prenomMasque}',
                            style: AppTextStyles.label,
                          ),
                        ),
                        TextButton(
                          onPressed: envoiEnCours
                              ? null
                              : () => setModalState(() {
                                    resultat = null;
                                    erreurLocale = null;
                                  }),
                          child: const Text('Changer'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Niveau d’accès', style: AppTextStyles.label),
                const SizedBox(height: 8),
                RadioListTile<DroitDelegation>(
                  contentPadding: EdgeInsets.zero,
                  value: DroitDelegation.lecture,
                  groupValue: droit,
                  title: const Text('Lecture seule'),
                  subtitle: const Text('Consultation du solde et des factures'),
                  onChanged: envoiEnCours ? null : (v) => setModalState(() => droit = v!),
                ),
                RadioListTile<DroitDelegation>(
                  contentPadding: EdgeInsets.zero,
                  value: DroitDelegation.lectureEtPaiement,
                  groupValue: droit,
                  title: const Text('Lecture & paiement'),
                  subtitle: const Text('Peut également régler ou recharger'),
                  onChanged: envoiEnCours ? null : (v) => setModalState(() => droit = v!),
                ),
                if (erreurLocale != null) ...[
                  const SizedBox(height: 6),
                  Text(erreurLocale!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: resultat == null || envoiEnCours ? null : confirmer,
                    child: Text(envoiEnCours ? 'Envoi…' : 'Confirmer la délégation'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _CompteurDeContratTile extends StatelessWidget {
  final CompteurModel compteur;
  const _CompteurDeContratTile({required this.compteur});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                compteur.type == TypeCompteur.prepaye ? Icons.flash_on : Icons.receipt_long,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(compteur.numero, style: AppTextStyles.label),
                  Text(
                    compteur.adresse.isNotEmpty ? compteur.adresse : 'Adresse non disponible',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            StatusBadge(label: compteur.statutLabel),
          ],
        ),
      ),
    );
  }
}

class _DelegationContratTile extends StatelessWidget {
  final DelegationModel delegation;
  final VoidCallback onRevoke;
  const _DelegationContratTile({required this.delegation, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.surface,
              child: Text(
                delegation.nomTiers.isNotEmpty ? delegation.nomTiers[0] : '?',
                style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(delegation.nomTiers, style: AppTextStyles.label),
                  Text(delegation.droitLabel, style: AppTextStyles.caption),
                ],
              ),
            ),
            IconButton(
              onPressed: onRevoke,
              icon: const Icon(Icons.close, color: AppColors.danger, size: 20),
              tooltip: 'Révoquer',
            ),
          ],
        ),
      ),
    );
  }
}