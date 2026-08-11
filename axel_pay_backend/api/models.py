# -*- coding: utf-8 -*-
# This is an auto-generated Django model module.
# You'll have to do the following manually to clean this up:
#   * Rearrange models' order
#   * Make sure each model has one field with primary_key=True
#   * Make sure each ForeignKey and OneToOneField has `on_delete` set to the desired behavior
#   * Remove `managed = False` lines if you wish to allow Django to create, modify, and delete the table
# Feel free to rename the models, but don't rename db_table values or field names.
from django.db import models


class Adresses(models.Model):
    id_adresse = models.AutoField(primary_key=True)
    ville = models.CharField(max_length=100)
    commune = models.CharField(max_length=100)
    quartier_description = models.TextField()
    est_immeuble = models.BooleanField()
    date_creation = models.DateTimeField()

    class Meta:
        managed = False
        db_table = 'adresses'
        db_table_comment = "Référentiel des adresses d'installation, évite la duplication sur un immeuble multi-compteurs."


class AuditLogs(models.Model):
    id_audit = models.AutoField(primary_key=True)
    action = models.CharField(max_length=100)
    objet_touche = models.CharField(max_length=150)
    motif = models.TextField(blank=True, null=True)
    ip_adresse = models.CharField(max_length=45)
    terminal = models.CharField(max_length=150, blank=True, null=True)
    date_heure = models.DateTimeField()
    id_auteur = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_auteur', db_comment="Administrateur auteur de l'action (anciennement id_user).")
    id_utilisateur_cible = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_utilisateur_cible', related_name='auditlogs_id_utilisateur_cible_set', blank=True, null=True, db_comment="Client concerné, notamment lors d'une session d'impersonation (anciennement id_user1).")

    class Meta:
        managed = False
        db_table = 'audit_logs'
        db_table_comment = "Piste d'audit de toute action administrative sensible, y compris impersonation (RG-04)  APPEND-ONLY."


class ComptesTechniques(models.Model):
    id_compte_tech = models.AutoField(primary_key=True)
    nom_service = models.CharField(max_length=100)
    cle_api_hash = models.CharField(max_length=255)
    scope = models.TextField()  # This field type is a guess.
    statut = models.TextField()  # This field type is a guess.
    date_creation = models.DateTimeField()

    class Meta:
        managed = False
        db_table = 'comptes_techniques'
        db_table_comment = "Comptes des intégrations automatisées (webhooks, synchronisation Eneo)  jamais les droits d'un administrateur humain (RG-05)."


class Contrats(models.Model):
    """
    REFONTE v1.5 — Nouvelle racine du graphe de propriété. Un utilisateur
    détient un ou plusieurs contrats (numero_contrat unique) ; un contrat
    regroupe un ou plusieurs compteurs (voir Compteurs.id_contrat). La
    propriété d'un compteur se lit désormais via Contrats.id_user, plus via
    une ligne GestionCompteurs(type_droit='Gestionnaire') (cf. models
    GestionCompteurs ci-dessous).
    """
    id_contrat = models.AutoField(primary_key=True)
    numero_contrat = models.CharField(unique=True, max_length=30)
    id_user = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_user')
    statut = models.TextField()  # This field type is a guess.
    date_creation = models.DateTimeField()
    date_resiliation = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'contrats'
        db_table_comment = "Racine du graphe de propriété : un utilisateur détient un ou plusieurs contrats, chacun regroupant un ou plusieurs compteurs."


class Compteurs(models.Model):
    id_compteur = models.AutoField(primary_key=True)
    numero_compteur = models.CharField(unique=True, max_length=25)
    type_compteur = models.TextField()  # This field type is a guess.
    proprietaire_legal = models.CharField(max_length=150)
    statut = models.TextField()  # This field type is a guess.
    date_installation = models.DateField(blank=True, null=True)
    date_creation = models.DateTimeField()
    id_adresse = models.OneToOneField(Adresses, models.DO_NOTHING, db_column='id_adresse', unique=True, db_comment='REFONTE v1.5 : relation 1—1, une adresse correspond à un seul compteur.')
    id_contrat = models.ForeignKey(Contrats, models.DO_NOTHING, db_column='id_contrat', db_comment="REFONTE v1.5 : contrat propriétaire de ce compteur — remplace la notion de propriété portée par GestionCompteurs.")

    class Meta:
        managed = False
        db_table = 'compteurs'
        db_table_comment = "Compteur physique Eneo (prépayé ou postpayé), rattaché à un contrat, point d'ancrage de l'historique financier."


