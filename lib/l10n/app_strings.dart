// ============================================================
// CHAÎNES TRADUITES (FR/EN) — moteur DeepL + cache local
// ============================================================
// Le FRANÇAIS est la SEULE langue écrite en dur dans ce fichier : c'est la
// langue par défaut de l'app, et la source à partir de laquelle l'anglais
// est généré automatiquement par DeepL (api/services/deepl_translate.py
// côté Django), puis mis en cache sur l'appareil pour un usage hors ligne
// (voir `TranslationController` / `translation_cache_store.dart`) — donc
// PLUS de paires FR/EN écrites à la main comme dans la version précédente
// de ce fichier.
//
// Convention pour ajouter une chaîne : choisis une CLÉ stable et unique
// (ex: `'auth_login_bouton'`), et écris `_t('ma_cle', 'Mon texte en français')`.
// La clé n'a besoin d'être unique QUE dans ce fichier — elle sert de nom de
// cache, pas d'affichage. Si tu modifies le texte français d'une clé déjà
// utilisée, le cache anglais correspondant est automatiquement invalidé et
// re-traduit (voir `TranslationController.translate`) : pas de nettoyage
// manuel de cache à faire.
//
// Pas de génération de code (`flutter gen-l10n` / fichiers `.arb`) : ce
// projet n'a pas de `pubspec.yaml` fourni dans cet export pour y déclarer
// la config `l10n.yaml`, donc une classe `S` écrite à la main reste la
// solution la plus simple à intégrer sans étape de build supplémentaire.
//
// Couverture ACTUELLE : la barre de navigation (`main_shell.dart`),
// l'écran Paramètres (`settings_screen.dart` — sections principales, hors
// FAQ/dialogues secondaires) et tout le parcours d'authentification
// (`login_screen.dart`, `register_screen.dart`, `otp_screen.dart`). Les
// autres écrans (accueil/dashboard, contrats, prépayé/postpayé, factures,
// support...) restent en français en dur pour l'instant — voir
// `I18N_DEEPL.md` à la racine du projet pour la méthode à suivre (toujours
// la même : ajouter un getter ici, remplacer `Text('...')` par
// `Text(S.of(context).monGetter)` dans l'écran concerné) et un script qui
// repère automatiquement les `Text('...')` non encore migrés.
//
// Les messages renvoyés PAR LE SERVEUR (ex: `export['message']` de
// `_exporterDonnees`, les erreurs `ApiException.message`) restent dans la
// langue du serveur (français) quel que soit la langue choisie côté
// client : ils sont générés côté Django, pas traduisibles depuis le
// client sans faire évoluer le backend (`Accept-Language` côté API) — hors
// périmètre ici. C'est aussi pourquoi les méthodes ci-dessous qui affichent
// un message d'erreur SERVEUR (ex: catch d'`ApiException`) ne passent PAS
// par `S` : elles affichent `e.message` tel quel.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_locale_controller.dart';
import 'translation_controller.dart';

class S {
  final Locale locale;
  final TranslationController _tc;
  const S(this.locale, this._tc);

  /// `S.of(context)` s'abonne à la fois à [LocaleController] (langue
  /// choisie) et [TranslationController] (cache de traduction) : tout
  /// widget qui l'appelle dans son `build()` se reconstruit automatiquement
  /// dès que la langue change OU qu'une traduction en attente arrive du
  /// serveur (pas besoin de `setState` manuel dans les écrans consommateurs).
  static S of(BuildContext context) {
    final locale = context.watch<LocaleController>().locale;
    final tc = context.watch<TranslationController>();
    return S(locale, tc);
  }

  /// Variante pour un usage HORS `build()` (callbacks, `catch` de méthodes
  /// async, `SnackBar` déclenchés après un appel réseau...) : `context.watch`
  /// lève une erreur en dehors de `build()`, donc on utilise `context.read`
  /// ici — pas d'abonnement aux changements, ce qui est le comportement
  /// voulu pour un texte affiché une seule fois (ex: un message de `SnackBar`).
  static S read(BuildContext context) {
    final locale = context.read<LocaleController>().locale;
    final tc = context.read<TranslationController>();
    return S(locale, tc);
  }

  bool get _en => locale.languageCode == 'en';

  /// [cle] : identifiant stable (voir convention en tête de fichier).
  /// [fr] : texte français, source de vérité ET valeur de repli tant que
  /// la traduction anglaise n'est pas encore en cache.
  String _t(String cle, String fr) => _en ? _tc.translate(cle, fr) : fr;

