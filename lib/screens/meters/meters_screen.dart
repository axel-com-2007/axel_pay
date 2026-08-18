// ============================================================
// ÉCRAN "TOUS MES COMPTEURS" (VUE GLOBALE, TOUS CONTRATS CONFONDUS)
// ============================================================
// REFONTE v1.5 (backend) : un compteur DOIT désormais être rattaché à un
// contrat existant (FK NOT NULL) — le rattachement d'un nouveau compteur
// se fait donc depuis l'écran d'un contrat précis (voir
// `screens/contracts/contracts_screen.dart` -> ContratDetailScreen), plus
// depuis cet écran, qui redevient une simple vue de consultation
// transverse (utile dès qu'on a plusieurs contrats) + gestion des
// délégations à portée "compteur".
//
// Branché sur GET /profile/, GET /compteurs/, GET /delegations/,
// POST /delegations/<id>/revoquer/.
//
// CORRECTIF (24/07/2026) : la délégation "par numéro de téléphone" est
// désormais branchée de bout en bout — voir `_ouvrirDelegation` :
// `EneoRepository.rechercherUtilisateurParTelephone()` résout le tiers
// (nom + prénom masqué affichés pour confirmation), puis
// `EneoRepository.createDelegation()` crée la délégation avec l'`id_user`
// ainsi résolu.
// ============================================================

import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_badge.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_loader.dart';
import '../../l10n/app_strings.dart';

class MetersScreen extends StatefulWidget {
  const MetersScreen({super.key});

  @override
  State<MetersScreen> createState() => _MetersScreenState();
}

class _MetersScreenState extends State<MetersScreen> {
  final _repo = EneoRepository();

  late Future<void> _chargement;
  UserModel? user;
  List<CompteurModel> compteurs = [];
  List<DelegationModel> delegations = [];
  String? erreur;

  /// `true` si le profil ou la liste des compteurs vient du cache local
  /// plutôt que du réseau (§7.6). Les délégations (`getDelegations`) ne
  /// sont pas mises en cache — cf. `EneoRepository.getDelegations`, qui
  /// renvoie une `List` brute, pas un `CachedResult` — donc elles
  /// n'entrent pas dans ce calcul.
  bool horsLigne = false;
  DateTime? derniereSynchro;

  @override
  void initState() {
    super.initState();
    _chargement = _charger();
  }

