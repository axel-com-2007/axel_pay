// ============================================================
// MODÈLES DE DONNÉES
// ============================================================
// Ces classes reflètent le modèle de données du cahier des charges
// (section 8). Chaque classe expose désormais un `fromJson` qui
// mappe EXACTEMENT les champs renvoyés par les serializers DRF
// (voir api/serializers.py + api/models.py côté backend).
//
// ⚠️ Plusieurs écrans ont besoin de données qui ne sortent PAS
// directement d'un seul endpoint (ex : l'adresse texte d'un
// compteur, son solde, son dernier jeton...). Ces champs restent
// `null` après un `fromJson` "brut" et sont complétés via
// `copyWith(...)` par la couche d'orchestration (voir
// `lib/data/eneo_repository.dart`) qui agrège plusieurs appels API.
// ============================================================

enum TypeCompteur { prepaye, postpaye }

enum StatutFacture { payee, enCours, impayee }

enum StatutTransaction { reussi, enAttente, echoue }

enum DroitDelegation { lecture, lectureEtPaiement }

enum StatutContrat { actif, suspendu, resilie }

/// REFONTE v1.5 — une délégation porte soit sur un compteur précis, soit
/// sur un contrat entier (tous ses compteurs actuels ET futurs). Reflète
/// la contrainte CHECK `chk_gestion_compteurs_scope_exclusif` côté SQL.
enum PorteeDelegation { compteur, contrat }

// ---- Helpers de parsing tolérants (DRF renvoie parfois des String
// pour des DecimalField, parfois des num) ----

double _num(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

DateTime _date(dynamic v) {
  if (v == null) return DateTime.now();
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString()) ?? DateTime.now();
}

const List<String> _moisFr = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
];

const List<String> _moisFrCourt = [
  'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
  'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc',
];

/// "2026-07-01" (DateField `mois_facturation`) -> "Juillet 2026"
String moisLabelLong(DateTime d) => '${_moisFr[d.month - 1]} ${d.year}';

/// -> "Juil"
String moisLabelCourt(DateTime d) => _moisFrCourt[d.month - 1];

class UserModel {
  final int? idUser;
  final String nom;
  final String prenom;
  final String telephone; // format +237XXXXXXXXX
  final String email;
  final String quartier;
  final String situationMatrimoniale;
  final String? avatarUrl;

  const UserModel({
    this.idUser,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.email,
    required this.quartier,
    required this.situationMatrimoniale,
    this.avatarUrl,
  });

  /// Mappe la sortie de `UsersSerializer` (ProfileView, LoginView...).
  /// `mot_de_passe` n'est jamais présent (write_only côté serializer).
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      idUser: json['id_user'] is int ? json['id_user'] as int : int.tryParse('${json['id_user']}'),
      nom: json['nom'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      telephone: json['telephone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      quartier: json['quartier'] as String? ?? '',
      situationMatrimoniale: json['situation_matrimoniale'] as String? ?? '',
    );
  }

  String get nomComplet => '$prenom $nom';
  String get initiales =>
      '${prenom.isNotEmpty ? prenom[0] : ''}${nom.isNotEmpty ? nom[0] : ''}'
          .toUpperCase();

  /// Sérialisation pour le CACHE LOCAL (§7.6) — format interne, distinct
  /// de `fromJson` (qui mappe le format serveur DRF). Utilisé par
  /// `EneoRepository`/`LocalCache` pour persister le dernier profil connu
  /// et le relire hors-ligne, champ Dart pour champ Dart (pas de perte
  /// d'information contrairement à un aller-retour par `fromJson`).
  Map<String, dynamic> toCacheJson() => {
        'idUser': idUser,
        'nom': nom,
        'prenom': prenom,
        'telephone': telephone,
        'email': email,
        'quartier': quartier,
        'situationMatrimoniale': situationMatrimoniale,
        'avatarUrl': avatarUrl,
      };