  // -- Navigation basse (main_shell.dart) --------------------------------
  String get navAccueil => _t('nav_accueil', 'Accueil');
  String get navContrats => _t('nav_contrats', 'Contrats');
  String get navParametres => _t('nav_parametres', 'Paramètres');

  // -- Paramètres : sections ----------------------------------------------
  String get sectionPreferences => _t('parametres_section_preferences', 'Préférences');
  String get sectionSecurite => _t('parametres_section_securite', 'Sécurité');
  String get sectionDonnees =>
      _t('parametres_section_donnees', 'Données & confidentialité');
  String get sectionAideSupport => _t('parametres_section_aide_support', 'Aide & support');
  String get sectionFaq => _t('parametres_section_faq', 'FAQ');

  // -- Paramètres : Préférences --------------------------------------------
  String get langueTitre => _t('parametres_langue_titre', 'Langue');
  String get langueFrancais => _t('parametres_langue_francais', 'Français');
  String get langueAnglais => _t('parametres_langue_anglais', 'English');
  String get notificationsTitre => _t('parametres_notifications_titre', 'Notifications');
  String canauxActives(int n) =>
      _en ? '$n ${_tc.translate('parametres_canaux_actives_suffixe', 'canaux activés')}' : '$n canaux activés';
  String get preferencesNotificationTooltip => _t(
        'parametres_notification_tooltip',
        'Préférences de notification',
      );

  // -- Paramètres : Sécurité ------------------------------------------------
  String get changerNumeroTitre =>
      _t('parametres_changer_numero_titre', 'Changer mon numéro de téléphone');
  String get changerMotDePasseTitre =>
      _t('parametres_changer_mdp_titre', 'Changer mon mot de passe');
  String get changerMotDePasseSousTitre => _t(
        'parametres_changer_mdp_sous_titre',
        'Un code de vérification vous sera envoyé',
      );

  // -- Paramètres : Données & confidentialité -------------------------------
  String get exporterDonneesTitre =>
      _t('parametres_export_titre', 'Exporter mes données');
  String get exporterDonneesSousTitre => _t(
        'parametres_export_sous_titre',
        'Recevoir une copie de vos données personnelles',
      );
  String get supprimerCompteTitre =>
      _t('parametres_supprimer_compte_titre', 'Supprimer mon compte');
  String get supprimerCompteSousTitre => _t(
        'parametres_supprimer_compte_sous_titre',
        'Conformité ANTIC — profil anonymisé, historique conservé',
      );
  String get exportPret => _t('parametres_export_pret', 'Export prêt');
  String get exportEnvoye => _t('parametres_export_envoye', 'Export envoyé');
  String get fermer => _t('commun_fermer', 'Fermer');

  // -- Paramètres : Aide & support -------------------------------------------
  String get ouvrirTicketTitre => _t('parametres_ouvrir_ticket_titre', 'Ouvrir un ticket');
  String get ouvrirTicketSousTitre => _t(
        'parametres_ouvrir_ticket_sous_titre',
        'Notre équipe répond sous 24h ouvrées',
      );
  String get chatDirectTitre => _t('parametres_chat_direct_titre', 'Chat en direct');
  String get chatDirectSousTitre => _t(
        'parametres_chat_direct_sous_titre',
        'Discutez avec un conseiller AxelPay',
      );

  String get seDeconnecter => _t('commun_se_deconnecter', 'Se déconnecter');

  // ==========================================================================
  // AUTHENTIFICATION — commun aux 3 écrans (login/inscription/OTP)
  // ==========================================================================
  String get authTagline =>
      _t('auth_tagline', 'Gérez vos factures et recharges Eneo');
  String get authChampObligatoire => _t('auth_champ_obligatoire', 'Ce champ est obligatoire');
  String get authChampRequis => _t('auth_champ_requis', 'Champ requis');
  String erreurInattendue(String detail) => _en
      ? '${_tc.translate('auth_erreur_inattendue_prefixe', 'Erreur inattendue')} : $detail'
      : 'Erreur inattendue : $detail';

