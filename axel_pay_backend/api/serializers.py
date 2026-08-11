from rest_framework import serializers
from .crypto import decrypt_token
from .models import (
    Adresses,
    AuditLogs,
    ComptesTechniques,
    Compteurs,
    Contrats,
    FacturesPostpayees,
    GestionCompteurs,
    HistoriqueArchive,
    Litiges,
    Notifications,
    Paiements,
    Tarifs,
    TransactionsPrepayees,
    UserConsentLogs,
    UserDevices,
    Users,
    WebhookLogs,
)


def masquer_telephone(numero):
    """
    Masque partiellement un numéro de téléphone pour l'affichage client
    (§11.2 du CDC), ex: '699123456' -> '6•• •• •• 56'. Conserve le premier
    chiffre et les deux derniers (suffisant pour que l'utilisateur
    reconnaisse son propre numéro dans une liste), masque le reste par
    groupes de 2 caractères.
    Ne touche jamais à la valeur en base : c'est une transformation
    d'affichage uniquement (cf. UsersSerializer.to_representation).
    """
    if not numero:
        return numero
    valeur = str(numero)
    if len(valeur) <= 3:
        return "•" * len(valeur)

    prefixe, suffixe = valeur[0], valeur[-2:]
    milieu = valeur[1:-2]
    tailles_groupes = [min(2, len(milieu) - i) for i in range(0, len(milieu), 2)]

    if not tailles_groupes:
        return f"{prefixe} {suffixe}"

    premier_groupe = prefixe + "•" * tailles_groupes[0]
    autres_groupes = ["•" * taille for taille in tailles_groupes[1:]]
    return " ".join([premier_groupe, *autres_groupes, suffixe])


def masquer_numero_compteur(numero):
    """
    Masque partiellement un numéro de compteur pour l'affichage client
    (§11.2 du CDC), ex: 'CPT2026001234' -> 'CPT2•••••1234'. Conserve un
    préfixe et un suffixe suffisants pour que le client identifie
    visuellement le bon compteur dans une liste, sans exposer
    l'identifiant complet à un tiers qui intercepterait la réponse — le
    rapprochement exact (recherche par valeur complète) reste possible
    côté backend, qui continue de travailler sur la valeur réelle en base.
    """
    if not numero:
        return numero
    valeur = str(numero)
    if len(valeur) <= 6:
        return valeur[0] + "•" * (len(valeur) - 1) if len(valeur) > 1 else valeur

    debut, fin = valeur[:4], valeur[-4:]
    return f"{debut}{'•' * (len(valeur) - 8)}{fin}"


def masquer_prenom(prenom):
    """
    Masque partiellement un prénom pour l'affichage client (§11.2),
    ex: 'Jeanne' -> 'J•••••'. Utilisé par la recherche d'utilisateur par
    téléphone (RG-02, UserRechercheView) : le titulaire d'un contrat doit
    pouvoir vérifier qu'il a trouvé le bon tiers avant de le déléguer,
    sans obtenir son identité complète depuis un simple numéro de
    téléphone.
    """
    if not prenom:
        return prenom
    valeur = str(prenom)
    if len(valeur) <= 1:
        return valeur
    return valeur[0] + "•" * (len(valeur) - 1)


class AdressesSerializer(serializers.ModelSerializer):
    class Meta:
        model = Adresses
        fields = '__all__'
        extra_kwargs = {
            'date_creation': {'required': False},
        }

class AuditLogsSerializer(serializers.ModelSerializer):
    class Meta:
        model = AuditLogs
        fields = '__all__'


class ComptesTechniquesSerializer(serializers.ModelSerializer):
    class Meta:
        model = ComptesTechniques
        fields = '__all__'
        # Même principe que UsersSerializer.mot_de_passe : une clé API ne se
        # renvoie jamais en clair dans une réponse, même si ce serializer
        # n'est pas encore branché sur une vue à ce jour.
        extra_kwargs = {
            'cle_api_hash': {'write_only': True},
        }


