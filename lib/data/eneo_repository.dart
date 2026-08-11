// ============================================================
// COUCHE D'ORCHESTRATION — remplace `mock_data.dart`
// ============================================================
// `EneoApiService` (lib/api/eneo_api_service.dart) expose une méthode par
// endpoint, en JSON brut. Mais plusieurs écrans ont besoin de données qui
// n'existent dans AUCUN endpoint unique côté backend (l'adresse texte d'un
// compteur, son solde courant, son dernier jeton, le nom d'un tiers
// délégataire...). `EneoRepository` agrège ces appels et construit les
// modèles Dart (`models.dart`) que les écrans consomment, à la place des
// données bidon de `mock_data.dart`.
//
// ⚠️ Limites CONNUES et volontairement rendues explicites (plutôt que
// masquées par des valeurs par défaut trompeuses) :
//  1. `CompteursSerializer` ne renvoie que `id_adresse` (un entier) : il
//     faut `GET /adresses/` pour résoudre le libellé. Fait ici.
//  2. CORRECTIF (finalisation module prépayé) : `SoldeCreditView` calcule
//     désormais un solde net réel (`solde_kwh`/`solde_fcfa`), à partir d'un
//     MODÈLE DE CONSOMMATION SIMULÉ documenté côté backend (donnée de test
//     tant que la synchro IoT/API Eneo n'est pas branchée, §2.6 du CDC) —
//     ce n'est plus le simple cumul des recharges (`solde_kwh_achete_total`)
//     qui surestimait le solde réel. Ce dernier champ reste renvoyé par
//     l'API à titre indicatif et sert uniquement de repli défensif
//     ci-dessous si `solde_kwh` venait à manquer.
//  3. `SoldeCreditView` renvoie également `jours_autonomie_estimes` (même
//     modèle simulé) : lu ci-dessous et propagé sur `CompteurModel`, l'UI
//     n'affiche "non disponible" que si le backend renvoie `null` (compteur
//     sans historique de recharge suffisant pour estimer un rythme).
//  4. CORRECTIF (audit du 24/07/2026, `api/crypto.py`) : `token_genere` est
//     chiffré au repos (AES-256-GCM) côté serveur, mais déchiffré à la
//     volée par `TransactionsPrepayeesSerializer` avant sérialisation — la
//     valeur renvoyée par `getTokenHistorique`/`getSoldeCredit` est donc
//     bien le jeton STS en clair, prêt à être affiché/saisi tel quel.
//  5. CORRECTIF (audit du 24/07/2026) : `GET /users/recherche/?telephone=`
//     (`UserRechercheView` côté backend, RG-02) permet désormais de
//     retrouver un tiers par son numéro exact avant de créer une
//     délégation — voir `rechercherUtilisateurParTelephone` ci-dessous,
//     branché sur le formulaire de `meters_screen.dart` /
//     `contracts_screen.dart`. Ne renvoie que `id_user` + `nom` +
//     `prenom_masque` (jamais l'email/mot de passe) : `DelegationModel`
//     continue donc de recevoir `nomTiers`/`telephoneTiers` fournis par
//     l'appelant plutôt que résolus depuis `GestionCompteursSerializer`
//     (qui ne renvoie toujours que `id_user`, un entier).
//  6. REFONTE v1.5 — `CompteursSerializer` ne renvoie que `id_contrat` (un
//     entier) : comme pour l'adresse, il faut `GET /contrats/` pour
//     résoudre `numero_contrat`. Fait ici (voir `_numerosContrats`).
// ============================================================

import 'dart:async';

import '../api/api_exception.dart';
import '../api/eneo_api_service.dart';
import '../models/models.dart';
import 'local_cache.dart';

/// Résultat d'une lecture passée par [EneoRepository._cached] : la donnée
/// elle-même, accompagnée de la provenance (réseau frais vs cache local
/// hors-ligne, §7.6) et de l'horodatage de la dernière synchronisation
/// réseau réussie qui l'a produite. Les écrans (dashboard, prépayé...)
/// utilisent [isFromCache] pour afficher un bandeau "hors connexion" et
/// [syncedAt] pour le "Dernière mise à jour : il y a Xh".
/// Une page de `GET /notifications/` : les notifications de cette page,
/// plus le lien `next` DRF (`null` s'il n'y a pas de page suivante) à
/// repasser à [EneoRepository.getNotifications] pour charger la suite.
class NotificationsPage {
  final List<NotificationModel> notifications;
  final String? next;
  const NotificationsPage({required this.notifications, this.next});
}

class CachedResult<T> {
  final T data;
  final bool isFromCache;
  final DateTime syncedAt;
  const CachedResult({required this.data, required this.isFromCache, required this.syncedAt});
}