  // -- Connexion (login_screen.dart) ---------------------------------------
  String get loginIdentifiantLabel =>
      _t('auth_login_identifiant_label', 'Adresse e-mail ou numéro de téléphone :');
  String get loginIdentifiantHint =>
      _t('auth_login_identifiant_hint', 'ex: axel.mai@example.com');
  String get loginMotDePasseLabel => _t('auth_login_mdp_label', 'Mot de passe');
  String get loginMotDePasseHint =>
      _t('auth_login_mdp_hint', 'Entrez votre mot de passe');
  String get loginMotDePasseRequis => _t('auth_login_mdp_requis', 'Mot de passe requis');
  String get loginBouton => _t('auth_login_bouton', 'Se connecter');
  String get loginRenseigneIdentifiantDabord => _t(
        'auth_login_renseigne_identifiant',
        "Renseigne ton e-mail ou ton téléphone d'abord.",
      );
  String get loginResetInstructionsEnvoyees => _t(
        'auth_login_reset_instructions_envoyees',
        'Si ce compte existe, des instructions ont été envoyées.',
      );
  String get loginMotDePasseOublie => _t('auth_login_mdp_oublie', 'Mot de passe oublié ?');
  String get loginCreerUnCompte => _t('auth_login_creer_compte', 'Créer un compte');

  // -- Inscription (register_screen.dart) ----------------------------------
  String get registerPrenomLabel => _t('auth_register_prenom_label', 'Prénom');
  String get registerNomLabel => _t('auth_register_nom_label', 'Nom');
  String get registerTelephoneLabel =>
      _t('auth_register_telephone_label', 'Numéro de téléphone');
  String get registerTelephoneFormatInvalide =>
      _t('auth_register_telephone_format_invalide', 'Format attendu : +237XXXXXXXXX');
  String get registerQuartierLabel => _t('auth_register_quartier_label', 'Quartier');
  String get registerSituationMatrimonialeLabel =>
      _t('auth_register_situation_label', 'Situation matrimoniale');
  String get registerEmailLabel => _t('auth_register_email_label', 'e-mail');
  String get registerEmailInvalide => _t('auth_register_email_invalide', 'E-mail invalide');
  String get registerMotDePasseLabel => _t('auth_register_mdp_label', 'Mot de passe');
  String get registerConfirmMotDePasseLabel =>
      _t('auth_register_confirm_mdp_label', 'Confirmer le mot de passe');
  String get registerConfirmMotDePasseHint =>
      _t('auth_register_confirm_mdp_hint', 'Ressaisissez le mot de passe');
  String get registerMotsDePasseDifferents =>
      _t('auth_register_mdp_differents', 'Les mots de passe diffèrent');
  String get registerMdp12CaracteresMin =>
      _t('auth_register_mdp_12_car', '12 caractères minimum');
  String get registerMdpComplexite => _t(
        'auth_register_mdp_complexite',
        'Majuscule, minuscule, chiffre et caractère spécial requis',
      );
  String get registerCguLabel =>
      _t('auth_register_cgu_label', "J'accepte les conditions générales");
  String get registerPolitiqueConfidentialite => _t(
        'auth_register_politique_confidentialite',
        'Politique de confidentialité conforme à la loi camerounaise '
            'n° 2010/012 sur la protection des données personnelles.',
      );
  String get registerBouton => _t('auth_register_bouton', 'Créer mon compte');
  String get registerDejaUnCompte => _t('auth_register_deja_compte', 'Déjà un compte ?');
  String get registerCguObligatoire => _t(
        'auth_register_cgu_obligatoire',
        'Vous devez accepter les CGU pour continuer',
      );

  /// Les VALEURS de `situationMatrimoniale` envoyées à l'API (RegisterView)
  /// restent en français (ce sont des constantes métier, pas de l'UI — cf.
  /// `register_screen.dart::situations`) : seul le LIBELLÉ affiché change de
  /// langue, jamais la valeur transmise au serveur.
  String situationLabel(String valeurFr) {
    switch (valeurFr) {
      case 'Célibataire':
        return _t('auth_situation_celibataire', 'Célibataire');
      case 'Marié(e)':
        return _t('auth_situation_marie', 'Marié(e)');
      case 'Divorcé(e)':
        return _t('auth_situation_divorce', 'Divorcé(e)');
      case 'Veuf / Veuve':
        return _t('auth_situation_veuf', 'Veuf / Veuve');
      default:
        return valeurFr;
    }
  }

  // -- Vérification OTP (otp_screen.dart) ----------------------------------
  String get otpAppBarTitre => _t('auth_otp_appbar_titre', 'Vérification');
  String get otpSaisir6Chiffres =>
      _t('auth_otp_saisir_6_chiffres', 'Saisissez les 6 chiffres reçus par SMS');
  String get otpEntrezLeCodeRecu => _t('auth_otp_entrez_code_recu', 'Entrez le code reçu');
  String otpCodeEnvoyeAu(String telephone) => _en
      ? '${_tc.translate('auth_otp_code_envoye_prefixe', 'Un code à 6 chiffres a été envoyé au')} $telephone'
      : 'Un code à 6 chiffres a été envoyé au $telephone';
  String otpRenvoyerLeCode(int secondesAvantRenvoi) {
    if (secondesAvantRenvoi == 0) {
      return _t('auth_otp_renvoyer_code', 'Renvoyer le code');
    }
    return _en
        ? '${_tc.translate('auth_otp_renvoyer_code', 'Renvoyer le code')} (${secondesAvantRenvoi}s)'
        : 'Renvoyer le code (${secondesAvantRenvoi}s)';
  }

