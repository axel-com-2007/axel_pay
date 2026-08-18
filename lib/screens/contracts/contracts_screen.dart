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
import '../../design_system/responsive/responsive_utils.dart';
import '../../l10n/app_strings.dart';

enum ContratSortOption {
  anciennetePlusRecent,
  anciennetePlusAncien,
  montantCroissant,
  montantDecroissant,
}

extension ContratSortOptionX on ContratSortOption {
  bool get parMontant =>
      this == ContratSortOption.montantCroissant ||
      this == ContratSortOption.montantDecroissant;

  IconData get icon =>
      parMontant ? Icons.payments_outlined : Icons.event_outlined;
}

String _sortLabel(BuildContext context, ContratSortOption option) {
  final s = S.of(context);

  switch (option) {
    case ContratSortOption.anciennetePlusRecent:
      return s.contratsTriPlusRecentDabord;
    case ContratSortOption.anciennetePlusAncien:
      return s.contratsTriPlusAncienDabord;
    case ContratSortOption.montantCroissant:
      return s.contratsTriMontantCroissant;
    case ContratSortOption.montantDecroissant:
      return s.contratsTriMontantDecroissant;
  }
}

class ContratSortSheet {
  ContratSortSheet._();

  static Future<ContratSortOption?> choose(BuildContext context) {
    final s = S.read(context);

    return AppBottomSheet.show<ContratSortOption>(
      context: context,
      title: s.contratsTrierTitre,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.contratsTriParDate,
            style: AppTextStyles.label,
          ),
          _SortTile(
            option: ContratSortOption.anciennetePlusRecent,
            label: s.contratsTriPlusRecentDabord,
          ),
          _SortTile(
            option: ContratSortOption.anciennetePlusAncien,
            label: s.contratsTriPlusAncienDabord,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            s.contratsTriParMontant,
            style: AppTextStyles.label,
          ),
          _SortTile(
            option: ContratSortOption.montantCroissant,
            label: s.contratsTriMontantCroissant,
          ),
          _SortTile(
            option: ContratSortOption.montantDecroissant,
            label: s.contratsTriMontantDecroissant,
          ),
        ],
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  final ContratSortOption option;
  final String label;

  const _SortTile({
    required this.option,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        option.icon,
        color: AppColors.primaryDark,
      ),
      title: Text(
        label,
        style: AppTextStyles.body,
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.textMuted,
      ),
      onTap: () => Navigator.of(context).pop(option),
    );
  }
}

class ContractsScreen extends StatefulWidget {
  final ContratSortOption? initialSort;

  const ContractsScreen({
    super.key,
    this.initialSort,
  });

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

      final sortAReappliquer = _sort ?? widget.initialSort;

