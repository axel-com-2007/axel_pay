import 'api_client.dart';
import 'token_storage.dart';
import 'api_exception.dart';

/// Façade métier au-dessus d'[ApiClient] : une méthode par endpoint exposé
/// dans `urls.py`, regroupée par module fonctionnel (mêmes 9 modules que le
/// backend). C'est le SEUL fichier que le reste de l'app Flutter (widgets,
/// providers/blocs) doit connaître pour parler au backend.
///
/// Toutes les méthodes renvoient du JSON déjà décodé (Map/List Dart). Le
/// mapping vers des modèles Dart typés se fait dans la couche au-dessus
/// (fromJson dans tes modèles), volontairement laissée hors de ce client
/// pour qu'il reste indépendant de tes classes métier.
class EneoApiService {
  EneoApiService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;
  final TokenStorage _tokenStorage = TokenStorage.instance;

  // =========================================================================
  // MODULE 1 — Authentification, profil & préférences
  // =========================================================================

  Future<Map<String, dynamic>> register({
    required String nom,
    required String prenom,
    required String telephone,
    required String email,
    required String motDePasse,
    String? situationMatrimoniale,
    String? quartier,
  }) async {
    final data = await _client.post('/auth/register/', data: {
      'nom': nom,
      'prenom': prenom,
      'telephone': telephone,
      'email': email,
      'mot_de_passe': motDePasse,
      if (situationMatrimoniale != null) 'situation_matrimoniale': situationMatrimoniale,
      if (quartier != null) 'quartier': quartier,
    });
    return data as Map<String, dynamic>;
  }

  Future<void> verifyOtp({required String telephone, required String otp}) async {
    await _client.post('/auth/verify-otp/', data: {'telephone': telephone, 'otp': otp});
  }

  /// Connexion. `identifiant` = téléphone OU e-mail. Stocke automatiquement
  /// les tokens (access/refresh) reçus dans le stockage sécurisé.
  ///
  /// ⚠️ CORRECTIF (audit Flutter↔Django, point 1 — désérialisation) :
  /// l'ancienne version faisait `data['access'] as String` directement. Si
  /// jamais le backend renvoie un jour `{"access": null, ...}` (bug serveur,
  /// migration en cours, endpoint modifié...), Dart lève un `TypeError`
  /// générique ("type 'Null' is not a subtype of type 'String'") qui n'est
  /// PAS une [ApiException] — remonte tel quel jusqu'à l'appelant. On
  /// valide donc explicitement la forme de la réponse et on lève une
  /// [ApiException] lisible plutôt qu'un crash Dart opaque.
  Future<Map<String, dynamic>> login({
    required String identifiant,
    required String motDePasse,
  }) async {
    final raw = await _client.post('/auth/login/', data: {
      'identifiant': identifiant,
      'mot_de_passe': motDePasse,
    });

    if (raw is! Map<String, dynamic>) {
      throw ApiException('Réponse de connexion invalide (format inattendu).');
    }
    final data = raw;

    final access = data['access'];
    final refresh = data['refresh'];
    final user = data['user'];
    if (access is! String || access.isEmpty) {
      throw ApiException('Réponse de connexion invalide (token d\'accès manquant).');
    }
    if (refresh is! String || refresh.isEmpty) {
      throw ApiException('Réponse de connexion invalide (token de rafraîchissement manquant).');
    }
    if (user is! Map<String, dynamic>) {
      throw ApiException('Réponse de connexion invalide (profil utilisateur manquant).');
    }

    await _tokenStorage.saveTokens(access: access, refresh: refresh);
    return data; // contient aussi data['user']
  }

  /// Déconnexion : blackliste le refresh token côté serveur puis nettoie le
  /// stockage local, que l'appel réseau réussisse ou non.
  Future<void> logout() async {
    final refresh = await _tokenStorage.refreshToken;
    try {
      if (refresh != null) {
        await _client.post('/auth/logout/', data: {'refresh': refresh});
      }
    } finally {
      await _tokenStorage.clear();
    }
  }

  Future<void> passwordResetRequest({required String identifiant}) async {
    await _client.post('/auth/password-reset/', data: {'identifiant': identifiant});
  }