  String get otpValider => _t('auth_otp_valider', 'Valider');
  String get otpCompteVerifie => _t(
        'auth_otp_compte_verifie',
        'Compte vérifié. Vous pouvez maintenant vous connecter.',
      );

  // ==========================================================================
  // COMMUN — chaînes partagées par plusieurs écrans
  // ==========================================================================
  String get reessayer => _t('commun_reessayer', 'Réessayer');
  String get enregistrementEnCours => _t('commun_enregistrement_en_cours', 'Enregistrement…');
  String get envoiEnCours => _t('commun_envoi_en_cours', 'Envoi…');
  String get changer => _t('commun_changer', 'Changer');
  String get rechercher => _t('commun_rechercher', 'Rechercher');
  String get mesContratsTitre => _t('commun_mes_contrats_titre', 'Mes contrats');
  String get revoquer => _t('commun_revoquer', 'Révoquer');
  String get revoquerCetAccesTitre => _t('commun_revoquer_cet_acces_titre', 'Révoquer cet accès ?');
  String get typePrepaye => _t('commun_type_prepaye', 'Prépayé');
  String get typePostpaye => _t('commun_type_postpaye', 'Postpayé');
  String get numeroTelephoneTiersLabel =>
      _t('commun_numero_telephone_tiers_label', 'Numéro de téléphone du tiers');
  String get niveauAccesLabel => _t('commun_niveau_acces_label', 'Niveau d’accès');
  String get droitLectureSeuleTitre => _t('commun_droit_lecture_seule_titre', 'Lecture seule');
  String get droitLectureSeuleDesc =>
      _t('commun_droit_lecture_seule_desc', 'Consultation du solde et des factures');
  String get droitLecturePaiementTitre =>
      _t('commun_droit_lecture_paiement_titre', 'Lecture & paiement');
  String get droitLecturePaiementDesc =>
      _t('commun_droit_lecture_paiement_desc', 'Peut également régler ou recharger');
  String get recuPdf => _t('commun_recu_pdf', 'Reçu PDF');
  String get payerCetteFacture => _t('commun_payer_cette_facture', 'Payer cette facture');
  String get signalerAnomalieTitre => _t('commun_signaler_anomalie_titre', 'Signaler une anomalie');
  String signalerAnomalieTitreAvecMois(String mois) => _en
      ? '${_tc.translate('commun_signaler_anomalie_prefixe', 'Signaler une anomalie')} — $mois'
      : 'Signaler une anomalie — $mois';
  String get signalerAnomalieHint => _t(
        'commun_signaler_anomalie_hint',
        'Décrivez le problème rencontré (montant incorrect, index erroné...)',
      );
  String get envoyerAuSupport => _t('commun_envoyer_au_support', 'Envoyer au support');
  String get adresseNonDisponible =>
      _t('commun_adresse_non_disponible', 'Adresse non disponible');
  /// Confirmation affichée après résolution d'un tiers par numéro de
  /// téléphone (flux de délégation) — [nomPrenom] est déjà composé
  /// (`nom prenomMasque`), voir `_ouvrirDelegation` dans
  /// `meters_screen.dart` / `contracts_screen.dart`.
  String tiersTrouve(String nomPrenom) => _en
      ? '${_tc.translate('commun_tiers_trouve_prefixe', 'Tiers trouvé')} : $nomPrenom'
      : 'Tiers trouvé : $nomPrenom';
  String get uneErreurEstSurvenue => _t(
        'commun_une_erreur_est_survenue',
        'Une erreur est survenue. Vérifiez votre connexion.',
      );
  String get annuler => _t('commun_annuler', 'Annuler');
  String get confirmer => _t('commun_confirmer', 'Confirmer');
  String get confirmerMotDePasseHint =>
      _t('commun_confirmer_mdp_hint', 'Confirmez votre mot de passe');

