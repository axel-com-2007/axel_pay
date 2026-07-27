// ============================================================
// TABLEAU DE BORD PRINCIPAL / ACCUEIL (MULTI-CONTRATS)
// ============================================================
// REFONTE — reprend la maquette "page_d_accueil" :
//  - Bulle de bienvenue turquoise "Bonjour, {prénom}" + avatar rond
//  - Rangée de raccourcis (pilule blanche avec icônes)
//  - Boutons "Actualiser" / "Réorganiser"
//  - Grande carte jaune doré avec 3 raccourcis : Contrats / Factures /
//    Statistiques (remplace l'ancienne section "Actions rapides")
//  - Illustration décorative en bas d'écran
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
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_badge.dart';
import '../contracts/contracts_screen.dart';
import '../payment/payment_screen.dart';
import '../postpaid/postpaid_screen.dart';
import '../prepaid/prepaid_screen.dart';
import '../settings/settings_screen.dart';

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
      setState(() {
        user = u.data;
        totalContrats = apercu.data.total;
        contrats = apercu.data.contrats;
        horsLigne = estHorsLigne;
        derniereSynchro = synchro.first;
      });
      if (contrats.isNotEmpty) {
        await _selectionnerContrat(contrats.first);
      }
    } on ApiException catch (e) {
      setState(() => erreur = e.message);
    } catch (e) {
      setState(() => erreur = 'Une erreur est survenue. Vérifiez votre connexion.');
    }
  }

  /// Sélectionne un contrat et charge son compteur ACTIF (celui qui
  /// alimente la carte de statut). Utilisé aussi bien pour un contrat de
  /// l'aperçu que pour un résultat de recherche.
  Future<void> _selectionnerContrat(ContratModel contrat) async {
    setState(() {
      contratActif = contrat;
      compteurActif = null;
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
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
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
      //  SliverToBoxAdapter(child: _buildBarreOutils()),
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
                FadeSlideIn(index: 1, child: const SectionHeader(title: 'Accès rapide')),
                const SizedBox(height: 12),
                FadeSlideIn(index: 2, child: _buildCarteMenuDoree()),
                const SizedBox(height: 24),
                if (compteurSuspendu) ...[
                  FadeSlideIn(index: 3, child: _buildAlerteSuspendu()),
                  const SizedBox(height: 24),
                ],
                FadeSlideIn(index: compteurSuspendu ? 4 : 3, child: _buildIllustrationBasDePage()),
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
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bonjour, ${user?.prenom ?? ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
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
          const SizedBox(width: 14),
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
    );
  }

  /// Pilule d'icônes + boutons "Actualiser" / "Réorganiser", repris de
  /// la maquette (rangée d'icônes sous la bulle de bienvenue).
  Widget _buildBarreOutils() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              boxShadow: const [
                BoxShadow(color: AppColors.cardShadow, blurRadius: 14, offset: Offset(0, 6)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ToolbarIcon(
                  icon: Icons.support_agent_outlined,
                  onTap: () => _showSnack('Contacter le support AxelPay'),
                ),
                _ToolbarIcon(
                  icon: Icons.lock_outline,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
                _ToolbarIcon(
                  icon: Icons.copy_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: AppColors.background,
                        appBar: AppBar(title: const Text('Mes contrats')),
                        body: const SafeArea(child: ContractsScreen()),
                      ),
                    ),
                  ),
                ),
                _ToolbarIcon(
                  icon: Icons.delete_outline,
                  onTap: () => _showSnack('Gérez vos compteurs depuis l’onglet Contrats'),
                ),
                _ToolbarIcon(
                  icon: Icons.more_horiz,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundIconButton(
                icon: Icons.refresh,
                onTap: () => setState(() => _chargement = _charger()),
              ),
              const SizedBox(width: 18),
              _RoundIconButton(
                icon: Icons.open_with,
                onTap: () => _showSnack('Réorganisation des compteurs à venir'),
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
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
              suffixIcon: rechercheEnCours
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_forward, color: AppColors.primaryDark),
                      onPressed: _rechercherContrat,
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
      color: AppColors.surface,
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
                    Text('Contrat ${contrat.numeroContrat}', style: AppTextStyles.h3),
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
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  c.freshnessLabel(DateTime.now()),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PaymentScreen(
                            compteur: c,
                            montantSuggere: estPrepaye ? 5000 : (c.soldeDuFcfa ?? 0),
                          ),
                        ),
                      );
                    },
                    icon: Icon(estPrepaye ? Icons.flash_on : Icons.receipt_long, size: 18),
                    label: Text(estPrepaye ? 'Recharger' : 'Payer la facture'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.field),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Grande carte jaune doré avec bordure turquoise, fidèle à la
  /// maquette d'accueil : 3 raccourcis "Contrats / Factures /
  /// Statistiques", chacun avec une icône dans un rond blanc. "Compteurs"
  /// cède la place à "Contrats" — c'est désormais le contrat, pas le
  /// compteur, qui est le point d'entrée depuis l'accueil.
  Widget _buildCarteMenuDoree() {
    final c = compteurActif;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.primary, width: 3),
        boxShadow: [
          BoxShadow(color: AppColors.goldDark.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MenuDoreItem(
            icon: Icons.description_outlined,
            label: 'Contrats',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: AppColors.background,
                  appBar: AppBar(title: const Text('Mes contrats')),
                  body: const SafeArea(child: ContractsScreen()),
                ),
              ),
            ),
          ),
          _MenuDoreItem(
            icon: Icons.receipt_long,
            label: 'Factures',
            onTap: c == null
                ? () => _showSnack('Chargement du compteur actif en cours…')
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            estPrepaye ? PrepaidScreen(compteur: c) : PostpaidScreen(compteur: c),
                      ),
                    ),
          ),
          _MenuDoreItem(
            icon: Icons.bar_chart_rounded,
            label: 'Statistiques',
            onTap: c == null
                ? () => _showSnack('Chargement du compteur actif en cours…')
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            estPrepaye ? PrepaidScreen(compteur: c) : PostpaidScreen(compteur: c),
                      ),
                    ),
          ),
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

  /// Illustration décorative en pied de page, comme dans la maquette
  /// d'accueil. Voir README_ASSETS.md pour la marche à suivre pour
  /// remplacer/ajouter ce type d'image.
  Widget _buildIllustrationBasDePage() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 30, right: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Tout est plus simple avec AxelPay !',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/home_illustration.png',
              height: 110,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ToolbarIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: AppColors.textPrimary, size: 22),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
          boxShadow: const [
            BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Icon(icon, color: AppColors.primaryDark, size: 20),
      ),
    );
  }
}

class _MenuDoreItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuDoreItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
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
