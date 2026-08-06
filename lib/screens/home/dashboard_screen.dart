// ============================================================
// TABLEAU DE BORD PRINCIPAL / ACCUEIL (MULTI-CONTRATS)
// ============================================================
// REFONTE v2 — reprend fidèlement la maquette "page_d_accueil" (AxelPay) :
//  - Bulle de bienvenue bleue "Bonjour, {prénom}" + cloche de
//    notification + avatar rond
//  - Chips horizontales de sélection de contrat + barre de recherche
//    avec icône de filtre
//  - Carte de statut blanche : titre + badge de statut, montant,
//    boîte grise "Dernière mise à jour" / "Autonomie estimée", bouton
//    plein "Payer la facture maintenant" / "Recharger", grille de 4
//    raccourcis (Voir les factures / Historique des paiements /
//    Télécharger reçu / Activer rappel)
//  - Section "Accès rapide" : bandeau bleu pâle promotionnel avec
//    illustration décorative
//
// REFONTE — les compteurs cèdent la place aux contrats sur l'accueil
// (RG métier : un contrat peut avoir plusieurs compteurs, mais un seul
// est ACTIF à la fois — le sélecteur de compteurs faisait donc doublon
// avec le sélecteur de contrats) :
//  - Au chargement, les 3 contrats les plus récents du client sont
//    affichés (moins de 3 s'il en a moins).
//  - Sélectionner un contrat charge son compteur ACTIF, qui alimente la
//    carte de statut (solde, type prépayé/postpayé, actions "Payer" /
//    "Recharger").
//  - Si le client a plus de 3 contrats, une barre de recherche par
//    numéro de contrat permet d'en afficher un directement, sans le
//    faire défiler dans une longue liste (RG UX de fluidité).
//  - Indicateur de fraîcheur des données (mode hors-ligne)
//
// Branché sur le backend via EneoRepository (lib/data/eneo_repository.dart) :
// GET /profile/, GET /contrats/(?search=), GET /contrats/<id>/compteurs/
// (+ enrichissement adresse/solde/jeton du compteur actif).
// ============================================================

import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/connectivity_gate.dart';
import '../../data/contrat_selection.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_badge.dart';
import '../../shared/widgets/app_loader.dart';
import '../contracts/contracts_screen.dart';
import '../payment/payment_screen.dart';
import '../postpaid/postpaid_screen.dart';
import '../prepaid/prepaid_screen.dart';
import '../settings/settings_screen.dart';
import '../support/support_screen.dart';
import 'calendar_history_screen.dart';
import 'contract_search_overlay.dart';