  // ==========================================================================
  // CONTRATS (contracts_screen.dart)
  // ==========================================================================
  String get contratsTrierTitre => _t('contrats_trier_titre', 'Trier les contrats');
  String get contratsTriParDate => _t('contrats_tri_par_date', 'Par date d’ancienneté');
  String get contratsTriPlusRecentDabord =>
      _t('contrats_tri_plus_recent_dabord', 'Du plus récent au plus ancien');
  String get contratsTriPlusAncienDabord =>
      _t('contrats_tri_plus_ancien_dabord', 'Du plus ancien au plus récent');
  String get contratsTriParMontant => _t('contrats_tri_par_montant', 'Par montant');
  String get contratsTriMontantCroissant =>
      _t('contrats_tri_montant_croissant', 'Montant croissant');
  String get contratsTriMontantDecroissant =>
      _t('contrats_tri_montant_decroissant', 'Montant décroissant');
  String get contratsAucunContrat => _t('contrats_aucun_contrat', 'Aucun contrat pour le moment.');
  String get contratsAjouterUnContrat => _t('contrats_ajouter_un_contrat', 'Ajouter un contrat');
  String get contratsNumeroContratLabel =>
      _t('contrats_numero_contrat_label', 'Numéro de contrat');
  String get contratsAjouterCeContratBouton =>
      _t('contrats_ajouter_ce_contrat_bouton', 'Ajouter ce contrat');
  String get contratsAucunCompteurRattache => _t(
        'contrats_aucun_compteur_rattache',
        'Aucun compteur rattaché à ce contrat pour le moment.',
      );
  String get contratsVoirFacturesDuContrat =>
      _t('contrats_voir_factures_du_contrat', 'Voir les factures du contrat');
  String get contratsDelegationSurTout =>
      _t('contrats_delegation_sur_tout', 'Délégation sur tout le contrat');
  String get contratsAucuneDelegation =>
      _t('contrats_aucune_delegation', 'Aucune délégation sur ce contrat.');
  String get contratsDeleguerToutLeContrat =>
      _t('contrats_deleguer_tout_le_contrat', 'Déléguer tout le contrat');
  String get contratsDeleguerAutreTiers =>
      _t('contrats_deleguer_autre_tiers', 'Déléguer à un autre tiers');
  String contratsAjouterCompteurTitre(String numeroContrat) => _en
      ? '${_tc.translate('contrats_ajouter_compteur_prefixe', 'Ajouter un compteur')} — $numeroContrat'
      : 'Ajouter un compteur — $numeroContrat';
  String get contratsNumeroCompteurUniqueLabel =>
      _t('contrats_numero_compteur_unique_label', 'Numéro de compteur unique');
  String get contratsAdresseInstallationLabel =>
      _t('contrats_adresse_installation_label', 'Adresse d’installation');
  String get contratsAjouterCeCompteurBouton =>
      _t('contrats_ajouter_ce_compteur_bouton', 'Ajouter ce compteur');
  String contratsDeleguerToutTitreAvecNumero(String numeroContrat) => _en
      ? '${_tc.translate('contrats_deleguer_tout_titre_prefixe', 'Déléguer tout le contrat')} — $numeroContrat'
      : 'Déléguer tout le contrat — $numeroContrat';
  String get contratsConfirmerDelegationBouton =>
      _t('contrats_confirmer_delegation_bouton', 'Confirmer la délégation');