/// Sérialise `data` qu'il soit une liste brute (endpoints non paginés,
/// ex: `/compteurs/`, `/delegations/`, `/adresses/`) ou une page DRF
/// (`{"count":..,"results":[...]}`, ex: `/factures/`, `/tokens/`).
List<dynamic> asList(dynamic data) {
  if (data is List) return data;
  if (data is Map<String, dynamic> && data['results'] is List) {
    return data['results'] as List<dynamic>;
  }
  return const [];
}

class EneoRepository {
  EneoRepository({EneoApiService? api}) : _api = api ?? EneoApiService();

  final EneoApiService _api;

  /// Rétention locale : 12 mois (§7.6, en cohérence avec l'historique de
  /// 12 mois affiché côté serveur). Purge best-effort, en tâche de fond,
  /// déclenchée après chaque synchro réseau réussie — jamais bloquante.
  static const _retentionLocale = Duration(days: 366);

  /// Cœur du mode hors-ligne (§7.6). Encapsule le pattern répété par
  /// chaque méthode de lecture "offline-critique" du repository :
  ///  1. tente l'appel réseau [fetch] ;
  ///  2. si ça réussit : sauvegarde l'instantané en cache local (sous
  ///     [key], via [encode]) et renvoie la donnée fraîche
  ///     (`isFromCache: false`) ;
  ///  3. si ça échoue PAR ABSENCE DE RÉSEAU ([ApiNetworkException]
  ///     uniquement — jamais sur une vraie erreur serveur 401/403/500,
  ///     qui doit continuer à remonter normalement) : relit le dernier
  ///     instantané connu dans le cache local (via [decode]) et le
  ///     renvoie avec `isFromCache: true` + la date de cette dernière
  ///     synchronisation. Si le cache est vide (jamais synchronisé),
  ///     l'exception réseau d'origine remonte quand même — impossible de
  ///     faire mieux sans donnée.
  Future<CachedResult<T>> _cached<T>({
    required String key,
    required Future<T> Function() fetch,
    required Map<String, dynamic> Function(T data) encode,
    required T Function(Map<String, dynamic> json) decode,
  }) async {
    try {
      final data = await fetch();
      final now = DateTime.now();
      // Écriture cache en tâche de fond : ne bloque jamais le retour de
      // la donnée fraîche à l'appelant, et une écriture qui échoue
      // (cf. LocalCache.saveSnapshot, silencieuse) ne doit jamais faire
      // échouer une lecture par ailleurs réussie.
      unawaited(LocalCache.instance.saveSnapshot(key, encode(data)));
      unawaited(LocalCache.instance.purgeOlderThan(_retentionLocale));
      return CachedResult(data: data, isFromCache: false, syncedAt: now);
    } on ApiNetworkException {
      final cached = await LocalCache.instance.getSnapshot(key);
      if (cached == null) rethrow;
      return CachedResult(data: decode(cached.value), isFromCache: true, syncedAt: cached.updatedAt);
    }
  }

  /// Profil utilisateur, consultable hors-ligne (§7.6) : `isFromCache` et
  /// `syncedAt` permettent à l'UI d'afficher "Dernière mise à jour : il y
  /// a Xh" quand la donnée provient du cache plutôt que du réseau.
  Future<CachedResult<UserModel>> getProfile() {
    return _cached<UserModel>(
      key: 'profile',
      fetch: () async => UserModel.fromJson(await _api.getProfile()),
      encode: (u) => u.toCacheJson(),
      decode: UserModel.fromCacheJson,
    );
  }

  Future<UserModel> updateProfile(Map<String, dynamic> champs) async {
    final json = await _api.updateProfile(champs);
    return UserModel.fromJson(json);
  }

