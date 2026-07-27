/// Modèle typé pour la table `Users` (voir `models.py` / `UsersSerializer`).
///
/// Reflète exactement ce que renvoie l'API : tous les champs de
/// `UsersSerializer` SAUF `mot_de_passe`, qui est `write_only` côté Django et
/// n'apparaît donc JAMAIS dans une réponse JSON (RegisterView, LoginView,
/// ProfileView, ChangePhoneNumberView...).
class UserModel {
  final int idUser;
  final String nom;
  final String prenom;
  final String telephone;
  final String email;
  final String? situationMatrimoniale;
  final String? quartier;
  final String role; // Client | Gestionnaire | Agent_Terrain | Admin_Technicien | Admin_Financier ...
  final String statutCompte; // Actif | Verrouillé | Désactivé
  final int tentativesConnexionEchouees;
  final DateTime? dateVerrouillage;
  final String? fcmToken;
  final DateTime? dateCreation;
  final DateTime? dateDerniereConnexion;

  const UserModel({
    required this.idUser,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.email,
    this.situationMatrimoniale,
    this.quartier,
    required this.role,
    required this.statutCompte,
    this.tentativesConnexionEchouees = 0,
    this.dateVerrouillage,
    this.fcmToken,
    this.dateCreation,
    this.dateDerniereConnexion,
  });

  String get nomComplet => '$prenom $nom';

  bool get estActif => statutCompte == 'Actif';
  bool get estVerrouille => statutCompte == 'Verrouillé';
  bool get estDesactive => statutCompte == 'Désactivé';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

    return UserModel(
      idUser: (json['id_user'] as num?)?.toInt() ?? 0,
      nom: json['nom'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      telephone: json['telephone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      situationMatrimoniale: json['situation_matrimoniale'] as String?,
      quartier: json['quartier'] as String?,
      role: json['role'] as String? ?? 'Client',
      statutCompte: json['statut_compte'] as String? ?? 'Actif',
      tentativesConnexionEchouees: (json['tentatives_connexion_echouees'] as num?)?.toInt() ?? 0,
      dateVerrouillage: parseDate(json['date_verrouillage']),
      fcmToken: json['fcm_token'] as String?,
      dateCreation: parseDate(json['date_creation']),
      dateDerniereConnexion: parseDate(json['date_derniere_connexion']),
    );
  }

  /// Utile pour PATCH `/profile/` : uniquement les champs éditables via
  /// `ProfileView` (le téléphone passe exclusivement par `changePhoneNumber`,
  /// cf. commentaire dans `ChangePhoneNumberView`).
  Map<String, dynamic> toEditableJson() => {
        'nom': nom,
        'prenom': prenom,
        if (situationMatrimoniale != null) 'situation_matrimoniale': situationMatrimoniale,
        if (quartier != null) 'quartier': quartier,
      };

  UserModel copyWith({
    String? nom,
    String? prenom,
    String? telephone,
    String? email,
    String? situationMatrimoniale,
    String? quartier,
    String? statutCompte,
  }) {
    return UserModel(
      idUser: idUser,
      nom: nom ?? this.nom,
      prenom: prenom ?? this.prenom,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      situationMatrimoniale: situationMatrimoniale ?? this.situationMatrimoniale,
      quartier: quartier ?? this.quartier,
      role: role,
      statutCompte: statutCompte ?? this.statutCompte,
      tentativesConnexionEchouees: tentativesConnexionEchouees,
      dateVerrouillage: dateVerrouillage,
      fcmToken: fcmToken,
      dateCreation: dateCreation,
      dateDerniereConnexion: dateDerniereConnexion,
    );
  }
}