  factory UserModel.fromCacheJson(Map<String, dynamic> json) {
    return UserModel(
      idUser: json['idUser'] as int?,
      nom: json['nom'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      telephone: json['telephone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      quartier: json['quartier'] as String? ?? '',
      situationMatrimoniale: json['situationMatrimoniale'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

/// REFONTE v1.5 — nouvelle racine du graphe de propriété :
/// Users (1—N) Contrats (1—N) Compteurs (1—N) Factures.
/// Mappe la sortie de `ContratsSerializer`.
class ContratModel {
  final String id;
  final String numeroContrat;
  final StatutContrat statut;
  final DateTime dateCreation;
  final DateTime? dateResiliation;

  /// Nombre de compteurs rattachés — renvoyé directement par
  /// `ContratsSerializer.nombre_compteurs` (annotation `Count()` côté
  /// Django, voir `ContratListCreateView.get_queryset`). Avant le
  /// correctif de l'audit "lenteur accueil", ce champ n'existait pas côté
  /// backend et nécessitait un second appel HTTP par contrat
  /// (`GET /contrats/<id>/compteurs/`) — jusqu'à 250 requêtes
  /// séquentielles pour l'accueil.
  final int? nombreCompteurs;

  const ContratModel({
    required this.id,
    required this.numeroContrat,
    required this.statut,
    required this.dateCreation,
    this.dateResiliation,
    this.nombreCompteurs,
  });

  factory ContratModel.fromJson(Map<String, dynamic> json) {
    return ContratModel(
      id: '${json['id_contrat']}',
      numeroContrat: json['numero_contrat'] as String? ?? '',
      statut: _statutContratFromApi(json['statut'] as String?),
      dateCreation: _date(json['date_creation']),
      dateResiliation:
          json['date_resiliation'] != null ? _date(json['date_resiliation']) : null,
      nombreCompteurs: json['nombre_compteurs'] as int? ??
          int.tryParse('${json['nombre_compteurs'] ?? ''}'),
    );
  }

  ContratModel copyWith({int? nombreCompteurs}) {
    return ContratModel(
      id: id,
      numeroContrat: numeroContrat,
      statut: statut,
      dateCreation: dateCreation,
      dateResiliation: dateResiliation,
      nombreCompteurs: nombreCompteurs ?? this.nombreCompteurs,
    );
  }

  String get statutLabel {
    switch (statut) {
      case StatutContrat.actif:
        return 'Actif';
      case StatutContrat.suspendu:
        return 'Suspendu';
      case StatutContrat.resilie:
        return 'Résilié';
    }
  }

  /// Cf. `UserModel.toCacheJson` — même principe.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'numeroContrat': numeroContrat,
        'statut': statut.name,
        'dateCreation': dateCreation.toIso8601String(),
        'dateResiliation': dateResiliation?.toIso8601String(),
        'nombreCompteurs': nombreCompteurs,
      };

  factory ContratModel.fromCacheJson(Map<String, dynamic> json) {
    return ContratModel(
      id: json['id'] as String? ?? '',
      numeroContrat: json['numeroContrat'] as String? ?? '',
      statut: StatutContrat.values.byName(json['statut'] as String? ?? 'actif'),
      dateCreation: DateTime.tryParse(json['dateCreation'] as String? ?? '') ?? DateTime.now(),
      dateResiliation: json['dateResiliation'] != null
          ? DateTime.tryParse(json['dateResiliation'] as String)
          : null,
      nombreCompteurs: json['nombreCompteurs'] as int?,
    );
  }
}

StatutContrat _statutContratFromApi(String? v) {
  switch (v) {
    case 'Suspendu':
      return StatutContrat.suspendu;
    case 'Résilié':
      return StatutContrat.resilie;
    case 'Actif':
    default:
      return StatutContrat.actif;
  }
}

class CompteurModel {
  final String id;
  final String numero;
  final TypeCompteur type;
  final String adresse;
  final bool actif;
  final DateTime derniereMiseAJour;

  // REFONTE v1.5 : chaque compteur est désormais rattaché à un contrat
  // (Compteurs.id_contrat, FK NOT NULL côté SQL).
  final int idContrat;
  // Le libellé n'est pas renvoyé par `CompteursSerializer` (seul l'entier
  // `id_contrat` l'est) : résolu séparément via `GET /contrats/` puis
  // complété par `copyWith(...)`, comme `adresse` l'est déjà pour
  // `id_adresse`.
  final String? numeroContrat;

  // Champs spécifiques Postpayé
  final double? soldeDuFcfa;

  // Champs spécifiques Prépayé
  final double? soldeKwh;
  final double? soldeFcfaEquivalent;
  final int? joursAutonomieEstimes;
  final String? dernierToken;
  final DateTime? dateDernierToken;

  const CompteurModel({
    required this.id,
    required this.numero,
    required this.type,
    required this.adresse,
    required this.actif,
    required this.derniereMiseAJour,
    required this.idContrat,
    this.numeroContrat,
    this.soldeDuFcfa,
    this.soldeKwh,
    this.soldeFcfaEquivalent,
    this.joursAutonomieEstimes,
    this.dernierToken,
    this.dateDernierToken,
  });

  /// Mappe la sortie brute de `CompteursSerializer` (fields = '__all__').
  ///
  /// ⚠️ Le backend ne renvoie QUE `id_adresse` (l'identifiant de la ligne
  /// `Adresses`), jamais le libellé texte : il faut un second appel à
  /// `GET /adresses/` pour le résoudre (voir `EneoRepository`). Idem pour
  /// le solde, le dernier jeton, etc. — absents de ce endpoint, ils
  /// restent `null` tant que `copyWith(...)` n'a pas été appelé avec les
  /// données des endpoints dédiés (`/solde/`, `/tokens/`, `/factures/`).
  factory CompteurModel.fromJson(
    Map<String, dynamic> json, {
    String? adresseLabel,
    String? numeroContrat,
  }) {
    final idContrat = json['id_contrat'] is int
        ? json['id_contrat'] as int
        : int.tryParse('${json['id_contrat']}') ?? 0;
    return CompteurModel(
      id: '${json['id_compteur']}',
      numero: json['numero_compteur'] as String? ?? '',
      type: (json['type_compteur'] == 'PREPAYE') ? TypeCompteur.prepaye : TypeCompteur.postpaye,
      adresse: adresseLabel ?? '',
      actif: (json['statut'] as String? ?? 'Actif') == 'Actif',
      derniereMiseAJour: _date(json['date_creation']),
      idContrat: idContrat,
      numeroContrat: numeroContrat,
    );
  }

  CompteurModel copyWith({
    String? adresse,
    bool? actif,
    DateTime? derniereMiseAJour,
    String? numeroContrat,
    double? soldeDuFcfa,
    double? soldeKwh,
    double? soldeFcfaEquivalent,
    int? joursAutonomieEstimes,
    String? dernierToken,
    DateTime? dateDernierToken,
  }) {
    return CompteurModel(
      id: id,
      numero: numero,
      type: type,
      adresse: adresse ?? this.adresse,
      actif: actif ?? this.actif,
      derniereMiseAJour: derniereMiseAJour ?? this.derniereMiseAJour,
      idContrat: idContrat,
      numeroContrat: numeroContrat ?? this.numeroContrat,
      soldeDuFcfa: soldeDuFcfa ?? this.soldeDuFcfa,
      soldeKwh: soldeKwh ?? this.soldeKwh,
      soldeFcfaEquivalent: soldeFcfaEquivalent ?? this.soldeFcfaEquivalent,
      joursAutonomieEstimes: joursAutonomieEstimes ?? this.joursAutonomieEstimes,
      dernierToken: dernierToken ?? this.dernierToken,
      dateDernierToken: dateDernierToken ?? this.dateDernierToken,
    );
  }

  String get statutLabel => actif ? 'Actif' : 'Suspendu';

  String get typeLabel =>
      type == TypeCompteur.prepaye ? 'Prépayé' : 'Postpayé';

  /// Texte de fraîcheur des données, utile pour le mode hors-ligne
  /// (section 7.6 du cahier des charges).
  String freshnessLabel(DateTime now) {
    final diff = now.difference(derniereMiseAJour);
    if (diff.inMinutes < 1) return 'Mise à jour à l’instant';
    if (diff.inMinutes < 60) return 'Dernière mise à jour : il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Dernière mise à jour : il y a ${diff.inHours} h';
    return 'Dernière mise à jour : il y a ${diff.inDays} j';
  }

  /// Sérialisation pour le CACHE LOCAL (§7.6). Capture l'objet
  /// ENTIÈREMENT ENRICHI (solde, dernier jeton, adresse résolue...), pas
  /// seulement les champs bruts du serializer DRF — contrairement à
  /// `fromJson`, qui ne connaît que la forme serveur et perdrait tout
  /// l'enrichissement fait par `EneoRepository` (adresse, solde, jeton).
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'numero': numero,
        'type': type.name,
        'adresse': adresse,
        'actif': actif,
        'derniereMiseAJour': derniereMiseAJour.toIso8601String(),
        'idContrat': idContrat,
        'numeroContrat': numeroContrat,
        'soldeDuFcfa': soldeDuFcfa,
        'soldeKwh': soldeKwh,
        'soldeFcfaEquivalent': soldeFcfaEquivalent,
        'joursAutonomieEstimes': joursAutonomieEstimes,
        'dernierToken': dernierToken,
        'dateDernierToken': dateDernierToken?.toIso8601String(),
      };

  factory CompteurModel.fromCacheJson(Map<String, dynamic> json) {
    return CompteurModel(
      id: json['id'] as String? ?? '',
      numero: json['numero'] as String? ?? '',
      type: TypeCompteur.values.byName(json['type'] as String? ?? 'postpaye'),
      adresse: json['adresse'] as String? ?? '',
      actif: json['actif'] as bool? ?? true,
      derniereMiseAJour:
          DateTime.tryParse(json['derniereMiseAJour'] as String? ?? '') ?? DateTime.now(),
      idContrat: json['idContrat'] as int? ?? 0,
      numeroContrat: json['numeroContrat'] as String?,
      soldeDuFcfa: (json['soldeDuFcfa'] as num?)?.toDouble(),
      soldeKwh: (json['soldeKwh'] as num?)?.toDouble(),
      soldeFcfaEquivalent: (json['soldeFcfaEquivalent'] as num?)?.toDouble(),
      joursAutonomieEstimes: json['joursAutonomieEstimes'] as int?,
      dernierToken: json['dernierToken'] as String?,
      dateDernierToken: json['dateDernierToken'] != null
          ? DateTime.tryParse(json['dateDernierToken'] as String)
          : null,
    );
  }
}

class ConsommationPoint {
  final String moisLabel; // ex: "Jan"
  final double kwh;
  final double fcfa;

  /// Date complète du point (1er jour de la période), conservée en plus
  /// du libellé court pour permettre de filtrer la série sur une plage
  /// de dates (ex : calendrier "historique de consommation").
  final DateTime periode;

  const ConsommationPoint({
    required this.moisLabel,
    required this.kwh,
    required this.fcfa,
    required this.periode,
  });

  /// Mappe une entrée de la `serie` renvoyée par `ConsommationGraphView`
  /// (`{"periode": "2026-06-01", "kwh": ..., "fcfa": ...}`).
  factory ConsommationPoint.fromJson(Map<String, dynamic> json) {
    final periode = _date(json['periode']);
    return ConsommationPoint(
      moisLabel: moisLabelCourt(periode),
      kwh: _num(json['kwh']),
      fcfa: _num(json['fcfa']),
      periode: periode,
    );
  }
}

class FactureModel {
  final String id;
  final String moisFacturation; // ex: "Juin 2026"
  final double montantFcfa;
  final double indexConsommation;
  final StatutFacture statut;
  final DateTime dateLimite;

  // Présent dans la sortie brute de `FacturesPostpayeesSerializer`
  // (fields='__all__') — utile pour la vue AGRÉGÉE par contrat
  // (`ContratFacturesListView`), où plusieurs compteurs sont mélangés dans
  // une même liste et il faut pouvoir afficher/filtrer par compteur.
  final int idCompteur;

  /// Libellé du compteur (ex: "CM-2026-004821") — jamais renvoyé par le
  /// serializer (seul l'entier `id_compteur` l'est) : résolu côté écran en
  /// croisant avec la liste des compteurs du contrat déjà chargée, puis
  /// complété via [copyWith].
  final String? compteurNumero;

  const FactureModel({
    required this.id,
    required this.moisFacturation,
    required this.montantFcfa,
    required this.indexConsommation,
    required this.statut,
    required this.dateLimite,
    this.idCompteur = 0,
    this.compteurNumero,
  });

  /// Mappe la sortie de `FacturesPostpayeesSerializer`.
  factory FactureModel.fromJson(Map<String, dynamic> json) {
    return FactureModel(
      id: '${json['id_facture']}',
      moisFacturation: moisLabelLong(_date(json['mois_facturation'])),
      montantFcfa: _num(json['montant_fcfa']),
      indexConsommation: _num(json['index_consommation']),
      statut: _statutFactureFromApi(json['statut'] as String?),
      dateLimite: _date(json['date_limite']),
      idCompteur: json['id_compteur'] is int
          ? json['id_compteur'] as int
          : int.tryParse('${json['id_compteur']}') ?? 0,
    );
  }

  FactureModel copyWith({String? compteurNumero}) {
    return FactureModel(
      id: id,
      moisFacturation: moisFacturation,
      montantFcfa: montantFcfa,
      indexConsommation: indexConsommation,
      statut: statut,
      dateLimite: dateLimite,
      idCompteur: idCompteur,
      compteurNumero: compteurNumero ?? this.compteurNumero,
    );
  }

  String get statutLabel {
    switch (statut) {
      case StatutFacture.payee:
        return 'Payée';
      case StatutFacture.enCours:
        return 'En cours';
      case StatutFacture.impayee:
        return 'Impayée';
    }
  }

  /// Cf. `CompteurModel.toCacheJson` — `moisFacturation` est déjà un
  /// libellé formaté ("Juin 2026") côté Dart, sans date brute conservée :
  /// un aller-retour par `fromJson` (qui attend une date ISO à reformater)
  /// le corromprait. On sérialise donc l'état Dart tel quel.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'moisFacturation': moisFacturation,
        'montantFcfa': montantFcfa,
        'indexConsommation': indexConsommation,
        'statut': statut.name,
        'dateLimite': dateLimite.toIso8601String(),
        'idCompteur': idCompteur,
        'compteurNumero': compteurNumero,
      };

  factory FactureModel.fromCacheJson(Map<String, dynamic> json) {
    return FactureModel(
      id: json['id'] as String? ?? '',
      moisFacturation: json['moisFacturation'] as String? ?? '',
      montantFcfa: (json['montantFcfa'] as num?)?.toDouble() ?? 0,
      indexConsommation: (json['indexConsommation'] as num?)?.toDouble() ?? 0,
      statut: StatutFacture.values.byName(json['statut'] as String? ?? 'impayee'),
      dateLimite: DateTime.tryParse(json['dateLimite'] as String? ?? '') ?? DateTime.now(),
      idCompteur: json['idCompteur'] as int? ?? 0,
      compteurNumero: json['compteurNumero'] as String?,
    );
  }
}

StatutFacture _statutFactureFromApi(String? v) {
  // CORRECTIF (21/07/2026) : le champ `statut` renvoyé par l'API est le
  // littéral EXACT de l'ENUM PostgreSQL `enum_statut_facture` (axel.sql :
  // 'Impayée', 'En_cours', 'Payée' — avec un underscore). L'ancien code
  // comparait à 'En cours' (avec un espace), qui ne correspond à AUCUNE
  // valeur jamais renvoyée par le backend : toute facture réellement
  // 'En_cours' tombait donc silencieusement dans le `default` et
  // s'affichait comme "Impayée" dans l'app, sans erreur visible.
  switch (v) {
    case 'Payée':
      return StatutFacture.payee;
    case 'En_cours':
      return StatutFacture.enCours;
    case 'Impayée':
    default:
      return StatutFacture.impayee;
  }
}

class TransactionPrepaieeModel {
  final String id;
  final DateTime date;
  final double montantFcfa;
  final double valeurKwh;
  final double prixKwhApplique;
  final String? tokenGenere;
  final StatutTransaction statut;

  const TransactionPrepaieeModel({
    required this.id,
    required this.date,
    required this.montantFcfa,
    required this.valeurKwh,
    required this.prixKwhApplique,
    required this.tokenGenere,
    required this.statut,
  });

  /// Mappe la sortie de `TransactionsPrepayeesSerializer`.
  ///
  /// ⚠️ `token_genere` est stocké chiffré (AES-256) côté serveur d'après
  /// le commentaire du modèle Django — ce endpoint ne fait aucun
  /// déchiffrement avant de le sérialiser. Tant que cette étape n'est pas
  /// branchée côté backend, la valeur reçue ici est un texte chiffré, pas
  /// un jeton STS lisible : on l'affiche quand même (mieux que rien) mais
  /// avec un avertissement dans l'UI plutôt que de prétendre qu'il est
  /// utilisable tel quel.
  factory TransactionPrepaieeModel.fromJson(Map<String, dynamic> json) {
    return TransactionPrepaieeModel(
      id: '${json['id_transaction']}',
      date: _date(json['date_transaction']),
      montantFcfa: _num(json['montant_fcfa']),
      valeurKwh: _num(json['valeur_kwh']),
      prixKwhApplique: _num(json['prix_kwh_applique']),
      tokenGenere: json['token_genere'] as String?,
      statut: _statutTransactionFromApi(json['statut_paiement'] as String?),
    );
  }

  /// Cf. `CompteurModel.toCacheJson` — même principe (utilisé pour
  /// l'historique des recharges consultable hors-ligne, §7.6).
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'montantFcfa': montantFcfa,
        'valeurKwh': valeurKwh,
        'prixKwhApplique': prixKwhApplique,
        'tokenGenere': tokenGenere,
        'statut': statut.name,
      };

  factory TransactionPrepaieeModel.fromCacheJson(Map<String, dynamic> json) {
    return TransactionPrepaieeModel(
      id: json['id'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      montantFcfa: (json['montantFcfa'] as num?)?.toDouble() ?? 0,
      valeurKwh: (json['valeurKwh'] as num?)?.toDouble() ?? 0,
      prixKwhApplique: (json['prixKwhApplique'] as num?)?.toDouble() ?? 0,
      tokenGenere: json['tokenGenere'] as String?,
      statut: StatutTransaction.values.byName(json['statut'] as String? ?? 'echoue'),
    );
  }
}

StatutTransaction _statutTransactionFromApi(String? v) {
  switch (v) {
    case 'Réussie':
      return StatutTransaction.reussi;
    case 'Initiée':
      return StatutTransaction.enAttente;
    default:
      return StatutTransaction.echoue;
  }
}

/// Résultat de `GET /users/recherche/?telephone=...` (RG-02) : le strict
/// nécessaire pour que le titulaire d'un contrat confirme l'identité du
/// tiers avant de créer une délégation. Jamais d'email ni de mot de passe
/// (cf. `UserRechercheView` côté backend, §11.2).
class UtilisateurRechercheModel {
  final int idUser;
  final String nom;
  final String prenomMasque;

  const UtilisateurRechercheModel({
    required this.idUser,
    required this.nom,
    required this.prenomMasque,
  });

  factory UtilisateurRechercheModel.fromJson(Map<String, dynamic> json) {
    return UtilisateurRechercheModel(
      idUser: json['id_user'] is int ? json['id_user'] as int : int.tryParse('${json['id_user']}') ?? 0,
      nom: json['nom'] as String? ?? '',
      prenomMasque: json['prenom_masque'] as String? ?? '',
    );
  }
}

class DelegationModel {
  final String id;

  // REFONTE v1.5 — portée exclusive : soit un compteur précis, soit un
  // contrat entier (tous ses compteurs actuels ET futurs). Exactement un
  // des deux champs est non-null, jamais les deux (même règle que la
  // contrainte CHECK `chk_gestion_compteurs_scope_exclusif` côté SQL).
  final PorteeDelegation portee;
  final int? idCompteur;
  final int? idContrat;
  /// Libellé cible affichable ("Compteur CM-2026-..." ou "Contrat CTR-...").
  /// Fourni par l'appelant (voir limite documentée dans `EneoRepository`),
  /// sinon un libellé générique par id.
  final String cibleLabel;

  final int? idUserTiers;
  final String nomTiers;
  final String telephoneTiers;
  final DroitDelegation droit;

  const DelegationModel({
    required this.id,
    required this.portee,
    this.idCompteur,
    this.idContrat,
    required this.cibleLabel,
    this.idUserTiers,
    required this.nomTiers,
    required this.telephoneTiers,
    required this.droit,
  });

  /// Mappe la sortie de `GestionCompteursSerializer`.
  ///
  /// ⚠️ Le backend ne renvoie que `id_user` (l'identifiant numérique du
  /// tiers), jamais son nom ni son téléphone : `UsersSerializer` n'est pas
  /// imbriqué ici. `nomTiers`/`telephoneTiers` doivent donc être fournis
  /// séparément par l'appelant, sinon on retombe sur un libellé générique
  /// "Utilisateur #id".
  factory DelegationModel.fromJson(
    Map<String, dynamic> json, {
    String? nomTiers,
    String? telephoneTiers,
    String? cibleLabel,
  }) {
    final idUser = json['id_user'] is int
        ? json['id_user'] as int
        : int.tryParse('${json['id_user']}');
    final idCompteur = json['id_compteur'] == null
        ? null
        : (json['id_compteur'] is int ? json['id_compteur'] as int : int.tryParse('${json['id_compteur']}'));
    final idContrat = json['id_contrat'] == null
        ? null
        : (json['id_contrat'] is int ? json['id_contrat'] as int : int.tryParse('${json['id_contrat']}'));
    final portee = idContrat != null ? PorteeDelegation.contrat : PorteeDelegation.compteur;

    return DelegationModel(
      id: '${json['id_delegation']}',
      portee: portee,
      idCompteur: idCompteur,
      idContrat: idContrat,
      cibleLabel: cibleLabel ??
          (portee == PorteeDelegation.contrat
              ? 'Contrat #${idContrat ?? '?'}'
              : 'Compteur #${idCompteur ?? '?'}'),
      idUserTiers: idUser,
      nomTiers: nomTiers ?? (idUser != null ? 'Utilisateur #$idUser' : 'Utilisateur inconnu'),
      telephoneTiers: telephoneTiers ?? '',
      droit: _droitFromApi(json['type_droit'] as String?),
    );
  }

  String get droitLabel {
    switch (droit) {
      case DroitDelegation.lecture:
        return 'Lecture seule';
      case DroitDelegation.lectureEtPaiement:
        return 'Lecture & paiement';
    }
  }

  String get porteeLabel =>
      portee == PorteeDelegation.contrat ? 'Tout le contrat' : 'Ce compteur uniquement';
}

/// `type_droit` ∈ {Lecture, Paiement, Lecture_Paiement} depuis la
/// REFONTE v1.5 (extension de `enum_type_droit`). Les anciennes valeurs
/// `Gestionnaire` / `Tiers_Lecture` / `Tiers_Paiement` restent lisibles
/// pour l'historique déjà écrit mais ne sont plus produites par l'app.
DroitDelegation _droitFromApi(String? v) {
  switch (v) {
    case 'Lecture':
    case 'Tiers_Lecture':
      return DroitDelegation.lecture;
    case 'Paiement':
    case 'Lecture_Paiement':
    case 'Tiers_Paiement':
    case 'Gestionnaire':
    default:
      return DroitDelegation.lectureEtPaiement;
  }
}

/// Renvoie la valeur `type_droit` attendue par `GestionCompteursView` pour
/// un choix d'accès fait dans l'UI (valeurs REFONTE v1.5 uniquement — l'app
/// ne produit plus jamais Gestionnaire/Tiers_Lecture/Tiers_Paiement).
String droitToApi(DroitDelegation d) =>
    d == DroitDelegation.lecture ? 'Lecture' : 'Lecture_Paiement';

class NotificationPrefModel {
  final String cle;
  final String label;
  final String description;
  bool active;
  final bool obligatoire; // RG-13 : sécurité et jetons non désactivables

  NotificationPrefModel({
    required this.cle,
    required this.label,
    required this.description,
    required this.active,
    this.obligatoire = false,
  });
}