class FacturesPostpayees(models.Model):
    id_facture = models.CharField(primary_key=True, max_length=25)
    mois_facturation = models.DateField()
    index_consommation = models.DecimalField(max_digits=10, decimal_places=2)
    montant_fcfa = models.DecimalField(max_digits=12, decimal_places=2)
    statut = models.TextField()  # This field type is a guess.
    date_limite = models.DateField()
    facture_rectificative_de = models.ForeignKey('self', models.DO_NOTHING, db_column='facture_rectificative_de', blank=True, null=True)
    date_creation = models.DateTimeField()
    id_compteur = models.ForeignKey(Compteurs, models.DO_NOTHING, db_column='id_compteur')

    # ── NOUVEAUX CHAMPS (migration SQL requise) ───────────────────
    index_ancien = models.DecimalField(
        max_digits=10, decimal_places=2, blank=True, null=True,
        db_comment="Relevé précédent du compteur (kWh). NULL pour la 1re facture.",
    )
    index_nouveau = models.DecimalField(
        max_digits=10, decimal_places=2, blank=True, null=True,
        db_comment="Relevé actuel du compteur (kWh).",
    )
    date_releve = models.DateField(
        blank=True, null=True,
        db_comment="Date du relevé physique par l'agent.",
    )
    # ─────────────────────────────────────────────────────────────

    class Meta:
        managed = False
        db_table = 'factures_postpayees'
        db_table_comment = 'Historique des factures mensuelles des compteurs postpayés.'


class GestionCompteurs(models.Model):
    """
    REFONTE v1.5 — Délégations à des TIERS uniquement (lecture et/ou
    paiement). Ne modélise plus la propriété primaire (portée par
    Contrats.id_user) : une ligne porte soit sur un compteur précis
    (id_compteur renseigné, id_contrat NULL), soit sur un contrat entier
    (id_contrat renseigné, id_compteur NULL — s'applique à tous les
    compteurs actuels et futurs de ce contrat). Exclusivité imposée par la
    contrainte CHECK chk_gestion_compteurs_scope_exclusif côté SQL.
    """
    id_delegation = models.AutoField(primary_key=True)
    id_user = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_user')
    id_compteur = models.ForeignKey(Compteurs, models.DO_NOTHING, db_column='id_compteur', blank=True, null=True)
    id_contrat = models.ForeignKey(Contrats, models.DO_NOTHING, db_column='id_contrat', blank=True, null=True, db_comment="REFONTE v1.5 : portée 'contrat entier' — mutuellement exclusif avec id_compteur.")
    type_droit = models.TextField(db_comment="Nature du droit délégué : Lecture, Paiement ou Lecture_Paiement. Les valeurs historiques Gestionnaire/Tiers_Lecture/Tiers_Paiement restent lisibles mais ne sont plus produites.")  # This field type is a guess.
    statut = models.TextField()  # This field type is a guess.
    date_octroi = models.DateTimeField()
    date_revocation = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'gestion_compteurs'
        unique_together = (('id_user', 'id_compteur', 'type_droit'), ('id_user', 'id_contrat', 'type_droit'))
        db_table_comment = "REFONTE v1.5 — Délégations à des tiers (lecture et/ou paiement), portant sur un compteur précis ou sur un contrat entier. Ne modélise plus la propriété primaire."