  // -- Contrats : chaînes manquantes ajoutées lors de la correction --------
  String get contratsDescription => _t(
        'contrats_description',
        'Retrouvez ici tous vos contrats Eneo et leurs compteurs.',
      );
  String get contratsTrierTooltip => _t('contrats_trier_tooltip', 'Trier');
  String get contratsVoirTousCompteursTooltip =>
      _t('contrats_voir_tous_compteurs_tooltip', 'Voir tous les compteurs');
  String get contratsFacturesTooltip =>
      _t('contrats_factures_tooltip', 'Voir les factures');
  String get contratsCompteursIndisponibles => _t(
        'contrats_compteurs_indisponibles',
        'Compteurs indisponibles',
      );
  String contratsNombreCompteurs(int n) => _en
      ? '$n ${_tc.translate('contrats_nombre_compteurs_suffixe', 'compteur(s) rattaché(s)')}'
      : '$n compteur(s) rattaché(s)';
  String get contratsNumeroContratDescription => _t(
        'contrats_numero_contrat_description',
        'Saisissez le numéro de contrat indiqué sur votre facture ou votre '
            'contrat Eneo.',
      );
  String get contratsNumeroContratRequis =>
      _t('contrats_numero_contrat_requis', 'Le numéro de contrat est requis');
  String contratsAjoute(String numeroContrat) => _en
      ? '${_tc.translate('contrats_ajoute_prefixe', 'Contrat ajouté')} : $numeroContrat'
      : 'Contrat ajouté : $numeroContrat';
  String get ajouter => _t('commun_ajouter', 'Ajouter');
  String contratsCreeLe(String date) => _en
      ? '${_tc.translate('contrats_cree_le_prefixe', 'Créé le')} $date'
      : 'Créé le $date';
  String contratsCompteursTitre(int n) => _en
      ? '${_tc.translate('contrats_compteurs_titre_prefixe', 'Compteurs')} ($n)'
      : 'Compteurs ($n)';
  String get contratsAjouterCompteurDescription => _t(
        'contrats_ajouter_compteur_description',
        'Renseignez les informations du compteur à rattacher à ce contrat.',
      );
  String get typeCompteur => _t('contrats_type_compteur', 'Type de compteur');
  String get ville => _t('commun_ville', 'Ville');
  String get commune => _t('commun_commune', 'Commune');
  String get quartier => _t('commun_quartier', 'Quartier');
  String get contratsNumeroEtVilleRequis => _t(
        'contrats_numero_et_ville_requis',
        'Le numéro de compteur et la ville sont requis',
      );
  String contratsCompteurAjoute(String numero) => _en
      ? '${_tc.translate('contrats_compteur_ajoute_prefixe', 'Compteur ajouté')} : $numero'
      : 'Compteur ajouté : $numero';
  String get contratsDelegationDescription => _t(
        'contrats_delegation_description',
        'Personnes ayant reçu un accès à ce contrat.',
      );
  String contratsRevoquerMessage(String nomTiers) => _en
      ? '$nomTiers ${_tc.translate('contrats_revoquer_message_suffixe', 'perdra immédiatement l’accès à ce contrat.')}'
      : '$nomTiers perdra immédiatement l’accès à ce contrat.';
  String get numeroTelephoneRequis =>
      _t('contrats_numero_telephone_requis', 'Numéro de téléphone requis');
  String get aucunUtilisateurAvecCeNumero => _t(
        'contrats_aucun_utilisateur_avec_ce_numero',
        'Aucun utilisateur inscrit avec ce numéro.',
      );
  String contratsDelegationAccordee(String nomPrenom) => _en
      ? '${_tc.translate('contrats_delegation_accordee_prefixe', 'Délégation accordée à')} $nomPrenom.'
      : 'Délégation accordée à $nomPrenom.';
  String get contratsDelegationTousCompteursDescription => _t(
        'contrats_delegation_tous_compteurs_description',
        'Cette personne aura accès à tous les compteurs de ce contrat, '
            'actuels et futurs.',
      );

  // ==========================================================================
  // FACTURES D'UN CONTRAT (contrat_factures_screen.dart)
  // ==========================================================================
  String get factContratFiltreTous => _t('fact_contrat_filtre_tous', 'Tous');
  /// Libellé AFFICHÉ pour le filtre "Payée" — la VALEUR envoyée à l'API et
  /// comparée dans `_statutFiltre` reste le littéral français `'Payée'`
  /// (voir commentaire dans contrat_factures_screen.dart).
  String get factContratFiltrePayee => _t('fact_contrat_filtre_payee', 'Payée');
  String get factContratFiltreEnCours => _t('fact_contrat_filtre_en_cours', 'En cours');
  String get factContratFiltreImpayee => _t('fact_contrat_filtre_impayee', 'Impayée');
  String get factContratAnomalie => _t('fact_contrat_anomalie', 'Anomalie');
  String get factContratAucuneFactureTitre =>
      _t('fact_contrat_aucune_facture_titre', 'Aucune facture disponible');
  String get factContratAucuneFactureSousTitre => _t(
        'fact_contrat_aucune_facture_sous_titre',
        'Aucune facture ne correspond à ces filtres, ou ce contrat ne '
            'compte que des compteurs prépayés (pas de facturation mensuelle).',
      );

  // ==========================================================================
  // PARAMÈTRES — FAQ & dialogues restants (settings_screen.dart)
  // ==========================================================================
  /// Libellé AFFICHÉ d'une préférence de notification, à partir de sa
  /// `cle` métier (STABLE, jamais traduite — voir `NotificationPrefModel`).
  String notifPrefLabel(String cle) {
    switch (cle) {
      case 'securite':
        return _t('parametres_notif_securite_label', 'Alertes de sécurité');
      case 'jeton':
        return _t('parametres_notif_jeton_label', 'Livraison de jeton');
      case 'solde_bas':
        return _t('parametres_notif_solde_bas_label', 'Solde bas');
      case 'facture':
        return _t('parametres_notif_facture_label', 'Nouvelle facture');
      case 'recap':
        return _t('parametres_notif_recap_label', 'Récapitulatif mensuel');
      default:
        return cle;
    }
  }