      if (sortAReappliquer != null) {
        _montantsParContrat.clear();
        await _appliquerTri(sortAReappliquer);
      }
    } on ApiException catch (e) {
      setState(() => erreur = e.message);
    } catch (_) {
      setState(
        () => erreur = S.read(context).uneErreurEstSurvenue,
      );
    }
  }

  Future<void> _choisirTri() async {
    final choix = await ContratSortSheet.choose(context);

    if (choix != null) {
      await _appliquerTri(choix);
    }
  }

  Future<void> _appliquerTri(
    ContratSortOption option,
  ) async {
    if (option.parMontant &&
        _montantsParContrat.length < _contratsOriginal.length) {
      setState(() => _chargementMontants = true);

      await Future.wait(
        _contratsOriginal.map(
          (contrat) async {
            if (_montantsParContrat.containsKey(contrat.id)) {
              return;
            }

            try {
              final idContrat = int.tryParse(contrat.id);

              if (idContrat == null) {
                _montantsParContrat[contrat.id] = 0;
                return;
              }

              final factures = await _repo.getContratFactures(
                idContrat,
                statut: 'Impayée',
              );

              _montantsParContrat[contrat.id] =
                  factures.fold<double>(
                0,
                (total, f) => total + f.montantFcfa,
              );
            } catch (_) {
              _montantsParContrat[contrat.id] = 0;
            }
          },
        ),
      );

      if (!mounted) return;

      setState(() => _chargementMontants = false);
    }

    final trie = List<ContratModel>.of(_contratsOriginal);

    switch (option) {
      case ContratSortOption.anciennetePlusRecent:
        trie.sort(
          (a, b) => b.dateCreation.compareTo(a.dateCreation),
        );
        break;

      case ContratSortOption.anciennetePlusAncien:
        trie.sort(
          (a, b) => a.dateCreation.compareTo(b.dateCreation),
        );
        break;

      case ContratSortOption.montantCroissant:
        trie.sort(
          (a, b) => (_montantsParContrat[a.id] ?? 0)
              .compareTo(_montantsParContrat[b.id] ?? 0),
        );
        break;

      case ContratSortOption.montantDecroissant:
        trie.sort(
          (a, b) => (_montantsParContrat[b.id] ?? 0)
              .compareTo(_montantsParContrat[a.id] ?? 0),
        );
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
    final s = S.of(context);

    return FutureBuilder<void>(
      future: _chargement,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ListView(
            padding: EdgeInsets.fromLTRB(
              context.isDesktop
                  ? 48
                  : context.isTablet
                      ? 32
                      : 20,
              16,
              context.isDesktop
                  ? 48
                  : context.isTablet
                      ? 32
                      : 20,
              32,
            ),
            children: const [
              ShimmerBox(
                width: 140,
                height: 22,
              ),
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
                  Text(
                    erreur!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _chargement = _charger();
                      });
                    },
                    child: Text(s.reessayer),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _chargement = _charger();
            });

            await _chargement;
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              context.isDesktop
                  ? 48
                  : context.isTablet
                      ? 32
                      : 20,
              16,
              context.isDesktop
                  ? 48
                  : context.isTablet
                      ? 32
                      : 20,
              32,
            ),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.mesContratsTitre,
                    style: AppTextStyles.h2,
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: s.contratsTrierTooltip,
                        icon: _chargementMontants
                            ? const AppLoader.small()
                            : Icon(
                                Icons.tune_rounded,
                                color: _sort != null
                                    ? AppColors.primary
                                    : AppColors.primaryDark,
                              ),
                        onPressed: _chargementMontants
                            ? null
                            : _choisirTri,
                      ),
                      IconButton(
                        tooltip: s.contratsVoirTousCompteursTooltip,
                        icon: const Icon(
                          Icons.speed_outlined,
                          color: AppColors.primaryDark,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MetersScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 4),

              Text(
                s.contratsDescription,
                style: AppTextStyles.bodyMuted,
              ),

              if (_sort != null) ...[
                const SizedBox(height: 12),
                InputChip(
                  avatar: Icon(
                    _sort!.icon,
                    size: 18,
                    color: AppColors.primaryDark,
                  ),
                  label: Text(
                    _sortLabel(context, _sort!),
                    style: AppTextStyles.caption,
                  ),
                  onDeleted: _reinitialiserTri,
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 16,
                  ),
                  backgroundColor:
                      AppColors.primary.withOpacity(0.08),
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
                          Lottie.asset(
                            LottieAssets.girlSayHi,
                            width: 48,
                            height: 48,
                            repeat: true,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.contratsAucunContrat,
                              style: AppTextStyles.bodyMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _ouvrirCreationContrat,
                          icon: const Icon(Icons.add),
                          label: Text(
                            s.contratsAjouterUnContrat,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                ...contrats.asMap().entries.map(
                      (entry) => FadeSlideIn(
                        index: entry.key,
                        child: _ContratTile(
                          contrat: entry.value,
                          onTap: () =>
                              _ouvrirFactures(entry.value),
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _ouvrirCreationContrat,
                    icon: const Icon(Icons.add),
                    label: Text(
                      s.contratsAjouterUnContrat,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _ouvrirFactures(ContratModel contrat) {
    ContratSelectionExterne.enAttente = contrat;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContratFacturesScreen(
          contrat: contrat,
        ),
      ),
    );
  }

  void _ouvrirCreationContrat() {
    final numeroController = TextEditingController();

    bool envoi = false;
    String? erreurLocale;

    AppBottomSheet.show(
      context: context,
      title: S.read(context).contratsAjouterUnContrat,
      child: StatefulBuilder(
        builder: (ctx, setModalState) {
          final s = S.of(ctx);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.contratsNumeroContratDescription,
                style: AppTextStyles.caption,
              ),

              const SizedBox(height: 14),

              AppTextField(
                label: s.contratsNumeroContratLabel,
                controller: numeroController,
                hintText: 'CTR-2026-000123',
              ),

              if (erreurLocale != null) ...[
                const SizedBox(height: 12),
                Text(
                  erreurLocale!,
                  style: const TextStyle(
                    color: AppColors.danger,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              AppButton(
                label: envoi
                    ? s.enregistrementEnCours
                    : s.contratsAjouterCeContratBouton,
                loading: envoi,
                onPressed: envoi
                    ? null
                    : () async {
                        final numero =
                            numeroController.text.trim();

                        if (numero.isEmpty) {
                          setModalState(
                            () => erreurLocale =
                                s.contratsNumeroContratRequis,
                          );
                          return;
                        }

                        setModalState(() {
                          envoi = true;
                          erreurLocale = null;
                        });

                        try {
                          final nouveau =
                              await _repo.createContrat(
                            numeroContrat: numero,
                          );

                          if (!mounted) return;

                          Navigator.pop(context);

                          setState(() {
                            contrats = [
                              ...contrats,
                              nouveau,
                            ];
                          });

                          _showSnack(
                            s.contratsAjoute(
                              nouveau.numeroContrat,
                            ),
                          );
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
          );
        },
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
}

class _ContratTile extends StatelessWidget {
  final ContratModel contrat;
  final VoidCallback onTap;

  const _ContratTile({
    required this.contrat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

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
              child: const Icon(
                Icons.description_outlined,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    contrat.numeroContrat,
                    style: AppTextStyles.label,
                  ),
                  Text(
                    contrat.nombreCompteurs != null
                        ? s.contratsNombreCompteurs(
                            contrat.nombreCompteurs!,
                          )
                        : s.contratsCompteursIndisponibles,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),

            StatusBadge(
              label: contrat.statutLabel,
            ),

            const SizedBox(width: 4),

            const Icon(
              Icons.chevron_right,
              color: AppColors.background,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DÉTAIL D'UN CONTRAT
// ============================================================

class ContratDetailScreen extends StatefulWidget {
  final ContratModel contrat;

  const ContratDetailScreen({
    super.key,
    required this.contrat,
  });

  @override
  State<ContratDetailScreen> createState() =>
      _ContratDetailScreenState();
}

class _ContratDetailScreenState
    extends State<ContratDetailScreen> {
  final _repo = EneoRepository();

  late Future<void> _chargement;

  List<CompteurModel> compteurs = [];
  List<DelegationModel> delegationsContrat = [];

  String? erreur;
  bool _modifie = false;

  bool horsLigne = false;
  DateTime? derniereSynchro;

  int get _idContrat =>
      int.tryParse(widget.contrat.id) ?? 0;

  @override
  void initState() {
    super.initState();
    _chargement = _charger();
  }

  Future<void> _charger() async {
    setState(() => erreur = null);

    try {
      final compteursFuture =
          _repo.getContratCompteurs(
        _idContrat,
        numeroContrat: widget.contrat.numeroContrat,
      );

      final delegationsFuture =
          _repo.getDelegations();

      final compteursResult =
          await compteursFuture;

      final listeDelegations =
          await delegationsFuture;

      setState(() {
        compteurs = compteursResult.data;
        horsLigne = compteursResult.isFromCache;
        derniereSynchro =
            compteursResult.syncedAt;

        delegationsContrat = listeDelegations
            .where(
              (d) =>
                  d.portee ==
                      PorteeDelegation.contrat &&
                  d.idContrat == _idContrat,
            )
            .toList();
      });
    } on ApiException catch (e) {
      setState(() => erreur = e.message);
    } catch (_) {
      setState(
        () => erreur =
            S.read(context).uneErreurEstSurvenue,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

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
          title: Text(
            widget.contrat.numeroContrat,
          ),
          actions: [
            IconButton(
              tooltip: s.contratsFacturesTooltip,
              icon: const Icon(
                Icons.receipt_long_outlined,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ContratFacturesScreen(
                      contrat: widget.contrat,
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        body: SafeArea(
          child: FutureBuilder<void>(
            future: _chargement,
            builder: (context, snapshot) {
              if (snapshot.connectionState !=
                  ConnectionState.done) {
                return const LottieLoader();
              }

              if (erreur != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          erreur!,
                          textAlign: TextAlign.center,
                          style:
                              AppTextStyles.bodyMuted,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _chargement =
                                  _charger();
                            });
                          },
                          child: Text(s.reessayer),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _chargement = _charger();
                  });

                  await _chargement;
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    context.isDesktop
                        ? 48
                        : context.isTablet
                            ? 32
                            : 20,
                    12,
                    context.isDesktop
                        ? 48
                        : context.isTablet
                            ? 32
                            : 20,
                    32,
                  ),
                  children: [
                    if (horsLigne) ...[
                      OfflineBanner(
                        derniereSynchro:
                            derniereSynchro,
                        margin: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                    ],

                    AppCard(
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                widget.contrat
                                    .numeroContrat,
                                style:
                                    AppTextStyles.h3,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s.contratsCreeLe(
                                  _formatDate(
                                    widget.contrat
                                        .dateCreation,
                                  ),
                                ),
                                style:
                                    AppTextStyles.caption,
                              ),
                            ],
                          ),
                          StatusBadge(
                            label: widget
                                .contrat.statutLabel,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    SectionHeader(
                      title:
                          s.contratsCompteursTitre(
                        compteurs.length,
                      ),
                      actionLabel: s.ajouter,
                      onAction:
                          _ouvrirAjoutCompteur,
                    ),

                    const SizedBox(height: 12),

                    if (compteurs.isEmpty)
                      AppCard(
                        child: EmptyStateLottie(
                          asset:
                              LottieAssets.search,
                          title: s
                              .contratsAucunCompteurRattache,
                          size: 100,
                        ),
                      )
                    else
                      ...compteurs.map(
                        (c) =>
                            _CompteurDeContratTile(
                          compteur: c,
                        ),
                      ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child:
                          OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ContratFacturesScreen(
                                contrat:
                                    widget.contrat,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons
                              .receipt_long_outlined,
                          size: 18,
                        ),
                        label: Text(
                          s.contratsVoirFacturesDuContrat,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    SectionHeader(
                      title:
                          s.contratsDelegationSurTout,
                    ),

                    const SizedBox(height: 8),

                    Text(
                      s.contratsDelegationDescription,
                      style:
                          AppTextStyles.bodyMuted,
                    ),

                    const SizedBox(height: 12),

                    if (delegationsContrat.isEmpty)
                      AppCard(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Lottie.asset(
                                  LottieAssets.search,
                                  width: 44,
                                  height: 44,
                                  repeat: true,
                                ),
                                const SizedBox(
                                    width: 10),
                                Expanded(
                                  child: Text(
                                    s.contratsAucuneDelegation,
                                    style:
                                        AppTextStyles
                                            .bodyMuted,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            SizedBox(
                              width: double.infinity,
                              child:
                                  OutlinedButton
                                      .icon(
                                onPressed:
                                    _ouvrirDelegationContrat,
                                icon: const Icon(
                                  Icons
                                      .person_add_alt,
                                  size: 18,
                                ),
                                label: Text(
                                  s.contratsDeleguerToutLeContrat,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      ...delegationsContrat.map(
                        (d) =>
                            _DelegationContratTile(
                          delegation: d,
                          onRevoke: () =>
                              _revoquerDelegation(
                            d,
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),

                      SizedBox(
                        width: double.infinity,
                        child:
                            OutlinedButton.icon(
                          onPressed:
                              _ouvrirDelegationContrat,
                          icon: const Icon(
                            Icons.person_add_alt,
                            size: 18,
                          ),
                          label: Text(
                            s.contratsDeleguerAutreTiers,
                          ),
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

  void _revoquerDelegation(
    DelegationModel d,
  ) async {
    final s = S.read(context);

    final confirme = await AppDialog.confirm(
      context: context,
      title: s.revoquerCetAccesTitre,
      message:
          s.contratsRevoquerMessage(d.nomTiers),
      confirmLabel: s.revoquer,
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
    final numeroController =
        TextEditingController();

    final villeController =
        TextEditingController();

    final communeController =
        TextEditingController();

    final quartierController =
        TextEditingController();

    TypeCompteur type =
        TypeCompteur.prepaye;

    bool envoi = false;
    String? erreurLocale;

    AppBottomSheet.show(
      context: context,
      title: S.read(context)
          .contratsAjouterCompteurTitre(
        widget.contrat.numeroContrat,
      ),
      child: StatefulBuilder(
        builder: (ctx, setModalState) {
          final s = S.of(ctx);

          return SingleChildScrollView(
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  s.contratsAjouterCompteurDescription,
                  style:
                      AppTextStyles.caption,
                ),

                const SizedBox(height: 14),

                AppTextField(
                  label: s
                      .contratsNumeroCompteurUniqueLabel,
                  controller:
                      numeroController,
                  hintText:
                      'CM-2026-004821',
                ),

                const SizedBox(height: 14),

                Text(
                  s.typeCompteur,
                  style: AppTextStyles.label,
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    Expanded(
                      child:
                          RadioListTile<
                              TypeCompteur>(
                        contentPadding:
                            EdgeInsets.zero,
                        value:
                            TypeCompteur.prepaye,
                        groupValue: type,
                        title: Text(
                          s.typePrepaye,
                        ),
                        onChanged: (v) {
                          setModalState(
                            () => type = v!,
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child:
                          RadioListTile<
                              TypeCompteur>(
                        contentPadding:
                            EdgeInsets.zero,
                        value:
                            TypeCompteur.postpaye,
                        groupValue: type,
                        title: Text(
                          s.typePostpaye,
                        ),
                        onChanged: (v) {
                          setModalState(
                            () => type = v!,
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                AppTextField(
                  label: s
                      .contratsAdresseInstallationLabel,
                  controller:
                      villeController,
                  hintText: s.ville,
                ),

                const SizedBox(height: 8),

                AppTextField(
                  controller:
                      communeController,
                  hintText: s.commune,
                ),

                const SizedBox(height: 8),

                AppTextField(
                  controller:
                      quartierController,
                  hintText: s.quartier,
                ),

                if (erreurLocale != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    erreurLocale!,
                    style: const TextStyle(
                      color: AppColors.danger,
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                AppButton(
                  label: envoi
                      ? s.enregistrementEnCours
                      : s.contratsAjouterCeCompteurBouton,
                  loading: envoi,
                  onPressed: envoi
                      ? null
                      : () async {
                          if (numeroController
                                  .text
                                  .trim()
                                  .isEmpty ||
                              villeController
                                  .text
                                  .trim()
                                  .isEmpty) {
                            setModalState(
                              () => erreurLocale =
                                  s.contratsNumeroEtVilleRequis,
                            );
                            return;
                          }

                          setModalState(() {
                            envoi = true;
                            erreurLocale = null;
                          });

                          try {
                            final nouveau =
                                await _repo
                                    .rattacherCompteur(
                              idContrat:
                                  _idContrat,
                              numero:
                                  numeroController
                                      .text
                                      .trim(),
                              typeApi:
                                  type ==
                                          TypeCompteur
                                              .prepaye
                                      ? 'PREPAYE'
                                      : 'POSTPAYE',
                              ville:
                                  villeController
                                      .text
                                      .trim(),
                              commune:
                                  communeController
                                      .text
                                      .trim(),
                              quartier:
                                  quartierController
                                      .text
                                      .trim(),
                              proprietaireLegal: '',
                            );

                            if (!mounted) return;

                            Navigator.pop(context);

                            setState(() {
                              compteurs = [
                                ...compteurs,
                                nouveau,
                              ];
                              _modifie = true;
                            });

                            _showSnack(
                              s.contratsCompteurAjoute(
                                nouveau.numero,
                              ),
                            );
                          } on ApiValidationException catch (e) {
                            setModalState(() {
                              envoi = false;
                              erreurLocale =
                                  e.firstMessage;
                            });
                          } on ApiException catch (e) {
                            setModalState(() {
                              envoi = false;
                              erreurLocale =
                                  e.message;
                            });
                          }
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _ouvrirDelegationContrat() {
    final phoneController =
        TextEditingController();

    DroitDelegation droit =
        DroitDelegation.lecture;

    UtilisateurRechercheModel? resultat;

    bool rechercheEnCours = false;
    bool envoiEnCours = false;

    String? erreurLocale;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(
            AppRadius.sheet,
          ),
        ),
      ),
      builder: (ctx) =>
          StatefulBuilder(
        builder:
            (ctx, setModalState) {
          final s = S.of(ctx);

          Future<void> rechercher() async {
            final telephone =
                phoneController.text.trim();

            if (telephone.isEmpty) {
              setModalState(
                () => erreurLocale =
                    s.numeroTelephoneRequis,
              );
              return;
            }

            setModalState(() {
              rechercheEnCours = true;
              erreurLocale = null;
              resultat = null;
            });

            try {
              final trouve =
                  await _repo
                      .rechercherUtilisateurParTelephone(
                telephone,
              );

              setModalState(() {
                rechercheEnCours = false;

                if (trouve == null) {
                  erreurLocale =
                      s.aucunUtilisateurAvecCeNumero;
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
                erreurLocale =
                    s.uneErreurEstSurvenue;
              });
            }
          }

          Future<void> confirmer() async {
            final trouve = resultat;

            final idContrat =
                int.tryParse(widget.contrat.id);

            if (trouve == null ||
                idContrat == null) {
              return;
            }

            setModalState(() {
              envoiEnCours = true;
              erreurLocale = null;
            });

            try {
              await _repo.createDelegation(
                idUserTiers:
                    trouve.idUser,
                idContrat: idContrat,
                droit: droit,
                cibleLabel:
                    widget.contrat.numeroContrat,
              );

              if (ctx.mounted) {
                Navigator.pop(ctx);
              }

              _showSnack(
                s.contratsDelegationAccordee(
                  '${trouve.nom} ${trouve.prenomMasque}',
                ),
              );

              _modifie = true;

              setState(
                () => _chargement =
                    _charger(),
              );
            } on ApiException catch (e) {
              setModalState(() {
                envoiEnCours = false;
                erreurLocale = e.message;
              });
            } catch (_) {
              setModalState(() {
                envoiEnCours = false;
                erreurLocale =
                    s.uneErreurEstSurvenue;
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom:
                  MediaQuery.of(ctx)
                          .viewInsets
                          .bottom +
                      20,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  s.contratsDeleguerToutTitreAvecNumero(
                    widget.contrat.numeroContrat,
                  ),
                  style: AppTextStyles.h3,
                ),

                const SizedBox(height: 6),

                Text(
                  s.contratsDelegationTousCompteursDescription,
                  style:
                      AppTextStyles.caption,
                ),

                const SizedBox(height: 14),

                Text(
                  s.numeroTelephoneTiersLabel,
                  style: AppTextStyles.label,
                ),

                const SizedBox(height: 8),

                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller:
                            phoneController,
                        keyboardType:
                            TextInputType.phone,
                        enabled:
                            resultat == null &&
                                !envoiEnCours,
                        decoration:
                            InputDecoration(
                          hintText:
                              '+237 6XX XXX XXX',
                        ),
                        onSubmitted: (_) =>
                            rechercher(),
                      ),
                    ),

                    const SizedBox(width: 10),

                    if (resultat == null)
                      ElevatedButton(
                        onPressed:
                            rechercheEnCours
                                ? null
                                : rechercher,
                        child:
                            rechercheEnCours
                                ? const AppLoader
                                    .small(
                                    color: AppColors
                                        .white,
                                  )
                                : Text(
                                    s.rechercher,
                                  ),
                      ),
                  ],
                ),

                if (resultat != null) ...[
                  const SizedBox(height: 14),

                  Container(
                    padding:
                        const EdgeInsets.all(12),
                    decoration:
                        BoxDecoration(
                      color: AppColors.primary
                          .withOpacity(0.08),
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color:
                              AppColors.primary,
                          size: 20,
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            s.tiersTrouve(
                              '${resultat!.nom} ${resultat!.prenomMasque}',
                            ),
                            style:
                                AppTextStyles.label,
                          ),
                        ),

                        TextButton(
                          onPressed:
                              envoiEnCours
                                  ? null
                                  : () {
                                      setModalState(
                                        () {
                                          resultat =
                                              null;
                                          erreurLocale =
                                              null;
                                        },
                                      );
                                    },
                          child:
                              Text(s.changer),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                Text(
                  s.niveauAccesLabel,
                  style: AppTextStyles.label,
                ),

                const SizedBox(height: 8),

                RadioListTile<
                    DroitDelegation>(
                  contentPadding:
                      EdgeInsets.zero,
                  value:
                      DroitDelegation.lecture,
                  groupValue: droit,
                  title: Text(
                    s.droitLectureSeuleTitre,
                  ),
                  subtitle: Text(
                    s.droitLectureSeuleDesc,
                  ),
                  onChanged:
                      envoiEnCours
                          ? null
                          : (v) {
                              setModalState(
                                () => droit = v!,
                              );
                            },
                ),

                RadioListTile<
                    DroitDelegation>(
                  contentPadding:
                      EdgeInsets.zero,
                  value: DroitDelegation
                      .lectureEtPaiement,
                  groupValue: droit,
                  title: Text(
                    s.droitLecturePaiementTitre,
                  ),
                  subtitle: Text(
                    s.droitLecturePaiementDesc,
                  ),
                  onChanged:
                      envoiEnCours
                          ? null
                          : (v) {
                              setModalState(
                                () => droit = v!,
                              );
                            },
                ),

                if (erreurLocale != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    erreurLocale!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        resultat == null ||
                                envoiEnCours
                            ? null
                            : confirmer,
                    child: Text(
                      envoiEnCours
                          ? s.envoiEnCours
                          : s.contratsConfirmerDelegationBouton,
                    ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

class _CompteurDeContratTile
    extends StatelessWidget {
  final CompteurModel compteur;

  const _CompteurDeContratTile({
    required this.compteur,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Padding(
      padding:
          const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary
                    .withOpacity(0.12),
                borderRadius:
                    BorderRadius.circular(12),
              ),
              child: Icon(
                compteur.type ==
                        TypeCompteur.prepaye
                    ? Icons.flash_on
                    : Icons.receipt_long,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    compteur.numero,
                    style: AppTextStyles.label,
                  ),
                  Text(
                    compteur.adresse.isNotEmpty
                        ? compteur.adresse
                        : s.adresseNonDisponible,
                    style:
                        AppTextStyles.caption,
                  ),
                ],
              ),
            ),

            StatusBadge(
              label: compteur.statutLabel,
            ),
          ],
        ),
      ),
    );
  }
}

class _DelegationContratTile
    extends StatelessWidget {
  final DelegationModel delegation;
  final VoidCallback onRevoke;

  const _DelegationContratTile({
    required this.delegation,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Padding(
      padding:
          const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding:
            const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  AppColors.surface,
              child: Text(
                delegation.nomTiers.isNotEmpty
                    ? delegation.nomTiers[0]
                    : '?',
                style: const TextStyle(
                  color:
                      AppColors.primaryDark,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    delegation.nomTiers,
                    style:
                        AppTextStyles.label,
                  ),
                  Text(
                    delegation.droitLabel,
                    style:
                        AppTextStyles.caption,
                  ),
                ],
              ),
            ),

            IconButton(
              onPressed: onRevoke,
              icon: const Icon(
                Icons.close,
                color: AppColors.danger,
                size: 20,
              ),
              tooltip: s.revoquer,
            ),
          ],
        ),
      ),
    );
  }
}