class HistoriqueArchive(models.Model):
    id_archive = models.AutoField(primary_key=True)
    table_origine = models.TextField()  # This field type is a guess.
    id_origine = models.CharField(max_length=25)
    donnees_json = models.JSONField()
    date_archivage = models.DateTimeField()

    class Meta:
        managed = False
        db_table = 'historique_archive'
        db_table_comment = 'Bascule des enregistrements de plus de 12 mois (RG-14)  APPEND-ONLY, jamais de suppression.'


class Litiges(models.Model):
    id_litige = models.CharField(primary_key=True, max_length=25)
    niveau = models.CharField(max_length=2)
    statut = models.TextField()  # This field type is a guess.
    description = models.TextField()
    resolution = models.TextField(blank=True, null=True)
    date_ouverture = models.DateTimeField()
    date_resolution = models.DateTimeField(blank=True, null=True)
    id_user = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_user', blank=True, null=True)
    id_paiement = models.ForeignKey(
        'Paiements', models.DO_NOTHING, db_column='id_paiement',
        blank=True, null=True,
    )
    traite_par = models.ForeignKey('Users', models.DO_NOTHING, db_column='traite_par', related_name='litiges_traite_par_set', blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'litiges'
        db_table_comment = 'Politique de gestion des litiges à trois niveaux (diagnostic, vérification comptable, résolution).'


class Notifications(models.Model):
    id_notification = models.CharField(primary_key=True, max_length=25)
    canal = models.TextField()  # This field type is a guess.
    niveau_criticite = models.TextField()  # This field type is a guess.
    objet = models.CharField(max_length=255)
    contenu = models.TextField()
    statut = models.TextField()  # This field type is a guess.
    date_envoi = models.DateTimeField()
    date_lecture = models.DateTimeField(blank=True, null=True)
    id_compteur = models.ForeignKey(Compteurs, models.DO_NOTHING, db_column='id_compteur', blank=True, null=True)
    id_user = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_user')

    class Meta:
        managed = False
        db_table = 'notifications'
        db_table_comment = 'Historique des messages envoyés, orchestrés selon la matrice de criticité multicanale.'


class Paiements(models.Model):
    id_paiement = models.CharField(primary_key=True, max_length=25)
    type_paiement = models.TextField()  # This field type is a guess.
    reference_cible = models.CharField(max_length=25, db_comment='Référence polymorphe vers Factures_Postpayees.id_facture ou Transactions_Prepayees.id_transaction, selon type_paiement. Validée par le trigger trg_verifier_reference_cible_paiement.')
    agregateur = models.TextField()  # This field type is a guess.
    operateur_mobile_money = models.TextField()  # This field type is a guess.
    numero_mobile_money = models.CharField(max_length=20)
    montant_fcfa = models.DecimalField(max_digits=12, decimal_places=2)
    frais_agregateur_fcfa = models.DecimalField(max_digits=10, decimal_places=2)
    statut = models.TextField()  # This field type is a guess.
    numero_recu = models.CharField(unique=True, max_length=50, blank=True, null=True)
    donnees_recu_json = models.JSONField(blank=True, null=True)
    correlation_id = models.CharField(max_length=50, db_comment="Identifiant de corrélation technique inter-systèmes (§7.5), permet de reconstituer le parcours complet d'une transaction en cas de litige.")
    date_initiation = models.DateTimeField()
    date_confirmation = models.DateTimeField(blank=True, null=True)
    id_user = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_user')

    class Meta:
        managed = False
        db_table = 'paiements'
        db_table_comment = 'Table unifiée des règlements (facture postpayée OU recharge prépayée), référence polymorphe via reference_cible.'


class Tarifs(models.Model):
    id_tarif = models.AutoField(primary_key=True)
    type_compteur = models.TextField()  # This field type is a guess.
    prix_kwh = models.DecimalField(max_digits=10, decimal_places=2)
    date_debut = models.DateField()
    date_fin = models.DateField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'tarifs'
        db_table_comment = 'Grille tarifaire historisée du prix du kWh (RG-07 : le prix appliqué est figé dans chaque transaction).'


class TransactionsPrepayees(models.Model):
    id_transaction = models.CharField(primary_key=True, max_length=25)
    montant_fcfa = models.DecimalField(max_digits=12, decimal_places=2)
    prix_kwh_applique = models.DecimalField(max_digits=10, decimal_places=2)
    valeur_kwh = models.DecimalField(max_digits=10, decimal_places=3)
    token_genere = models.CharField(max_length=255, blank=True, null=True, db_comment='Jeton de recharge STS à 20 chiffres, chiffré au repos (AES-256) au niveau applicatif avant stockage.')
    statut_paiement = models.TextField()  # This field type is a guess.
    date_transaction = models.DateTimeField()
    id_compteur = models.ForeignKey(Compteurs, models.DO_NOTHING, db_column='id_compteur')

    class Meta:
        managed = False
        db_table = 'transactions_prepayees'
        db_table_comment = 'Historique des recharges de crédit prépayé  APPEND-ONLY (RG-12), hors statut_paiement/token_genere.'


class UserConsentLogs(models.Model):
    id_consent = models.AutoField(primary_key=True)
    canal = models.CharField(max_length=50)
    version_cgu = models.CharField(max_length=20)
    action = models.TextField()  # This field type is a guess.
    ip_adresse = models.CharField(max_length=45)
    date_consentement = models.DateTimeField()
    id_user = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_user')

    class Meta:
        managed = False
        db_table = 'user_consent_logs'
        db_table_comment = 'Preuve opposable du consentement RGPD  APPEND-ONLY.'


class UserDevices(models.Model):
    id_device = models.AutoField(primary_key=True)
    fcm_token = models.CharField(unique=True, max_length=255)
    type_appareil = models.TextField()  # This field type is a guess.
    statut = models.TextField()  # This field type is a guess.
    date_enregistrement = models.DateTimeField()
    date_derniere_activite = models.DateTimeField(blank=True, null=True)
    id_user = models.ForeignKey('Users', models.DO_NOTHING, db_column='id_user')

    class Meta:
        managed = False
        db_table = 'user_devices'
        db_table_comment = 'Terminaux et jetons FCM enregistrés pour les notifications push.'


class Users(models.Model):
    id_user = models.AutoField(primary_key=True)
    nom = models.CharField(max_length=100)
    prenom = models.CharField(max_length=100)
    telephone = models.CharField(unique=True, max_length=20)
    email = models.CharField(unique=True, max_length=150)
    mot_de_passe = models.CharField(max_length=255, db_comment='Empreinte du mot de passe (Argon2id)  jamais stocké en clair.')
    situation_matrimoniale = models.TextField(blank=True, null=True)  # This field type is a guess.
    quartier = models.CharField(max_length=100, blank=True, null=True)
    role = models.TextField()  # This field type is a guess.
    statut_compte = models.TextField()  # This field type is a guess.
    tentatives_connexion_echouees = models.IntegerField()
    date_verrouillage = models.DateTimeField(blank=True, null=True)
    fcm_token = models.CharField(max_length=255, blank=True, null=True)
    date_creation = models.DateTimeField()
    date_derniere_connexion = models.DateTimeField(blank=True, null=True)

    @property
    def is_authenticated(self):
        return True

    @property
    def is_anonymous(self):
        return False
    class Meta:
        managed = False
        db_table = 'users'
        db_table_comment = 'Comptes utilisateurs humains (clients, gestionnaires, tiers autorisés, agents terrain, admins back-office).'


class WebhookLogs(models.Model):
    id_webhook = models.CharField(primary_key=True, max_length=25)
    id_evenement_agregateur = models.CharField(unique=True, max_length=100)
    payload_brut = models.JSONField()
    signature_hmac_valide = models.BooleanField()
    date_reception = models.DateTimeField()
    id_paiement = models.ForeignKey(Paiements, models.DO_NOTHING, db_column='id_paiement')

    class Meta:
        managed = False
        db_table = 'webhook_logs'
        db_table_comment = 'Registre brut des notifications entrantes des agrégateurs Mobile Money  APPEND-ONLY (RG-09, idempotence).'