  String notifPrefDescription(String cle) {
    switch (cle) {
      case 'securite':
        return _t('parametres_notif_securite_desc',
            'Connexions inhabituelles, changement de mot de passe');
      case 'jeton':
        return _t('parametres_notif_jeton_desc', 'Confirmation de chaque recharge prépayée');
      case 'solde_bas':
        return _t(
            'parametres_notif_solde_bas_desc', 'Alerte quand votre crédit prépayé devient faible');
      case 'facture':
        return _t('parametres_notif_facture_desc', 'Notification à chaque émission de facture');
      case 'recap':
        return _t('parametres_notif_recap_desc', 'Résumé de consommation en fin de mois');
      default:
        return cle;
    }
  }

  String get parametresNotifToujoursActifSuffixe =>
      _t('parametres_notif_toujours_actif_suffixe', 'toujours actif');
  String get parametresNotifPrefsTitre =>
      _t('parametres_notif_prefs_titre', 'Préférences de notification');
  String get parametresExportPreparationLabel =>
      _t('parametres_export_preparation_label', 'Préparation de votre export…');
  String get parametresSupprimerCompteConfirmTitre =>
      _t('parametres_supprimer_compte_confirm_titre', 'Supprimer mon compte ?');
  String get parametresSupprimerCompteConfirmMessage => _t(
        'parametres_supprimer_compte_confirm_message',
        'Vos données de profil seront anonymisées. Votre historique financier '
            'restera archivé pour répondre aux obligations légales comptables.',
      );
  String get parametresChangerNumeroDialogTitre =>
      _t('parametres_changer_numero_dialog_titre', 'Changer mon numéro');
  String parametresNumeroActuel(String telephone) => _en
      ? '${_tc.translate('parametres_numero_actuel_prefixe', 'Numéro actuel')} : $telephone'
      : 'Numéro actuel : $telephone';
  String get parametresNouveauNumeroHint =>
      _t('parametres_nouveau_numero_hint', 'Nouveau numéro (ex: +237690000000)');
  String get parametresChangerMdpDialogTitre =>
      _t('parametres_changer_mdp_dialog_titre', 'Changer mon mot de passe');
  String get parametresRecevoirLeCodeBouton =>
      _t('parametres_recevoir_le_code_bouton', 'Recevoir le code');
  String get parametresCodeRecuHint =>
      _t('parametres_code_recu_hint', 'Code reçu par SMS/e-mail');
  String get parametresNouveauMdpHint =>
      _t('parametres_nouveau_mdp_hint', 'Nouveau mot de passe');
  String get parametresValidationEnCours =>
      _t('parametres_validation_en_cours', 'Validation…');
  String get parametresValiderNouveauMdpBouton =>
      _t('parametres_valider_nouveau_mdp_bouton', 'Valider le nouveau mot de passe');

  // ==========================================================================
  // COMPTEURS — vue transverse (meters_screen.dart)
  // ==========================================================================
  String metersMesCompteursTitre(int n) => _en
      ? '${_tc.translate('meters_mes_compteurs_prefixe', 'Mes compteurs')} ($n)'
      : 'Mes compteurs ($n)';
  String get metersRattacherNouveauCompteurHint => _t(
        'meters_rattacher_nouveau_compteur_hint',
        'Pour rattacher un nouveau compteur, ouvrez l’un de vos '
            'contrats depuis l’onglet "Contrats".',
      );
  String get metersAucunCompteurRattache =>
      _t('meters_aucun_compteur_rattache', 'Aucun compteur rattaché pour le moment.');
  String get metersAccesDelegues => _t('meters_acces_delegues', 'Accès délégués');
  String get metersPersonnesAyantRecuAcces => _t(
        'meters_personnes_ayant_recu_acces',
        'Personnes ayant reçu un accès à l’un de vos compteurs.',
      );
  String get metersAucuneDelegationActive =>
      _t('meters_aucune_delegation_active', 'Aucune délégation active.');
  String get metersModifierMonProfil =>
      _t('meters_modifier_mon_profil', 'Modifier mon profil');
  String get metersRendezVousParametres => _t(
        'meters_rendez_vous_parametres',
        'Rendez-vous dans l’onglet Paramètres pour modifier votre profil.',
      );
  String get metersChangerDeMotDePasse =>
      _t('meters_changer_de_mot_de_passe', 'Changer de mot de passe');
  String get metersReAuthentificationRequise =>
      _t('meters_reauthentification_requise', 'Ré-authentification requise');
  String metersDelegerAccesTitre(String numeroCompteur) => _en
      ? '${_tc.translate('meters_deleguer_acces_prefixe', 'Déléguer l’accès')} — $numeroCompteur'
      : 'Déléguer l’accès — $numeroCompteur';
  String get metersDelegerBouton => _t('meters_deleguer_bouton', 'Déléguer');
  String get metersSaisirNumeroTelephone =>
      _t('meters_saisir_numero_telephone', 'Saisissez un numéro de téléphone.');
  String get metersAucunUtilisateurTrouve => _t(
        'meters_aucun_utilisateur_trouve',
        'Aucun utilisateur inscrit avec ce numéro.',
      );
  String metersDelegationAccordeeA(String nomPrenom) => _en
      ? '${_tc.translate('meters_delegation_accordee_prefixe', 'Délégation accordée à')} $nomPrenom.'
      : 'Délégation accordée à $nomPrenom.';
  String metersPerdImmediatementAccesCompteur(String nomTiers) => _en
      ? '$nomTiers ${_tc.translate('meters_perd_acces_compteur_suffixe', 'perdra immédiatement l’accès à ce compteur.')}'
      : '$nomTiers perdra immédiatement l’accès à ce compteur.';