class ContratsSerializer(serializers.ModelSerializer):
    """
    CORRECTIF (audit du 21/07/2026) — `POST /contrats/` ne crée plus de
    ligne : `ContratListCreateView.create()` recherche le contrat Eneo
    existant par `numero_contrat` et vérifie que `Contrats.id_user`
    correspond bien à `request.user` avant de le renvoyer. Ce serializer
    n'est donc utilisé en écriture que pour sérialiser le contrat trouvé en
    réponse ; `id_user` reste néanmoins `required: False` ci-dessous par
    précaution, pour qu'un éventuel payload client contenant ce champ ne
    puisse de toute façon jamais l'écraser côté serveur (même logique de
    séparation client/serveur que UserConsentLogsSerializer /
    UserDevicesSerializer).
    """
    # CORRECTIF (audit lenteur accueil) : expose directement le nombre de
    # compteurs rattaches a ce contrat, calcule cote serveur. Avant ce
    # correctif, le client Flutter devait appeler
    # GET /contrats/<id>/compteurs/ separement pour chaque contrat rien
    # que pour compter ses compteurs (N+1 orchestre cote client - voir
    # EneoRepository.getContrats). ContratListCreateView.get_queryset
    # annote nombre_compteurs via Count() (une seule requete SQL avec
    # GROUP BY pour toute la liste) ; si l'instance n'a pas ete annotee
    # (ex: ContratDetailView, ou la reponse de POST /contrats/), on
    # retombe sur un .count() ponctuel plutot que de planter.
    nombre_compteurs = serializers.SerializerMethodField()

    def get_nombre_compteurs(self, obj):
        annote = getattr(obj, 'nombre_compteurs', None)
        if annote is not None:
            return annote
        return obj.compteurs.count()

    class Meta:
        model = Contrats
        fields = '__all__'
        extra_kwargs = {
            'id_user': {'required': False},
            'statut': {'required': False},
            'date_creation': {'required': False},
        }


class CompteursSerializer(serializers.ModelSerializer):
    """
    Masquage partiel (§11.2) : `numero_compteur_masque` expose une version
    partiellement masquée du numéro de compteur pour l'affichage client.
    Par défaut, `to_representation` masque aussi le champ brut
    `numero_compteur` dans la réponse — pour l'exposer en clair (recherche
    exacte, export RGPD via ExportDataView, usages backend légitimes),
    passer explicitement `context={'masquer': False}` au serializer. La
    valeur complète reste inchangée en base et pleinement disponible côté
    backend (ORM, `perform_create`, etc.), ce masquage n'agit qu'en sortie.
    """
    numero_compteur_masque = serializers.SerializerMethodField()

    def get_numero_compteur_masque(self, obj):
        return masquer_numero_compteur(getattr(obj, 'numero_compteur', None))

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if self.context.get('masquer', True):
            data['numero_compteur'] = masquer_numero_compteur(data.get('numero_compteur'))
        return data

    class Meta:
        model = Compteurs
        fields = '__all__'
        extra_kwargs = {
            'date_creation': {'required': False},
            'statut': {'required': False},
            # REFONTE v1.5 : id_contrat reste un champ normal du serializer
            # (le client doit désigner explicitement le contrat auquel
            # rattacher le nouveau compteur), mais la vue vérifie que
            # request.user est bien le titulaire de ce contrat avant
            # d'accepter la création (cf. CompteurListCreateView.perform_create).
        }


class FacturesPostpayeesSerializer(serializers.ModelSerializer):
    class Meta:
        model = FacturesPostpayees
        fields = '__all__'