  Future<void> passwordResetConfirm({
    required String token,
    required String nouveauMotDePasse,
  }) async {
    await _client.post('/auth/password-reset/confirm/', data: {
      'token': token,
      'nouveau_mot_de_passe': nouveauMotDePasse,
    });
  }

  /// Nécessite une ré-authentification par mot de passe (contrôle fait
  /// côté serveur dans `ChangePhoneNumberView.update`).
  Future<Map<String, dynamic>> changePhoneNumber({
    required String nouveauTelephone,
    required String motDePasseConfirmation,
  }) async {
    final data = await _client.patch('/auth/change-phone/', data: {
      'telephone': nouveauTelephone,
      'mot_de_passe_confirmation': motDePasseConfirmation,
    });
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getProfile() async {
    final data = await _client.get('/profile/');
    return data as Map<String, dynamic>;
  }

  /// Champs éditables : nom, prénom, situation_matrimoniale, quartier...
  /// (le téléphone passe exclusivement par [changePhoneNumber]).
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> fields) async {
    final data = await _client.patch('/profile/', data: fields);
    return data as Map<String, dynamic>;
  }

  Future<List<dynamic>> listConsents() async {
    final data = await _client.get('/profile/consent/');
    return data as List<dynamic>;
  }

  Future<Map<String, dynamic>> recordConsent({
    required String canal,
    required String versionCgu,
    required String action, // GRANTED | REVOKED
  }) async {
    final data = await _client.post('/profile/consent/', data: {
      'canal': canal,
      'version_cgu': versionCgu,
      'action': action,
    });
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getNotificationPreferences(int idCompteur) async {
    final data = await _client.get('/profile/compteurs/$idCompteur/notification-preferences/');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateNotificationPreferences(
    int idCompteur,
    Map<String, dynamic> preferences,
  ) async {
    final data = await _client.patch(
      '/profile/compteurs/$idCompteur/notification-preferences/',
      data: {'preferences': preferences},
    );
    return data as Map<String, dynamic>;
  }

  // =========================================================================
  // MODULE 2 — Contrats, comptes & compteurs
  // =========================================================================
  // REFONTE v1.5 : CONTRATS est la nouvelle racine du graphe de propriété
  // (Users 1—N Contrats 1—N Compteurs 1—N Factures).

  /// Contrats dont l'utilisateur courant est titulaire, triés du plus
  /// récent au plus ancien côté serveur. `search` filtre sur
  /// `numero_contrat` (correspondance partielle) — utilisé par la barre
  /// de recherche de l'accueil quand le client a plus de 3 contrats.
  /// CORRECTIF (audit lenteur accueil) : `GET /contrats/` est désormais
  /// paginé côté serveur (`ContratListCreateView.pagination_class =
  /// StandardResultsSetPagination`), donc la réponse est un objet DRF
  /// `{"count":.., "next":.., "previous":.., "results":[...]}` et non plus
  /// une liste JSON brute — d'où le retour en `dynamic` (à passer à
  /// `asList()` côté repository) plutôt qu'un cast direct en `List`, qui
  /// aurait fait planter l'appel.
  Future<dynamic> listContrats({String? search, int? pageSize}) async {
    final q = search?.trim();
    final query = <String, dynamic>{};
    if (q != null && q.isNotEmpty) query['search'] = q;
    if (pageSize != null) query['page_size'] = pageSize;
    return await _client.get('/contrats/', query: query.isEmpty ? null : query);
  }

  /// Suit le lien `next` d'une page DRF précédente (URL absolue renvoyée
  /// telle quelle par `GET /contrats/`) — utilisé par
  /// `EneoRepository.getAllContrats` pour parcourir toutes les pages d'un
  /// client qui a plus de `max_page_size` contrats, sans jamais refaire
  /// une requête par contrat.
  Future<dynamic> listContratsPage(String url) async {
    return await _client.get(url);
  }

  /// `numeroContrat` = numéro du contrat papier/Eneo à rattacher au compte
  /// (id_user, statut='Actif' et date_creation sont fixés côté serveur).
  Future<Map<String, dynamic>> createContrat({required String numeroContrat}) async {
    final data = await _client.post('/contrats/', data: {'numero_contrat': numeroContrat});
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getContrat(int idContrat) async {
    final data = await _client.get('/contrats/$idContrat/');
    return data as Map<String, dynamic>;
  }

  /// Compteurs rattachés à ce contrat (accessible au titulaire ou à un
  /// délégataire du contrat entier).
  Future<List<dynamic>> listContratCompteurs(int idContrat) async =>
      await _client.get('/contrats/$idContrat/compteurs/') as List<dynamic>;

  /// Factures agrégées, tous compteurs du contrat confondus. Filtres
  /// optionnels et cumulables : `statut` ∈ {Payée, En cours, Impayée},
  /// `idCompteur` pour restreindre à un seul compteur du contrat,
  /// `historiqueComplet` pour sortir de la fenêtre glissante des 12
  /// derniers mois (RG-14).
  Future<dynamic> listContratFactures(
    int idContrat, {
    String? statut,
    int? idCompteur,
    bool historiqueComplet = false,
  }) {
    final query = <String, dynamic>{};
    if (statut != null) query['statut'] = statut;
    if (idCompteur != null) query['id_compteur'] = idCompteur.toString();
    if (historiqueComplet) query['historique_complet'] = 'true';
    return _client.get('/contrats/$idContrat/factures/', query: query.isEmpty ? null : query);
  }

  Future<List<dynamic>> listCompteurs() async => await _client.get('/compteurs/') as List<dynamic>;

  Future<Map<String, dynamic>> createCompteur(Map<String, dynamic> payload) async {
    final data = await _client.post('/compteurs/', data: payload);
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCompteur(int idCompteur) async {
    final data = await _client.get('/compteurs/$idCompteur/');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCompteur(int idCompteur, Map<String, dynamic> payload) async {
    final data = await _client.patch('/compteurs/$idCompteur/', data: payload);
    return data as Map<String, dynamic>;
  }

  /// Retrait "soft" du compteur du profil (révoque la délégation ; le
  /// compteur physique n'est jamais supprimé, cf. commentaire
  /// `CompteurDetailView.destroy` dans views.py).
  Future<void> removeCompteurFromProfile(int idCompteur) async {
    await _client.delete('/compteurs/$idCompteur/');
  }

  /// RG-03 : réservé au rôle Admin_Technicien côté backend.
  ///
  /// REFONTE v1.5 — le transfert réaffecte désormais réellement le
  /// compteur vers un AUTRE contrat (`nouveauIdContrat`), ce qui le déplace
  /// mécaniquement dans le graphe de propriété (les délégations à portée
  /// "contrat" de l'ancien contrat cessent de s'appliquer ; celles à
  /// portée "compteur" restent valides).
  Future<Map<String, dynamic>> transferCompteur({
    required int idCompteur,
    required int nouveauIdContrat,
    String? nouveauProprietaireLegal,
    String motif = '',
  }) async {
    final data = await _client.post('/compteurs/$idCompteur/transfert/', data: {
      'nouveau_id_contrat': nouveauIdContrat,
      if (nouveauProprietaireLegal != null) 'nouveau_proprietaire_legal': nouveauProprietaireLegal,
      'motif': motif,
    });
    return data as Map<String, dynamic>;
  }

  /// Réservé au rôle Agent_Terrain — enregistrement initial d'un compteur.
  Future<Map<String, dynamic>> registerCompteurAsAgentTerrain(Map<String, dynamic> payload) async {
    final data = await _client.post('/compteurs/agent-terrain/enregistrement/', data: payload);
    return data as Map<String, dynamic>;
  }

  /// Recherche EXACTE d'un utilisateur par téléphone, pour pré-remplir la
  /// création d'une délégation (RG-02, `UserRechercheView` côté backend).
  /// Renvoie `null` si aucun utilisateur ne correspond (404) plutôt que de
  /// laisser remonter l'exception : l'appelant doit pouvoir afficher
  /// "aucun résultat" sans un try/catch dédié pour ce seul cas.
  Future<Map<String, dynamic>?> rechercherUtilisateurParTelephone(String telephone) async {
    try {
      final data = await _client.get('/users/recherche/', query: {'telephone': telephone});
      return data as Map<String, dynamic>;
    } on ApiNotFoundException {
      return null;
    }
  }

  Future<List<dynamic>> listDelegations() async => await _client.get('/delegations/') as List<dynamic>;

  /// `typeDroit` ∈ {Lecture, Paiement, Lecture_Paiement} (REFONTE v1.5).
  ///
  /// REFONTE v1.5 — exactement UN des deux doit être fourni :
  ///  - `idCompteur` : délégation sur ce compteur uniquement ;
  ///  - `idContrat` : délégation sur TOUT le contrat (compteurs actuels et
  ///    futurs) ; seul son titulaire peut l'accorder.
  /// Fournir les deux, ou aucun des deux, lève une [ArgumentError] côté
  /// client avant même d'atteindre le serveur (qui rejetterait de toute
  /// façon via `GestionCompteursSerializer.validate`).
  Future<Map<String, dynamic>> createDelegation({
    required int idUser,
    int? idCompteur,
    int? idContrat,
    required String typeDroit,
  }) async {
    if ((idCompteur == null) == (idContrat == null)) {
      throw ArgumentError(
        'createDelegation: fournir exactement un de idCompteur OU idContrat, jamais les deux, jamais aucun des deux.',
      );
    }
    final data = await _client.post('/delegations/', data: {
      'id_user': idUser,
      if (idCompteur != null) 'id_compteur': idCompteur,
      if (idContrat != null) 'id_contrat': idContrat,
      'type_droit': typeDroit,
    });
    return data as Map<String, dynamic>;
  }

  Future<void> revokeDelegation(int idDelegation) async {
    await _client.post('/delegations/$idDelegation/revoquer/');
  }

  // =========================================================================
  // MODULE 3 — Client postpayé
  // =========================================================================

  /// Par défaut : 12 dernières factures. `historiqueComplet: true` pour tout
  /// l'historique (RG-14).
  Future<dynamic> listFactures(int idCompteur, {bool historiqueComplet = false}) {
    return _client.get(
      '/compteurs/$idCompteur/factures/',
      query: historiqueComplet ? {'historique_complet': 'true'} : null,
    );
  }

  Future<Map<String, dynamic>> getConsommationGraph(int idCompteur) async {
    final data = await _client.get('/compteurs/$idCompteur/consommation/');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getFacture(String idFacture) async {
    final data = await _client.get('/factures/$idFacture/');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getFactureStatut(String idFacture) async {
    final data = await _client.get('/factures/$idFacture/statut/');
    return data as Map<String, dynamic>;
  }

  /// Le backend renvoie pour l'instant les données brutes du reçu (la
  /// génération PDF réelle est un TODO INTEGRATION côté serveur, cf.
  /// `FactureReçuPDFView`) — adapte le parsing si tu branches un vrai
  /// FileResponse plus tard.
  Future<Map<String, dynamic>> getFactureRecu(String idFacture) async {
    final data = await _client.get('/factures/$idFacture/recu/');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> signalerAnomalieFacture(
    String idFacture, {
    required String description,
  }) async {
    final data = await _client.post('/factures/$idFacture/signaler-anomalie/', data: {
      'description': description,
    });
    return data as Map<String, dynamic>;
  }

  // =========================================================================
  // MODULE 4 — Client prépayé
  // =========================================================================

  Future<Map<String, dynamic>> getSoldeCredit(int idCompteur) async {
    final data = await _client.get('/compteurs/$idCompteur/solde/');
    return data as Map<String, dynamic>;
  }

  /// Montant encadré côté serveur entre 500 et 500 000 FCFA (cf.
  /// `AchatCreditView.MONTANT_MIN_FCFA` / `MONTANT_MAX_FCFA`).
  Future<Map<String, dynamic>> achatCredit(int idCompteur, {required double montantFcfa}) async {
    final data = await _client.post('/compteurs/$idCompteur/achat-credit/', data: {
      'montant_fcfa': montantFcfa,
    });
    return data as Map<String, dynamic>;
  }

  Future<dynamic> getTokenHistorique(int idCompteur) {
    return _client.get('/compteurs/$idCompteur/tokens/');
  }

  Future<Map<String, dynamic>> getAlerteSoldeBas(int idCompteur, {double seuilKwh = 5}) async {
    final data = await _client.get(
      '/compteurs/$idCompteur/alerte-solde-bas/',
      query: {'seuil_kwh': seuilKwh.toString()},
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setSeuilAlerteSoldeBas(int idCompteur, {required double seuilKwh}) async {
    final data = await _client.post('/compteurs/$idCompteur/alerte-solde-bas/', data: {
      'seuil_kwh': seuilKwh,
    });
    return data as Map<String, dynamic>;
  }

  /// Réservé aux comptes techniques (IsCompteTechnique) — pas destiné à un
  /// appel direct depuis l'app cliente, documenté ici pour complétude.
  Future<Map<String, dynamic>> alerteTechniqueCompteur(
    int idCompteur, {
    required String typeAlerte,
    String message = '',
  }) async {
    final data = await _client.post('/compteurs/$idCompteur/alerte-technique/', data: {
      'type_alerte': typeAlerte,
      'message': message,
    });
    return data as Map<String, dynamic>;
  }

  // =========================================================================
  // MODULE 5 — Paiements & agrégateurs Mobile Money
  // =========================================================================

  /// `typePaiement` ∈ {"FACTURE", "RECHARGE"} (mappé côté serveur vers
  /// l'ENUM `Facture_Postpayee` / `Recharge_Prepayee`).
  /// `operateurMobileMoney` ∈ {"MTN_MOMO", "ORANGE_MONEY"}.
  /// RG-06 : au-delà de 50 000 FCFA, `otpConfirmation` est obligatoire.
  Future<Map<String, dynamic>> initierPaiement({
    required String typePaiement,
    required String referenceCible,
    required double montantFcfa,
    required String numeroMobileMoney,
    required String operateurMobileMoney,
    String? otpConfirmation,
  }) async {
    final data = await _client.post('/paiements/initier/', data: {
      'type_paiement': typePaiement,
      'reference_cible': referenceCible,
      'montant_fcfa': montantFcfa,
      'numero_mobile_money': numeroMobileMoney,
      'operateur_mobile_money': operateurMobileMoney,
      if (otpConfirmation != null) 'otp_confirmation': otpConfirmation,
    });
    return data as Map<String, dynamic>;
  }

  // Note : `/paiements/webhook/` (WebhookPaiementView) n'a pas de méthode ici
  // — c'est un endpoint serveur-à-serveur appelé par l'agrégateur Mobile
  // Money via un compte technique, jamais depuis l'app Flutter.

  Future<Map<String, dynamic>> getPaiementStatut(String idPaiement) async {
    final data = await _client.get('/paiements/$idPaiement/');
    return data as Map<String, dynamic>;
  }

  /// Réservé à IsAdminFinancier. RG-06 : `otpConfirmation` obligatoire.
  Future<Map<String, dynamic>> rembourserPaiement(
    String idPaiement, {
    required String otpConfirmation,
    String motif = '',
  }) async {
    final data = await _client.post('/paiements/$idPaiement/rembourser/', data: {
      'otp_confirmation': otpConfirmation,
      'motif': motif,
    });
    return data as Map<String, dynamic>;
  }

  /// Réservé à IsAdminFinancier. `date` au format YYYY-MM-DD.
  Future<Map<String, dynamic>> reconciliationComptable({String? date}) async {
    final data = await _client.get('/paiements/reconciliation/', query: date != null ? {'date': date} : null);
    return data as Map<String, dynamic>;
  }

  // =========================================================================
  // MODULE 6 — Notifications
  // Partagé entre Dashboard ET Paramètres : même endpoint, même donnée.
  // Le badge "non lues" est synchronisé automatiquement car les deux écrans
  // interrogent le même `/notifications/non-lues/count/`.
  // =========================================================================

  /// Liste paginée des notifications.
  /// [nonLuesSeulement] : si true, n'inclut que les notifications non lues
  /// (pratique pour l'écran Paramètres qui affiche un compteur de non-lues).
  Future<dynamic> listNotifications({bool nonLuesSeulement = false}) {
    final query = nonLuesSeulement ? {'non_lues': 'true'} : null;
    return _client.get('/notifications/', query: query);
  }

  /// Page suivante de `/notifications/` (pagination DRF, lien `next`).
  Future<dynamic> listNotificationsPage(String url) => _client.get(url);

  /// Retourne le nombre de notifications non lues : {"count": int}.
  /// Appelé par le badge du dashboard ET par l'écran Paramètres → synchronisé.
  Future<int> countNotificationsNonLues() async {
    final data = await _client.get('/notifications/non-lues/count/');
    return (data as Map<String, dynamic>)['count'] as int? ?? 0;
  }

  /// Marque une notification individuelle comme lue (date_lecture = now()).
  /// Appel depuis dashboard OU paramètres — le flag est commun en base.
  Future<Map<String, dynamic>> marquerNotificationLue(String idNotification) async {
    final data = await _client.patch('/notifications/$idNotification/lue/');
    return data as Map<String, dynamic>;
  }

  /// Marque toutes les notifications non lues comme lues.
  /// Accessible depuis le dashboard ET l'écran Paramètres.
  Future<Map<String, dynamic>> marquerToutesNotificationsLues() async {
    final data = await _client.post('/notifications/tout-lire/');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registerDevice({
    required String fcmToken,
    required String typeAppareil,
  }) async {
    final data = await _client.post('/devices/', data: {
      'fcm_token': fcmToken,
      'type_appareil': typeAppareil,
    });
    return data as Map<String, dynamic>;
  }

  Future<void> unregisterDevice(int idDevice) async {
    await _client.post('/devices/$idDevice/desenregistrer/');
  }

  // =========================================================================
  // MODULE 7 — Back-office administrateur (réservé aux rôles admin côté API)
  // =========================================================================

  Future<Map<String, dynamic>> getAdminDashboardKpi() async {
    final data = await _client.get('/admin/dashboard/kpi/');
    return data as Map<String, dynamic>;
  }

  Future<dynamic> listAdminUsers() => _client.get('/admin/utilisateurs/');

  Future<Map<String, dynamic>> createAdminUser(Map<String, dynamic> payload) async {
    final data = await _client.post('/admin/utilisateurs/', data: payload);
    return data as Map<String, dynamic>;
  }

  /// RG-04 : `motif` obligatoire côté serveur.
  Future<Map<String, dynamic>> startImpersonation(int idUserCible, {required String motif}) async {
    final data = await _client.post('/admin/impersonation/$idUserCible/start/', data: {'motif': motif});
    return data as Map<String, dynamic>;
  }

  Future<void> endImpersonation(int idUserCible) async {
    await _client.post('/admin/impersonation/$idUserCible/end/');
  }

  Future<dynamic> listAuditLogs() => _client.get('/admin/audit-logs/');

  Future<dynamic> listWebhookLogs() => _client.get('/admin/webhook-logs/');

  Future<dynamic> listLitiges({String? niveau, String? statut}) {
    final query = <String, dynamic>{};
    if (niveau != null) query['niveau'] = niveau;
    if (statut != null) query['statut'] = statut;
    return _client.get('/litiges/', query: query.isEmpty ? null : query);
  }

  Future<Map<String, dynamic>> creerLitige(Map<String, dynamic> payload) async {
    final data = await _client.post('/litiges/ouvrir/', data: payload);
    return data as Map<String, dynamic>;
  }

  /// `action` ∈ {"RENVOI_JETON", "FORCAGE_JETON", "REMBOURSEMENT", "REJET"}.
  /// FORCAGE_JETON et REMBOURSEMENT nécessitent le rôle Admin_Financier
  /// (contrôlé côté serveur).
  Future<Map<String, dynamic>> resoudreLitige(
    String idLitige, {
    required String action,
    String resolution = '',
  }) async {
    final data = await _client.post('/litiges/$idLitige/resoudre/', data: {
      'action': action,
      'resolution': resolution,
    });
    return data as Map<String, dynamic>;
  }

  // =========================================================================
  // MODULE 8 — Référentiels
  // =========================================================================

  Future<dynamic> listTarifs({String? typeCompteur}) {
    return _client.get('/tarifs/', query: typeCompteur != null ? {'type_compteur': typeCompteur} : null);
  }

  Future<dynamic> listAdresses() => _client.get('/adresses/');

  Future<Map<String, dynamic>> createAdresse(Map<String, dynamic> payload) async {
    final data = await _client.post('/adresses/', data: payload);
    return data as Map<String, dynamic>;
  }

  // =========================================================================
  // MODULE 9 — Conformité / RGPD
  // =========================================================================

  Future<Map<String, dynamic>> exportMyData() async {
    final data = await _client.get('/compte/export/');
    return data as Map<String, dynamic>;
  }

  /// Nécessite `mot_de_passe_confirmation` (ré-authentification, cf.
  /// `DeleteAccountView`). Le profil est anonymisé mais l'historique
  /// financier est conservé (obligations légales, RG-12).
  Future<Map<String, dynamic>> deactivateAccount({required String motDePasseConfirmation}) async {
    final data = await _client.post('/compte/desactiver/', data: {
      'mot_de_passe_confirmation': motDePasseConfirmation,
    });
    return data as Map<String, dynamic>;
  }

  // =========================================================================
  // MODULE 10 — Assistant de support IA (écran Assistance & Paramètres)
  // =========================================================================
  // Point d'entrée UNIQUE du chatbot Gemini — appelé indifféremment depuis :
  //   • L'écran "Support" du dashboard (bouton "Chat en direct").
  //   • L'écran "Paramètres" (section "Chat en direct" / "Écrire un message").
  // Les deux écrans envoient le même payload ; le serveur est stateless.

  /// Envoie un tour de conversation au chatbot IA de support.
  ///
  /// [messages] est l'historique COMPLET de la conversation : liste de
  /// `{'role': 'user'|'assistant', 'content': '...'}`, dernier élément
  /// obligatoirement `role: 'user'`.
  ///
  /// Réponse : `{'reponse': '...', 'escalade_recommandee': bool}`.
  /// Si [escalade_recommandee] est true, proposer à l'utilisateur d'ouvrir
  /// un ticket via [ouvrirTicket].
  Future<Map<String, dynamic>> supportChat(List<Map<String, String>> messages) async {
    final data = await _client.post('/support/chat/', data: {'messages': messages});
    return data as Map<String, dynamic>;
  }

  // =========================================================================
  // MODULE 11 — Tickets de support (écran Paramètres → "Ouvrir un ticket")
  // =========================================================================
  // Crée un litige formel en base ET envoie deux e-mails HTML professionnels :
  //   • Au client    : accusé de réception + numéro de ticket.
  //   • À l'équipe support : fiche complète du dossier client.

  /// Ouvre un ticket de support et déclenche l'envoi des e-mails SMTP.
  ///
  /// Paramètres :
  ///   [sujet]       : titre court du problème (obligatoire, max 200 chars).
  ///   [description] : détail complet (obligatoire, min 20 chars).
  ///   [categorie]   : "Facturation"|"Recharge"|"Technique"|"Paiement"|"Autre"
  ///                   (optionnel, défaut "Autre").
  ///   [priorite]    : "Normale"|"Haute"|"Urgente" (optionnel, défaut "Normale").
  ///   [idCompteur]  : ID du compteur concerné (optionnel).
  ///
  /// Réponse 201 :
  ///   {
  ///     "ticket_id":            "TKT-XXXXXXXXXXXXXXXX",
  ///     "statut":               "Ouvert",
  ///     "message":              String,
  ///     "email_client_envoye":  bool,
  ///     "email_support_envoye": bool
  ///   }
  Future<Map<String, dynamic>> ouvrirTicket({
    required String sujet,
    required String description,
    String categorie = 'Autre',
    String priorite  = 'Normale',
    int?   idCompteur,
  }) async {
    final payload = <String, dynamic>{
      'sujet'      : sujet,
      'description': description,
      'categorie'  : categorie,
      'priorite'   : priorite,
    };
    if (idCompteur != null) payload['id_compteur'] = idCompteur;

    final data = await _client.post('/support/tickets/ouvrir/', data: payload);
    return data as Map<String, dynamic>;
  }
}