  // ==========================================================================
  // DÉTAIL FACTURE (facture_detail_screen.dart) — labels partagés entre
  // l'écran Flutter ET la génération du PDF (`_genererPdf`), d'où leur
  // regroupement ici plutôt que dans une section propre à un seul rendu.
  // ==========================================================================
  String get factureDetailAppBarTitre =>
      _t('facture_detail_appbar_titre', 'Détail de la facture');
  String get factureDetailImprimer => _t('facture_detail_imprimer', 'Imprimer');
  String get factureDetailTelechargerPdf =>
      _t('facture_detail_telecharger_pdf', 'Télécharger PDF');
  String factureDetailErreurImpression(String detail) => _en
      ? '${_tc.translate('facture_detail_erreur_impression_prefixe', 'Erreur impression')} : $detail'
      : 'Erreur impression : $detail';
  String factureDetailErreurTelechargement(String detail) => _en
      ? '${_tc.translate('facture_detail_erreur_telechargement_prefixe', 'Erreur téléchargement')} : $detail'
      : 'Erreur téléchargement : $detail';
  String get platformeGestionElectrique =>
      _t('facture_detail_platforme_gestion_electrique', 'Plateforme de gestion électrique');
  String get factureDElectriciteTitre =>
      _t('facture_detail_facture_electricite_titre', 'FACTURE D\'ÉLECTRICITÉ');
  String get montantAPayerLabel => _t('facture_detail_montant_a_payer_label', 'MONTANT À PAYER');
  String get documentGenereParAxelPay =>
      _t('facture_detail_document_genere_par_axelpay', 'Document généré par Axel Pay');
  String documentGenereParAxelPayLe(String date) => _en
      ? '${_tc.translate('facture_detail_document_genere_par_axelpay', 'Document généré par Axel Pay')} — $date'
      : 'Document généré par Axel Pay — $date';
  String get informationsClientTitre =>
      _t('facture_detail_informations_client_titre', 'INFORMATIONS CLIENT');
  String get informationsCompteurTitre =>
      _t('facture_detail_informations_compteur_titre', 'INFORMATIONS COMPTEUR');
  String get releveDeConsommationTitre =>
      _t('facture_detail_releve_consommation_titre', 'RELEVÉ DE CONSOMMATION');
  String get facturationTitre => _t('facture_detail_facturation_titre', 'FACTURATION');
  String get nomLabel => _t('facture_detail_nom_label', 'Nom');
  String get adresseLabel => _t('facture_detail_adresse_label', 'Adresse');
  String get villeLabel => _t('facture_detail_ville_label', 'Ville');
  String get numeroCompteurLabel => _t('facture_detail_numero_compteur_label', 'N° Compteur');
  String get dateDeReleveLabel => _t('facture_detail_date_de_releve_label', 'Date de relevé');
  String get ancienIndexLabel => _t('facture_detail_ancien_index_label', 'Ancien index');
  String get premierReleve => _t('facture_detail_premier_releve', 'Premier relevé');
  String get nouvelIndexLabel => _t('facture_detail_nouvel_index_label', 'Nouveau index');
  String get indexAPayerLabel => _t('facture_detail_index_a_payer_label', 'Index à payer');
  String get periodeFactureeLabel =>
      _t('facture_detail_periode_facturee_label', 'Période facturée');
  String get dateLimiteLabel => _t('facture_detail_date_limite_label', 'Date limite');
}