/// Nombre de contrats affichés d'emblée sur l'accueil (les plus récents).
/// Au-delà, la barre de recherche par numéro de contrat prend le relais.
const int _apercuContratsAccueil = 3;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _repo = EneoRepository();
  final _rechercheController = TextEditingController();

  late Future<void> _chargement;
  UserModel? user;

  /// Aperçu : les 3 contrats les plus récents (ou moins s'il y en a moins).
  List<ContratModel> contrats = [];

  /// Nombre total de contrats du client — sert à savoir s'il faut afficher
  /// la barre de recherche (> 3 contrats).
  int totalContrats = 0;

  ContratModel? contratActif;
  CompteurModel? compteurActif;

  /// Facture impayée à l'échéance la plus proche du compteur POSTPAYÉ
  /// actif. Chargée en complément du compteur (endpoint séparé) pour
  /// afficher une vraie "Échéance estimée" dans la boîte d'infos — cette
  /// donnée n'existe qu'au niveau facture, jamais au niveau compteur.
  /// `null` en prépayé, ou si aucune facture impayée n'a pu être chargée.
  FactureModel? _factureUrgentePostpaye;

  /// Dernière facture payée du compteur postpayé actif, si disponible :
  /// permet au raccourci "Télécharger reçu" d'agir directement sur cette
  /// facture précise plutôt que de rediriger vers l'écran Postpayé.
  FactureModel? _dernierRecuDisponible;

  String? erreur;
  String? erreurRecherche;
  bool rechercheEnCours = false;

  /// `true` si les données affichées viennent du cache local plutôt que
  /// du réseau (§7.6) — pilote le bandeau "Mode hors connexion".
  bool horsLigne = false;
  DateTime? derniereSynchro;

  @override
  void initState() {
    super.initState();
    _chargement = _charger();
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => erreur = null);
    try {
      final profileFuture = _repo.getProfile();
      final apercuFuture = _repo.getContratsApercu(limit: _apercuContratsAccueil);
      final u = await profileFuture;
      final apercu = await apercuFuture;
      // Hors-ligne (§7.6) si AU MOINS une des deux lectures vient du
      // cache local plutôt que du réseau ; on affiche la synchro la plus
      // ancienne des deux, plus prudente qu'une moyenne pour indiquer à
      // l'utilisateur jusqu'où remonte la donnée la moins fraîche visible
      // à l'écran.
      final estHorsLigne = u.isFromCache || apercu.isFromCache;
      final synchro = [u.syncedAt, apercu.syncedAt]..sort();

      // REFONTE — un contrat choisi depuis la page "Contrats" doit
      // remplacer l'aperçu habituel : "le contrat actuel + les 2 plus
      // proches en date" plutôt que "les 3 plus récents".
      final externe = ContratSelectionExterne.enAttente;
      List<ContratModel> contratsAffiches = apercu.data.contrats;
      ContratModel? contratAOuvrir = contratsAffiches.isNotEmpty ? contratsAffiches.first : null;

      if (externe != null) {
        ContratSelectionExterne.enAttente = null;
        try {
          final tous = await _repo.getAllContrats();
          contratsAffiches = _contratsProches(externe, tous);
          contratAOuvrir = externe;
        } catch (_) {
          // Repli silencieux : on garde l'aperçu habituel si le calcul
          // des contrats les plus proches échoue (ex: hors-ligne).
        }
      }

      setState(() {
        user = u.data;
        totalContrats = apercu.data.total;
        contrats = contratsAffiches;
        horsLigne = estHorsLigne;
        derniereSynchro = synchro.first;
      });
      if (contratAOuvrir != null) {
        await _selectionnerContrat(contratAOuvrir);
      }
    } on ApiException catch (e) {
      setState(() => erreur = e.message);
    } catch (e) {
      setState(() => erreur = 'Une erreur est survenue. Vérifiez votre connexion.');
    }
  }

  /// [contratActuel] + les 2 contrats dont la date de création est la
  /// plus proche de la sienne, parmi [tous] les contrats du client —
  /// remplace l'aperçu "3 plus récents" quand on arrive d'un contrat
  /// choisi sur la page Contrats.
  List<ContratModel> _contratsProches(ContratModel contratActuel, List<ContratModel> tous) {
    final autres = tous.where((c) => c.id != contratActuel.id).toList()
      ..sort((a, b) {
        final diffA = a.dateCreation.difference(contratActuel.dateCreation).abs();
        final diffB = b.dateCreation.difference(contratActuel.dateCreation).abs();
        return diffA.compareTo(diffB);
      });
    return [contratActuel, ...autres.take(2)];
  }

  /// Sélectionne un contrat et charge son compteur ACTIF (celui qui
  /// alimente la carte de statut). Utilisé aussi bien pour un contrat de
  /// l'aperçu que pour un résultat de recherche.
  Future<void> _selectionnerContrat(ContratModel contrat) async {
    setState(() {
      contratActif = contrat;
      compteurActif = null;
      _factureUrgentePostpaye = null;
      _dernierRecuDisponible = null;
    });
    try {
      final result = await _repo.getCompteurActifDuContrat(contrat);
      if (!mounted) return;
      setState(() {
        compteurActif = result.data;
        // Ne "dégrade" jamais horsLigne de true vers false ici : si le
        // profil/aperçu de contrats était déjà servi depuis le cache,
        // sélectionner un contrat qui, lui, a pu être rafraîchi entre
        // temps ne doit pas faire disparaître le bandeau tant que
        // l'ensemble de l'écran n'a pas été rechargé via _charger().
        horsLigne = horsLigne || result.isFromCache;
        if (result.isFromCache && (derniereSynchro == null || result.syncedAt.isBefore(derniereSynchro!))) {
          derniereSynchro = result.syncedAt;
        }
      });
      final compteurCharge = result.data;
      if (compteurCharge != null && compteurCharge.type == TypeCompteur.postpaye) {
        await _chargerFacturesPostpaye(compteurCharge);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    }
  }

  /// Charge les factures du compteur postpayé actif pour en extraire :
  ///  - la facture impayée à l'échéance la plus proche (→ "Échéance
  ///    estimée" dans la boîte d'infos, symétrique de l'autonomie
  ///    estimée en prépayé) ;
  ///  - la dernière facture payée disponible (→ téléchargement de reçu
  ///    direct depuis l'accueil pour "Télécharger reçu").
  /// Best-effort et silencieux : un échec ici (ex: hors-ligne sans cache
  /// facture) ne doit jamais casser l'affichage du compteur déjà chargé,
  /// donc on se contente de laisser les deux champs à `null`.
  Future<void> _chargerFacturesPostpaye(CompteurModel compteur) async {
    final idCompteur = int.tryParse(compteur.id);
    if (idCompteur == null) return;
    try {
      final result = await _repo.getFactures(idCompteur);
      if (!mounted) return;
      final impayees = result.data.where((f) => f.statut == StatutFacture.impayee).toList()
        ..sort((a, b) => a.dateLimite.compareTo(b.dateLimite));
      final payees = result.data.where((f) => f.statut == StatutFacture.payee).toList()
        ..sort((a, b) => b.dateLimite.compareTo(a.dateLimite));
      setState(() {
        _factureUrgentePostpaye = impayees.isNotEmpty ? impayees.first : null;
        _dernierRecuDisponible = payees.isNotEmpty ? payees.first : null;
      });
    } catch (_) {
      // Silencieux : voir note ci-dessus.
    }
  }

  Future<void> _rechercherContrat() async {
    final numero = _rechercheController.text.trim();
    if (numero.isEmpty) return;
    setState(() {
      rechercheEnCours = true;
      erreurRecherche = null;
    });
    try {
      final resultats = await _repo.getContrats(search: numero);
      if (!mounted) return;
      if (resultats.isEmpty) {
        setState(() {
          rechercheEnCours = false;
          erreurRecherche = 'Aucun contrat ne correspond au numéro « $numero ».';
        });
        return;
      }
      setState(() => rechercheEnCours = false);
      await _selectionnerContrat(resultats.first);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        rechercheEnCours = false;
        erreurRecherche = e.message;
      });
    }
  }

  /// Filtre de la barre de recherche : on choisit d'abord le critère de
  /// tri (date d'ancienneté, ou montant croissant/décroissant), puis la
  /// page Contrats s'ouvre déjà triée — c'est là que le tri est
  /// réellement implémenté et affiché.
  Future<void> _ouvrirTriContrats() async {
    final choix = await ContratSortSheet.choose(context);
    if (choix == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContractsScreen(initialSort: choix)),
    );
  }

  /// Ouvre le calendrier en overlay (fond flouté), puis, une fois une
  /// date choisie, la page à 3 options d'historique (transactions /
  /// factures / consommation) pour le compteur actuellement affiché.
  Future<void> _ouvrirCalendrierHistorique() async {
    final compteur = compteurActif;
    if (compteur == null) {
      _showSnack('Chargement du compteur actif en cours…');
      return;
    }
    final date = await CalendarOverlay.pick(context);
    if (date == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HistoryOptionsScreen(compteur: compteur, dateChoisie: date),
      ),
    );
  }

  /// Clic sur la loupe : ouvre l'overlay de recherche étendue (fond
  /// flouté, 8 contrats suggérés). Le contrat choisi devient le contrat
  /// affiché en page d'accueil ; l'overlay se referme et l'accueil
  /// revient à son état normal.
  Future<void> _ouvrirRechercheEtendue() async {
    final choisi = await ContractSearchOverlay.show(context);
    if (choisi == null || !mounted) return;
    await _selectionnerContrat(choisi);
  }

  /// Bouton principal de la carte de statut : "Recharger maintenant" en
  /// prépayé (inchangé), "Payer la facture maintenant" en postpayé.
  ///
  /// REFONTE — ce dernier ouvre désormais DIRECTEMENT l'écran de
  /// paiement sur la facture impayée la plus urgente
  /// (`_factureUrgentePostpaye`, déjà chargée en même temps que le
  /// compteur actif), au lieu de passer par la liste des factures. Si
  /// cette facture n'a pas encore fini de charger, ou qu'aucune facture
  /// impayée n'a pu être trouvée, on retombe honnêtement sur la liste
  /// des factures plutôt que d'inventer un montant.
  Future<void> _boutonPrincipalAppuye(CompteurModel c) async {
    if (estPrepaye) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentScreen(compteur: c, montantSuggere: 5000),
        ),
      );
      return;
    }
    final facture = _factureUrgentePostpaye;
    if (facture == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostpaidScreen(compteur: c)),
      );
      return;
    }
    final connecte = await ConnectivityGate.hasConnection;
    if (!connecte) {
      if (!mounted) return;
      _showSnack('Vous êtes hors connexion. Le paiement d’une facture nécessite une connexion active.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          compteur: c,
          montantSuggere: facture.montantFcfa,
          factureId: facture.id,
        ),
      ),
    );
  }

  bool get estPrepaye => compteurActif?.type == TypeCompteur.prepaye;

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _chargement,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildSquelette();
        }
        if (erreur != null) {
          return _buildErreur();
        }
        if (contratActif == null) {
          return _buildAucunContrat();
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => setState(() => _chargement = _charger()),
          child: _buildContenu(),
        );
      },
    );
  }

  /// Squelette Shimmer affiché pendant le chargement initial (profil +
  /// compteurs), pour éviter l'écran blanc suivi d'un saut brutal de
  /// contenu.
  Widget _buildSquelette() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: const [
        ShimmerBox(width: 220, height: 70, borderRadius: BorderRadius.all(Radius.circular(18))),
        SizedBox(height: 20),
        ShimmerBox(height: 40, borderRadius: BorderRadius.all(Radius.circular(22))),
        SizedBox(height: 20),
        ShimmerCard(titleWidth: 160),
        SizedBox(height: 24),
        ShimmerBox(width: 120, height: 16),
        SizedBox(height: 12),
        ShimmerBox(height: 120, borderRadius: BorderRadius.all(Radius.circular(24))),
      ],
    );
  }

  Widget _buildErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
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

  Widget _buildAucunContrat() {
    return const EmptyStateLottie(
      asset: LottieAssets.girlSayHi,
      title: 'Aucun contrat rattaché',
      subtitle: 'Ouvrez l’onglet "Contrats" pour ajouter votre premier contrat.',
    );
  }

  Widget _buildContenu() {
    final compteurSuspendu = compteurActif != null && !compteurActif!.actif;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildEnTete()),
        if (horsLigne) SliverToBoxAdapter(child: OfflineBanner(derniereSynchro: derniereSynchro)),
        SliverToBoxAdapter(child: _buildSelecteurContrats()),
        if (totalContrats > _apercuContratsAccueil)
          SliverToBoxAdapter(child: _buildRechercheContrat()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeSlideIn(index: 0, child: _buildCarteStatutPrincipale()),
                const SizedBox(height: 24),
                if (compteurSuspendu) ...[
                  FadeSlideIn(index: 1, child: _buildAlerteSuspendu()),
                  const SizedBox(height: 24),
                ],
                FadeSlideIn(index: 2, child: const SectionHeader(title: 'Accès rapide')),
                const SizedBox(height: 12),
                FadeSlideIn(index: 3, child: _buildAccesRapidePromo()),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// Bulle de bienvenue turquoise + avatar, fidèle à la maquette d'accueil.
  Widget _buildEnTete() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: CustomPaint(
              painter: _SpeechBubblePainter(color: AppColors.primary),
              child: Padding(
                // REFONTE : padding droit resserré (18 -> 14) pour laisser
                // la place à l'icône assistance ajoutée à côté de la
                // cloche, sans que la bulle "Bonjour" ne pousse les icônes
                // hors de l'écran sur les petits appareils.
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bonjour, ${user?.prenom ?? ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Voici la situation de vos contrats',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AssistanceButton(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SupportScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _NotificationBell(
                    onTap: () => _showSnack('Aucune nouvelle notification pour le moment.'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  user?.initiales ?? '',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Aperçu des 3 contrats les plus récents (ou moins) — remplace
  /// l'ancien sélecteur de compteurs : un contrat sélectionné charge
  /// automatiquement son compteur ACTIF pour la carte de statut.
  Widget _buildSelecteurContrats() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: contrats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final ct = contrats[index];
          final selected = contratActif != null && ct.id == contratActif!.id;
          return ChoiceChip(
            label: Text(ct.numeroContrat),
            selected: selected,
            onSelected: (_) {
              if (!selected) _selectionnerContrat(ct);
            },
            selectedColor: AppColors.primary.withOpacity(0.16),
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primaryDark : AppColors.textSecondary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
            ),
          );
        },
      ),
    );
  }

  /// N'apparaît que si le client a plus de 3 contrats (RG UX) : recherche
  /// le numéro de contrat directement en base côté serveur
  /// (`GET /contrats/?search=`) et affiche le résultat sur cet écran,
  /// sans passer par l'onglet "Contrats".
  Widget _buildRechercheContrat() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _rechercheController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _rechercherContrat(),
            decoration: InputDecoration(
              hintText: 'Rechercher un numéro de contrat',
              filled: true,
              fillColor: AppColors.white,
              prefixIcon: IconButton(
                tooltip: 'Recherche étendue',
                icon: const Icon(Icons.search, color: AppColors.textMuted),
                onPressed: _ouvrirRechercheEtendue,
              ),
              suffixIcon: rechercheEnCours
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: AppLoader.small(),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 1, height: 20, color: AppColors.divider),
                          IconButton(
                            tooltip: 'Trier les contrats',
                            icon: const Icon(Icons.tune_rounded, color: AppColors.primaryDark),
                            onPressed: _ouvrirTriContrats,
                          ),
                        ],
                      ),
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (erreurRecherche != null) ...[
            const SizedBox(height: 6),
            Text(erreurRecherche!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  /// En-tête basé sur le CONTRAT sélectionné (numéro, statut) ; les
  /// données financières (solde, type prépayé/postpayé...) viennent de
  /// son compteur ACTIF, chargé de façon asynchrone après la sélection —
  /// d'où le loader tant que [compteurActif] est `null`.
  Widget _buildCarteStatutPrincipale() {
    final contrat = contratActif!;
    final c = compteurActif;
    return AppCard(
      color: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contrat ${contrat.numeroContrat}', style: AppTextStyles.h2),
                    const SizedBox(height: 4),
                    Text(
                      c != null
                          ? (c.adresse.isNotEmpty ? c.adresse : 'Adresse non disponible')
                          : 'Chargement du compteur actif…',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              StatusBadge(label: contrat.statutLabel),
            ],
          ),
          const SizedBox(height: 18),
          if (c == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: LottieLoader(size: 56)),
            )
          else ...[
            if (estPrepaye) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedCounter(
                    value: c.soldeKwh ?? 0,
                    formatter: (v) => '${v.toStringAsFixed(1)} kWh',
                    style: AppTextStyles.h1,
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      c.soldeFcfaEquivalent != null
                          ? '≈ ${formatFcfa(c.soldeFcfaEquivalent!)}'
                          : '≈ montant non disponible',
                      style: AppTextStyles.bodyMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                c.joursAutonomieEstimes != null
                    ? 'Autonomie estimée : ${c.joursAutonomieEstimes} jours'
                    : 'Autonomie estimée : non disponible',
                style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600),
              ),
            ] else ...[
              AnimatedCounter(
                value: c.soldeDuFcfa ?? 0,
                formatter: (v) => formatFcfa(v),
                style: AppTextStyles.h1,
              ),
              const SizedBox(height: 6),
              const Text('Montant dû sur les factures impayées', style: AppTextStyles.bodyMuted),
            ],
            const SizedBox(height: 16),
            _buildBoiteInfos(c),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => _boutonPrincipalAppuye(c),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(estPrepaye ? Icons.flash_on : Icons.receipt_long, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      estPrepaye ? 'Recharger maintenant' : 'Payer la facture maintenant',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildActionsRapidesGrille(c),
          ],
        ],
      ),
    );
  }

  /// Boîte grise arrondie reprenant les infos de fraîcheur des données,
  /// fidèle à la maquette d'accueil (icône + libellé + valeur, séparateur
  /// vertical entre deux blocs). En prépayé, le second bloc reprend
  /// l'autonomie estimée déjà calculée côté backend ; en postpayé, faute
  /// d'échéance de facture chargée sur cet écran (donnée disponible
  /// uniquement écran "Factures"), seule la fraîcheur de mise à jour est
  /// affichée, sur toute la largeur — on évite ainsi d'inventer une
  /// échéance fictive.
  Widget _buildBoiteInfos(CompteurModel c) {
    final maj = c.derniereMiseAJour;
    final maintenant = DateTime.now();
    final memeJour = maintenant.year == maj.year &&
        maintenant.month == maj.month &&
        maintenant.day == maj.day;
    final heure =
        '${maj.hour.toString().padLeft(2, '0')}:${maj.minute.toString().padLeft(2, '0')}';
    // `freshnessLabel` inclut déjà le préfixe "Dernière mise à jour :" —
    // on ne garde que la partie relative ("il y a X h/j") pour éviter la
    // répétition avec le libellé de la boîte ci-dessous.
    final majValeur = memeJour
        ? 'Aujourd’hui • $heure'
        : c.freshnessLabel(maintenant).replaceFirst('Dernière mise à jour : ', '');

    final majBloc = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.field),
      onTap: _ouvrirCalendrierHistorique,
      child: _InfoBoiteItem(
        icon: Icons.calendar_today_rounded,
        iconColor: AppColors.primary,
        label: 'Dernière mise à jour',
        value: majValeur,
      ),
    );

    Widget? secondBloc;
    if (estPrepaye) {
      secondBloc = _InfoBoiteItem(
        icon: Icons.bolt_rounded,
        iconColor: AppColors.secondaryGreenDark,
        label: 'Autonomie estimée',
        value: c.joursAutonomieEstimes != null ? '${c.joursAutonomieEstimes} jours' : 'Non disponible',
      );
    } else if (_factureUrgentePostpaye != null) {
      // Donnée réelle (facture la plus urgente), et non un chiffre
      // inventé : cf. note de la tâche "Échéance estimée en postpayé".
      final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
      final echeance = _factureUrgentePostpaye!.dateLimite;
      final diffJours = DateTime(echeance.year, echeance.month, echeance.day).difference(aujourdhui).inDays;
      final enRetard = diffJours < 0;
      final echeanceValeur = enRetard
          ? 'Il y a ${-diffJours} jour${-diffJours > 1 ? 's' : ''}'
          : diffJours == 0
              ? 'Aujourd’hui'
              : 'Dans $diffJours jour${diffJours > 1 ? 's' : ''}';
      secondBloc = _InfoBoiteItem(
        icon: Icons.access_time_rounded,
        iconColor: enRetard ? AppColors.danger : AppColors.secondaryGreenDark,
        label: 'Échéance estimée',
        value: echeanceValeur,
        valueColor: enRetard ? AppColors.danger : null,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.divider),
      ),
      child: secondBloc == null
          ? majBloc
          : Row(
              children: [
                Expanded(child: majBloc),
                Container(width: 1, height: 34, color: AppColors.divider),
                const SizedBox(width: 14),
                Expanded(child: secondBloc),
              ],
            ),
    );
  }

  /// Grille des 4 raccourcis d'action, à l'intérieur de la carte de
  /// statut, fidèle à la maquette : icône dans un carré blanc bordé +
  /// libellé en dessous.
  Widget _buildActionsRapidesGrille(CompteurModel? c) {
    void ouvrirEcranContrat() {
      if (c == null) {
        _showSnack('Chargement du compteur actif en cours…');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => estPrepaye ? PrepaidScreen(compteur: c) : PostpaidScreen(compteur: c),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _ActionRapideItem(
            icon: Icons.description_outlined,
            label: 'Voir les\nfactures',
            onTap: ouvrirEcranContrat,
          ),
        ),
        Expanded(
          child: _ActionRapideItem(
            icon: Icons.bar_chart_rounded,
            label: 'Historique des\npaiements',
            onTap: ouvrirEcranContrat,
          ),
        ),
        Expanded(
          child: _ActionRapideItem(
            icon: Icons.file_download_outlined,
            label: 'Télécharger\nreçu',
            onTap: () => _telechargerDernierRecu(c),
          ),
        ),
        Expanded(
          child: _ActionRapideItem(
            icon: Icons.notifications_none_rounded,
            label: 'Activer\nrappel',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(ouvrirNotificationsAuDemarrage: true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tente un téléchargement direct du reçu de la dernière facture payée
  /// (`_dernierRecuDisponible`, chargée en même temps que le compteur
  /// postpayé actif). Repli honnête si l'info n'est pas disponible
  /// (compteur prépayé, ou aucune facture payée trouvée) : on retombe sur
  /// la navigation vers l'écran dédié plutôt que d'inventer un reçu.
  Future<void> _telechargerDernierRecu(CompteurModel? c) async {
    if (c == null) {
      _showSnack('Chargement du compteur actif en cours…');
      return;
    }
    if (estPrepaye || _dernierRecuDisponible == null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => estPrepaye ? PrepaidScreen(compteur: c) : PostpaidScreen(compteur: c),
        ),
      );
      return;
    }
    _showSnack('Préparation du reçu…');
    try {
      // ⚠️ Comme dans PostpaidScreen._telechargerRecu : le PDF n'est pas
      // encore généré côté serveur (stub JSON), donc on ne simule pas un
      // téléchargement qui n'existe pas — même message honnête ici.
      await _repo.getFactureRecu(_dernierRecuDisponible!.id);
      if (!mounted) return;
      _showSnack(
        'Le reçu a été retrouvé côté serveur, mais la génération du PDF '
        'téléchargeable n’est pas encore disponible dans cette version.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    }
  }

  /// Bloc promotionnel "Accès rapide", fidèle à la maquette d'accueil :
  /// carte bleu pâle avec titre, sous-titre, lien "En savoir plus" et une
  /// petite illustration décorative (téléphone + paiement validé) à
  /// droite. Remplace l'ancienne carte dorée de raccourcis "Contrats /
  /// Factures / Statistiques" — ces raccourcis vivent désormais dans la
  /// grille d'actions rapides de la carte de statut ci-dessus.
  Widget _buildAccesRapidePromo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
      decoration: BoxDecoration(
        color: AppColors.primaryBlueLight,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payez vos factures en toute simplicité',
                  style: AppTextStyles.h3,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sécurisé, rapide et disponible 24h/24 et 7j/7.',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: AppColors.background,
                        appBar: AppBar(title: const Text('Mes contrats')),
                        body: const SafeArea(child: ContractsScreen()),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'En savoir plus',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 15, color: AppColors.primaryDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _PromoIllustration(),
        ],
      ),
    );
  }

  Widget _buildAlerteSuspendu() {
    return AppCard(
      color: AppColors.danger.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Ce compteur est suspendu pour impayé. Réglez votre facture pour '
              'rétablir le service.',
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

}

/// Icône assistance blanche, jumelle visuelle de `_NotificationBell` (même
/// taille, même ombre) mais sans pastille, placée juste à sa gauche.
class _AssistanceButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AssistanceButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: AppShadows.soft,
        ),
        child: const Center(
          child: Icon(Icons.support_agent_rounded, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

/// Cloche de notification blanche + pastille bleue, fidèle au coin
/// supérieur droit de la maquette d'accueil.
class _NotificationBell extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: AppShadows.soft,
        ),
        child: Stack(
          children: [
            const Center(
              child: Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary, size: 20),
            ),
            Positioned(
              top: 7,
              right: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un bloc icône + libellé + valeur de la boîte d'infos grise sous le
/// montant, fidèle à la maquette (icône ronde colorée, libellé gris,
/// valeur en gras).
class _InfoBoiteItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoBoiteItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: iconColor.withOpacity(0.12), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? AppColors.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Icône dans un carré blanc bordé + libellé en dessous, utilisée pour
/// la grille "Voir les factures / Historique des paiements / Télécharger
/// reçu / Activer rappel" de la carte de statut, fidèle à la maquette.
class _ActionRapideItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRapideItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.primary, size: 21),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petite illustration décorative (téléphone + paiement validé + pièces)
/// pour le bloc promotionnel "Accès rapide", dessinée avec des formes
/// simples pour ne dépendre d'aucun asset image.
class _PromoIllustration extends StatelessWidget {
  const _PromoIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 8,
            top: 2,
            child: Container(
              width: 46,
              height: 62,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppShadows.floating,
              ),
              alignment: Alignment.center,
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.check_rounded, color: AppColors.secondaryGreenDark, size: 20),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFFF5B400),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: const Color(0xFFF5B400),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dessine une bulle de dialogue (rectangle arrondi + petite pointe en
/// bas à gauche), utilisée pour le message "Bonjour, {prénom}" repris
/// de la maquette d'accueil.
class _SpeechBubblePainter extends CustomPainter {
  final Color color;
  const _SpeechBubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 12),
      const Radius.circular(18),
    );
    final path = Path()..addRRect(r);
    path.moveTo(24, size.height - 12);
    path.lineTo(16, size.height);
    path.lineTo(40, size.height - 12);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}