class GestionCompteursSerializer(serializers.ModelSerializer):
    """
    REFONTE v1.5 — Une délégation porte soit sur `id_compteur`, soit sur
    `id_contrat`, jamais les deux, jamais aucun des deux (même règle que la
    contrainte CHECK `chk_gestion_compteurs_scope_exclusif` côté SQL) : on
    la valide ici aussi pour renvoyer un 400 exploitable par le client
    Flutter plutôt que de laisser remonter l'IntegrityError Postgres en 500.
    """
    class Meta:
        model = GestionCompteurs
        fields = '__all__'
        # IMPORTANT : on désactive les UniqueTogetherValidator auto-générés
        # par DRF à partir de `Meta.unique_together` du modèle. Ces
        # validators forcent `required=True` sur TOUS les champs qu'ils
        # couvrent (id_compteur ET id_contrat), ce qui écrase le
        # `required=False` défini ci-dessous et empêche d'envoyer une
        # délégation à portée "contrat" (sans id_compteur) ou "compteur"
        # (sans id_contrat) — DRF exige alors à tort le champ absent.
        # L'exclusivité et l'unicité restent garanties par `validate()`
        # ci-dessous et par les contraintes SQL (CHECK + UNIQUE) en base.
        validators = []
        extra_kwargs = {
            'statut': {'required': False},
            'date_octroi': {'required': False, 'allow_null': True},
            'id_compteur': {'required': False, 'allow_null': True},
            'id_contrat': {'required': False, 'allow_null': True},
        }

    def validate(self, attrs):
        id_compteur = attrs.get('id_compteur', getattr(self.instance, 'id_compteur', None))
        id_contrat = attrs.get('id_contrat', getattr(self.instance, 'id_contrat', None))
        if bool(id_compteur) == bool(id_contrat):
            raise serializers.ValidationError(
                "Une délégation doit porter sur exactement un compteur (id_compteur) "
                "ou un contrat entier (id_contrat), jamais les deux, jamais aucun des deux."
            )

        # On avait désactivé les UniqueTogetherValidator auto-générés
        # (`validators = []` ci-dessus) car ils forçaient id_compteur ET
        # id_contrat à `required=True`. Du coup on reproduit ici, à la
        # main, la même vérification (id_user + cible + type_droit déjà
        # utilisés) — sinon un doublon n'est plus intercepté par DRF et
        # remonte comme une IntegrityError Postgres (500) au lieu d'un 400
        # propre.
        id_user = attrs.get('id_user', getattr(self.instance, 'id_user', None))
        type_droit = attrs.get('type_droit', getattr(self.instance, 'type_droit', None))
        doublons = GestionCompteurs.objects.filter(id_user=id_user, type_droit=type_droit)
        doublons = doublons.filter(id_compteur=id_compteur) if id_compteur \
            else doublons.filter(id_contrat=id_contrat)
        if self.instance is not None:
            doublons = doublons.exclude(pk=self.instance.pk)
        if doublons.exists():
            raise serializers.ValidationError(
                "Une délégation avec ce même droit existe déjà pour cet utilisateur sur cette cible."
            )

        return attrs

class HistoriqueArchiveSerializer(serializers.ModelSerializer):
    class Meta:
        model = HistoriqueArchive
        fields = '__all__'


class LitigesSerializer(serializers.ModelSerializer):
    class Meta:
        model = Litiges
        fields = '__all__'
        extra_kwargs = {
            'statut': {'required': False},
            'date_ouverture': {'required': False},
            'id_litige': {'required': False},
            'niveau': {'required': False}
        }


class NotificationsSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notifications
        fields = '__all__'


class PaiementsSerializer(serializers.ModelSerializer):
    class Meta:
        model = Paiements
        fields = '__all__'


class TarifsSerializer(serializers.ModelSerializer):
    class Meta:
        model = Tarifs
        fields = '__all__'