  Future<void> _charger() async {
    setState(() => erreur = null);
    try {
      final profileFuture = _repo.getProfile();
      final compteursFuture = _repo.getCompteurs();
      final delegationsFuture = _repo.getDelegations();
      final profil = await profileFuture;
      final listeCompteurs = await compteursFuture;
      final listeDelegations = await delegationsFuture;
      final synchro = [profil.syncedAt, listeCompteurs.syncedAt]..sort();
      setState(() {
        user = profil.data;
        compteurs = listeCompteurs.data;
        delegations = listeDelegations;
        horsLigne = profil.isFromCache || listeCompteurs.isFromCache;
        derniereSynchro = synchro.first;
      });
    } on ApiException catch (e) {
      setState(() => erreur = e.message);
    } catch (_) {
      setState(() => erreur = S.read(context).uneErreurEstSurvenue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return FutureBuilder<void>(
      future: _chargement,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: const [
              ShimmerBox(height: 60, borderRadius: BorderRadius.all(Radius.circular(16))),
              SizedBox(height: 28),
              ShimmerBox(width: 150, height: 18),
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
                    child: Text(s.reessayer),
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
              _buildEnTeteProfil(s),
              if (horsLigne) ...[
                const SizedBox(height: 16),
                OfflineBanner(derniereSynchro: derniereSynchro, margin: EdgeInsets.zero),
              ],
              const SizedBox(height: 28),
              SectionHeader(title: s.metersMesCompteursTitre(compteurs.length)),
              const SizedBox(height: 4),
              Text(
                s.metersRattacherNouveauCompteurHint,
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 12),
              if (compteurs.isEmpty)
                AppCard(
                  child: EmptyStateLottie(
                    asset: LottieAssets.girlSayHi,
                    title: s.metersAucunCompteurRattache,
                    size: 100,
                  ),
                )
              else
                ...compteurs.asMap().entries.map((entry) => FadeSlideIn(
                      index: entry.key,
                      child: _CompteurTile(
                        compteur: entry.value,
                        onDelegate: () => _ouvrirDelegation(entry.value),
                      ),
                    )),
              const SizedBox(height: 28),
              SectionHeader(title: s.metersAccesDelegues),
              const SizedBox(height: 8),
              Text(
                s.metersPersonnesAyantRecuAcces,
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 12),
              if (delegations.isEmpty)
                AppCard(
                  child: EmptyStateLottie(
                    asset: LottieAssets.search,
                    title: s.metersAucuneDelegationActive,
                    size: 100,
                  ),
                )
              else
                ...delegations.asMap().entries.map((entry) => FadeSlideIn(
                      index: entry.key,
                      child: _DelegationTile(
                        delegation: entry.value,
                        onRevoke: () => _revoquer(entry.value),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEnTeteProfil(S s) {
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: AppColors.surface,
          child: Text(
            user?.initiales ?? '',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text((user?.nomComplet ?? '').toUpperCase(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(user?.email ?? '', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 2),
        Text(user?.telephone ?? '', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          children: [
            _ProfileLink(
              label: s.metersModifierMonProfil,
              onTap: () => _showSnack(S.read(context).metersRendezVousParametres),
            ),
            _ProfileLink(
              label: s.metersChangerDeMotDePasse,
              onTap: () => _showSnack(S.read(context).metersReAuthentificationRequise),
            ),
          ],
        ),
      ],
    );
  }

  void _revoquer(DelegationModel d) async {
    final s = S.read(context);
    final confirme = await AppDialog.confirm(
      context: context,
      title: s.revoquerCetAccesTitre,
      message: s.metersPerdImmediatementAccesCompteur(d.nomTiers),
      confirmLabel: s.revoquer,
      danger: true,
    );
    if (confirme != true) return;
    try {
      await _repo.revokeDelegation(d.id);
      setState(() => delegations.remove(d));
    } on ApiException catch (e) {
      _showSnack(e.message);
    }
  }

  void _ouvrirDelegation(CompteurModel compteur) {
    final phoneController = TextEditingController();
    DroitDelegation droit = DroitDelegation.lecture;

    // État local de la recherche : tant que `resultat` est null, on est en
    // phase "saisie du téléphone" ; une fois un utilisateur trouvé, on passe
    // en phase "confirmation" (nom + prénom masqué) avant d'envoyer la
    // délégation. `rechercheEnCours`/`envoiEnCours` pilotent les spinners,
    // `erreurLocale` les messages d'erreur inline (téléphone introuvable,
    // erreur réseau, etc.).
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
            final sRead = S.read(ctx);
            final telephone = phoneController.text.trim();
            if (telephone.isEmpty) {
              setModalState(() => erreurLocale = sRead.metersSaisirNumeroTelephone);
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
                  erreurLocale = sRead.metersAucunUtilisateurTrouve;
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
                erreurLocale = sRead.uneErreurEstSurvenue;
              });
            }
          }

          Future<void> confirmer() async {
            final sRead = S.read(ctx);
            final trouve = resultat;
            final idCompteur = int.tryParse(compteur.id);
            if (trouve == null || idCompteur == null) return;
            setModalState(() {
              envoiEnCours = true;
              erreurLocale = null;
            });
            try {
              await _repo.createDelegation(
                idUserTiers: trouve.idUser,
                idCompteur: idCompteur,
                droit: droit,
                cibleLabel: compteur.numero,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _showSnack(sRead.metersDelegationAccordeeA('${trouve.nom} ${trouve.prenomMasque}'));
              _charger();
            } on ApiException catch (e) {
              setModalState(() {
                envoiEnCours = false;
                erreurLocale = e.message;
              });
            } catch (_) {
              setModalState(() {
                envoiEnCours = false;
                erreurLocale = sRead.uneErreurEstSurvenue;
              });
            }
          }

          final s = S.of(ctx);
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
                Text(s.metersDelegerAccesTitre(compteur.numero), style: AppTextStyles.h3),
                const SizedBox(height: 14),
                Text(s.numeroTelephoneTiersLabel, style: AppTextStyles.label),
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
                            : Text(s.rechercher),
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
                            s.tiersTrouve('${resultat!.nom} ${resultat!.prenomMasque}'),
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
                          child: Text(s.changer),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(s.niveauAccesLabel, style: AppTextStyles.label),
                const SizedBox(height: 8),
                RadioListTile<DroitDelegation>(
                  contentPadding: EdgeInsets.zero,
                  value: DroitDelegation.lecture,
                  groupValue: droit,
                  title: Text(s.droitLectureSeuleTitre),
                  subtitle: Text(s.droitLectureSeuleDesc),
                  onChanged: envoiEnCours ? null : (v) => setModalState(() => droit = v!),
                ),
                RadioListTile<DroitDelegation>(
                  contentPadding: EdgeInsets.zero,
                  value: DroitDelegation.lectureEtPaiement,
                  groupValue: droit,
                  title: Text(s.droitLecturePaiementTitre),
                  subtitle: Text(s.droitLecturePaiementDesc),
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
                    child: Text(envoiEnCours ? s.envoiEnCours : s.contratsConfirmerDelegationBouton),
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

class _ProfileLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ProfileLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.secondary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _CompteurTile extends StatelessWidget {
  final CompteurModel compteur;
  final VoidCallback onDelegate;

  const _CompteurTile({required this.compteur, required this.onDelegate});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    compteur.type == TypeCompteur.prepaye
                        ? Icons.flash_on
                        : Icons.receipt_long,
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
                        compteur.adresse.isNotEmpty ? compteur.adresse : s.adresseNonDisponible,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                StatusBadge(label: compteur.statutLabel),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  compteur.numeroContrat != null
                      ? '${compteur.typeLabel} · Contrat ${compteur.numeroContrat}'
                      : compteur.typeLabel,
                  style: AppTextStyles.bodyMuted,
                ),
                TextButton.icon(
                  onPressed: onDelegate,
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: Text(s.metersDelegerBouton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DelegationTile extends StatelessWidget {
  final DelegationModel delegation;
  final VoidCallback onRevoke;

  const _DelegationTile({required this.delegation, required this.onRevoke});

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
                  Text(
                    delegation.telephoneTiers.isNotEmpty
                        ? '${delegation.telephoneTiers} · ${delegation.droitLabel}'
                        : delegation.droitLabel,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRevoke,
              icon: const Icon(Icons.close, color: AppColors.danger, size: 20),
              tooltip: S.of(context).revoquer,
            ),
          ],
        ),
      ),
    );
  }
}