  /// §7.6 : purge du cache local hors-ligne au logout, que l'appel réseau
  /// ait réussi ou non — même logique que le nettoyage du TokenStorage
  /// dans `EneoApiService.logout()`.
  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      await LocalCache.instance.clear();
    }
  }

  Future<Map<String, dynamic>> exportMyData() => _api.exportMyData();

  /// §7.6 : purge du cache local hors-ligne une fois le compte désactivé
  /// côté serveur. Contrairement à [logout], on ne purge qu'en cas de
  /// succès : un échec de désactivation laisse le compte actif, le cache
  /// hors-ligne reste donc légitime.
  Future<Map<String, dynamic>> deactivateAccount({required String motDePasseConfirmation}) async {
    final result =
        await _api.deactivateAccount(motDePasseConfirmation: motDePasseConfirmation);
    await LocalCache.instance.clear();
    return result;
  }

  /// ⚠️ `NotificationPreferencesView` est un stub côté serveur (cf.
  /// commentaire "TODO INTEGRATION : persister ces préférences" dans
  /// views.py) : le GET renvoie toujours `{}` et le PATCH ne persiste
  /// rien. Ces méthodes sont branchées pour être prêtes dès que le
  /// backend implémentera la persistance, mais n'attendez pas qu'un
  /// changement survive un redémarrage pour l'instant.
  Future<Map<String, dynamic>> getNotificationPreferences(int idCompteur) {
    return _api.getNotificationPreferences(idCompteur);
  }

  Future<Map<String, dynamic>> updateNotificationPreferences(
    int idCompteur,
    Map<String, dynamic> preferences,
  ) {
    return _api.updateNotificationPreferences(idCompteur, preferences);
  }

  /// Libellé "Quartier — Ville" par id_adresse, construit à partir de
  /// `GET /adresses/` (le seul endpoint qui expose ce texte).
  Future<Map<int, String>> _adresseLabels() async {
    final data = await _adresseData();
    return data.labels;
  }

  /// Résout toutes les adresses depuis `GET /adresses/`.
  /// Retourne labels (texte complet) ET villes (ville seule) en un seul appel.
  Future<({Map<int, String> labels, Map<int, String> villes})> _adresseData() async {
    final raw = asList(await _api.listAdresses());
    final labels = <int, String>{};
    final villes = <int, String>{};
    for (final a in raw) {
      final id = a['id_adresse'] as int? ?? int.tryParse('${a['id_adresse']}');
      if (id == null) continue;
      final quartier = (a['quartier_description'] as String? ?? '').trim();
      final commune = (a['commune'] as String? ?? '').trim();
      final ville = (a['ville'] as String? ?? '').trim();
      labels[id] = [quartier, commune, ville].where((s) => s.isNotEmpty).join(', ');
      villes[id] = ville;
    }
    return (labels: labels, villes: villes);
  }

  /// Prix du kWh actuellement en vigueur pour un type de compteur donné
  /// (`date_fin IS NULL` = tarif courant, RG-07).
  Future<double?> _tarifCourant(String typeCompteurApi) async {
    final raw = asList(await _api.listTarifs(typeCompteur: typeCompteurApi));
    for (final t in raw) {
      if (t['date_fin'] == null) {
        final v = t['prix_kwh'];
        if (v is num) return v.toDouble();
        return double.tryParse('$v');
      }
    }
    return null;
  }

  // ==========================================================================
  // CONTRATS (REFONTE v1.5 — nouvelle racine du graphe de propriété)
  // ==========================================================================

  /// `numero_contrat` par `id_contrat`, construit à partir de
  /// `GET /contrats/` (même principe que `_adresseLabels`).
  /// CORRECTIF (audit lenteur accueil) : `GET /contrats/` est maintenant
  /// paginé (`page_size` par défaut 20). Passe donc par [getAllContrats],
  /// qui parcourt toutes les pages, pour ne jamais perdre le libellé des
  /// contrats au-delà de la première page (sinon régression silencieuse :
  /// compteurs/délégations d'un contrat "page 2+" affichés sans numéro).
  Future<Map<int, String>> _numerosContrats() async {
    final tous = await getAllContrats();
    final map = <int, String>{};
    for (final c in tous) {
      final id = int.tryParse(c.id);
      if (id == null) continue;
      map[id] = c.numeroContrat;
    }
    return map;
  }

  /// Contrats dont l'utilisateur courant est titulaire (triés du plus
  /// récent au plus ancien par le serveur), chacun déjà enrichi de son
  /// nombre de compteurs par le backend (`ContratsSerializer.
  /// nombre_compteurs`, annotation `Count()` — voir
  /// `ContratListCreateView.get_queryset`).
  ///
  /// CORRECTIF (audit lenteur accueil) : cette méthode ne fait plus
  /// qu'UN SEUL appel HTTP, quel que soit le nombre de contrats. Avant ce
  /// correctif, une boucle appelait `GET /contrats/<id>/compteurs/` une
  /// fois PAR contrat pour calculer `nombreCompteurs` côté client — jusqu'à
  /// 250 requêtes séquentielles pour l'accueil (~74s), alors que 247
  /// d'entre elles étaient immédiatement jetées (`take(3)`).
  ///
  /// - [search] : filtre par numéro de contrat (barre de recherche de
  ///   l'accueil, utile dès que le client a plus de 3 contrats).
  /// - [limit] : ne renvoie que les [limit] premiers contrats (déjà triés
  ///   par le serveur). Purement une optimisation de bande passante
  ///   maintenant (`?page_size=` côté serveur) — n'est plus nécessaire
  ///   pour éviter un N+1, puisqu'il n'y en a plus.
  Future<List<ContratModel>> getContrats({String? search, int? limit}) async {
    final json = await _api.listContrats(
      search: search,
      pageSize: limit,
    );
    return asList(json).cast<Map<String, dynamic>>().map(ContratModel.fromJson).toList();
  }

  /// Liste COMPLÈTE des contrats du client (tous, pas seulement l'aperçu),
  /// pour l'écran "Mes contrats" (`contracts_screen.dart`). `GET
  /// /contrats/` étant paginé (max 100 par page), cette méthode suit le
  /// lien `next` renvoyé par DRF pour agréger toutes les pages en un
  /// nombre de requêtes proportionnel au nombre de PAGES (2-3 pour 250
  /// contrats), pas au nombre de contrats — donc jamais de retour au N+1
  /// corrigé au point 1 de l'audit.
  Future<List<ContratModel>> getAllContrats({String? search}) async {
    final contrats = <ContratModel>[];
    dynamic json = await _api.listContrats(search: search, pageSize: 100);
    contrats.addAll(
      asList(json).cast<Map<String, dynamic>>().map(ContratModel.fromJson),
    );
    String? next = (json is Map<String, dynamic>) ? json['next'] as String? : null;
    while (next != null) {
      json = await _api.listContratsPage(next);
      contrats.addAll(
        asList(json).cast<Map<String, dynamic>>().map(ContratModel.fromJson),
      );
      next = (json is Map<String, dynamic>) ? json['next'] as String? : null;
    }
    return contrats;
  }

  /// Aperçu de l'accueil : les [limit] contrats les plus récents, ET le
  /// nombre TOTAL de contrats du client (indépendant de [limit]) — utilisé
  /// pour savoir s'il faut afficher la barre de recherche ("plus de
  /// [limit] contrats"). `GET /contrats/` étant désormais paginé
  /// (`StandardResultsSetPagination`), le `count` renvoyé par DRF donne le
  /// total réel sans avoir à télécharger tous les contrats.
  /// Consultable hors-ligne (§7.6) — c'est le point d'entrée de l'accueil
  /// (`DashboardScreen`), donc la première chose qui doit fonctionner
  /// sans réseau.
  Future<CachedResult<({List<ContratModel> contrats, int total})>> getContratsApercu({
    required int limit,
  }) {
    return _cached<({List<ContratModel> contrats, int total})>(
      key: 'contrats_apercu_$limit',
      fetch: () async {
        final json = await _api.listContrats(pageSize: limit);
        final contrats =
            asList(json).cast<Map<String, dynamic>>().map(ContratModel.fromJson).toList();
        final total = (json is Map<String, dynamic> && json['count'] is int)
            ? json['count'] as int
            : contrats.length;
        return (contrats: contrats, total: total);
      },
      encode: (r) => {
        'contrats': r.contrats.map((c) => c.toCacheJson()).toList(),
        'total': r.total,
      },
      decode: (json) => (
        contrats: (json['contrats'] as List)
            .cast<Map<String, dynamic>>()
            .map(ContratModel.fromCacheJson)
            .toList(),
        total: json['total'] as int,
      ),
    );
  }

  /// Le compteur ACTIF d'un contrat — RG métier : un contrat peut avoir
  /// plusieurs compteurs mais un seul doit être actif à la fois. C'est ce
  /// compteur qui porte les données affichées sur la carte de statut de
  /// l'accueil (solde, type prépayé/postpayé...) une fois un contrat
  /// sélectionné. Si aucun compteur n'est marqué actif (cas limite), on
  /// retombe sur le premier compteur du contrat plutôt que de ne rien
  /// afficher.
  /// Consultable hors-ligne (§7.6). Quand la donnée vient du cache
  /// (`isFromCache: true`), le compteur retourné a son
  /// `derniereMiseAJour` réécrit sur la date de dernière synchro reçue du
  /// cache : `CompteurModel.freshnessLabel()`, déjà utilisé par
  /// `DashboardScreen`/`PrepaidScreen`, affiche alors automatiquement
  /// "Dernière mise à jour : il y a Xh" au lieu de la date de création du
  /// compteur — sans dupliquer la logique d'affichage.
  Future<CachedResult<CompteurModel?>> getCompteurActifDuContrat(ContratModel contrat) async {
    final id = int.tryParse(contrat.id);
    if (id == null) {
      return CachedResult(data: null, isFromCache: false, syncedAt: DateTime.now());
    }
    final result = await getContratCompteurs(id, numeroContrat: contrat.numeroContrat);
    if (result.data.isEmpty) {
      return CachedResult(data: null, isFromCache: result.isFromCache, syncedAt: result.syncedAt);
    }
    var actif = result.data.firstWhere((c) => c.actif, orElse: () => result.data.first);
    if (result.isFromCache) {
      actif = actif.copyWith(derniereMiseAJour: result.syncedAt);
    }
    return CachedResult(data: actif, isFromCache: result.isFromCache, syncedAt: result.syncedAt);
  }

  /// Crée un nouveau contrat pour l'utilisateur courant (`numeroContrat` =
  /// numéro du contrat papier/Eneo).
  Future<ContratModel> createContrat({required String numeroContrat}) async {
    final json = await _api.createContrat(numeroContrat: numeroContrat);
    return ContratModel.fromJson(json);
  }

  /// Compteurs rattachés à un contrat donné, enrichis (adresse, solde...)
  /// comme [getCompteurs].
  /// Compteurs d'un contrat (adresse, solde, dernier jeton...),
  /// consultables hors-ligne (§7.6). ⚠️ Le cache est mis à jour au niveau
  /// de CE point d'entrée (résultat final déjà enrichi), pas à chaque
  /// sous-appel interne (`_adresseLabels`, `_enrichirTous`...) : c'est
  /// volontaire — si le réseau tombe au milieu de l'enrichissement, on
  /// retombe entièrement sur le DERNIER résultat complet connu plutôt que
  /// de composer un résultat partiellement obsolète/partiellement frais.
  Future<CachedResult<List<CompteurModel>>> getContratCompteurs(
    int idContrat, {
    String? numeroContrat,
  }) {
    return _cached<List<CompteurModel>>(
      key: 'compteurs_contrat_$idContrat',
      fetch: () async {
        final rawCompteurs = asList(await _api.listContratCompteurs(idContrat));
        final adresseData = await _adresseData();

        final compteurs = rawCompteurs.map((json) {
          final idAdresse = json['id_adresse'] is int
              ? json['id_adresse'] as int
              : int.tryParse('${json['id_adresse']}');
          final c = CompteurModel.fromJson(
            json as Map<String, dynamic>,
            adresseLabel: adresseData.labels[idAdresse],
            numeroContrat: numeroContrat,
          );
          return c.copyWith(ville: adresseData.villes[idAdresse]);
        }).toList();

        return _enrichirTous(compteurs);
      },
      encode: (list) => {'compteurs': list.map((c) => c.toCacheJson()).toList()},
      decode: (json) => (json['compteurs'] as List)
          .cast<Map<String, dynamic>>()
          .map(CompteurModel.fromCacheJson)
          .toList(),
    );
  }

  /// Factures agrégées d'un contrat, tous compteurs confondus.
  Future<List<FactureModel>> getContratFactures(
    int idContrat, {
    String? statut,
    int? idCompteur,
    bool historiqueComplet = false,
  }) async {
    final raw = asList(await _api.listContratFactures(
      idContrat,
      statut: statut,
      idCompteur: idCompteur,
      historiqueComplet: historiqueComplet,
    ));
    return raw.cast<Map<String, dynamic>>().map(FactureModel.fromJson).toList();
  }

  /// Recherche EXACTE d'un utilisateur par téléphone (RG-02), pour
  /// pré-remplir la création d'une délégation. `null` si aucun utilisateur
  /// ne correspond à ce numéro exact — voir `_ouvrirDelegation` dans
  /// `meters_screen.dart` / `contracts_screen.dart` pour le flux complet.
  Future<UtilisateurRechercheModel?> rechercherUtilisateurParTelephone(String telephone) async {
    final json = await _api.rechercherUtilisateurParTelephone(telephone.trim());
    if (json == null) return null;
    return UtilisateurRechercheModel.fromJson(json);
  }

  /// Accorde une délégation à un tiers, sur un compteur précis OU sur tout
  /// un contrat (exclusif — voir `EneoApiService.createDelegation`).
  Future<DelegationModel> createDelegation({
    required int idUserTiers,
    int? idCompteur,
    int? idContrat,
    required DroitDelegation droit,
    String? cibleLabel,
  }) async {
    final json = await _api.createDelegation(
      idUser: idUserTiers,
      idCompteur: idCompteur,
      idContrat: idContrat,
      typeDroit: droitToApi(droit),
    );
    return DelegationModel.fromJson(json, cibleLabel: cibleLabel);
  }

  /// Liste des compteurs accessibles à l'utilisateur, enrichis (adresse,
  /// solde, dernier jeton pour le prépayé / montant dû pour le postpayé,
  /// et numéro du contrat auquel chacun est rattaché).
  /// Tous les compteurs de l'utilisateur, consultables hors-ligne (§7.6).
  /// Utilisé par `meters_screen.dart` (vue globale, tous contrats
  /// confondus).
  Future<CachedResult<List<CompteurModel>>> getCompteurs() {
    return _cached<List<CompteurModel>>(
      key: 'compteurs_tous',
      fetch: () async {
        final rawCompteurs = asList(await _api.listCompteurs());
        final adresseData = await _adresseData();
        final contrats = await _numerosContrats();

        final compteurs = rawCompteurs.map((json) {
          final m = json as Map<String, dynamic>;
          final idAdresse = m['id_adresse'] is int
              ? m['id_adresse'] as int
              : int.tryParse('${m['id_adresse']}');
          final idContrat = m['id_contrat'] is int
              ? m['id_contrat'] as int
              : int.tryParse('${m['id_contrat']}');
          final c = CompteurModel.fromJson(
            m,
            adresseLabel: adresseData.labels[idAdresse],
            numeroContrat: idContrat != null ? contrats[idContrat] : null,
          );
          return c.copyWith(ville: adresseData.villes[idAdresse]);
        }).toList();

        return _enrichirTous(compteurs);
      },
      encode: (list) => {'compteurs': list.map((c) => c.toCacheJson()).toList()},
      decode: (json) => (json['compteurs'] as List)
          .cast<Map<String, dynamic>>()
          .map(CompteurModel.fromCacheJson)
          .toList(),
    );
  }

  /// Enrichit une liste de compteurs bruts (solde, dernier jeton pour le
  /// prépayé / montant dû pour le postpayé) — factorisé pour être partagé
  /// entre [getCompteurs] (vue globale) et [getContratCompteurs] (vue par
  /// contrat).
  Future<List<CompteurModel>> _enrichirTous(List<CompteurModel> compteurs) async {
    double? prixPrepaye;

    final enrichis = <CompteurModel>[];
    for (final c in compteurs) {
      final idCompteur = int.tryParse(c.id);
      if (idCompteur == null) {
        enrichis.add(c);
        continue;
      }
      if (c.type == TypeCompteur.prepaye) {
        enrichis.add(await _enrichirPrepaye(c, idCompteur, () async {
          prixPrepaye ??= await _tarifCourant('PREPAYE');
          return prixPrepaye;
        }));
      } else {
        enrichis.add(await _enrichirPostpaye(c, idCompteur));
      }
    }
    return enrichis;
  }

  Future<CompteurModel> _enrichirPrepaye(
    CompteurModel c,
    int idCompteur,
    Future<double?> Function() prixKwh,
  ) async {
    try {
      final solde = await _api.getSoldeCredit(idCompteur);
      // cf. limite (2) documentée en tête de fichier : `solde_kwh` est
      // désormais le solde net réel renvoyé par le backend ; le repli sur
      // `solde_kwh_achete_total` ne joue plus que si l'API venait à ne pas
      // renvoyer `solde_kwh` (ex: ancienne réponse en cache).
      final soldeKwh = (solde['solde_kwh'] as num?)?.toDouble() ??
          (solde['solde_kwh_achete_total'] as num?)?.toDouble() ??
          double.tryParse('${solde['solde_kwh_achete_total']}') ??
          0.0;
      final prix = await prixKwh();
      final soldeFcfa = (solde['solde_fcfa'] as num?)?.toDouble() ??
          (prix != null ? soldeKwh * prix : null);
      final derniereSync = solde['derniere_synchronisation'] != null
          ? DateTime.tryParse('${solde['derniere_synchronisation']}')
          : null;
      // cf. limite (3) : arrondi à l'entier le plus proche pour affichage
      // ("X jours"), le backend renvoyant une valeur à une décimale.
      final joursAutonomie = (solde['jours_autonomie_estimes'] as num?)?.round();

      String? dernierToken;
      DateTime? dateDernierToken;
      final tokens = asList(await _api.getTokenHistorique(idCompteur));
      for (final t in tokens) {
        if (t['token_genere'] != null) {
          dernierToken = t['token_genere'] as String;
          dateDernierToken = DateTime.tryParse('${t['date_transaction']}');
          break;
        }
      }

      return c.copyWith(
        soldeKwh: soldeKwh,
        soldeFcfaEquivalent: soldeFcfa,
        derniereMiseAJour: derniereSync ?? c.derniereMiseAJour,
        dernierToken: dernierToken,
        dateDernierToken: dateDernierToken,
        joursAutonomieEstimes: joursAutonomie,
      );
    } catch (_) {
      // Le compteur reste affichable même si l'enrichissement échoue
      // (ex: hors-ligne) — cf. mode dégradé prévu par la CDC (7.6).
      return c;
    }
  }

  Future<CompteurModel> _enrichirPostpaye(CompteurModel c, int idCompteur) async {
    try {
      final factures = asList(await _api.listFactures(idCompteur))
          .cast<Map<String, dynamic>>()
          .map(FactureModel.fromJson)
          .toList();
      if (factures.isEmpty) return c;

      final impayees = factures.where((f) => f.statut == StatutFacture.impayee);
      final soldeDu = impayees.isNotEmpty
          ? impayees.map((f) => f.montantFcfa).reduce((a, b) => a + b)
          : 0.0;

      return c.copyWith(soldeDuFcfa: soldeDu);
    } catch (_) {
      return c;
    }
  }

  /// Factures d'un compteur. Le cache local (§7.6) ne couvre QUE le cas
  /// par défaut (`historiqueComplet: false`, les "12 dernières factures"
  /// explicitement citées par le cahier des charges) : la consultation de
  /// l'historique complet au-delà de 12 mois reste une action volontaire
  /// de l'utilisateur qui suppose déjà une connexion active, donc pas
  /// mise en cache (limite assumée pour rester dans le périmètre §7.6,
  /// qui ne mentionne que les 12 dernières factures comme consultables
  /// hors-ligne).
  Future<CachedResult<List<FactureModel>>> getFactures(
    int idCompteur, {
    bool historiqueComplet = false,
  }) {
    Future<List<FactureModel>> fetch() async {
      final raw = asList(await _api.listFactures(idCompteur, historiqueComplet: historiqueComplet));
      return raw.cast<Map<String, dynamic>>().map(FactureModel.fromJson).toList();
    }

    if (historiqueComplet) {
      // Réseau uniquement, pas de repli cache — cf. commentaire ci-dessus.
      return fetch().then((data) => CachedResult(data: data, isFromCache: false, syncedAt: DateTime.now()));
    }

    return _cached<List<FactureModel>>(
      key: 'factures_$idCompteur',
      fetch: fetch,
      encode: (list) => {'factures': list.map((f) => f.toCacheJson()).toList()},
      decode: (json) => (json['factures'] as List)
          .cast<Map<String, dynamic>>()
          .map(FactureModel.fromCacheJson)
          .toList(),
    );
  }

  Future<List<ConsommationPoint>> getConsommation(int idCompteur) async {
    final json = await _api.getConsommationGraph(idCompteur);
    final serie = (json['serie'] as List? ?? const []);
    return serie.cast<Map<String, dynamic>>().map(ConsommationPoint.fromJson).toList();
  }

  /// Historique des recharges (et donc des jetons), consultable
  /// hors-ligne (§7.6 : "le jeton de recharge le plus récent reste
  /// consultable hors-ligne depuis le cache local").
  Future<CachedResult<List<TransactionPrepaieeModel>>> getTransactions(int idCompteur) {
    return _cached<List<TransactionPrepaieeModel>>(
      key: 'transactions_$idCompteur',
      fetch: () async {
        final raw = asList(await _api.getTokenHistorique(idCompteur));
        return raw.cast<Map<String, dynamic>>().map(TransactionPrepaieeModel.fromJson).toList();
      },
      encode: (list) => {'transactions': list.map((t) => t.toCacheJson()).toList()},
      decode: (json) => (json['transactions'] as List)
          .cast<Map<String, dynamic>>()
          .map(TransactionPrepaieeModel.fromCacheJson)
          .toList(),
    );
  }

  /// Une page de `GET /notifications/` (append-only côté SQL, donc
  /// délibérément PAS chargée en une seule fois — cf. commentaire de
  /// `StandardResultsSetPagination` dans `api/pagination.py`). [pageUrl]
  /// est le lien `next` de la page précédente ; `null` pour la première
  /// page. Pas de cache local (contrairement à `getFactures`/
  /// `getTransactions`) : l'historique de notifications n'a pas de valeur
  /// hors-ligne documentée dans le CDC, donc pas de repli silencieux —
  /// l'écran affiche une erreur explicite plutôt qu'une liste vide
  /// trompeuse en cas de coupure réseau.
  Future<NotificationsPage> getNotifications({String? pageUrl}) async {
    final json = pageUrl != null
        ? await _api.listNotificationsPage(pageUrl)
        : await _api.listNotifications();
    final notifications =
        asList(json).cast<Map<String, dynamic>>().map(NotificationModel.fromJson).toList();
    final next = (json is Map<String, dynamic>) ? json['next'] as String? : null;
    return NotificationsPage(notifications: notifications, next: next);
  }

  /// Un tour de l'assistant de support IA (écran Assistance). [messages]
  /// est l'historique complet à renvoyer à chaque appel (le serveur ne
  /// garde aucun état, cf. `SupportChatView` côté backend). Pas de cache :
  /// chaque tour est un appel réseau direct.
  Future<Map<String, dynamic>> supportChat(List<Map<String, String>> messages) {
    return _api.supportChat(messages);
  }

  /// Délégations actives accordées par l'utilisateur courant, sur un
  /// compteur précis ou sur tout un contrat (REFONTE v1.5), tous compteurs
  /// confondus (cf. limite (5) : nom/téléphone du tiers non résolvables
  /// depuis cet endpoint).
  Future<List<DelegationModel>> getDelegations() async {
    final raw = asList(await _api.listDelegations())
        .cast<Map<String, dynamic>>()
        .where((j) => (j['statut'] as String? ?? 'Actif') == 'Actif')
        .toList();
    if (raw.isEmpty) return const [];

    // Résout les libellés cibles (numéro de compteur / numéro de contrat)
    // à partir des deux référentiels déjà chargés ailleurs, plutôt qu'un
    // "Compteur #12" / "Contrat #7" générique.
    final compteursParId = <int, Map<String, dynamic>>{};
    for (final c in asList(await _api.listCompteurs())) {
      final id = c['id_compteur'] as int? ?? int.tryParse('${c['id_compteur']}');
      if (id != null) compteursParId[id] = c as Map<String, dynamic>;
    }
    final contrats = await _numerosContrats();

    return raw.map((j) {
      final idCompteur = j['id_compteur'] == null
          ? null
          : (j['id_compteur'] as int? ?? int.tryParse('${j['id_compteur']}'));
      final idContrat = j['id_contrat'] == null
          ? null
          : (j['id_contrat'] as int? ?? int.tryParse('${j['id_contrat']}'));
      String? cibleLabel;
      if (idContrat != null) {
        cibleLabel = contrats[idContrat] != null ? 'Contrat ${contrats[idContrat]}' : null;
      } else if (idCompteur != null) {
        final numero = compteursParId[idCompteur]?['numero_compteur'] as String?;
        cibleLabel = numero != null ? 'Compteur $numero' : null;
      }
      return DelegationModel.fromJson(j, cibleLabel: cibleLabel);
    }).toList();
  }

  Future<void> revokeDelegation(String idDelegation) async {
    final id = int.tryParse(idDelegation);
    if (id == null) return;
    await _api.revokeDelegation(id);
  }

  Future<Map<String, dynamic>> signalerAnomalie(String idFacture, String description) {
    return _api.signalerAnomalieFacture(idFacture, description: description);
  }

  /// Rattache un nouveau compteur à l'un des contrats de l'utilisateur.
  ///
  /// REFONTE v1.5 : `id_contrat` est désormais une FK NOT NULL côté SQL —
  /// `CompteurListCreateView.perform_create` exige un `idContrat` explicite
  /// ET vérifie que ce contrat appartient bien à l'utilisateur courant
  /// avant d'accepter la création (sinon 403).
  ///
  /// ⚠️ IMPORTANT (limite déjà présente avant la refonte) : `POST
  /// /compteurs/` crée TOUJOURS une nouvelle ligne `Compteurs` — il
  /// n'existe aucun endpoint pour rechercher un compteur physique existant
  /// par son numéro et s'y rattacher. Cette méthode enregistre donc un
  /// nouveau compteur dans le référentiel, ce qui n'est correct que pour
  /// un premier enregistrement.
  Future<CompteurModel> rattacherCompteur({
    required int idContrat,
    required String numero,
    required String typeApi, // 'PREPAYE' | 'POSTPAYE'
    required String ville,
    required String commune,
    required String quartier,
    required String proprietaireLegal,
  }) async {
    final adresse = await _api.createAdresse({
      'ville': ville,
      'commune': commune,
      'quartier_description': quartier,
      'est_immeuble': false,
    });
    final idAdresse = adresse['id_adresse'];

    final compteur = await _api.createCompteur({
      'numero_compteur': numero,
      'type_compteur': typeApi,
      'id_adresse': idAdresse,
      'id_contrat': idContrat,
      'proprietaire_legal': proprietaireLegal,
    });

    final adresseData = await _adresseData();
    final contrats = await _numerosContrats();
    final idAdresseInt = idAdresse is int ? idAdresse : int.tryParse('$idAdresse');
    final c = CompteurModel.fromJson(
      compteur,
      adresseLabel: adresseData.labels[idAdresseInt],
      numeroContrat: contrats[idContrat],
    );
    return c.copyWith(ville: adresseData.villes[idAdresseInt]);
  }

  Future<Map<String, dynamic>> initierPaiement({
    required String typePaiement, // 'FACTURE' | 'RECHARGE'
    required String referenceCible,
    required double montantFcfa,
    required String numeroMobileMoney,
    required String operateurMobileMoney, // 'MTN_MOMO' | 'ORANGE_MONEY'
    String? otpConfirmation,
  }) {
    return _api.initierPaiement(
      typePaiement: typePaiement,
      referenceCible: referenceCible,
      montantFcfa: montantFcfa,
      numeroMobileMoney: numeroMobileMoney,
      operateurMobileMoney: operateurMobileMoney,
      otpConfirmation: otpConfirmation,
    );
  }

  Future<Map<String, dynamic>> achatCredit(int idCompteur, double montantFcfa) {
    return _api.achatCredit(idCompteur, montantFcfa: montantFcfa);
  }

  Future<Map<String, dynamic>> getPaiementStatut(String idPaiement) {
    return _api.getPaiementStatut(idPaiement);
  }

  Future<Map<String, dynamic>> getFactureRecu(String idFacture) {
    return _api.getFactureRecu(idFacture);
  }

  /// Dernier jeton connu pour un compteur prépayé (utilisé après une
  /// recharge confirmée pour afficher le vrai jeton plutôt qu'une valeur
  /// inventée). Voir la limite (4) documentée en tête de fichier.
  ///
  /// Consultable hors-ligne (§7.6) : s'appuie sur [getTransactions], qui
  /// retombe déjà sur le cache local en l'absence de réseau — pas d'appel
  /// direct à `_api` ici, pour ne jamais dupliquer la logique de repli.
  Future<CachedResult<String?>> getDernierToken(int idCompteur) async {
    final result = await getTransactions(idCompteur);
    for (final t in result.data) {
      if (t.tokenGenere != null) {
        return CachedResult(data: t.tokenGenere, isFromCache: result.isFromCache, syncedAt: result.syncedAt);
      }
    }
    return CachedResult(data: null, isFromCache: result.isFromCache, syncedAt: result.syncedAt);
  }
}