class TransactionsPrepayeesSerializer(serializers.ModelSerializer):
    """
    Le jeton STS est chiffré en AES-256-GCM (api/crypto.py) avant stockage
    dans `token_genere` (cf. WebhookPaiementView._finaliser_recharge) : ce
    serializer le déchiffre à la volée pour l'afficher au client — le blob
    chiffré (base64) n'est donc jamais renvoyé tel quel dans les réponses
    API (TokenHistoriqueView, ExportDataView, réponse de AchatCreditView une
    fois la recharge finalisée...).
    """
    token_genere = serializers.SerializerMethodField()

    def get_token_genere(self, obj):
        valeur_stockee = getattr(obj, 'token_genere', None)
        dechiffre = decrypt_token(valeur_stockee)
        # Si le déchiffrement échoue (mauvaise clé, valeur historique restée
        # en clair avant ce correctif, etc.), on ne fait jamais planter la
        # réponse : on retombe sur la valeur brute stockée plutôt que de
        # lever une exception au milieu d'une liste paginée.
        return dechiffre if dechiffre is not None else valeur_stockee

    class Meta:
        model = TransactionsPrepayees
        fields = '__all__'
        extra_kwargs = {
            'statut_paiement': {'required': False},
            
        }


class UserConsentLogsSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserConsentLogs
        fields = '__all__'
        # id_user, ip_adresse et date_consentement sont fixés par
        # UserConsentView.perform_create() côté serveur — le client ne les
        # envoie jamais. Sans ce correctif, DRF les exige quand même en
        # entrée (fields='__all__' + colonnes NOT NULL) et renvoie 400 sur
        # CHAQUE appel à POST /profile/consent/.
        extra_kwargs = {
            'id_user': {'required': False},
            'ip_adresse': {'required': False},
            'date_consentement': {'required': False},
        }


class UserDevicesSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserDevices
        fields = '__all__'
        # id_user, statut et date_enregistrement sont fixés par
        # DeviceRegisterView.perform_create() côté serveur — même bug que
        # UserConsentLogsSerializer, corrigé de la même façon.
        extra_kwargs = {
            'id_user': {'required': False},
            'statut': {'required': False},
            'date_enregistrement': {'required': False},
        }


class UsersSerializer(serializers.ModelSerializer):
    """
    Masquage partiel (§11.2) : `telephone_masque` expose une version
    partiellement masquée du numéro pour l'affichage client
    ('6•• •• •• 56'). Par défaut, `to_representation` masque aussi le champ
    brut `telephone` dans la réponse — pour l'exposer en clair (export RGPD
    via ExportDataView, recherche exacte, autres usages backend
    légitimes), passer explicitement `context={'masquer': False}` au
    serializer. La valeur complète reste inchangée en base et pleinement
    disponible côté backend (ORM, RegisterView, ChangePhoneNumberView...),
    ce masquage n'agit qu'en sortie.
    """
    telephone_masque = serializers.SerializerMethodField()

    def get_telephone_masque(self, obj):
        return masquer_telephone(getattr(obj, 'telephone', None))

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if self.context.get('masquer', True):
            data['telephone'] = masquer_telephone(data.get('telephone'))
        return data

    class Meta:
        model = Users
        fields = '__all__'
        # CRITIQUE : `mot_de_passe` (empreinte Argon2id) ne doit JAMAIS
        # apparaître dans une réponse API. Avant ce correctif, chaque appel à
        # UsersSerializer(user).data — Register, Login, Profile,
        # ChangePhoneNumberView, AdminUserManagementView, ExportDataView —
        # renvoyait le hash au client. `write_only` autorise toujours la
        # création/mise à jour du mot de passe via ce serializer (utilisé par
        # AdminUserManagementView) sans jamais le sérialiser en sortie.
        extra_kwargs = {
            'mot_de_passe': {'write_only': True},
            # statut_compte, tentatives_connexion_echouees, date_creation,
            # date_verrouillage et date_derniere_connexion sont fixés côté
            # serveur (RegisterView, AdminUserManagementView.perform_create,
            # VerifyOTPView, etc.) — jamais par le client. Même bug/même
            # correctif que UserConsentLogsSerializer/UserDevicesSerializer.
            'statut_compte': {'required': False},
            'tentatives_connexion_echouees': {'required': False},
            'date_creation': {'required': False},
            'date_verrouillage': {'required': False},
            'date_derniere_connexion': {'required': False},
        }


class WebhookLogsSerializer(serializers.ModelSerializer):
    class Meta:
        model = WebhookLogs
        fields = '__all__'