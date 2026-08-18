# -*- coding: utf-8 -*-
"""
===============================================================================
 views.py — Plateforme Eneo (Gestion des Factures & Recharges)
===============================================================================
Ce fichier regroupe l'ensemble des vues Django REST Framework de l'application,
organisées en 9 modules fonctionnels, conformément au Cahier des Charges v1.0
(Juillet 2026). Chaque bloc de code référence explicitement :
    - la section du Cahier des Charges (CDC) dont il découle ;
    - les Règles de Gestion (RG-xx) qu'il doit respecter.

⚠️ NOTE D'ARCHITECTURE :
Le modèle `Users` de ce projet est un modèle "métier" (managed=False, table
existante), distinct du modèle `django.contrib.auth.User`. Il n'hérite donc
PAS de AbstractUser/AbstractBaseUser. Cela implique que :
    - l'authentification (login, JWT, permissions) ne peut pas s'appuyer sur
      les mécanismes automatiques de Django (`request.user` classique,
      `IsAuthenticated` standard, `django.contrib.auth.authenticate`) ;
    - il faut soit (a) brancher un backend d'authentification JWT personnalisé
      (ex: djangorestframework-simplejwt avec un AUTH_USER_MODEL adapté ou un
      backend custom), soit (b) gérer une authentification "maison" au-dessus
      de DRF (TokenAuthentication custom).
Dans ce fichier, on suppose qu'un tel mécanisme existe déjà et qu'il peuple
`request.user` avec une instance de `Users` (voir authentication.py — hors
périmètre de ce fichier).

✅ CORRECTIFS APPLIQUÉS (voir CHANGELOG_OPTIMISATIONS.md pour le détail) :
    - Le hachage/la vérification du mot de passe utilisent désormais
      `django.contrib.auth.hashers` (Argon2id si `argon2-cffi` est installé,
      PBKDF2 sinon) au lieu d'un stockage/comparaison en clair.
    - La vérification OTP compare réellement le code saisi à un code généré
      et mis en cache (`django.core.cache`, TTL 5 min) au lieu d'accepter
      n'importe quelle valeur.
Ces deux points ne dépendaient d'aucun service externe et ont donc été
implémentés pour de vrai plutôt que laissés en `TODO INTEGRATION`.

Les points qui dépendent réellement d'un service externe (Eneo, agrégateurs
Mobile Money, Firebase, SMS, Celery/RQ, génération de JWT, génération de PDF)
restent marqués par des commentaires « TODO INTEGRATION » : la logique
métier et les contrôles de sécurité/RG sont en place, mais l'appel réseau
réel doit être branché sur les services dédiés.
===============================================================================
"""

import hashlib
import hmac
import logging
import secrets
import string
from datetime import timedelta
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError
from django.core.mail import send_mail, EmailMultiAlternatives
from django.template.loader import render_to_string
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import smtplib


from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.core.cache import cache
from django.db import transaction
from django.db.models import Count, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone

from rest_framework import generics, permissions, status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from .crypto import encrypt_token
from .pagination import StandardResultsSetPagination
from .services import notchpay
from .services.notchpay import NotchPayError
from .services.orange_sms import OrangeSmsError, envoyer_sms
from .services import ai_support
from .services import deepl_translate
from .services.deepl_translate import DeepLError
from .services.pdf_reports import generer_pdf_export_donnees, generer_pdf_ticket
from .models import (
    Adresses,
    AuditLogs,
    Compteurs,
    Contrats,
    FacturesPostpayees,
    GestionCompteurs,
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
from .serializers import (
    AdressesSerializer,
    AuditLogsSerializer,
    CompteursSerializer,
    ContratsSerializer,
    FacturesPostpayeesSerializer,
    GestionCompteursSerializer,
    LitigesSerializer,
    NotificationsSerializer,
    PaiementsSerializer,
    TarifsSerializer,
    TransactionsPrepayeesSerializer,
    UserConsentLogsSerializer,
    UserDevicesSerializer,
    UsersSerializer,
    WebhookLogsSerializer,
    masquer_prenom,
)

logger = logging.getLogger(__name__)


# ==============================================================================
# OUTILS COMMUNS — Permissions personnalisées & helpers
# ==============================================================================
# Ces classes de permission matérialisent la "Matrice synthétique des droits"
# du CDC (section 4.4). Elles supposent que `request.user` est une instance
# `Users` avec un champ `role` dont les valeurs possibles sont EXACTEMENT
# celles de l'ENUM PostgreSQL `enum_role` (axel.sql) :
#   'Client', 'Gestionnaire', 'Tiers_Autorise', 'Agent_Terrain',
#   'Admin_Support', 'Admin_Financier', 'Admin_Technicien'
# ⚠️ La casse compte : PostgreSQL est sensible à la casse sur les ENUM.

class IsAdminSupport(permissions.BasePermission):
    """Réservé à l'Administrateur Support Client (CDC 4.2)."""
    def has_permission(self, request, view):
        return bool(request.user and getattr(request.user, "role", None) == "Admin_Support")


class IsAdminFinancier(permissions.BasePermission):
    """Réservé à l'Administrateur Responsable Financier (CDC 4.2, 9.4 Niveau 3)."""
    def has_permission(self, request, view):
        return bool(request.user and getattr(request.user, "role", None) == "Admin_Financier")


class IsAdminTechnicien(permissions.BasePermission):
    """
    Réservé à l'Administrateur Technicien API.
    RG-03 : seul ce rôle peut exécuter un transfert de propriété de compteur.
    """
    def has_permission(self, request, view):
        return bool(request.user and getattr(request.user, "role", None) == "Admin_Technicien")


class IsAnyAdmin(permissions.BasePermission):
    """Vrai pour n'importe lequel des 3 profils back-office (accès lecture commun)."""
    def has_permission(self, request, view):
        role = getattr(request.user, "role", None)
        return bool(request.user and role in ("Admin_Support", "Admin_Financier", "Admin_Technicien"))


class IsAgentTerrain(permissions.BasePermission):
    """Réservé à l'Agent Terrain Eneo (CDC 4.1, 5.5)."""
    def has_permission(self, request, view):
        return bool(request.user and getattr(request.user, "role", None) == "Agent_Terrain")


class IsCompteTechnique(permissions.BasePermission):
    """
    ⚠️ INCOHÉRENCE DE SCHÉMA DÉTECTÉE, NON CORRIGÉE AUTOMATIQUEMENT :
    `enum_role` (axel.sql) NE CONTIENT PAS de valeur "Compte_Technique". Les
    comptes techniques vivent dans une table dédiée `COMPTES_TECHNIQUES`
    (colonnes `scope enum_scope_technique`, `statut enum_statut_delegation`),
    distincte de `USERS`. Un `request.user` issu du modèle `Users` ne pourra
    donc JAMAIS satisfaire cette permission telle quelle : elle renverra
    toujours False, quel que soit l'appelant.
    Il faut brancher une authentification dédiée aux comptes techniques
    (ex: clé API / JWT signé séparément, résolu vers `COMPTES_TECHNIQUES`
    plutôt que vers `Users`) avant que `AlerteTechniqueCompteurView` et
    `WebhookPaiementView` ne puissent fonctionner comme prévu au CDC (RG-05).
    """
    def has_permission(self, request, view):
        return bool(request.user and getattr(request.user, "role", None) == "Compte_Technique")


def hash_password(mot_de_passe_clair):
    """
    Hache un mot de passe avec Argon2id (CDC 11.1).
    Utilise `django.contrib.auth.hashers.make_password`, indépendant du
    modèle `django.contrib.auth.User` — fonctionne avec `Users` (managed).
    Nécessite le paquet `argon2-cffi` (cf. requirements.txt) ; à défaut,
    Django se rabat silencieusement sur PBKDF2 (toujours sûr, moins conforme
    à la CDC qui demande explicitement Argon2id).
    """
    try:
        return make_password(mot_de_passe_clair, hasher="argon2")
    except ValueError:
        # `argon2-cffi` non installé : on ne bloque pas l'inscription pour
        # autant, mais on utilise le hasher par défaut du projet.
        return make_password(mot_de_passe_clair)


def verify_password(mot_de_passe_clair, mot_de_passe_hash):
    """Vérifie un mot de passe en clair contre son empreinte stockée."""
    if not mot_de_passe_hash:
        return False
    return check_password(mot_de_passe_clair, mot_de_passe_hash)


def generate_and_cache_otp(identifiant, length=6, ttl_seconds=300):
    """
    Génère un OTP à `length` chiffres et le met en cache (TTL 5 min par
    défaut), clé par identifiant (téléphone). Ne dépend d'aucun service
    externe : fonctionne avec n'importe quel backend de cache Django
    (LocMemCache en dev, Redis/Memcached en prod).
    """
    otp = "".join(secrets.choice(string.digits) for _ in range(length))
    cache.set(f"otp:{identifiant}", otp, timeout=ttl_seconds)
    return otp


def verify_and_consume_otp(identifiant, otp_saisi):
    """
    Compare le code saisi à celui stocké en cache pour cet identifiant, puis
    le supprime immédiatement du cache (un OTP est à usage unique, qu'il
    soit correct ou non — évite les tentatives répétées sur le même code).
    """
    otp_attendu = cache.get(f"otp:{identifiant}")
    cache.delete(f"otp:{identifiant}")
    return bool(otp_attendu) and secrets.compare_digest(str(otp_saisi), str(otp_attendu))


def require_otp_for_sensitive_action(request, scope, montant=None, seuil=None):
    """
    2FA réelle (RG-06) pour une action sensible : jusqu'ici, le code se
    contentait de vérifier la PRÉSENCE du champ `otp_confirmation` dans le
    payload, sans jamais vérifier sa valeur — un client pouvait envoyer
    n'importe quelle chaîne non vide (`"otp_confirmation": "x"`) et passer
    l'action. Ce helper généralise `verify_and_consume_otp` (déjà utilisé
    pour la vérification d'inscription) aux actions sensibles côté paiement.

    - `scope` identifie l'action protégée (ex: "paiement", "remboursement") ;
      combiné à l'utilisateur courant, ça donne une clé de cache dédiée à
      CET utilisateur et CETTE action, indépendante de l'OTP d'inscription.
    - Si `montant`/`seuil` sont fournis, la 2FA n'est exigée qu'à partir du
      seuil (RG-06 : "au-delà d'un seuil") ; sinon (`seuil=None`), la 2FA
      est TOUJOURS exigée (ex: remboursement, toujours sensible quel que
      soit le montant).

    Flux en 2 appels côté client, sans état supplémentaire à persister
    côté serveur :
      1. Premier appel sans `otp_confirmation` : on génère un OTP, on le met
         en cache (TTL 5 min, `generate_and_cache_otp`) et on répond 400 en
         demandant la confirmation — le TODO INTEGRATION couvre l'envoi
         réel du code (SMS/push), le contrôle métier est lui bien réel.
      2. Second appel avec `otp_confirmation` : on consomme l'OTP via
         `verify_and_consume_otp` (comparaison à temps constant, usage
         unique) ; s'il est invalide/expiré, l'action est bloquée.
    """
    if seuil is not None and (montant is None or montant < seuil):
        return  # Sous le seuil : 2FA non requise pour cette action.

    identifiant = f"{scope}:{getattr(request.user, 'pk', None)}"
    otp_saisi = request.data.get("otp_confirmation")

    if not otp_saisi:
        generate_and_cache_otp(identifiant)
        # TODO INTEGRATION : envoyer ce code via le canal transactionnel
        # (cascade Push → WhatsApp → SMS, CDC 10) plutôt que de le garder
        # uniquement en cache.
        raise ValidationError({
            "otp_confirmation": (
                "Authentification à deux facteurs requise (RG-06). Un code "
                "de confirmation vient d'être envoyé ; renvoyez la requête "
                "avec ce code dans `otp_confirmation`."
            ),
        })

    if not verify_and_consume_otp(identifiant, otp_saisi):
        raise ValidationError({"otp_confirmation": "Code de confirmation invalide ou expiré."})


def log_audit(auteur, action, objet_touche, motif="", cible=None, request=None):
    """
    Écrit une entrée dans la piste d'audit (RG-04, CDC 5.4, table Append-Only).
    À appeler systématiquement pour toute action administrative sensible :
    impersonation, remboursement, transfert de compteur, modification de rôle...

    NB: `AuditLogs` est en écriture seule (Append-Only) — on ne fait jamais
    d'update/delete dessus, uniquement des `create`.
    """
    AuditLogs.objects.create(
        action=action,
        objet_touche=objet_touche,
        motif=motif,
        ip_adresse=(request.META.get("REMOTE_ADDR", "") if request else ""),
        terminal=(request.META.get("HTTP_USER_AGENT", "") if request else ""),
        date_heure=timezone.now(),
        id_auteur=auteur,
        id_utilisateur_cible=cible,
    )


def get_delegated_compteur_ids(user):
    """
    REFONTE v1.5 — Retourne l'ensemble des id_compteur accessibles à `user`,
    qu'il en soit titulaire (via un CONTRAT dont il est `Contrats.id_user`)
    ou délégataire actif — à portée compteur (GestionCompteurs.id_compteur)
    ou à portée contrat entier (GestionCompteurs.id_contrat, qui couvre
    alors tous les compteurs actuels de ce contrat).

    Le compteur n'étant plus le pivot du modèle, la propriété directe
    passe désormais par CONTRATS.id_user — ce n'est plus une ligne
    GestionCompteurs(type_droit='Gestionnaire') qui en fait foi.

    Reste utile quand on a réellement besoin de la LISTE complète (ex:
    FacturesListView filtre par un id_compteur déjà connu, ExportDataView a
    besoin de tous les compteurs pour construire l'export RGPD). Pour un
    simple contrôle d'accès booléen sur un seul compteur, préférer
    `user_has_access_to_compteur()` ci-dessous : plus rapide, car traduit en
    une requête SQL EXISTS() au lieu de charger toute la liste en mémoire
    Python pour tester une appartenance.
    """
    ids_possedes = Compteurs.objects.filter(
        id_contrat__id_user=user, id_contrat__statut="Actif"
    ).values_list("id_compteur", flat=True)

    ids_delegues_compteur = GestionCompteurs.objects.filter(
        id_user=user, statut="Actif", id_compteur__isnull=False
    ).values_list("id_compteur", flat=True)

    ids_delegues_contrat = Compteurs.objects.filter(
        id_contrat__gestioncompteurs__id_user=user,
        id_contrat__gestioncompteurs__statut="Actif",
        id_contrat__gestioncompteurs__id_contrat__isnull=False,
    ).values_list("id_compteur", flat=True)

    return set(ids_possedes) | set(ids_delegues_compteur) | set(ids_delegues_contrat)


def user_has_access_to_compteur(user, id_compteur):
    """
    REFONTE v1.5 — Vérifie que `user` a un droit actif sur `id_compteur`,
    qu'il en soit le titulaire (propriétaire du CONTRAT auquel appartient ce
    compteur) ou délégataire (à portée compteur ou à portée contrat entier),
    sans charger l'ensemble de ses compteurs accessibles en mémoire.
    """
    try:
        id_compteur = int(id_compteur)
    except (TypeError, ValueError):
        return False

    return (
        Compteurs.objects.filter(
            id_compteur=id_compteur, id_contrat__id_user=user, id_contrat__statut="Actif",
        ).exists()
        or GestionCompteurs.objects.filter(
            id_user=user, id_compteur_id=id_compteur, statut="Actif",
        ).exists()
        or GestionCompteurs.objects.filter(
            id_user=user, statut="Actif", id_contrat__isnull=False,
            id_contrat__compteurs__id_compteur=id_compteur,
        ).exists()
    )


def user_owns_contrat(user, id_contrat):
    """
    REFONTE v1.5 — Vérifie que `user` est bien le TITULAIRE (pas un simple
    délégataire) du contrat `id_contrat`. Utilisé pour tout ce qui touche à
    la structure même du contrat : rattacher un compteur, créer/révoquer une
    délégation — des actions qu'un tiers délégataire ne doit jamais pouvoir
    effectuer, même s'il a un accès en lecture/paiement.
    """
    try:
        id_contrat = int(id_contrat)
    except (TypeError, ValueError):
        return False
    return Contrats.objects.filter(id_contrat=id_contrat, id_user=user).exists()


# ==============================================================================
# MODULE 1 — AUTHENTIFICATION, PROFIL & PRÉFÉRENCES (CDC 5.1)
# ==============================================================================

class RegisterView(APIView):
    """
    Inscription d'un nouvel utilisateur.
    - Téléphone ET e-mail sont tous deux obligatoires (CDC 5.1).
    - Le mot de passe est haché (Argon2id) avant stockage — jamais en clair.
    - Déclenche l'envoi d'un OTP à 6 chiffres pour vérification du téléphone.
    - Le consentement RGPD doit être capturé séparément via UserConsentView
      dès l'écran d'inscription (action positive de l'utilisateur, CDC 5.1 / 11.3).
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        data = request.data
        required = ("nom", "prenom", "telephone", "email", "mot_de_passe")
        missing = [f for f in required if not data.get(f)]
        if missing:
            raise ValidationError({"detail": f"Champs manquants : {missing}"})

        if Users.objects.filter(telephone=data["telephone"]).exists():
            raise ValidationError({"telephone": "Ce numéro est déjà utilisé."})
        if Users.objects.filter(email=data["email"]).exists():
            raise ValidationError({"email": "Cet e-mail est déjà utilisé."})

        # Mot de passe haché Argon2id (CDC 11.1) — jamais stocké en clair.
        mot_de_passe_hash = hash_password(data["mot_de_passe"])

        user = Users.objects.create(
            nom=data["nom"],
            prenom=data["prenom"],
            telephone=data["telephone"],
            email=data["email"],
            mot_de_passe=mot_de_passe_hash,
            situation_matrimoniale=data.get("situation_matrimoniale"),
            quartier=data.get("quartier"),
            role="Client",
            # ⚠️ Django envoie TOUJOURS la colonne dans l'INSERT (avec la
            # valeur par défaut du champ Python, pas celle de la base) —
            # compter sur le DEFAULT SQL 'Actif' ne fonctionne pas ici.
            # `enum_statut_compte` (axel.sql) ne contient QUE 'Actif',
            # 'Verrouillé', 'Désactivé' — pas de valeur "en attente de
            # vérification". On fixe donc explicitement 'Actif'. Si vous
            # voulez bloquer l'accès tant que l'OTP n'est pas confirmé, il
            # faut ajouter une valeur à l'ENUM côté SQL (ex:
            # 'En_Attente_Verification') puis migrer, et l'utiliser ici.
            statut_compte="Actif",
            tentatives_connexion_echouees=0,
            date_creation=timezone.now(),
        )

        # OTP généré et mis en cache (TTL 5 min), vérifié pour de vrai par
        # VerifyOTPView — voir generate_and_cache_otp().
        otp = generate_and_cache_otp(user.telephone)
        print(f"[DEBUG OTP] telephone={user.telephone} otp={otp}")
        # Envoi réel de l'OTP par SMS via l'API Orange SMS (CDC 5.1/10).
        # ⚠️ Volontairement non bloquant : le compte est déjà créé et l'OTP
        # déjà généré/mis en cache avant cet appel — un incident réseau ou
        # une mauvaise configuration Orange (secret manquant, etc.) ne doit
        # jamais empêcher l'inscription. Le `print` de debug ci-dessus reste
        # le filet de secours en environnement de développement.
        # TODO INTEGRATION : basculer cet appel synchrone vers une file
        # d'attente asynchrone (Celery/RQ, CDC 7.3) dès qu'elle sera câblée.
        try:
            envoyer_sms(user.telephone, f"Votre code de vérification Eneo : {otp}")
        except OrangeSmsError as exc:
            logger.warning("Échec de l'envoi SMS OTP à %s : %s", user.telephone, exc)

        return Response(
            UsersSerializer(user).data,
            status=status.HTTP_201_CREATED,
        )


class VerifyOTPView(APIView):
    """
    Vérifie le code OTP à 6 chiffres envoyé lors de l'inscription (ou d'un
    changement de téléphone). Active le compte une fois validé.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        telephone = request.data.get("telephone")
        otp_saisi = request.data.get("otp")
        user = get_object_or_404(Users, telephone=telephone)

        if not verify_and_consume_otp(telephone, otp_saisi):
            raise ValidationError({"otp": "Code invalide ou expiré."})

        user.statut_compte = "Actif"
        user.save(update_fields=["statut_compte"])
        return Response({"detail": "Compte vérifié avec succès."})


class LoginView(APIView):
    """
    Connexion par téléphone/e-mail + mot de passe.

    RG applicable (implicite CDC 5.1) :
    - Verrouillage du compte 1h après 5 tentatives échouées consécutives,
      avec envoi d'une alerte de sécurité (canal Critique — non désactivable,
      RG-13).
    - Émission d'un JWT d'accès (15-30 min) + refresh token (30 jours),
      cf. CDC 11.1.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        identifiant = request.data.get("identifiant")  # téléphone ou e-mail
        mot_de_passe = request.data.get("mot_de_passe")

        user = Users.objects.filter(telephone=identifiant).first() \
            or Users.objects.filter(email=identifiant).first()
        if user is None:
            raise ValidationError({"detail": "Identifiants invalides."})

        # Verrouillage actif ?
        if user.date_verrouillage and user.date_verrouillage > timezone.now():
            raise PermissionDenied(
                "Compte temporairement verrouillé suite à trop de tentatives échouées."
            )

        # Vérification du hash Argon2id (CDC 11.1).
        mot_de_passe_valide = verify_password(mot_de_passe, user.mot_de_passe)

        if not mot_de_passe_valide:
            user.tentatives_connexion_echouees += 1
            if user.tentatives_connexion_echouees >= 5:
                user.date_verrouillage = timezone.now() + timedelta(hours=1)
                # TODO INTEGRATION : notification "Critique" de sécurité
                # (SMS + Push + WhatsApp simultanés, RG-13).
            user.save(update_fields=["tentatives_connexion_echouees", "date_verrouillage"])
            raise ValidationError({"detail": "Identifiants invalides."})

        # Connexion réussie : reset du compteur d'échecs.
        user.tentatives_connexion_echouees = 0
        user.date_verrouillage = None
        user.date_derniere_connexion = timezone.now()
        user.save(update_fields=[
            "tentatives_connexion_echouees", "date_verrouillage", "date_derniere_connexion"
        ])

        from rest_framework_simplejwt.tokens import RefreshToken

# ... remplace ces deux lignes :
        refresh = RefreshToken()
        refresh["id_user"] = user.id_user
        refresh["role"] = user.role
        access_token = str(refresh.access_token)
        refresh_token = str(refresh)

        return Response({
            "access": access_token,
            "refresh": refresh_token,
            "user": UsersSerializer(user).data,
        })


class LogoutView(APIView):
    """
    Déconnexion : invalide le refresh token côté serveur (blacklist).
    Session utilisateur également expirée après 25 min d'inactivité (CDC 5.1)
    — cette expiration est gérée au niveau du middleware/du JWT, pas ici.
    """
    permission_classes = [permissions.IsAuthenticated]

  
        
    def post(self, request):
        refresh_token = request.data.get("refresh")
        try:
            RefreshToken(refresh_token).blacklist()
        except TokenError:
            pass  # déjà invalide/expiré, rien à faire
        return Response(status=status.HTTP_205_RESET_CONTENT)


class RefreshTokenView(APIView):
    """Émet un nouveau JWT d'accès à partir d'un refresh token valide (30 jours)."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        # CORRECTIF P0 (audit du 20/07/2026) : cette méthode contenait une
        # fonction `post` imbriquée jamais appelée — le corps réel de la vue
        # ne retournait donc jamais de Response (None implicite), et DRF
        # levait une erreur 500 systématique sur /auth/refresh/. Le code est
        # remonté ici, au bon niveau d'indentation, sans fonction imbriquée.
        refresh_token = request.data.get("refresh")
        if not refresh_token:
            raise ValidationError({"refresh": "Ce champ est requis."})

        try:
            refresh = RefreshToken(refresh_token)
        except TokenError:
            raise ValidationError({"refresh": "Token invalide ou expiré."})

        return Response({"access": str(refresh.access_token)})

class PasswordResetRequestView(APIView):
    """
    Déclenche la procédure de mot de passe oublié, par e-mail OU téléphone
    (CDC 5.1). Envoie un lien/OTP de réinitialisation.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        identifiant = request.data.get("identifiant")
        user = Users.objects.filter(telephone=identifiant).first() \
            or Users.objects.filter(email=identifiant).first()
        # Réponse volontairement neutre pour ne pas divulguer l'existence du compte.
        if user:
            # TODO INTEGRATION : générer un token de reset à durée de vie courte
            # et l'envoyer par e-mail/SMS.
            pass
        return Response({"detail": "Si ce compte existe, des instructions ont été envoyées."})


class PasswordResetConfirmView(APIView):
    """Confirme la réinitialisation avec le token reçu et le nouveau mot de passe."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        token = request.data.get("token")
        nouveau_mdp = request.data.get("nouveau_mot_de_passe")
        if not token or not nouveau_mdp:
            raise ValidationError({"detail": "Token et nouveau mot de passe requis."})
        # TODO INTEGRATION : valider le token, appliquer la politique de mot de
        # passe renforcée (12 caractères min, maj/min/chiffres/spéciaux,
        # rejet des mots de passe compromis — CDC 11.1), puis hacher (Argon2id).
        return Response({"detail": "Mot de passe réinitialisé avec succès."})


class ChangePhoneNumberView(generics.UpdateAPIView):
    """
    Modification du numéro de téléphone.
    CDC 5.1 : soumise à ré-authentification par mot de passe (protection
    contre le détournement de compte).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UsersSerializer

    def get_object(self):
        return self.request.user

    def update(self, request, *args, **kwargs):
        mot_de_passe = request.data.get("mot_de_passe_confirmation")
        mot_de_passe_valide = verify_password(mot_de_passe, request.user.mot_de_passe)
        if not mot_de_passe_valide:
            raise PermissionDenied("Ré-authentification requise pour cette opération.")

        nouveau_telephone = request.data.get("telephone")
        if Users.objects.exclude(pk=request.user.pk).filter(telephone=nouveau_telephone).exists():
            raise ValidationError({"telephone": "Déjà utilisé par un autre compte."})

        user = request.user
        user.telephone = nouveau_telephone
        # ⚠️ Même limitation que RegisterView : pas de valeur "en attente de
        # vérification" dans enum_statut_compte. On ne touche donc pas
        # statut_compte ici — le compte reste dans son état courant pendant
        # que l'OTP de re-vérification est envoyé sur le nouveau numéro.
        user.save(update_fields=["telephone"])
        # TODO INTEGRATION : renvoyer un OTP sur le nouveau numéro.
        return Response(UsersSerializer(user).data)


class ProfileView(generics.RetrieveUpdateAPIView):
    """
    Consultation et mise à jour du profil de l'utilisateur connecté.
    Champs éditables : nom, prénom, situation matrimoniale, quartier, etc.
    (le téléphone passe exclusivement par ChangePhoneNumberView, l'e-mail
    par un flux équivalent avec vérification).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UsersSerializer

    def get_object(self):
        return self.request.user


class UserRechercheView(APIView):
    """
    Recherche d'un utilisateur par téléphone, pour la délégation de
    compteur/contrat à un tiers (CDC 4.1, RG-02) : avant de créer une
    délégation via `POST /delegations/` (GestionCompteursView), le
    titulaire doit pouvoir retrouver le `id_user` du tiers à partir de son
    numéro de téléphone, et vérifier visuellement qu'il s'agit bien de la
    bonne personne avant de valider.

    GET /users/recherche/?telephone=<numéro exact>

    - Recherche EXACTE uniquement (pas de préfixe/`icontains`) : le
      titulaire doit connaître le numéro complet du tiers pour le
      retrouver. Une recherche par préfixe transformerait cet endpoint en
      annuaire consultable par quiconque est authentifié — inacceptable
      même en `IsAuthenticated` seul.
    - Ne renvoie jamais l'email ni le mot de passe (même hashé) : seuls
      `id_user`, `nom` et `prenom` (masqué, §11.2, cf.
      `serializers.masquer_prenom`) sont exposés, strictement le nécessaire
      pour que le titulaire confirme l'identité du tiers avant délégation.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        telephone = request.query_params.get("telephone")
        if not telephone:
            raise ValidationError({"telephone": "Requis (recherche exacte)."})

        utilisateur = Users.objects.filter(telephone=telephone).exclude(
            id_user=request.user.id_user
        ).first()
        if not utilisateur:
            return Response(status=status.HTTP_404_NOT_FOUND)

        return Response({
            "id_user": utilisateur.id_user,
            "nom": utilisateur.nom,
            "prenom_masque": masquer_prenom(utilisateur.prenom),
        })


class UserConsentView(generics.ListCreateAPIView):
    """
    Recueil et traçabilité du consentement RGPD (CDC 5.1 / 11.3).
    Table `UserConsentLogs` en écriture seule (Append-Only, RG-12) : on ne
    fait jamais d'update, chaque nouvelle décision (GRANTED/REVOKED) crée une
    nouvelle ligne, opposable en cas de contrôle réglementaire (ANTIC).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UserConsentLogsSerializer

    def get_queryset(self):
        return UserConsentLogs.objects.filter(id_user=self.request.user).order_by("-date_consentement")

    def perform_create(self, serializer):
        serializer.save(
            id_user=self.request.user,
            ip_adresse=self.request.META.get("REMOTE_ADDR", ""),
            date_consentement=timezone.now(),
        )


class NotificationPreferencesView(APIView):
    """
    Gestion fine des préférences de notification PAR COMPTEUR (CDC 5.1),
    utile aux utilisateurs multi-compteurs (RG-01).
    NB : les notifications de sécurité et de livraison de jeton restent
    obligatoires quel que soit le paramétrage (RG-13) — ce endpoint ne doit
    donc jamais permettre de désactiver le canal "Critique"/"Transactionnel"
    lié à la livraison du jeton.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, id_compteur):
        # TODO : modéliser une table dédiée `PreferencesNotification` si la
        # granularité dépasse un simple JSON stocké côté compteur/utilisateur.
        return Response({"id_compteur": id_compteur, "preferences": {}})

    def patch(self, request, id_compteur):
        preferences = request.data.get("preferences", {})
        # Garde-fou RG-13 : on ignore toute tentative de désactivation des
        # canaux obligatoires (sécurité / livraison de jeton).
        preferences.pop("securite_desactivee", None)
        preferences.pop("livraison_jeton_desactivee", None)
        # TODO INTEGRATION : persister les préférences.
        return Response({"id_compteur": id_compteur, "preferences": preferences})


# ==============================================================================
# MODULE 2 — CONTRATS, COMPTES & COMPTEURS (CDC 5.1, 5.5 — RG-01 à RG-03)
# ==============================================================================
# REFONTE v1.5 : CONTRATS est la nouvelle racine du graphe de propriété.
# Hiérarchie : USERS (1—N) CONTRATS (1—N) COMPTEURS (1—N) FACTURES. Le
# compteur n'est plus le point d'ancrage direct des droits : c'est le
# contrat qui l'est. GESTION_COMPTEURS ne modélise plus que des délégations
# à des tiers (lecture et/ou paiement), jamais la propriété primaire.
# ==============================================================================

class ContratListCreateView(generics.ListCreateAPIView):
    """
    Liste les contrats dont l'utilisateur est TITULAIRE.

    CORRECTIF (audit du 21/07/2026) : le bouton "Ajouter un contrat" ne doit
    JAMAIS créer une nouvelle ligne CONTRATS. Un contrat Eneo existe déjà en
    base — il est créé par l'agence/le back-office au moment de la
    souscription réelle, avec son `numero_contrat` officiel et son
    `id_user` (le client identifié par Eneo à ce moment-là, indépendamment
    de l'app mobile). Ce que fait ce bouton, c'est simplement RATTACHER un
    compte applicatif existant à un contrat Eneo déjà existant, à partir de
    son numéro.

    Avant ce correctif, `perform_create` créait purement et simplement un
    nouveau contrat avec le numéro tapé par l'utilisateur et lui attribuait
    automatiquement `id_user = request.user` — ce qui permettait à
    n'importe quel client de "s'approprier" n'importe quel numéro de
    contrat en le saisissant, sans aucune vérification, et fabriquait des
    doublons de contrats qui n'existent pas réellement chez Eneo.

    Nouveau comportement :
      1. On recherche le contrat par `numero_contrat` (déjà en base).
      2. S'il n'existe pas -> erreur explicite (rien n'est créé).
      3. S'il existe mais que `Contrats.id_user` ne correspond PAS au
         client connecté -> refus (le contrat appartient à quelqu'un
         d'autre) ; le message reste neutre pour ne pas divulguer
         l'existence/la titularité réelle du contrat à un tiers non
         autorisé.
      4. S'il existe ET que `Contrats.id_user` correspond au client
         connecté -> on renvoie simplement le contrat existant (200), sans
         rien créer ni modifier : il devient visible dans "Mes contrats".
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = ContratsSerializer

    pagination_class = StandardResultsSetPagination

    def get_queryset(self):
        """
        REFONTE — page d'accueil : les 3 contrats les plus récents sont
        affichés par défaut (tri `-date_creation`), et un client avec plus
        de 3 contrats recherche un numéro précis via `?search=`. La
        recherche reste bornée aux contrats du client connecté (pas de
        fuite vers les contrats d'un autre utilisateur) et fonctionne par
        correspondance partielle insensible à la casse sur
        `numero_contrat`.

        CORRECTIF (audit lenteur accueil) : `nombre_compteurs` est calculé
        ici via une annotation SQL (`Count` + `GROUP BY`), en UNE seule
        requête pour l'ensemble des contrats. Avant ce correctif, le
        client Flutter recalculait cette valeur en appelant
        `GET /contrats/<id>/compteurs/` une fois PAR contrat (jusqu'à 250
        requêtes HTTP séquentielles rien que pour afficher les 3 premiers
        contrats de l'accueil, ~74s de chargement). Exposer directement
        `nombre_compteurs` dans `GET /contrats/` élimine ce N+1 orchestré
        côté client à la racine.
        """
        qs = (
            Contrats.objects.filter(id_user=self.request.user)
            .annotate(nombre_compteurs=Count('compteurs'))
            .order_by('-date_creation')
        )
        recherche = (self.request.query_params.get('search') or '').strip()
        if recherche:
            qs = qs.filter(numero_contrat__icontains=recherche)
        return qs

    def create(self, request, *args, **kwargs):
        numero_contrat = (request.data.get("numero_contrat") or "").strip()
        if not numero_contrat:
            raise ValidationError({"numero_contrat": "Ce champ est requis."})

        contrat = Contrats.objects.filter(numero_contrat=numero_contrat).first()
        if contrat is None:
            raise ValidationError({
                "numero_contrat": "Aucun contrat Eneo ne correspond à ce numéro."
            })

        if contrat.id_user_id != request.user.id_user:
            # Message volontairement neutre : on ne confirme jamais si le
            # numéro existe mais appartient à un autre client (évite de
            # divulguer l'existence/la titularité d'un contrat à un tiers).
            raise ValidationError({
                "numero_contrat": "Ce numéro de contrat n'est associé à aucun compte correspondant au vôtre."
            })

        serializer = self.get_serializer(contrat)
        return Response(serializer.data, status=status.HTTP_200_OK)


class ContratDetailView(generics.RetrieveAPIView):
    """
    Détail d'un contrat (numéro, statut, date de création) — lecture seule :
    la résiliation d'un contrat est une décision commerciale qui sort du
    périmètre client (cf. TransferCompteurView pour la réaffectation d'un
    compteur, réservée à un compte technicien).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = ContratsSerializer
    lookup_field = "id_contrat"

    def get_queryset(self):
        return Contrats.objects.filter(id_user=self.request.user)


class ContratCompteursListView(generics.ListAPIView):
    """Liste des compteurs rattachés à un contrat donné (RG : un contrat
    peut avoir un ou plusieurs compteurs)."""
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = CompteursSerializer

    def get_queryset(self):
        id_contrat = self.kwargs["id_contrat"]
        if not user_owns_contrat(self.request.user, id_contrat) and not (
            GestionCompteurs.objects.filter(
                id_user=self.request.user, id_contrat=id_contrat, statut="Actif",
            ).exists()
        ):
            raise PermissionDenied("Vous n'avez pas accès à ce contrat.")
        return Compteurs.objects.filter(id_contrat=id_contrat)


class CompteurListCreateView(generics.ListCreateAPIView):
    """
    Liste les compteurs accessibles à l'utilisateur (titulaire du contrat +
    délégations actives, RG-01/RG-02) et permet le rattachement d'un
    nouveau compteur à l'un de ses contrats.

    REFONTE v1.5 : le compteur n'est plus créé "flottant" avec une
    délégation `Gestionnaire` auto-générée — il DOIT être rattaché à un
    `id_contrat` explicite dans le payload, et ce contrat doit appartenir à
    l'utilisateur courant (on ne peut pas rattacher un compteur au contrat
    de quelqu'un d'autre depuis cet endpoint client).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = CompteursSerializer
    pagination_class = StandardResultsSetPagination

    def get_queryset(self):
        ids = get_delegated_compteur_ids(self.request.user)
        return Compteurs.objects.filter(id_compteur__in=ids)

    def perform_create(self, serializer):
        contrat = serializer.validated_data.get("id_contrat")
        if contrat is None:
            raise ValidationError({"id_contrat": "Requis : un compteur doit être rattaché à un contrat."})
        if not user_owns_contrat(self.request.user, contrat.id_contrat):
            raise PermissionDenied("Vous ne pouvez rattacher un compteur qu'à l'un de vos propres contrats.")
        serializer.save(date_creation=timezone.now(), statut="Actif")


class CompteurDetailView(generics.RetrieveUpdateDestroyAPIView):
    """
    Détail d'un compteur.

    REFONTE v1.5 — CHANGEMENT DE SÉMANTIQUE DU "RETRAIT" : la propriété
    n'étant plus portée par une ligne GestionCompteurs mais par
    CONTRATS.id_user, un titulaire ne peut plus "se retirer" lui-même de son
    propre compteur via un simple DELETE (ça n'aurait pas de sens : il
    resterait titulaire du contrat qui le contient). Ce endpoint ne permet
    donc plus qu'à un TIERS délégataire de renoncer à son propre accès
    (auto-révocation de sa délégation, portée compteur ou contrat) ; le
    titulaire reçoit un 403 explicite l'invitant à passer par la gestion de
    contrat (résiliation, transfert — hors périmètre client).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = CompteursSerializer
    lookup_field = "id_compteur"

    def get_queryset(self):
        ids = get_delegated_compteur_ids(self.request.user)
        return Compteurs.objects.filter(id_compteur__in=ids)

    def destroy(self, request, *args, **kwargs):
        compteur = self.get_object()

        if user_owns_contrat(request.user, compteur.id_contrat_id):
            raise PermissionDenied(
                "Vous êtes titulaire du contrat de ce compteur : il ne peut pas être "
                "'retiré' individuellement. Contactez le support pour une résiliation "
                "ou un transfert de contrat."
            )

        # Le requérant est un tiers délégataire : on révoque SA délégation,
        # qu'elle porte directement sur ce compteur ou sur tout le contrat.
        revoques = GestionCompteurs.objects.filter(
            id_user=request.user, statut="Actif",
        ).filter(
            models_q_compteur_ou_contrat(compteur)
        ).update(statut="Révoqué", date_revocation=timezone.now())

        if not revoques:
            raise PermissionDenied("Aucune délégation active à révoquer sur ce compteur.")
        return Response(status=status.HTTP_204_NO_CONTENT)


def models_q_compteur_ou_contrat(compteur):
    """Petit utilitaire : construit le Q() '(id_compteur = X) OR (id_contrat = contrat de X)'
    réutilisé par CompteurDetailView.destroy et AlerteTechniqueCompteurView."""
    return Q(id_compteur=compteur) | Q(id_contrat_id=compteur.id_contrat_id)


class GestionCompteursView(generics.ListCreateAPIView):
    """
    Délégation de droits à un tiers (bailleur/locataire, tiers autorisé,
    entreprise/collaborateur — CDC 4.1, RG-02 étendu).
    type_droit ∈ {Lecture, Paiement, Lecture_Paiement}.

    REFONTE v1.5 — DEUX PORTÉES POSSIBLES, exclusives (imposées par la
    contrainte CHECK SQL et par `GestionCompteursSerializer.validate`) :
      - `id_compteur` renseigné : délégation sur CE compteur uniquement ;
      - `id_contrat` renseigné : délégation sur TOUS les compteurs de ce
        contrat, actuels ET futurs.

    Seul le TITULAIRE du contrat concerné (directement, ou via le contrat
    du compteur ciblé) peut accorder une délégation — un délégataire, même
    avec le droit 'Paiement', ne peut jamais lui-même déléguer à un tiers.
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = GestionCompteursSerializer

    def get_queryset(self):
        return GestionCompteurs.objects.filter(id_user=self.request.user)

    def perform_create(self, serializer):
        compteur = serializer.validated_data.get("id_compteur")
        contrat = serializer.validated_data.get("id_contrat")

        id_contrat_cible = contrat.id_contrat if contrat else compteur.id_contrat_id
        if not user_owns_contrat(self.request.user, id_contrat_cible):
            raise PermissionDenied(
                "Seul le titulaire du contrat peut déléguer l'accès à un compteur "
                "ou à l'ensemble de son contrat."
            )
        serializer.save(date_octroi=timezone.now(), statut="Actif")


class RevokeDelegationView(APIView):
    """
    Révocation d'une délégation (CDC 5.5 : le titulaire peut révoquer
    l'accès d'un tiers à tout moment).
    On ne supprime pas la ligne (traçabilité) : on horodate `date_revocation`
    et on bascule `statut` à "Révoqué".
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, id_delegation):
        delegation = get_object_or_404(GestionCompteurs, pk=id_delegation)
        id_contrat_cible = delegation.id_contrat_id or delegation.id_compteur.id_contrat_id
        if not user_owns_contrat(request.user, id_contrat_cible):
            raise PermissionDenied("Seul le titulaire du contrat concerné peut révoquer cette délégation.")

        delegation.statut = "Révoqué"
        delegation.date_revocation = timezone.now()
        delegation.save(update_fields=["statut", "date_revocation"])
        return Response({"detail": "Délégation révoquée."})


class TransferCompteurView(APIView):
    """
    Transfert d'un compteur vers un AUTRE CONTRAT (résiliation, vente,
    correction d'un rattachement erroné).
    RG-03 : ne peut être exécuté QUE par un compte technicien API — jamais
    directement par un client. Toute exécution est journalisée (audit).

    REFONTE v1.5 : auparavant ce endpoint ne renommait que le champ texte
    libre `proprietaire_legal` et révoquait les délégations 'Gestionnaire' —
    un artefact de l'ancien modèle où la propriété vivait dans
    GestionCompteurs. Il réaffecte maintenant réellement `id_contrat`, ce
    qui déplace mécaniquement le compteur dans le graphe de propriété
    (les délégations à portée contrat de l'ANCIEN contrat cessent de
    s'appliquer automatiquement ; celles à portée compteur restent valides
    quel que soit le contrat, ce qui est le comportement voulu).
    """
    permission_classes = [IsAdminTechnicien]

    @transaction.atomic
    def post(self, request, id_compteur):
        compteur = get_object_or_404(Compteurs, pk=id_compteur)
        id_nouveau_contrat = request.data.get("nouveau_id_contrat")
        nouveau_proprietaire_legal = request.data.get("nouveau_proprietaire_legal")
        motif = request.data.get("motif", "")
        if not id_nouveau_contrat:
            raise ValidationError({"nouveau_id_contrat": "Requis : le compteur doit être transféré vers un contrat existant."})

        nouveau_contrat = get_object_or_404(Contrats, pk=id_nouveau_contrat)
        ancien_contrat = compteur.id_contrat

        compteur.id_contrat = nouveau_contrat
        champs_modifies = ["id_contrat"]
        if nouveau_proprietaire_legal:
            compteur.proprietaire_legal = nouveau_proprietaire_legal
            champs_modifies.append("proprietaire_legal")
        compteur.save(update_fields=champs_modifies)

        log_audit(
            auteur=request.user,
            action="TRANSFERT_COMPTEUR",
            objet_touche=f"Compteur {compteur.numero_compteur}",
            motif=f"{motif} (ancien contrat : {ancien_contrat.numero_contrat} -> nouveau : {nouveau_contrat.numero_contrat})",
            request=request,
        )
        return Response(CompteursSerializer(compteur).data)


class AgentTerrainCompteurRegisterView(generics.CreateAPIView):
    """
    Enregistrement initial d'un nouveau compteur par un agent terrain Eneo,
    avec l'accord du client, lors d'une intervention (pose, remplacement) —
    CDC 4.1 / 5.5. L'agent n'obtient PAS de droit de paiement ou de gestion
    (cf. matrice des droits 4.4 : "Enregistrement initial uniquement").

    REFONTE v1.5 — CORRECTIF : la version précédente accordait par erreur
    une délégation `Gestionnaire` à L'AGENT lui-même (`self.request.user`),
    contredisant frontalement son propre commentaire ("l'agent n'obtient
    pas de droit de gestion"). L'agent doit désormais désigner explicitement
    le `id_contrat` du CLIENT auquel rattacher le compteur ; aucune
    délégation n'est créée pour l'agent.
    """
    permission_classes = [IsAgentTerrain]
    serializer_class = CompteursSerializer

    def perform_create(self, serializer):
        contrat = serializer.validated_data.get("id_contrat")
        if contrat is None:
            raise ValidationError({"id_contrat": "Requis : le contrat client auquel rattacher ce compteur."})
        compteur = serializer.save(date_creation=timezone.now(), statut="Actif")
        log_audit(
            auteur=self.request.user,
            action="ENREGISTREMENT_COMPTEUR_AGENT_TERRAIN",
            objet_touche=f"Compteur {compteur.numero_compteur} (contrat {contrat.numero_contrat})",
            request=self.request,
        )


# MODULE 3 — CLIENT POSTPAYÉ (CDC 5.2)
# ==============================================================================

def _debut_fenetre_douze_mois(reference):
    """Premier jour du mois, 12 mois avant `reference` — pure arithmétique de
    calendrier (pas de dépendance dateutil) : sert de borne pour la fenêtre
    "12 derniers mois" par défaut, calculée UNE FOIS pour tous les compteurs
    d'un contrat plutôt que par un `[:12]` par compteur (qui donnerait un
    nombre de factures variable et peu prévisible dès qu'un contrat a
    plusieurs compteurs).
    """
    annee, mois = reference.year, reference.month - 12
    while mois <= 0:
        mois += 12
        annee -= 1
    return reference.replace(year=annee, month=mois, day=1)


class ContratFacturesListView(generics.ListAPIView):
    """
    REFONTE v1.5 — Factures agrégées au niveau du CONTRAT, tous compteurs
    postpayés confondus (le compteur n'étant plus le pivot, un client avec
    plusieurs compteurs sur un même contrat veut voir ses factures
    consolidées, pas compteur par compteur).

    Filtres disponibles (tous optionnels, cumulables) :
      - `?statut=Payée` | `En_cours` | `Impayée` — statut exact (CDC 5.2).
        ⚠️ Ces valeurs doivent correspondre EXACTEMENT aux libellés de
        l'ENUM PostgreSQL `enum_statut_facture` (axel.sql :
        'Impayée', 'En_cours', 'Payée') — un `En cours` avec un espace au
        lieu d'un underscore passe la validation Python ci-dessous mais
        provoque un DataError PostgreSQL non catché (500) au moment du
        `.filter()`, puisque Postgres n'accepte que le littéral exact de
        l'ENUM (bug corrigé le 21/07/2026, cf. CHANGELOG_OPTIMISATIONS.md).
      - `?id_compteur=123` — restreint à un seul compteur du contrat.
      - `?historique_complet=true` — sinon, uniquement les 12 derniers mois
        (RG-14, même politique que FacturesListView, mais calculée sur une
        fenêtre de dates commune à tous les compteurs plutôt qu'un simple
        `[:12]` par compteur).

    Accès : la liste ne contient que les factures des compteurs du contrat
    RÉELLEMENT accessibles à l'utilisateur (titulaire, délégataire du
    contrat entier, ou délégataire d'un seul compteur de ce contrat) — pas
    un accès "tout ou rien" au contrat. Un compteur du contrat auquel
    l'utilisateur n'a aucun droit n'apparaît simplement pas dans la liste.
    Si AUCUN compteur du contrat n'est accessible, la liste renvoyée est
    vide (200), comme `ContratCompteursListView` — pas un 403 : l'absence
    totale de résultat n'est qu'un cas particulier de ce filtrage, pas une
    tentative d'accès à refuser. Seul un `?id_compteur=` explicite pointant
    vers un compteur non accessible lève un 403 (tentative précise, pas une
    simple absence de résultat).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = FacturesPostpayeesSerializer
    pagination_class = StandardResultsSetPagination

    def get_queryset(self):
        id_contrat = self.kwargs["id_contrat"]
        contrat = get_object_or_404(Contrats, pk=id_contrat)

        ids_accessibles = get_delegated_compteur_ids(self.request.user)
        ids_du_contrat = set(
            Compteurs.objects.filter(id_contrat=contrat.id_contrat).values_list("id_compteur", flat=True)
        )
        ids_visibles = ids_du_contrat & ids_accessibles
        # COHÉRENCE AVEC ContratCompteursListView : un contrat sans compteur
        # accessible à l'utilisateur courant renvoie une liste vide, pas un
        # 403. Le 403 est réservé au cas ci-dessous (id_compteur explicite
        # ET non accessible) — c'est-à-dire une tentative d'accès précise
        # à quelque chose qui existe mais n'appartient pas à l'utilisateur,
        # pas la simple absence de résultat.
        if not ids_visibles:
            return FacturesPostpayees.objects.none()

        id_compteur_filtre = self.request.query_params.get("id_compteur")
        if id_compteur_filtre:
            try:
                id_compteur_filtre = int(id_compteur_filtre)
            except ValueError:
                raise ValidationError({"id_compteur": "Doit être un entier."})
            if id_compteur_filtre not in ids_visibles:
                raise PermissionDenied("Ce compteur n'est pas accessible sur ce contrat.")
            ids_visibles = {id_compteur_filtre}

        qs = FacturesPostpayees.objects.filter(id_compteur_id__in=ids_visibles)

        statut = self.request.query_params.get("statut")
        if statut:
            if statut not in ("Payée", "En_cours", "Impayée"):
                raise ValidationError({"statut": "Doit être l'une des valeurs : Payée, En_cours, Impayée."})
            qs = qs.filter(statut=statut)

        historique_complet = self.request.query_params.get("historique_complet") == "true"
        if not historique_complet:
            qs = qs.filter(mois_facturation__gte=_debut_fenetre_douze_mois(timezone.now().date()))

        return qs.order_by("-mois_facturation", "id_compteur_id")


class FacturesListView(generics.ListAPIView):
    """
    Historique des factures d'un compteur postpayé.
    - Par défaut : les 12 dernières factures (CDC 5.2).
    - Sur demande explicite (`?historique_complet=true`), renvoie l'ensemble
      des factures (y compris > 12 mois), en cohérence avec la stratégie
      d'archivage RG-14 (les données archivées peuvent nécessiter une requête
      complémentaire vers `HistoriqueArchive`, non couverte ici).
    - Si aucune facture n'existe pour un compteur nouvellement enregistré,
      la liste renvoyée est simplement vide → le front affiche l'écran
      "aucune facture disponible".
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = FacturesPostpayeesSerializer
    pagination_class = StandardResultsSetPagination

    def get_queryset(self):
        id_compteur = self.kwargs["id_compteur"]
        if not user_has_access_to_compteur(self.request.user, id_compteur):
            raise PermissionDenied("Accès non autorisé à ce compteur.")

        qs = FacturesPostpayees.objects.filter(id_compteur_id=id_compteur).order_by("-mois_facturation")
        historique_complet = self.request.query_params.get("historique_complet") == "true"
        return qs if historique_complet else qs[:12]


class FactureDetailView(generics.RetrieveAPIView):
    """Détail d'une facture (montant, statut Impayée/En_cours/Payée, index conso...)."""
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = FacturesPostpayeesSerializer
    lookup_field = "id_facture"

    def get_queryset(self):
        ids_accessibles = get_delegated_compteur_ids(self.request.user)
        return FacturesPostpayees.objects.filter(id_compteur_id__in=ids_accessibles)


class FactureReçuPDFView(APIView):
    """
    Téléchargement du reçu de paiement associé à une facture, au format PDF
    (CDC 5.2 / 9.3). Les données brutes du reçu sont archivées en JSON dans
    `Paiements.donnees_recu_json` ; le PDF est régénéré à la demande plutôt
    que stocké de façon permanente (économie de stockage, CDC 9.3).
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, id_facture):
        facture = get_object_or_404(FacturesPostpayees, pk=id_facture)
        if not user_has_access_to_compteur(request.user, facture.id_compteur_id):
            raise PermissionDenied("Accès non autorisé.")

        paiement = Paiements.objects.filter(reference_cible=id_facture, statut="Confirmé").first()
        if not paiement or not paiement.donnees_recu_json:
            raise ValidationError({"detail": "Aucun reçu disponible pour cette facture."})

        # TODO INTEGRATION : générer le PDF à partir de `donnees_recu_json`
        # (ex: WeasyPrint, ReportLab) et le retourner en FileResponse.
        return Response({
            "detail": "Génération PDF à brancher (WeasyPrint/ReportLab).",
            "donnees_recu": paiement.donnees_recu_json,
        })


class ConsommationGraphView(APIView):
    """
    Graphique d'évolution de la consommation, exprimé simultanément en kWh
    et en FCFA (CDC 5.2), sur la base des factures (postpayé) et/ou des
    transactions de recharge (prépayé) selon le type de compteur.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, id_compteur):
        if not user_has_access_to_compteur(request.user, id_compteur):
            raise PermissionDenied("Accès non autorisé à ce compteur.")

        compteur = get_object_or_404(Compteurs, pk=id_compteur)

        if compteur.type_compteur == "POSTPAYE":
            factures = FacturesPostpayees.objects.filter(
                id_compteur_id=id_compteur
            ).order_by("mois_facturation")
            serie = [
                {
                    "periode": f.mois_facturation,
                    "kwh": f.index_consommation,
                    "fcfa": f.montant_fcfa,
                }
                for f in factures
            ]
        else:
            # Compteur prépayé : pas de "facture" à proprement parler — la
            # série est construite à partir des recharges confirmées.
            # Auparavant cette branche n'existait pas du tout : la vue
            # renvoyait toujours une série vide pour un compteur prépayé,
            # malgré ce que son propre docstring annonçait.
            recharges = TransactionsPrepayees.objects.filter(
                id_compteur_id=id_compteur, statut_paiement="Réussie",
            ).order_by("date_transaction")
            serie = [
                {
                    "periode": tx.date_transaction.date(),
                    "kwh": tx.valeur_kwh,
                    "fcfa": tx.montant_fcfa,
                }
                for tx in recharges
            ]
        return Response({"id_compteur": id_compteur, "serie": serie})


class SignalerAnomalieFactureView(APIView):
    """
    Signalement d'une anomalie sur une facture, avec routage automatique vers
    le support technique (CDC 5.2). Crée un litige de Niveau 1 (diagnostic).
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, id_facture):
        facture = get_object_or_404(FacturesPostpayees, pk=id_facture)
        if not user_has_access_to_compteur(request.user, facture.id_compteur_id):
            raise PermissionDenied("Accès non autorisé à cette facture.")

        description = request.data.get("description", "")

        litige = Litiges.objects.create(
            id_litige=f"LIT-{secrets.token_hex(8).upper()}",
            niveau="1",
            statut="Ouvert",
            description=description or "Anomalie signalée sur facture.",
            id_user=request.user,
            id_paiement=Paiements.objects.filter(reference_cible=id_facture).first(),  # peut être None
            date_ouverture=timezone.now(),
        )

        return Response(LitigesSerializer(litige).data, status=status.HTTP_201_CREATED)

class FactureStatutView(APIView):
    """
    Statut détaillé d'une facture, y compris le cas particulier
    "Compteur suspendu" lorsqu'Eneo signale une coupure pour impayé
    (CDC 5.2). Gère également le recalcul suite à une facture rectificative
    (CDC 5.2 : bascule vers un crédit client si le montant initial était
    surévalué).
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, id_facture):
        facture = get_object_or_404(FacturesPostpayees, pk=id_facture)
        compteur = facture.id_compteur
        # Faille corrigée : aucune vérification d'accès n'existait ici,
        # contrairement aux autres vues du même module.
        if not user_has_access_to_compteur(request.user, compteur.id_compteur):
            raise PermissionDenied("Accès non autorisé à cette facture.")

        payload = FacturesPostpayeesSerializer(facture).data
        payload["compteur_suspendu"] = (compteur.statut == "Suspendu")

        if facture.facture_rectificative_de_id:
            originale = facture.facture_rectificative_de
            ecart = originale.montant_fcfa - facture.montant_fcfa
            payload["rectificatif"] = {
                "facture_originale": originale.id_facture,
                "ecart_fcfa": ecart,
                "credit_client_genere": ecart > 0,
            }
        return Response(payload)


# ==============================================================================
# MODULE 4 — CLIENT PRÉPAYÉ (CDC 5.3)
# ==============================================================================

def _consommation_estimee_kwh(transactions, total_kwh_achete):
    """
    Retourne (consommation_journaliere_simulee, consommation_estimee).
    `transactions` doit être trié par date_transaction croissante.

    CORRECTIF (audit du 24/07/2026) : aucune table de relevés de
    consommation réelle n'existe encore pour les compteurs prépayés (la
    synchronisation IoT/API Eneo reste un TODO INTEGRATION — cf. §2.6 du
    CDC, stratégie de repli). En son absence, on applique un MODÈLE DE
    CONSOMMATION SIMULÉ, explicitement documenté comme donnée de test :
    on suppose que l'utilisateur recharge à peu près au rythme de sa
    consommation réelle, donc que sa consommation journalière moyenne
    correspond au total acheté divisé par le nombre de jours écoulés
    depuis sa première recharge. Dès qu'un historique de consommation
    réelle existera en base, cette fonction devra être remplacée par une
    lecture de cette table — le reste (soustraction, jours d'autonomie,
    FCFA, seuil d'alerte) n'aura pas à changer, cf. `_calculer_solde_prepaye`
    ci-dessous, partagée par `SoldeCreditView` et `AlerteSoldeBasView`.
    """
    premiere_transaction = transactions.first()
    if not premiere_transaction or not total_kwh_achete:
        return 0.0, 0.0

    jours_ecoules = max(
        (timezone.now() - premiere_transaction.date_transaction).days, 1
    )
    consommation_journaliere_simulee = float(total_kwh_achete) / jours_ecoules
    consommation_estimee = consommation_journaliere_simulee * jours_ecoules
    # Le modèle simulé suppose un usage régulier calé sur les recharges :
    # on plafonne au total acheté pour ne jamais faire ressortir un solde
    # négatif du simple fait d'un arrondi.
    consommation_estimee = min(consommation_estimee, float(total_kwh_achete))
    return consommation_journaliere_simulee, consommation_estimee


def _calculer_solde_prepaye(id_compteur):
    """
    Calcule le solde de crédit prépayé d'un compteur (kWh + FCFA), l'autonomie
    estimée en jours et le prix du kWh utilisé pour la conversion.

    Factorisé depuis `SoldeCreditView` (correctif du 24/07/2026) pour être
    également consommé par `AlerteSoldeBasView`, qui avant ce correctif
    renvoyait toujours `solde_bas: None` / `jours_autonomie_estimes: None`
    sans le moindre calcul — alors même que la logique existait déjà ici.

    Renvoie un dict directement réutilisable comme corps de réponse (ou
    fragment de corps de réponse) par les deux vues.
    """
    compteur = get_object_or_404(Compteurs, pk=id_compteur)

    transactions = TransactionsPrepayees.objects.filter(
        id_compteur_id=id_compteur, statut_paiement="Réussie",
    ).order_by("date_transaction")
    total_kwh_achete = transactions.aggregate(total=Sum("valeur_kwh"))["total"] or 0

    consommation_journaliere_simulee, consommation_estimee = _consommation_estimee_kwh(
        transactions, total_kwh_achete
    )
    solde_kwh = round(float(total_kwh_achete) - consommation_estimee, 2)

    # "Jours d'autonomie estimés" : au rythme de consommation simulé
    # ci-dessus, combien de jours le solde restant doit-il durer ? Sans
    # aucune recharge (compteur neuf), il n'y a aucune base pour
    # l'estimer -> None plutôt qu'une valeur inventée.
    if consommation_journaliere_simulee > 0:
        jours_autonomie_estimes = round(solde_kwh / consommation_journaliere_simulee, 1)
    else:
        jours_autonomie_estimes = None

    # Conversion en FCFA : on utilise le tarif en vigueur pour le type de
    # ce compteur (même source que AchatCreditView) ; à défaut, on
    # retombe sur le prix appliqué à la dernière recharge connue plutôt
    # que de renvoyer un FCFA vide alors qu'on a un solde en kWh.
    tarif_courant = Tarifs.objects.filter(
        type_compteur=compteur.type_compteur, date_fin__isnull=True,
    ).order_by("-date_debut").first()
    derniere_transaction = transactions.last()
    prix_kwh = (
        tarif_courant.prix_kwh if tarif_courant
        else (derniere_transaction.prix_kwh_applique if derniere_transaction else None)
    )
    solde_fcfa = round(solde_kwh * float(prix_kwh), 2) if prix_kwh is not None else None

    return {
        "solde_kwh_achete_total": total_kwh_achete,
        "solde_kwh": solde_kwh,
        "solde_fcfa": solde_fcfa,
        "jours_autonomie_estimes": jours_autonomie_estimes,
        "prix_kwh": float(prix_kwh) if prix_kwh is not None else None,
    }


class SoldeCreditView(APIView):
    """
    Solde de crédit prépayé, affiché simultanément en kWh et en FCFA,
    actualisé à l'ouverture de l'application (CDC 5.3).
    Calculé comme la somme des recharges confirmées moins la consommation
    depuis la première recharge — cf. `_calculer_solde_prepaye` pour le
    détail du calcul (modèle de consommation simulé, donnée de test).
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, id_compteur):
        if not user_has_access_to_compteur(request.user, id_compteur):
            raise PermissionDenied("Accès non autorisé à ce compteur.")

        solde = _calculer_solde_prepaye(id_compteur)

        return Response({
            "id_compteur": id_compteur,
            "solde_kwh_achete_total": solde["solde_kwh_achete_total"],
            "solde_kwh": solde["solde_kwh"],
            "solde_fcfa": solde["solde_fcfa"],
            "jours_autonomie_estimes": solde["jours_autonomie_estimes"],
            # Signale explicitement au client que la consommation utilisée
            # est simulée (donnée de test) tant que la synchro IoT/API Eneo
            # n'est pas branchée — évite d'afficher un chiffre simulé comme
            # s'il s'agissait d'un relevé réel.
            "consommation_estimee_simulee": True,
            "derniere_synchronisation": timezone.now(),
        })


class AchatCreditView(APIView):
    """
    Initiation d'un achat de crédit prépayé (CDC 5.3).
    - Montant encadré par un plancher/plafond (politique tarifaire Eneo).
    - Conversion FCFA → kWh figée au tarif en vigueur à la date de la
      transaction (RG-07) — jamais recalculée rétroactivement.
    - Cette vue crée la transaction en base ; la génération du jeton et la
      confirmation du paiement sont finalisées via `InitierPaiementView` /
      `WebhookPaiementView` (module 5), suite à la validation Mobile Money.
    """
    permission_classes = [permissions.IsAuthenticated]

    MONTANT_MIN_FCFA = 500     # TODO : externaliser en configuration (politique Eneo)
    MONTANT_MAX_FCFA = 500000  # TODO : externaliser en configuration (politique Eneo)

    @transaction.atomic
    def post(self, request, id_compteur):
        if not user_has_access_to_compteur(request.user, id_compteur):
            raise PermissionDenied("Accès non autorisé à ce compteur.")

        montant = request.data.get("montant_fcfa")
        if montant is None:
            raise ValidationError({"montant_fcfa": "Requis."})
        montant = float(montant)
        if not (self.MONTANT_MIN_FCFA <= montant <= self.MONTANT_MAX_FCFA):
            raise ValidationError({
                "montant_fcfa": f"Doit être compris entre {self.MONTANT_MIN_FCFA} et {self.MONTANT_MAX_FCFA} FCFA."
            })

        # `select_for_update()` verrouille la ligne compteur pour la durée de
        # la transaction DB : deux achats simultanés sur le même compteur
        # s'exécutent désormais en série au niveau base de données. Ce n'est
        # pas le verrou distribué Redis prévu par la CDC (7.3) — utile
        # notamment en environnement multi-instance — mais une protection
        # anti-double-dépense réelle en attendant ce câblage, plutôt
        # qu'aucune protection du tout.
        compteur = get_object_or_404(Compteurs.objects.select_for_update(), pk=id_compteur)
        tarif_courant = Tarifs.objects.filter(
            type_compteur=compteur.type_compteur, date_fin__isnull=True,
        ).order_by("-date_debut").first()
        if not tarif_courant:
            raise ValidationError({"detail": "Aucun tarif en vigueur pour ce type de compteur."})

        valeur_kwh = round(montant / float(tarif_courant.prix_kwh), 3)

        # CORRECTIF : id_transaction est la clé primaire (CharField, non
        # auto-incrémentée) et n'était jamais fournie ici, ce qui insérait
        # une chaîne vide '' à chaque achat -> IntegrityError (clé dupliquée)
        # dès le 2e achat. Génération explicite, même pattern que id_paiement
        # / id_litige ailleurs dans ce fichier ("TRP-" + 16 car. hex = 20
        # car., dans la limite max_length=25 de la colonne).
        transaction_obj = TransactionsPrepayees.objects.create(
            id_transaction=f"TRP-{secrets.token_hex(8).upper()}",
            montant_fcfa=montant,
            prix_kwh_applique=tarif_courant.prix_kwh,  # figé (RG-07)
            valeur_kwh=valeur_kwh,
            statut_paiement="Initiée",  # transaction créée, en attente de confirmation paiement
            date_transaction=timezone.now(),
            id_compteur=compteur,
        )
        return Response(
            TransactionsPrepayeesSerializer(transaction_obj).data,
            status=status.HTTP_201_CREATED,
        )


class TokenHistoriqueView(generics.ListAPIView):
    """
    Historique des recharges, permettant de ré-afficher un ancien jeton déjà
    utilisé, à titre de justificatif uniquement (CDC 5.3). Lecture seule :
    `TransactionsPrepayees` est Append-Only hors `statut_paiement`/`token_genere`
    (RG-12).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = TransactionsPrepayeesSerializer
    pagination_class = StandardResultsSetPagination

    def get_queryset(self):
        id_compteur = self.kwargs["id_compteur"]
        if not user_has_access_to_compteur(self.request.user, id_compteur):
            raise PermissionDenied("Accès non autorisé à ce compteur.")
        return TransactionsPrepayees.objects.filter(id_compteur_id=id_compteur).order_by("-date_transaction")


class AlerteSoldeBasView(APIView):
    """
    Alerte proactive de solde bas selon un seuil paramétrable, avec
    estimation du nombre de jours d'autonomie restants basée sur
    l'historique de consommation de l'utilisateur (CDC 5.3).

    CORRECTIF (finalisation module prépayé) : cette vue renvoyait
    systématiquement `solde_bas: None` / `jours_autonomie_estimes: None`,
    alors que `_calculer_solde_prepaye` (partagée avec `SoldeCreditView`,
    cf. correctif du 24/07/2026) permet de les déduire directement — il ne
    manquait que la comparaison au seuil. Le solde utilisé reste le MODÈLE
    DE CONSOMMATION SIMULÉ documenté sur `_consommation_estimee_kwh` tant
    que la synchronisation IoT/API Eneo (donnée de consommation réelle)
    n'est pas branchée — cf. §2.6 du CDC.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, id_compteur):
        if not user_has_access_to_compteur(request.user, id_compteur):
            raise PermissionDenied("Accès non autorisé à ce compteur.")

        seuil_kwh = float(request.query_params.get("seuil_kwh", 5))
        solde = _calculer_solde_prepaye(id_compteur)
        solde_kwh = solde["solde_kwh"]

        return Response({
            "id_compteur": id_compteur,
            "seuil_kwh": seuil_kwh,
            "solde_kwh": solde_kwh,
            "solde_bas": solde_kwh <= seuil_kwh,
            "jours_autonomie_estimes": solde["jours_autonomie_estimes"],
            # cf. `SoldeCreditView` : même mise en garde sur la nature
            # simulée de la consommation utilisée pour ce calcul.
            "consommation_estimee_simulee": True,
        })

    def post(self, request, id_compteur):
        """Permet à l'utilisateur de paramétrer son propre seuil d'alerte."""
        if not user_has_access_to_compteur(request.user, id_compteur):
            raise PermissionDenied("Accès non autorisé à ce compteur.")

        nouveau_seuil = request.data.get("seuil_kwh")
        if nouveau_seuil is None:
            raise ValidationError({"seuil_kwh": "Requis."})
        # TODO INTEGRATION : persister le seuil (table préférences dédiée).
        return Response({"id_compteur": id_compteur, "seuil_kwh": nouveau_seuil})


class AlerteTechniqueCompteurView(APIView):
    """
    Relais des alertes techniques transmises par le compteur intelligent
    (anomalie de consommation, coupure) vers l'utilisateur (CDC 5.3).
    Ce endpoint est typiquement appelé par le service d'intégration IoT/API
    Eneo (via un compte technique — RG-05), pas directement par le client.
    """
    permission_classes = [IsCompteTechnique]

    def post(self, request, id_compteur):
        compteur = get_object_or_404(Compteurs, pk=id_compteur)
        type_alerte = request.data.get("type_alerte")  # ex: "ANOMALIE", "COUPURE"
        message = request.data.get("message", "")

        # REFONTE v1.5 : la propriété n'étant plus une ligne GestionCompteurs
        # de type 'Gestionnaire', on notifie explicitement (a) le titulaire
        # du contrat auquel appartient ce compteur, ET (b) tout délégataire
        # actif, que sa délégation porte directement sur ce compteur ou sur
        # le contrat entier.
        ids_beneficiaires = set(
            Contrats.objects.filter(id_contrat=compteur.id_contrat_id).values_list("id_user", flat=True)
        )
        ids_beneficiaires |= set(
            GestionCompteurs.objects.filter(statut="Actif")
            .filter(models_q_compteur_ou_contrat(compteur))
            .values_list("id_user", flat=True)
        )

        # OPTIMISATION (audit §4.1) : un seul bulk_create plutôt qu'un
        # Notifications.objects.create() par bénéficiaire dans une boucle.
        notifications = [
            Notifications(
                canal="Push",  # cascade réelle gérée par le worker asynchrone (module 6)
                niveau_criticite="Critique",
                objet=f"Alerte compteur {compteur.numero_compteur}",
                contenu=message or f"Alerte technique : {type_alerte}",
                # ⚠️ `enum_statut_notif` ne contient que 'Envoyé', 'Échoué',
                # 'Lu' — pas de valeur "en attente d'envoi". Django envoyant
                # toujours la colonne dans l'INSERT (même logique que le bug
                # rencontré sur RegisterView), il FAUT fixer une valeur
                # explicite plutôt que de compter sur un DEFAULT SQL. On
                # utilise 'Envoyé' au sens "mis en file pour le worker
                # asynchrone" ; si vous voulez un vrai statut "en attente"
                # distinct, ajoutez-le à l'ENUM.
                statut="Envoyé",
                date_envoi=timezone.now(),
                id_compteur=compteur,
                id_user_id=id_user,
            )
            for id_user in ids_beneficiaires
        ]
        Notifications.objects.bulk_create(notifications)
        return Response({"detail": "Alerte relayée aux utilisateurs concernés."})


# ==============================================================================
# MODULE 5 — PAIEMENTS & AGRÉGATEURS MOBILE MONEY (CDC 9 — RG-06 à RG-11)
# ==============================================================================

def finaliser_recharge_paiement(paiement):
    """
    Génère le jeton STS à 20 chiffres après confirmation (CDC 5.3/9).
    RG-11 : en cas d'échec de génération, la transaction n'est jamais
    clôturée sur un statut ambigu — elle reste "EN_ATTENTE_JETON" et
    fait l'objet d'un suivi explicite jusqu'à délivrance tardive ou
    remboursement automatique.

    Fonction module-level (extraite de `WebhookPaiementView`) afin d'être
    partagée par tous les webhooks d'agrégateur (générique + NotchPay) sans
    dupliquer la logique métier.
    """
    tx = get_object_or_404(TransactionsPrepayees, pk=paiement.reference_cible)
    try:
        # TODO INTEGRATION : appel réel à l'API Eneo/IoT pour générer le
        # jeton STS. Cet appel, potentiellement lent, doit être isolé
        # dans un traitement asynchrone (file d'attente + worker), pas
        # exécuté en synchrone dans une transaction DB (CDC 8.2).
        token = "".join(secrets.choice(string.digits) for _ in range(20))
        # Chiffrement AES-256-GCM réel avant stockage (api/crypto.py) :
        # `tx.token_genere` ne contient jamais le jeton en clair, mais
        # (nonce || ciphertext || tag) encodé en base64. Le
        # déchiffrement pour réaffichage au client se fait à la volée
        # dans TransactionsPrepayeesSerializer (TokenHistoriqueView,
        # AchatCreditView, ExportDataView...), jamais ici en écriture.
        tx.token_genere = encrypt_token(token)
        tx.statut_paiement = "Réussie"
        tx.save(update_fields=["token_genere", "statut_paiement"])
        # Notification transactionnelle (cascade Push → WhatsApp → SMS,
        # CDC 10) + SMS de secours explicite (CDC 5.3). Volontairement non
        # bloquant : le paiement/jeton sont déjà persistés au-dessus.
        try:
            envoyer_sms(
                paiement.id_user.telephone,
                f"Eneo : votre jeton de recharge est {token}. Conservez-le, il reste consultable dans l'historique.",
            )
        except OrangeSmsError as exc:
            logger.warning("Échec du SMS de secours pour le jeton (paiement=%s) : %s", paiement.id_paiement, exc)
    except Exception:
        # ⚠️ `enum_statut_transaction` (axel.sql) ne contient QUE
        # 'Initiée', 'Réussie', 'Échouée', 'Annulée', 'Remboursée' — pas
        # de statut "en attente de jeton" distinct. Le paiement lui-même
        # est déjà confirmé (Paiements.statut='Confirmé' plus haut) ; on
        # laisse donc la transaction à 'Réussie' et on s'appuie sur
        # `token_genere IS NULL` comme signal "jeton pas encore délivré"
        # pour le suivi RG-11. Si vous voulez un vrai statut dédié,
        # ajoutez une valeur à l'ENUM côté SQL (ex: 'En_Attente_Jeton').
        tx.statut_paiement = "Réussie"
        tx.save(update_fields=["statut_paiement"])
        # TODO INTEGRATION : programmer une nouvelle tentative (retry
        # exponentiel) et notifier le support si l'échec persiste (RG-11).


def finaliser_facture_paiement(paiement):
    """Marque la facture postpayée correspondante comme payée."""
    facture = get_object_or_404(FacturesPostpayees, pk=paiement.reference_cible)
    facture.statut = "Payée"
    facture.save(update_fields=["statut"])


class InitierPaiementView(APIView):
    """
    Initie un paiement (règlement de facture postpayée OU achat de crédit
    prépayé — table unifiée `Paiements`, CDC 8/9).

    Sécurité :
    - Pose un verrou distribué sur le compteur concerné dès la réception de
      la demande, pour empêcher deux achats simultanés (protection anti
      double-dépense, CDC 7.3). Implémenté ici via un TODO Redis ; en son
      absence, on s'appuie a minima sur `select_for_update()` en DB.
    - RG-06 : toute action de paiement au-delà d'un seuil doit être soumise
      à une authentification à deux facteurs — à vérifier en amont (middleware
      ou champ `otp_confirmation` dans le payload).
    """
    permission_classes = [permissions.IsAuthenticated]

    SEUIL_2FA_FCFA = 50000  # TODO : externaliser en configuration

    # `enum_type_paiement` (axel.sql) attend 'Facture_Postpayee' ou
    # 'Recharge_Prepayee' — pas les mots-clés bruts du payload client.
    # ⚠️ C'ÉTAIT LA MÊME CLASSE DE BUG QUE VOTRE ERREUR D'ORIGINE : le code
    # précédent stockait `type_paiement` (ex: "FACTURE") tel quel dans une
    # colonne ENUM qui n'accepte pas cette valeur → DataError garanti au
    # premier appel. On garde un contrat API simple ("FACTURE"/"RECHARGE")
    # côté client et on le traduit vers la valeur ENUM exacte avant écriture.
    TYPE_PAIEMENT_MAP = {
        "FACTURE": "Facture_Postpayee",
        "RECHARGE": "Recharge_Prepayee",
    }

    @transaction.atomic
    def post(self, request):
        type_paiement = request.data.get("type_paiement")  # "FACTURE" ou "RECHARGE"
        reference_cible = request.data.get("reference_cible")
        montant = float(request.data.get("montant_fcfa", 0))
        numero_mobile_money = request.data.get("numero_mobile_money")
        operateur = request.data.get("operateur_mobile_money")  # attendu : 'MTN_MOMO' ou 'ORANGE_MONEY' (enum_operateur_momo)

        # RG-06 : au-delà du seuil, la présence du champ ne suffit plus — on
        # vérifie réellement l'OTP (génération/envoi au 1er appel,
        # consommation au 2e), cf. require_otp_for_sensitive_action.
        require_otp_for_sensitive_action(
            request, scope="paiement", montant=montant, seuil=self.SEUIL_2FA_FCFA,
        )

        # `select_for_update()` verrouille la ligne référencée (facture ou
        # transaction prépayée, selon le type) pour la durée de la
        # transaction DB : deux initiations concurrentes sur la MÊME
        # référence s'exécutent en série plutôt qu'en parallèle. Ce n'est
        # pas le verrou distribué Redis prévu par la CDC (7.3) — utile
        # notamment en environnement multi-instance — mais une protection
        # anti-double-dépense réelle en attendant ce câblage.
        if type_paiement == "FACTURE":
            get_object_or_404(FacturesPostpayees.objects.select_for_update(), pk=reference_cible)
        elif type_paiement == "RECHARGE":
            get_object_or_404(TransactionsPrepayees.objects.select_for_update(), pk=reference_cible)
        else:
            raise ValidationError({"type_paiement": 'Doit être "FACTURE" ou "RECHARGE".'})

        # TODO INTEGRATION : en complément, verrou distribué Redis sur
        # `reference_cible` (ex: `redis.lock(f"lock:compteur:{compteur_id}",
        # timeout=60)`) pour la protection anti-double-dépense inter-process
        # (plusieurs workers/instances Django), que `select_for_update()`
        # seul ne couvre pas.

        paiement = Paiements.objects.create(
            id_paiement=f"PAY-{secrets.token_hex(8).upper()}",
             type_paiement=self.TYPE_PAIEMENT_MAP[type_paiement],
            reference_cible=reference_cible,
             agregateur="NotchPay",
            operateur_mobile_money=operateur,
            numero_mobile_money=numero_mobile_money,
            montant_fcfa=montant,
            frais_agregateur_fcfa=0,  # mis à jour après réponse de l'agrégateur
            statut="Initié",
            correlation_id=secrets.token_hex(16),  # cf. CDC 7.5 — traçabilité inter-systèmes
            date_initiation=timezone.now(),
            id_user=request.user,
        )

        # ⚠️ Si `agregateur` correspond à un type ENUM Postgres restreint
        # (ex: 'Campay'/'Monetbil'/'Maviance'/'Smobilpay', cf. CDC 7.1), cet
        # INSERT échoue avec une erreur DB tant que 'NotchPay' n'a pas été
        # ajouté à l'ENUM côté SQL, ex. :
        #   ALTER TYPE enum_agregateur ADD VALUE IF NOT EXISTS 'NotchPay';
        # (adapter le nom du type à celui réellement utilisé dans axel.sql).

        # Appel réel à NotchPay : initialisation de la transaction +
        # déclenchement du push USSD direct sur le canal Mobile Money choisi
        # (CDC 9.1). `id_paiement` sert de référence externe NotchPay — pas
        # besoin de stocker d'identifiant NotchPay supplémentaire en base.
        #
        # ⚠️ MODE SANDBOX (settings.NOTCHPAY_SANDBOX_FORCER_MONTANT_ZERO) :
        # le montant RÉELLEMENT transmis à NotchPay est alors forcé à 0
        # FCFA, quel que soit `montant` ci-dessus — voir
        # `api/services/notchpay.py` pour le détail. `paiement.montant_fcfa`
        # continue de refléter le vrai montant métier (RG-07).
        try:
            resultat_notchpay = notchpay.initialiser_paiement(
                reference=paiement.id_paiement,
                montant_fcfa=montant,
                email=request.user.email,
                telephone=numero_mobile_money,
                operateur=operateur,
                description=f"{self.TYPE_PAIEMENT_MAP[type_paiement]} — {reference_cible}",
            )
        except NotchPayError as exc:
            logger.error("Initialisation NotchPay échouée (paiement=%s) : %s", paiement.id_paiement, exc)
            paiement.statut = "Échoué"
            paiement.save(update_fields=["statut"])
            return Response(
                {"detail": "L'agrégateur de paiement n'a pas pu être contacté. Veuillez réessayer."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        reponse = PaiementsSerializer(paiement).data
        # Champs informatifs, non persistés en base (cf. commentaire de
        # `notchpay.initialiser_paiement`) : utiles au client pour afficher
        # un lien de secours (`authorization_url`) si le direct-charge USSD
        # ne se déclenche pas, et pour être transparent en sandbox sur le
        # montant réellement débité côté agrégateur de test.
        reponse["notchpay_authorization_url"] = resultat_notchpay["authorization_url"]
        reponse["montant_envoye_agregateur_fcfa"] = resultat_notchpay["montant_envoye_fcfa"]

        return Response(reponse, status=status.HTTP_202_ACCEPTED)


class WebhookPaiementView(APIView):
    """
    Point d'entrée des notifications entrantes des agrégateurs Mobile Money
    (CDC 9.2). Règles impératives :
    - RG-08 : le montant confirmé doit correspondre AU CENTIME PRÈS au
      montant initialement enregistré ; tout écart → blocage + alerte fraude.
    - RG-09 : idempotence stricte — un événement déjà traité avec succès est
      acquitté SANS nouveau traitement (évite double débit / double jeton).
    - La signature HMAC-SHA256 du webhook doit être vérifiée avant tout
      traitement (CDC 9.2).
    - Chaque webhook brut est journalisé dans `WebhookLogs`, Append-Only
      (RG-09), qu'il soit valide ou non.

    Ce endpoint est appelé par le compte technique de l'agrégateur (RG-05 :
    ce compte n'a jamais les droits d'un administrateur humain).
    """
    permission_classes = [permissions.AllowAny]  # authentifié via signature HMAC, pas JWT

    @transaction.atomic
    def post(self, request):
        payload = request.data
        id_evenement = payload.get("id_evenement_agregateur")
        signature = request.headers.get("X-Signature-HMAC", "")

        # CORRECTIF P0 (audit du 20/07/2026) : `bool(signature)` acceptait
        # comme valide n'importe quelle chaîne non vide dans l'en-tête, sur
        # un endpoint AllowAny — n'importe quel tiers pouvait forger une
        # confirmation de paiement Mobile Money. On calcule ici le véritable
        # HMAC-SHA256 attendu à partir d'un secret partagé (jamais transmis
        # au client, à définir dans `settings.MOBILE_MONEY_WEBHOOK_SECRET`
        # — ce fichier ne fournissant pas settings.py, la valeur par défaut
        # `None` fait volontairement échouer TOUTE signature tant que le
        # secret n'a pas été configuré, plutôt que de retomber silencieusement
        # sur l'ancien comportement permissif).
        secret_partage = getattr(settings, "MOBILE_MONEY_WEBHOOK_SECRET", None)
        signature_valide = False
        if secret_partage:
            signature_attendue = hmac.new(
                key=secret_partage.encode("utf-8"),
                msg=request.body,
                digestmod=hashlib.sha256,
            ).hexdigest()
            # Comparaison à temps constant (comme secrets.compare_digest
            # déjà utilisé pour l'OTP) — évite une attaque par timing sur la
            # comparaison caractère par caractère d'une comparaison naïve.
            signature_valide = bool(signature) and hmac.compare_digest(signature_attendue, signature)

        # Idempotence (RG-09) : un même id_evenement_agregateur est unique.
        deja_traite = WebhookLogs.objects.filter(id_evenement_agregateur=id_evenement).exists()

        # Le paiement concerné, retrouvé via correlation_id ou référence agrégateur.
        id_paiement = payload.get("id_paiement")
        paiement = get_object_or_404(Paiements, pk=id_paiement)

        # BUG CORRIGÉ : `id_evenement_agregateur` porte une contrainte
        # `unique=True` sur le modèle. Le code précédent appelait
        # `.create()` sans condition, y compris quand `deja_traite` était
        # vrai — ce qui levait une IntegrityError sur CHAQUE retry légitime
        # de l'agrégateur (le scénario même que RG-09 doit absorber
        # proprement). `get_or_create` ne journalise que les évènements
        # réellement nouveaux et laisse intacte la ligne déjà existante pour
        # un doublon.
        WebhookLogs.objects.get_or_create(
            id_evenement_agregateur=id_evenement,
            defaults={
                "payload_brut": payload,
                "signature_hmac_valide": signature_valide,
                "date_reception": timezone.now(),
                "id_paiement": paiement,
            },
        )

        if not signature_valide:
            # On journalise mais on ne traite jamais un webhook non authentifié.
            return Response({"detail": "Signature invalide, événement ignoré."}, status=status.HTTP_400_BAD_REQUEST)

        if deja_traite and paiement.statut == "Confirmé":
            # Idempotence : acquittement sans nouveau traitement (RG-09).
            return Response({"detail": "Événement déjà traité."}, status=status.HTTP_200_OK)

        montant_webhook = float(payload.get("montant_fcfa", 0))
        if round(montant_webhook, 2) != round(float(paiement.montant_fcfa), 2):
            # RG-08 : écart de montant → blocage + alerte de fraude.
            # ⚠️ `enum_statut_paiement` (axel.sql) ne contient QUE 'Initié',
            # 'Confirmé', 'Échoué', 'Annulé', 'Remboursé' — pas de statut
            # "bloqué pour anomalie". On retombe sur 'Échoué' comme état le
            # plus proche (le paiement n'est pas confirmé), mais ça perd la
            # distinction "fraude suspectée" vs "échec technique". Si ce
            # distinguo est important pour vous, il faut l'ajouter à l'ENUM.
            paiement.statut = "Échoué"
            paiement.save(update_fields=["statut"])
            # TODO INTEGRATION : déclencher une alerte fraude vers le back-office.
            return Response({"detail": "Écart de montant détecté, paiement bloqué."}, status=status.HTTP_409_CONFLICT)

        paiement.statut = "Confirmé"
        paiement.numero_recu = f"RECU-{secrets.token_hex(8).upper()}"
        paiement.donnees_recu_json = payload
        paiement.date_confirmation = timezone.now()
        paiement.save(update_fields=["statut", "numero_recu", "donnees_recu_json", "date_confirmation"])

        # Finalisation métier selon le type de paiement (valeurs ENUM
        # 'Recharge_Prepayee' / 'Facture_Postpayee', cf. InitierPaiementView).
        # Logique extraite en fonctions module-level (voir plus haut) pour
        # être partagée avec `NotchPayWebhookView`.
        if paiement.type_paiement == "Recharge_Prepayee":
            finaliser_recharge_paiement(paiement)
        elif paiement.type_paiement == "Facture_Postpayee":
            finaliser_facture_paiement(paiement)

        return Response({"detail": "Paiement confirmé."}, status=status.HTTP_200_OK)


class NotchPayWebhookView(APIView):
    """
    Point d'entrée dédié aux notifications NotchPay — URL de terminaison
    convenue : `/api/webhooks/notchpay/` (à renseigner côté dashboard
    NotchPay et dans `settings.NOTCHPAY_CALLBACK_URL`).

    Reprend les mêmes garanties que `WebhookPaiementView` (RG-08, RG-09,
    signature vérifiée avant tout traitement, journalisation Append-Only
    dans `WebhookLogs`), adaptées au format NotchPay :
    - signature HMAC-SHA256 dans l'en-tête `x-notchpay-signature`, vérifiée
      via `notchpay.verifier_signature_webhook` sur le corps BRUT de la
      requête (`request.body`), pas sur `request.data` re-sérialisé ;
    - événement typique : {"event": "payment.complete", "data": {"reference":
      ..., "amount": ..., "status": ...}} — `reference` correspond à notre
      `Paiements.id_paiement` (transmis tel quel à l'initialisation).

    ⚠️ RG-08 adapté au mode sandbox : le montant reçu est comparé au montant
    RÉELLEMENT ENVOYÉ à NotchPay (`notchpay.montant_attendu_agregateur`,
    0 FCFA en sandbox de test), PAS au montant métier `paiement.montant_fcfa`
    — sinon chaque webhook de test déclencherait à tort une alerte de
    fraude. Voir `api/services/notchpay.py` pour le détail de ce choix.
    """
    permission_classes = [permissions.AllowAny]  # authentifié via signature HMAC, pas JWT

    @transaction.atomic
    def post(self, request):
        signature = request.headers.get("x-notchpay-signature", "")
        signature_valide = notchpay.verifier_signature_webhook(request.body, signature)

        payload = request.data
        data = payload.get("data", payload)
        evenement = payload.get("event", "")
        reference = data.get("reference")

        # Identifiant d'idempotence (RG-09) : l'id de transaction NotchPay
        # si disponible, sinon un composite reference+événement (NotchPay
        # peut renvoyer plusieurs événements pour une même transaction —
        # ex. "payment.initiated" puis "payment.complete" — donc l'événement
        # fait partie de la clé, contrairement à la seule `reference`).
        id_evenement = str(data.get("id") or f"{reference}:{evenement}")

        paiement = get_object_or_404(Paiements, pk=reference)

        deja_traite = WebhookLogs.objects.filter(id_evenement_agregateur=id_evenement).exists()

        WebhookLogs.objects.get_or_create(
            id_evenement_agregateur=id_evenement,
            defaults={
                "id_webhook": f"WH-{secrets.token_hex(8).upper()}",
                "payload_brut": payload,
                "signature_hmac_valide": signature_valide,
                "date_reception": timezone.now(),
                "id_paiement": paiement,
            },
        )

        if not signature_valide:
            # On journalise mais on ne traite jamais un webhook non authentifié.
            return Response({"detail": "Signature invalide, événement ignoré."}, status=status.HTTP_400_BAD_REQUEST)

        if deja_traite and paiement.statut == "Confirmé":
            return Response({"detail": "Événement déjà traité."}, status=status.HTTP_200_OK)

        # On ne finalise que sur l'événement de succès ; les autres
        # événements NotchPay (initiated, failed, canceled...) sont
        # journalisés ci-dessus mais ne déclenchent pas de finalisation.
        if evenement not in ("payment.complete", "payment.success"):
            if evenement in ("payment.failed", "payment.canceled"):
                paiement.statut = "Échoué" if evenement == "payment.failed" else "Annulé"
                paiement.save(update_fields=["statut"])
            return Response({"detail": f"Événement '{evenement}' journalisé."}, status=status.HTTP_200_OK)

        montant_webhook = float(data.get("amount", 0))
        montant_attendu = notchpay.montant_attendu_agregateur(paiement.montant_fcfa)
        if round(montant_webhook, 2) != round(montant_attendu, 2):
            # RG-08 : écart de montant → blocage + alerte de fraude. Voir
            # WebhookPaiementView pour la note sur l'ENUM `enum_statut_paiement`
            # qui ne distingue pas "bloqué pour anomalie" de "Échoué".
            paiement.statut = "Échoué"
            paiement.save(update_fields=["statut"])
            # TODO INTEGRATION : déclencher une alerte fraude vers le back-office.
            return Response({"detail": "Écart de montant détecté, paiement bloqué."}, status=status.HTTP_409_CONFLICT)

        paiement.statut = "Confirmé"
        paiement.numero_recu = f"RECU-{secrets.token_hex(8).upper()}"
        paiement.donnees_recu_json = payload
        paiement.date_confirmation = timezone.now()
        paiement.save(update_fields=["statut", "numero_recu", "donnees_recu_json", "date_confirmation"])

        if paiement.type_paiement == "Recharge_Prepayee":
            finaliser_recharge_paiement(paiement)
        elif paiement.type_paiement == "Facture_Postpayee":
            finaliser_facture_paiement(paiement)

        return Response({"detail": "Paiement confirmé."}, status=status.HTTP_200_OK)


class PaiementStatutView(generics.RetrieveAPIView):
    """Consultation du statut d'un paiement en cours ou passé."""
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = PaiementsSerializer
    lookup_field = "id_paiement"

    def get_queryset(self):
        return Paiements.objects.filter(id_user=self.request.user)


class ReconciliationComptableView(APIView):
    """
    Réconciliation comptable quotidienne, réservée au back-office (CDC 9.2).
    Rapproche les transactions internes et le relevé officiel de
    l'agrégateur, classées en trois statuts :
    - RAPPROCHEE
    - ECART_POSITIF_INTERNE (jeton potentiellement délivré sans encaissement confirmé)
    - ECART_NEGATIF_INTERNE (client débité sans jeton délivré)
    """
    permission_classes = [IsAdminFinancier]

    def get(self, request):
        date_str = request.query_params.get("date")  # format YYYY-MM-DD
        # TODO INTEGRATION : comparer `Paiements` confirmés du jour avec le
        # relevé officiel récupéré auprès de l'agrégateur (appel API externe).
        paiements_du_jour = Paiements.objects.filter(date_confirmation__date=date_str) if date_str \
            else Paiements.objects.none()

        return Response({
            "date": date_str,
            "rapprochees": [],           # TODO : calcul réel
            "ecarts_positifs_internes": [],  # TODO : calcul réel
            "ecarts_negatifs_internes": [],  # TODO : calcul réel
            "total_paiements_confirmes": paiements_du_jour.count(),
        })


class RemboursementView(APIView):
    """
    Remboursement d'un paiement — réservé à l'Administrateur Financier.
    RG-06 : action sensible → 2FA obligatoire.
    Résolution de Niveau 3 des litiges (CDC 9.4) : remboursement automatique
    sous 24-48h si le service ne peut être délivré.
    Toute exécution est journalisée dans la piste d'audit (CDC 5.4).
    """
    permission_classes = [IsAdminFinancier]

    @transaction.atomic
    def post(self, request, id_paiement):
        # RG-06 : un remboursement est toujours une action sensible, quel
        # que soit son montant (pas de `seuil` ⇒ 2FA systématique) — même
        # correctif que InitierPaiementView : vérification réelle de l'OTP.
        require_otp_for_sensitive_action(request, scope="remboursement")

        paiement = get_object_or_404(Paiements, pk=id_paiement)
        motif = request.data.get("motif", "")

        paiement.statut = "Remboursé"
        paiement.save(update_fields=["statut"])

        # TODO INTEGRATION : déclencher le virement de remboursement réel
        # via l'agrégateur Mobile Money (délai cible 24-48h, CDC 9.4).

        log_audit(
            auteur=request.user,
            action="REMBOURSEMENT",
            objet_touche=f"Paiement {paiement.id_paiement}",
            motif=motif,
            cible=paiement.id_user,
            request=request,
        )
        return Response(PaiementsSerializer(paiement).data)


# ==============================================================================
# MODULE 6 — NOTIFICATIONS (CDC 10)
# ==============================================================================
# NB : les envois effectifs (choix du canal selon la matrice de criticité,
# cascade Push → WhatsApp → SMS, gestion des files d'attente et Dead Letter
# Queue) sont réalisés par des tâches asynchrones (Celery/RQ), hors périmètre
# de ce fichier de vues. Les vues ci-dessous couvrent uniquement les
# opérations exposées côté client (consultation, gestion des devices).

class NotificationHistoriqueView(generics.ListAPIView):
    """
    Historique des notifications reçues par l'utilisateur connecté.

    GET /api/notifications/
        Retourne la liste paginée des notifications (toutes, ou filtrées par
        ?non_lues=true). Partagé entre le dashboard ET l'écran Paramètres :
        les deux écrans appellent ce même endpoint.

    PATCH /api/notifications/<id_notification>/lue/
        Marque une notification comme lue (date_lecture = now()).
        Appel depuis le dashboard ET depuis l'écran Paramètres → synchronisation
        automatique : dès qu'un écran marque une notif comme lue, le badge
        de l'autre écran se met à jour à la prochaine interrogation.
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = NotificationsSerializer
    pagination_class = StandardResultsSetPagination

    def get_queryset(self):
        qs = Notifications.objects.filter(id_user=self.request.user).order_by("-date_envoi")
        non_lues = self.request.query_params.get("non_lues")
        if non_lues and non_lues.lower() in ("true", "1"):
            qs = qs.filter(date_lecture__isnull=True)
        return qs


class NotificationMarquerLueView(APIView):
    """
    PATCH /api/notifications/<id_notification>/lue/
    Marque une notification comme lue. Utilisé indifféremment depuis le
    dashboard et depuis l'écran Paramètres — la donnée est unique en base,
    donc les deux vues restent synchronisées sans état supplémentaire.
    """
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, id_notification):
        notif = get_object_or_404(
            Notifications,
            pk=id_notification,
            id_user=request.user,
        )
        if notif.date_lecture is None:
            notif.date_lecture = timezone.now()
            notif.save(update_fields=["date_lecture"])
        return Response(NotificationsSerializer(notif).data)


class NotificationNonLuesCountView(APIView):
    """
    GET /api/notifications/non-lues/count/
    Retourne le nombre de notifications non lues de l'utilisateur connecté.
    Appelé par le dashboard pour afficher le badge, et par l'écran Paramètres
    pour afficher le même badge — source unique de vérité.
    Réponse : {"count": <int>}
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        count = Notifications.objects.filter(
            id_user=request.user,
            date_lecture__isnull=True,
        ).count()
        return Response({"count": count})


class NotificationMarquerToutesLuesView(APIView):
    """
    POST /api/notifications/tout-lire/
    Marque TOUTES les notifications non lues de l'utilisateur comme lues.
    Accessible depuis le dashboard ET depuis l'écran Paramètres.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        updated = Notifications.objects.filter(
            id_user=request.user,
            date_lecture__isnull=True,
        ).update(date_lecture=timezone.now())
        return Response({"marquees_lues": updated})


class DeviceRegisterView(generics.CreateAPIView):
    """
    Enregistrement d'un terminal et de son jeton FCM (CDC 10, table
    `UserDevices`), nécessaire aux notifications push.
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UserDevicesSerializer

    def perform_create(self, serializer):
        serializer.save(
            id_user=self.request.user,
            statut="Actif",
            date_enregistrement=timezone.now(),
        )


class DeviceUnregisterView(APIView):
    """
    Désenregistrement d'un terminal (déconnexion, désinstallation) — permet
    également le nettoyage automatique des jetons FCM expirés/invalides
    (CDC 8, table `User_Devices`).
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, id_device):
        device = get_object_or_404(UserDevices, pk=id_device, id_user=request.user)
        device.statut = "Inactif"
        device.save(update_fields=["statut"])
        return Response({"detail": "Terminal désenregistré."})


# ==============================================================================
# MODULE 7 — BACK-OFFICE ADMINISTRATEUR (CDC 5.4 — RG-04, RG-05)
# ==============================================================================

class AdminDashboardKPIView(APIView):
    """
    Tableau de bord des KPI produit (CDC section 3) :
    - Taux de pénétration parmi les clients Eneo (cible 30% à 1 an)
    - Taux de facture postpayée en retard (cible -9% à 1 an)
    - Taux d'erreur sur les transactions (cible < 2%)
    - Part des paiements Eneo passant par l'app (cible 20% à 2 ans)
    Accessible aux 3 profils admin (lecture commune).
    """
    permission_classes = [IsAnyAdmin]

    def get(self, request):
        total_users = Users.objects.filter(role="Client").count()
        total_factures = FacturesPostpayees.objects.count()
        factures_en_retard = FacturesPostpayees.objects.filter(
            statut="Impayée", date_limite__lt=timezone.now().date(),
        ).count()
        total_paiements = Paiements.objects.count()
        paiements_en_echec = Paiements.objects.filter(statut__in=["Échoué", "Annulé"]).count()

        return Response({
            "total_clients": total_users,
            "taux_factures_en_retard": (
                round(100 * factures_en_retard / total_factures, 2) if total_factures else 0
            ),
            "taux_erreur_transactions": (
                round(100 * paiements_en_echec / total_paiements, 2) if total_paiements else 0
            ),
            # TODO : taux de pénétration et part des paiements via l'app
            # nécessitent une donnée externe (base clients Eneo totale).
            "taux_penetration": None,
            "part_paiements_app": None,
        })


class AdminUserManagementView(generics.ListCreateAPIView):
    """
    Gestion des comptes administrateurs (support / financier / technicien),
    CDC 5.4. La création d'un compte admin est elle-même une action
    sensible → journalisée (audit) et réservée aux profils déjà admin.
    """
    permission_classes = [IsAnyAdmin]
    serializer_class = UsersSerializer

    def get_queryset(self):
        return Users.objects.filter(role__in=["Admin_Support", "Admin_Financier", "Admin_Technicien"])

    def perform_create(self, serializer):
        # Le serializer accepte `mot_de_passe` en écriture (write_only) mais
        # ne le hache pas lui-même : on le fait ici avant sauvegarde, sinon
        # le mot de passe de tout nouveau compte admin serait stocké en clair.
        mot_de_passe_clair = serializer.validated_data.get("mot_de_passe")
        extra = {
            "date_creation": timezone.now(),
            # ⚠️ Django envoie TOUJOURS ces colonnes dans l'INSERT (valeur
            # par défaut du champ Python, pas de la base) — sans ça, même
            # bug DataError que RegisterView à la création d'un compte admin.
            "statut_compte": "Actif",
            "tentatives_connexion_echouees": 0,
        }
        if mot_de_passe_clair:
            extra["mot_de_passe"] = hash_password(mot_de_passe_clair)
        user = serializer.save(**extra)
        log_audit(
            auteur=self.request.user,
            action="CREATION_COMPTE_ADMIN",
            objet_touche=f"Utilisateur {user.id_user}",
            cible=user,
            request=self.request,
        )


class ImpersonationStartView(APIView):
    """
    Démarre une session d'impersonation : un administrateur agit
    temporairement au nom d'un client à des fins de support/diagnostic.
    RG-04 : journalisation EXHAUSTIVE et non falsifiable (identité admin,
    identité client, horodatage, IP, motif) dans `AuditLogs` (Append-Only).
    """
    permission_classes = [IsAdminSupport]

    def post(self, request, id_user_cible):
        client = get_object_or_404(Users, pk=id_user_cible, role="Client")
        motif = request.data.get("motif")
        if not motif:
            raise ValidationError({"motif": "Le motif d'impersonation est obligatoire (RG-04)."})

        log_audit(
            auteur=request.user,
            action="IMPERSONATION_START",
            objet_touche=f"Client {client.id_user}",
            motif=motif,
            cible=client,
            request=request,
        )

        # TODO INTEGRATION : émettre un jeton de session d'impersonation à
        # durée de vie très courte, clairement distinct d'un JWT client
        # normal, et visible côté back-office (bandeau "Vous agissez en tant
        # que...").
        return Response({
            "detail": "Session d'impersonation démarrée.",
            "id_user_cible": client.id_user,
            "session_token": "TODO_IMPERSONATION_TOKEN",
        })


class ImpersonationEndView(APIView):
    """Termine une session d'impersonation en cours — journalisée également."""
    permission_classes = [IsAdminSupport]

    def post(self, request, id_user_cible):
        client = get_object_or_404(Users, pk=id_user_cible)
        log_audit(
            auteur=request.user,
            action="IMPERSONATION_END",
            objet_touche=f"Client {client.id_user}",
            cible=client,
            request=request,
        )
        return Response({"detail": "Session d'impersonation terminée."})


class AuditLogsListView(generics.ListAPIView):
    """
    Consultation de la piste d'audit — lecture seule (Append-Only, RG-04/RG-12).
    Aucune vue d'update/delete n'existe volontairement pour cette ressource.
    """
    permission_classes = [IsAnyAdmin]
    serializer_class = AuditLogsSerializer
    pagination_class = StandardResultsSetPagination
    queryset = AuditLogs.objects.all().order_by("-date_heure")


class LitigeCreateView(generics.CreateAPIView):
    """Ouverture d'un litige (Niveau 1 par défaut) — cf. aussi SignalerAnomalieFactureView."""
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = LitigesSerializer

    def perform_create(self, serializer):
        serializer.save(
            id_litige=f"LIT-{secrets.token_hex(8).upper()}",
            niveau="1",
            statut="Ouvert",
            id_user=self.request.user,
            date_ouverture=timezone.now(),
        )


class LitigeListView(generics.ListAPIView):
    """
    Liste des litiges.
    - Un client ne voit que ses propres litiges.
    - Un admin (support/financier) voit l'ensemble des litiges, avec filtrage
      possible par niveau/statut.
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = LitigesSerializer
    pagination_class = StandardResultsSetPagination

    def get_queryset(self):
        user = self.request.user
        if getattr(user, "role", None) in ("Admin_Support", "Admin_Financier"):
            qs = Litiges.objects.all()
            niveau = self.request.query_params.get("niveau")
            statut = self.request.query_params.get("statut")
            if niveau:
                qs = qs.filter(niveau=niveau)
            if statut:
                qs = qs.filter(statut=statut)
            return qs.order_by("-date_ouverture")
        return Litiges.objects.filter(id_user=user).order_by("-date_ouverture")


class LitigeResolveView(APIView):
    """
    Traitement d'un litige selon la politique à 3 niveaux (CDC 9.4) :
    - Niveau 1 : diagnostic automatique (renvoi gratuit du jeton par
      SMS/e-mail si non reçu).
    - Niveau 2 : vérification comptable croisée (webhooks + relevé agrégateur).
    - Niveau 3 : résolution — forçage manuel de génération du jeton,
      remboursement automatique (24-48h) ou rejet motivé avec preuve
      d'exécution.
    Réservé aux administrateurs (support pour niveaux 1-2, financier pour le
    remboursement en niveau 3).
    """
    permission_classes = [IsAnyAdmin]

    @transaction.atomic
    def post(self, request, id_litige):
        litige = get_object_or_404(Litiges, pk=id_litige)
        action = request.data.get("action")  # RENVOI_JETON | FORCAGE_JETON | REMBOURSEMENT | REJET
        resolution = request.data.get("resolution", "")

        if action == "RENVOI_JETON":
            litige.niveau = "1"
            # TODO INTEGRATION : renvoyer gratuitement le dernier jeton connu
            # par SMS/e-mail.
        elif action == "FORCAGE_JETON":
            if getattr(request.user, "role", None) != "Admin_Financier":
                raise PermissionDenied("Le forçage de jeton relève du niveau 3 (Admin Financier).")
            litige.niveau = "3"
            # TODO INTEGRATION : forcer la génération du jeton (paiement
            # confirmé, service non rendu).
        elif action == "REMBOURSEMENT":
            if getattr(request.user, "role", None) != "Admin_Financier":
                raise PermissionDenied("Le remboursement relève du niveau 3 (Admin Financier).")
            litige.niveau = "3"
            # TODO INTEGRATION : déclencher le remboursement (cf. RemboursementView).
        elif action == "REJET":
            litige.niveau = "3"
        else:
            raise ValidationError({"action": "Valeur inconnue."})

        litige.statut = "Résolu"
        litige.resolution = resolution
        litige.date_resolution = timezone.now()
        litige.traite_par = request.user
        litige.save(update_fields=["niveau", "statut", "resolution", "date_resolution", "traite_par"])

        log_audit(
            auteur=request.user,
            action=f"LITIGE_{action}",
            objet_touche=f"Litige {litige.id_litige}",
            motif=resolution,
            request=request,
        )
        return Response(LitigesSerializer(litige).data)


class WebhookLogsListView(generics.ListAPIView):
    """
    Registre brut des notifications entrantes des agrégateurs — lecture
    seule, réservé au Technicien API (supervision des intégrations, CDC 5.4).
    Table Append-Only (RG-09).
    """
    permission_classes = [IsAdminTechnicien]
    serializer_class = WebhookLogsSerializer
    pagination_class = StandardResultsSetPagination
    queryset = WebhookLogs.objects.all().order_by("-date_reception")


# ==============================================================================
# MODULE 8 — RÉFÉRENTIELS
# ==============================================================================

class TarifsListView(generics.ListAPIView):
    """
    Grille tarifaire historisée, en lecture seule côté client (CDC 8 : la
    modification des tarifs est une opération back-office hors périmètre de
    ce module client). `date_fin = NULL` signifie "tarif actuellement en
    vigueur" — cf. RG-07 : le prix appliqué à une transaction reste figé
    indépendamment des évolutions ultérieures de cette grille.
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = TarifsSerializer

    def get_queryset(self):
        qs = Tarifs.objects.all().order_by("-date_debut")
        type_compteur = self.request.query_params.get("type_compteur")
        if type_compteur:
            qs = qs.filter(type_compteur=type_compteur)
        return qs


class AdressesView(generics.ListCreateAPIView):
    """
    Référentiel des adresses d'installation — table dédiée pour éviter la
    duplication sur un immeuble multi-compteurs (CDC 8).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = AdressesSerializer
    queryset = Adresses.objects.all()

    def perform_create(self, serializer):
        serializer.save(date_creation=timezone.now())


# ==============================================================================
# MODULE 9 — CONFORMITÉ / RGPD (CDC 11.3)
# ==============================================================================

class ExportDataView(APIView):
    """
    Droit à l'export des données personnelles, exercé depuis l'espace client
    (CDC 11.3 — cadre légal camerounais n°2010/012, sous contrôle ANTIC).
    Exporte le profil ET les données associées consultables par l'utilisateur
    (compteurs, factures, transactions, notifications) dans un format
    structuré exploitable (JSON), ET envoie par e-mail à l'utilisateur un
    PDF récapitulatif de son compte + de TOUTES ses factures.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        ids_compteurs = list(get_delegated_compteur_ids(user))
        date_export = timezone.now()

        contrats_qs = Contrats.objects.filter(id_user=user).annotate(
            nombre_compteurs=Count('compteurs')
        )
        compteurs_qs = Compteurs.objects.filter(id_compteur__in=ids_compteurs)
        factures_qs = FacturesPostpayees.objects.filter(id_compteur_id__in=ids_compteurs)
        transactions_qs = TransactionsPrepayees.objects.filter(id_compteur_id__in=ids_compteurs)

        # `context={"masquer": False}` : le masquage partiel (§11.2) protège
        # l'affichage courant contre un tiers qui intercepterait la réponse,
        # mais l'export RGPD (CDC 11.3, cadre légal camerounais n°2010/012)
        # doit au contraire fournir les données personnelles COMPLÈTES au
        # titulaire du compte qui les demande explicitement — les masquer
        # ici viderait ce droit de sa substance.
        export = {
            "profil": UsersSerializer(user, context={"masquer": False}).data,
            "contrats": ContratsSerializer(contrats_qs, many=True).data,
            "compteurs": CompteursSerializer(
                compteurs_qs, many=True, context={"masquer": False},
            ).data,
            "factures": FacturesPostpayeesSerializer(factures_qs, many=True).data,
            "transactions_prepayees": TransactionsPrepayeesSerializer(
                transactions_qs, many=True
            ).data,
            "paiements": PaiementsSerializer(
                Paiements.objects.filter(id_user=user), many=True
            ).data,
            "notifications": NotificationsSerializer(
                Notifications.objects.filter(id_user=user), many=True
            ).data,
            "consentements": UserConsentLogsSerializer(
                UserConsentLogs.objects.filter(id_user=user), many=True
            ).data,
            "date_export": date_export,
        }

        # ── PDF récapitulatif + envoi par e-mail ────────────────────────
        # Reconstruit les listes en mémoire une seule fois (déjà évaluées
        # ci-dessus pour la sérialisation JSON) afin d'éviter de refaire
        # les mêmes requêtes SQL pour le PDF.
        email_envoye = False
        erreur_envoi = None
        try:
            pdf_bytes = generer_pdf_export_donnees(
                user=user,
                contrats=list(contrats_qs),
                compteurs=list(compteurs_qs),
                factures=list(factures_qs),
                transactions_prepayees=list(transactions_qs),
                date_export=date_export,
            )
            msg = EmailMultiAlternatives(
                subject=f"📄 [ENEO] Export de vos données personnelles — {date_export:%d/%m/%Y}",
                body=(
                    f"Bonjour {user.prenom},\n\n"
                    "Veuillez trouver ci-joint le récapitulatif PDF de votre compte AxelPay "
                    "et de l'ensemble de vos factures, conformément à votre demande d'export "
                    "de données personnelles.\n\n"
                    "L'équipe AxelPay / ENEO"
                ),
                from_email=settings.DEFAULT_FROM_EMAIL,
                to=[user.email],
            )
            msg.attach(
                f"export_donnees_axelpay_{date_export:%Y%m%d}.pdf",
                pdf_bytes,
                "application/pdf",
            )
            msg.send(fail_silently=False)
            email_envoye = True
        except Exception as exc:
            erreur_envoi = str(exc)
            logger.error(
                "ExportDataView: échec de l'envoi du PDF d'export (user=%s): %s",
                user.pk, exc,
            )

        export["email_envoye"] = email_envoye
        export["destinataire"] = user.email if email_envoye else None
        export["message"] = (
            f"Le récapitulatif PDF de vos données et de vos factures a été envoyé à {user.email}."
            if email_envoye
            else "L'envoi de l'e-mail a échoué. Vos données restent disponibles ci-dessous ; "
                 "réessayez plus tard ou contactez le support."
        )
        if erreur_envoi and settings.DEBUG:
            export["erreur_envoi_debug"] = erreur_envoi

        return Response(export)


class DeviceRegisterView(generics.CreateAPIView):
    """
    Enregistrement (UPSERT) d'un terminal et de son jeton FCM (CDC 10,
    table `UserDevices`), nécessaire aux notifications push.

    POST /api/devices/
        {"fcm_token": "xxxxxxxx", "type_appareil": "android"}

    Comportement :
      - token inconnu           → création d'une nouvelle ligne.
      - token déjà enregistré,
        même utilisateur        → mise à jour (type_appareil, statut
                                   remis à "Actif", date_derniere_activite).
      - token déjà enregistré,
        AUTRE utilisateur       → réassignation à `request.user` (cas du
                                   terminal partagé entre plusieurs comptes).
    """
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UserDevicesSerializer

    def create(self, request, *args, **kwargs):
        fcm_token = request.data.get("fcm_token")
        if not fcm_token:
            return Response(
                {"fcm_token": "Ce champ est requis."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        type_appareil = request.data.get("type_appareil", "android")
        now = timezone.now()

        device, created = UserDevices.objects.update_or_create(
            fcm_token=fcm_token,
            defaults={
                "id_user": request.user,
                "type_appareil": type_appareil,
                "statut": "Actif",
                "date_derniere_activite": now,
            },
        )
        if created:
            device.date_enregistrement = now
            device.save(update_fields=["date_enregistrement"])

        serializer = self.get_serializer(device)
        return Response(
            serializer.data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class DeviceUnregisterView(APIView):
    """
    Désenregistrement d'un terminal PAR ID (déconnexion, désinstallation,
    ou action back-office) — inchangée par rapport à l'existant.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, id_device):
        device = get_object_or_404(UserDevices, pk=id_device, id_user=request.user)
        device.statut = "Inactif"
        device.save(update_fields=["statut"])
        return Response({"detail": "Terminal désenregistré."})


class DeviceUnregisterByTokenView(APIView):
    """
    Désenregistrement d'un terminal PAR TOKEN — utilisée par le client
    Flutter, qui ne connaît que son propre `fcm_token`, jamais `id_device`.

    DELETE /api/devices/desenregistrer/
        {"fcm_token": "xxxxxxxx"}

    Sécurité : le filtre `id_user=request.user` garantit qu'un utilisateur
    ne peut désactiver QUE ses propres terminaux.
    """
    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request):
        fcm_token = request.data.get("fcm_token")
        if not fcm_token:
            return Response(
                {"fcm_token": "Ce champ est requis."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        device = get_object_or_404(UserDevices, fcm_token=fcm_token, id_user=request.user)
        device.statut = "Inactif"
        device.save(update_fields=["statut"])
        return Response({"detail": "Terminal désenregistré."})    


class DeleteAccountView(APIView):
    """
    Suppression / désactivation de compte à l'initiative du client (CDC 5.5,
    11.3). Les données de PROFIL peuvent être effacées/anonymisées, mais
    l'HISTORIQUE FINANCIER est conservé sous forme archivée pour répondre aux
    obligations comptables légales (Code de commerce : conservation 10 ans
    des journaux financiers) — RG-12 : jamais de suppression physique des
    tables d'historique financier.
    """
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request):
        mot_de_passe = request.data.get("mot_de_passe_confirmation")
        mot_de_passe_valide = verify_password(mot_de_passe, request.user.mot_de_passe)
        if not mot_de_passe_valide:
            raise PermissionDenied("Ré-authentification requise pour cette opération.")

        user = request.user
        user.statut_compte = "Désactivé"
        # Anonymisation partielle des champs de profil non nécessaires à
        # l'historique financier (le détail exact dépend de la politique
        # de rétention légale à valider avec le service juridique/ANTIC).
        user.nom = "ANONYMISE"
        user.prenom = "ANONYMISE"
        user.save(update_fields=["statut_compte", "nom", "prenom"])

        log_audit(
            auteur=user,
            action="DESACTIVATION_COMPTE",
            objet_touche=f"Utilisateur {user.id_user}",
            motif="Demande du client (droit RGPD, CDC 11.3)",
            cible=user,
            request=request,
        )
        return Response({"detail": "Compte désactivé. Historique financier conservé (obligations légales)."})


# ==============================================================================
# MODULE 10 — ASSISTANT DE SUPPORT IA (écran "Assistance")
# ==============================================================================
# Chatbot de premier niveau, branché sur l'écran "Écrire un message" de
# `support_screen.dart` (jusqu'ici un stub honnête "Chat en direct — bientôt
# disponible"). Répond aux questions de facturation/recharge/litiges en
# s'appuyant sur le dossier RÉEL du client connecté plutôt qu'une FAQ
# statique — cf. `_construire_contexte_support` ci-dessous.
#
# Pas de nouvelle table de conversation : l'historique est tenu côté
# CLIENT, qui renvoie la liste complète des tours à chaque appel (pattern
# "stateless" standard de l'API Messages, cf. la doc d'intégration
# Anthropic dans les Artifacts). Ça évite une migration DB pour ce premier
# jet, au prix de re-transmettre l'historique à chaque tour — acceptable
# pour une conversation de support, généralement courte.
#
# ⚠️ TODO INTEGRATION : nécessite `ANTHROPIC_API_KEY` dans l'environnement
# (.env, settings.py). Sans clé configurée, la vue renvoie une erreur 503
# explicite (cf. `AiSupportError`) plutôt qu'une fausse réponse simulée.
# ==============================================================================
 
def _construire_contexte_support(user):
    """
    Résumé factuel et concis du dossier du client connecté, injecté dans le
    prompt système de l'assistant IA (`ai_support._construire_prompt_systeme`)
    pour qu'il réponde sur SA situation réelle plutôt que des généralités.
 
    Volontairement minimal et jamais sensible : ni mot de passe, ni jeton
    de recharge, ni numéro Mobile Money, ni email. Limité aux 5 contrats et
    5 litiges les plus récents — un dossier support n'a pas besoin de tout
    l'historique pour être utile, et ça borne la taille du prompt système.
    """
    contrats = list(Contrats.objects.filter(id_user=user).order_by("-date_creation")[:5])
    ids_compteurs = get_delegated_compteur_ids(user)
 
    factures_impayees = FacturesPostpayees.objects.filter(
        id_compteur_id__in=ids_compteurs, statut="Impayée",
    )
    total_impaye = factures_impayees.aggregate(total=Sum("montant_fcfa"))["total"] or 0
 
    litiges_ouverts = (
        Litiges.objects.filter(id_user=user)
        .exclude(statut="Résolu")
        .order_by("-date_ouverture")[:5]
    )
 
    return {
        "prenom": user.prenom,
        "contrats": [{"numero": c.numero_contrat, "statut": c.statut} for c in contrats],
        "nombre_factures_impayees": factures_impayees.count(),
        "total_impaye_fcfa": float(total_impaye),
        "litiges_ouverts": [
            {
                "id": l.id_litige,
                "niveau": l.niveau,
                "statut": l.statut,
                "description": (l.description or "")[:200],
            }
            for l in litiges_ouverts
        ],
    }
 
 
class SupportChatView(APIView):
    """
    POST /api/support/chat/
        {"messages": [{"role": "user", "content": "..."}, ...]}
 
    - Le CLIENT tient l'historique complet et le renvoie à chaque appel
      (pas de conversation_id, pas d'état côté serveur) ; cette vue ne fait
      que rejouer cet historique à l'API Anthropic avec le contexte métier
      du client en prompt système.
    - Rejette un historique vide ou dont le dernier message n'est pas de
      l'utilisateur (protège contre un client mal formé qui rejouerait la
      réponse de l'IA comme nouveau tour, doublant l'appel pour rien).
    - Garde-fous anti-abus grossiers : 20 tours maximum par requête, dernier
      message limité à 2000 caractères (l'API Anthropic a ses propres
      limites, mais on évite de lui transmettre un payload démesuré).
    - N'écrit JAMAIS dans `Litiges`/`Paiements` : si l'IA juge la situation
      hors de sa portée, elle le signale (`escalade_recommandee`) et c'est
      ensuite au CLIENT de décider, depuis l'écran Assistance, d'appeler un
      agent ou d'ouvrir un litige via les vues dédiées — cette vue informe,
      elle n'agit jamais à la place de l'utilisateur.
    """
    permission_classes = [permissions.IsAuthenticated]
 
    MAX_TOURS = 20
    MAX_LONGUEUR_MESSAGE = 2000
 
    def post(self, request):
        messages = request.data.get("messages")
        if not messages or not isinstance(messages, list):
            raise ValidationError({"messages": "Requis : liste non vide de {role, content}."})
        if len(messages) > self.MAX_TOURS:
            raise ValidationError({"messages": f"Maximum {self.MAX_TOURS} tours par requête."})
 
        dernier = messages[-1] if isinstance(messages[-1], dict) else {}
        if dernier.get("role") != "user":
            raise ValidationError({"messages": "Le dernier message doit être celui de l'utilisateur."})
        if len(dernier.get("content") or "") > self.MAX_LONGUEUR_MESSAGE:
            raise ValidationError({
                "messages": f"Message limité à {self.MAX_LONGUEUR_MESSAGE} caractères."
            })
 
        contexte = _construire_contexte_support(request.user)
 
        try:
            reponse, escalade = ai_support.repondre(messages, contexte)
        except ai_support.AiSupportError as exc:
            logger.error("Échec de l'assistant IA support (user=%s) : %s", request.user.pk, exc)
            return Response(
                {"detail": "L'assistant est momentanément indisponible. Réessayez, ou appelez un agent support."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
 
        return Response({"reponse": reponse, "escalade_recommandee": escalade})    

# ==============================================================================
# MODULE 11 — TICKETS DE SUPPORT (écran Paramètres → "Ouvrir un ticket")
# ==============================================================================
# Un ticket est un litige formel accompagné d'un e-mail ultra-professionnel
# envoyé via le SMTP configuré dans settings.py (EMAIL_HOST, EMAIL_PORT,
# EMAIL_HOST_USER, EMAIL_HOST_PASSWORD, DEFAULT_FROM_EMAIL).
#
# Le mail est envoyé :
#   • AU CLIENT     : accusé de réception avec numéro de ticket et récapitulatif.
#   • À L'ÉQUIPE SUPPORT (settings.SUPPORT_EMAIL) : fiche complète du ticket
#     avec le contexte du dossier client pour un traitement immédiat.
#
# ⚙️  Variables settings.py requises :
#     EMAIL_HOST, EMAIL_PORT, EMAIL_HOST_USER, EMAIL_HOST_PASSWORD,
#     DEFAULT_FROM_EMAIL  (déjà configurés via le SMTP existant)
#     SUPPORT_EMAIL       (adresse de l'équipe support interne, ex: support@eneo.cm)
# ==============================================================================


def _generer_html_ticket_client(ticket_id, user, sujet, description, categorie, priorite, date_ouverture):
    """Corps HTML de l'accusé de réception envoyé au client."""
    date_str = date_ouverture.strftime("%d/%m/%Y à %H:%M")
    sla = {
        "Urgente": "Réponse sous <strong>4 heures ouvrables</strong>.",
        "Haute":   "Réponse sous <strong>24 heures ouvrables</strong>.",
        "Normale": "Réponse sous <strong>48 heures ouvrables</strong>.",
    }.get(priorite, "Réponse dans les meilleurs délais.")
    return f"""<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8">
<title>Ticket {ticket_id} — ENEO Support</title>
<style>
body{{margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;color:#212121}}
.w{{max-width:640px;margin:36px auto;background:#fff;border-radius:10px;
    box-shadow:0 4px 20px rgba(0,0,0,.10);overflow:hidden}}
.hd{{background:linear-gradient(135deg,#1a237e 0%,#283593 100%);padding:32px 40px;text-align:center}}
.hd h1{{color:#fff;font-size:22px;margin:0 0 6px;letter-spacing:.4px}}
.hd p{{color:#c5cae9;font-size:13px;margin:0}}
.bd{{padding:36px 40px}}
.tkt{{background:#e8eaf6;border-left:5px solid #1a237e;border-radius:6px;padding:20px 24px;margin:24px 0}}
.tkt .num{{font-size:26px;font-weight:800;color:#1a237e;letter-spacing:1.5px}}
.tkt .lbl{{font-size:11px;color:#5c6bc0;text-transform:uppercase;letter-spacing:.7px;margin-bottom:4px}}
.grid{{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:24px 0}}
.cell{{background:#f8f9fa;border-radius:7px;padding:14px 18px}}
.cell .lbl{{font-size:11px;color:#757575;text-transform:uppercase;letter-spacing:.6px;margin-bottom:5px}}
.cell .val{{font-size:14px;font-weight:700;color:#212121}}
.desc-box{{background:#f8f9fa;border-radius:7px;padding:18px 20px;margin:24px 0}}
.desc-box .lbl{{font-size:11px;color:#757575;text-transform:uppercase;letter-spacing:.6px;margin-bottom:8px}}
.desc-box .txt{{font-size:14px;color:#424242;line-height:1.7;white-space:pre-wrap}}
.sla{{background:#e3f2fd;border-radius:7px;padding:16px 20px;margin:24px 0;font-size:13px;color:#1565c0}}
.badge{{display:inline-block;padding:3px 12px;border-radius:20px;font-size:12px;font-weight:700;color:#fff}}
.bg-N{{background:#388e3c}}.bg-H{{background:#e65100}}.bg-U{{background:#c62828}}
.ft{{background:#f4f6f9;padding:22px 40px;text-align:center;border-top:1px solid #e0e0e0}}
.ft p{{margin:0;font-size:12px;color:#9e9e9e;line-height:1.7}}
.ft a{{color:#1a237e;text-decoration:none}}
</style></head><body>
<div class="w">
  <div class="hd">
    <h1>⚡ ENEO — Confirmation de ticket</h1>
    <p>Votre demande a bien été enregistrée</p>
  </div>
  <div class="bd">
    <p>Bonjour <strong>{user.prenom} {user.nom}</strong>,</p>
    <p style="font-size:14px;color:#424242;line-height:1.6">
      Nous avons bien reçu votre demande de support. Un agent qualifié prendra en charge
      votre dossier dans les meilleurs délais. Conservez ce numéro de ticket pour tout suivi.
    </p>
    <div class="tkt">
      <div class="lbl">Numéro de ticket</div>
      <div class="num">{ticket_id}</div>
      <div style="font-size:12px;color:#5c6bc0;margin-top:6px">Ouvert le {date_str}</div>
    </div>
    <div class="grid">
      <div class="cell"><div class="lbl">Catégorie</div><div class="val">{categorie}</div></div>
      <div class="cell"><div class="lbl">Priorité</div>
        <div class="val"><span class="badge bg-{priorite[0]}">{priorite}</span></div></div>
    </div>
    <div class="cell" style="margin:0 0 24px;padding:14px 18px;background:#f8f9fa;border-radius:7px">
      <div class="lbl" style="font-size:11px;color:#757575;text-transform:uppercase;letter-spacing:.6px;margin-bottom:5px">Objet</div>
      <div class="val" style="font-size:14px;font-weight:700;color:#212121">{sujet}</div>
    </div>
    <div class="desc-box">
      <div class="lbl">Votre description</div>
      <div class="txt">{description}</div>
    </div>
    <div class="sla">⏱ <strong>Délai de traitement :</strong> {sla}</div>
    <p style="font-size:13px;color:#616161;line-height:1.6">
      Pour toute question ou précision, répondez à cet e-mail en mentionnant le numéro
      <strong>{ticket_id}</strong>, ou utilisez le chat de l'application.
    </p>
  </div>
  <div class="ft">
    <p>© 2024 ENEO Cameroun — <a href="https://eneo.cm">eneo.cm</a><br>
    Cet e-mail a été généré automatiquement. Ne pas répondre si votre problème est résolu.</p>
  </div>
</div></body></html>"""


def _generer_html_ticket_support(ticket_id, user, sujet, description, categorie, priorite,
                                  date_ouverture, contexte_dossier):
    """Corps HTML de l'e-mail interne envoyé à l'équipe support (dossier complet)."""
    date_str = date_ouverture.strftime("%d/%m/%Y à %H:%M")
    coul = {"Urgente": "#c62828", "Haute": "#e65100", "Normale": "#2e7d32"}.get(priorite, "#424242")
    contrats_html = "".join(
        f"<li>Contrat <strong>{c['numero']}</strong> — statut&nbsp;: {c['statut']}</li>"
        for c in (contexte_dossier.get("contrats") or [])
    ) or "<li style='color:#9e9e9e'>Aucun contrat rattaché</li>"
    litiges_html = "".join(
        f"<li>[{l['id']}] Niveau {l['niveau']} / {l['statut']} — {l['description'][:150]}</li>"
        for l in (contexte_dossier.get("litiges_ouverts") or [])
    ) or "<li style='color:#9e9e9e'>Aucun litige ouvert</li>"

    return f"""<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8">
<title>🎫 Ticket {ticket_id} — Support Interne</title>
<style>
body{{margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;color:#212121}}
.w{{max-width:700px;margin:32px auto;background:#fff;border-radius:10px;
    box-shadow:0 4px 20px rgba(0,0,0,.12);overflow:hidden}}
.hd{{background:{coul};padding:24px 36px}}
.hd h1{{color:#fff;margin:0;font-size:20px}}
.hd .sub{{color:rgba(255,255,255,.75);font-size:13px;margin-top:4px}}
.sec{{padding:22px 36px;border-bottom:1px solid #f0f0f0}}
.sec h2{{font-size:12px;text-transform:uppercase;letter-spacing:.9px;color:#757575;margin:0 0 16px}}
.kv{{display:flex;gap:8px;margin-bottom:10px;align-items:flex-start}}
.kv .k{{font-size:13px;color:#616161;min-width:180px;flex-shrink:0}}
.kv .v{{font-size:13px;color:#212121;font-weight:600}}
.badge{{display:inline-block;padding:3px 12px;border-radius:20px;font-size:12px;
        font-weight:700;color:#fff;background:{coul}}}
.desc{{background:#f8f9fa;border-radius:6px;padding:16px;font-size:13px;
       color:#424242;line-height:1.7;white-space:pre-wrap}}
ul{{margin:0;padding-left:20px;font-size:13px;color:#424242;line-height:1.9}}
.ft{{padding:14px 36px;background:#f8f9fa;font-size:11px;color:#9e9e9e;
     border-top:1px solid #e0e0e0}}
</style></head><body>
<div class="w">
  <div class="hd">
    <h1>🎫 Nouveau ticket — {ticket_id}</h1>
    <div class="sub">Reçu le {date_str} · Priorité : {priorite} · Catégorie : {categorie}</div>
  </div>
  <div class="sec">
    <h2>Identification</h2>
    <div class="kv"><span class="k">Numéro de ticket</span><span class="v">{ticket_id}</span></div>
    <div class="kv"><span class="k">Date d'ouverture</span><span class="v">{date_str}</span></div>
    <div class="kv"><span class="k">Catégorie</span><span class="v">{categorie}</span></div>
    <div class="kv"><span class="k">Priorité</span><span class="v"><span class="badge">{priorite}</span></span></div>
    <div class="kv"><span class="k">Objet</span><span class="v">{sujet}</span></div>
  </div>
  <div class="sec">
    <h2>Client</h2>
    <div class="kv"><span class="k">Nom complet</span><span class="v">{user.prenom} {user.nom}</span></div>
    <div class="kv"><span class="k">E-mail</span><span class="v">{user.email}</span></div>
    <div class="kv"><span class="k">Téléphone</span><span class="v">{user.telephone}</span></div>
    <div class="kv"><span class="k">ID utilisateur</span><span class="v">{user.id_user}</span></div>
    <div class="kv"><span class="k">Factures impayées</span>
      <span class="v">{contexte_dossier.get('nombre_factures_impayees', 0)} ticket(s) 
      — {contexte_dossier.get('total_impaye_fcfa', 0):.0f} FCFA</span></div>
  </div>
  <div class="sec">
    <h2>Contrats du client</h2>
    <ul>{contrats_html}</ul>
  </div>
  <div class="sec">
    <h2>Litiges en cours</h2>
    <ul>{litiges_html}</ul>
  </div>
  <div class="sec">
    <h2>Description du problème</h2>
    <div class="desc">{description}</div>
  </div>
  <div class="ft">
    Ticket généré automatiquement · Répondre à {user.email} · Ne pas transférer hors de l'équipe support
  </div>
</div></body></html>"""


class OuvrirTicketView(APIView):
    """
    POST /api/support/tickets/ouvrir/

    Ouvre un ticket de support formel et envoie deux e-mails HTML professionnels :
      1. AU CLIENT     : accusé de réception (numéro de ticket + récapitulatif).
      2. À L'ÉQUIPE SUPPORT (settings.SUPPORT_EMAIL) : fiche complète avec
         le dossier du client (contrats, litiges, factures impayées).

    Payload attendu :
      {
        "sujet":       str  (obligatoire, max 200 chars),
        "description": str  (obligatoire, min 20 chars),
        "categorie":   str  (optionnel — Facturation|Recharge|Technique|Paiement|Autre),
        "priorite":    str  (optionnel — Normale|Haute|Urgente),
        "id_compteur": int  (optionnel — si le problème concerne un compteur précis)
      }

    Réponse 201 :
      {
        "ticket_id":           "TKT-XXXXXXXXXXXXXXXX",
        "statut":              "Ouvert",
        "message":             str,
        "email_client_envoye": bool,
        "email_support_envoye": bool
      }
    """
    permission_classes = [permissions.IsAuthenticated]

    CATEGORIES_VALIDES = {"Facturation", "Recharge", "Technique", "Paiement", "Autre"}
    PRIORITES_VALIDES  = {"Normale", "Haute", "Urgente"}

    def post(self, request):
        user = request.user

        # ── Validation ─────────────────────────────────────────────────────────
        sujet       = (request.data.get("sujet") or "").strip()
        description = (request.data.get("description") or "").strip()
        categorie   = (request.data.get("categorie") or "Autre").strip()
        priorite    = (request.data.get("priorite")  or "Normale").strip()
        id_compteur = request.data.get("id_compteur")

        erreurs = {}
        if not sujet:
            erreurs["sujet"] = "Ce champ est obligatoire."
        elif len(sujet) > 200:
            erreurs["sujet"] = "Maximum 200 caractères."
        if not description:
            erreurs["description"] = "Ce champ est obligatoire."
        elif len(description) < 20:
            erreurs["description"] = "Minimum 20 caractères pour une description utile."
        if categorie not in self.CATEGORIES_VALIDES:
            erreurs["categorie"] = f"Valeurs acceptées : {', '.join(sorted(self.CATEGORIES_VALIDES))}."
        if priorite not in self.PRIORITES_VALIDES:
            erreurs["priorite"] = f"Valeurs acceptées : {', '.join(sorted(self.PRIORITES_VALIDES))}."

        if erreurs:
            raise ValidationError(erreurs)

        # ── Vérification compteur ───────────────────────────────────────────────
        if id_compteur is not None:
            if not user_has_access_to_compteur(user, id_compteur):
                raise ValidationError({"id_compteur": "Compteur inconnu ou accès non autorisé."})

        # ── Création du ticket (litige Niveau 1) en base ────────────────────────
        ticket_id      = f"TKT-{secrets.token_hex(8).upper()}"
        date_ouverture = timezone.now()

        with transaction.atomic():
            Litiges.objects.create(
                id_litige    = ticket_id,
                niveau       = "1",
                statut       = "Ouvert",
                description  = f"[{categorie} / {priorite}] {sujet}\n\n{description}",
                id_user      = user,
                date_ouverture = date_ouverture,
            )

        log_audit(
            auteur       = user,
            action       = "TICKET_OUVERT",
            objet_touche = ticket_id,
            motif        = f"Ticket client — catégorie={categorie}, priorité={priorite}",
            request      = request,
        )

        # ── Construction e-mails ────────────────────────────────────────────────
        contexte_dossier = _construire_contexte_support(user)

        html_client  = _generer_html_ticket_client(
            ticket_id, user, sujet, description, categorie, priorite, date_ouverture
        )
        html_support = _generer_html_ticket_support(
            ticket_id, user, sujet, description, categorie, priorite,
            date_ouverture, contexte_dossier
        )

        sujet_mail_client  = f"✅ [ENEO Support] Ticket {ticket_id} — {sujet}"
        sujet_mail_support = f"🎫 [Ticket {priorite.upper()}] {ticket_id} — {sujet}"

        support_email        = getattr(settings, "SUPPORT_EMAIL",
                                       getattr(settings, "DEFAULT_FROM_EMAIL", None))
        email_client_envoye  = False
        email_support_envoye = False

        # ── Envoi e-mail client (+ fiche PDF du ticket en pièce jointe) ─────────
        try:
            msg = EmailMultiAlternatives(
                subject   = sujet_mail_client,
                body      = f"Ticket {ticket_id} bien enregistré. Consultez la version HTML de cet e-mail.",
                from_email= settings.DEFAULT_FROM_EMAIL,
                to        = [user.email],
            )
            msg.attach_alternative(html_client, "text/html")
            try:
                pdf_ticket = generer_pdf_ticket(
                    ticket_id, user, sujet, description, categorie, priorite, date_ouverture,
                )
                msg.attach(f"ticket_{ticket_id}.pdf", pdf_ticket, "application/pdf")
            except Exception as exc_pdf:
                # Un échec de génération PDF ne doit pas empêcher l'envoi de
                # l'e-mail HTML de confirmation — le ticket reste ouvert.
                logger.error(
                    "OuvrirTicketView: échec génération PDF (ticket=%s): %s", ticket_id, exc_pdf
                )
            msg.send(fail_silently=False)
            email_client_envoye = True
        except Exception as exc:
            logger.error(
                "OuvrirTicketView: échec e-mail client (user=%s, ticket=%s): %s",
                user.pk, ticket_id, exc
            )

        # ── Envoi e-mail équipe support ─────────────────────────────────────────
        if support_email:
            try:
                msg_sup = EmailMultiAlternatives(
                    subject   = sujet_mail_support,
                    body      = (
                        f"Nouveau ticket {ticket_id} de {user.prenom} {user.nom} "
                        f"({user.email}). Priorité : {priorite}. Catégorie : {categorie}."
                    ),
                    from_email= settings.DEFAULT_FROM_EMAIL,
                    to        = [support_email],
                    reply_to  = [user.email],
                )
                msg_sup.attach_alternative(html_support, "text/html")
                msg_sup.send(fail_silently=False)
                email_support_envoye = True
            except Exception as exc:
                logger.error(
                    "OuvrirTicketView: échec e-mail support (ticket=%s): %s",
                    ticket_id, exc
                )
        else:
            logger.warning(
                "OuvrirTicketView: SUPPORT_EMAIL non configuré — e-mail interne ignoré (ticket=%s).",
                ticket_id
            )

        return Response(
            {
                "ticket_id"            : ticket_id,
                "statut"               : "Ouvert",
                "message"              : (
                    f"Ticket ouvert. E-mail de confirmation envoyé à {user.email}."
                    if email_client_envoye
                    else f"Ticket {ticket_id} ouvert. L'envoi de l'e-mail de confirmation a échoué — "
                         "contactez le support si nécessaire."
                ),
                "email_client_envoye"  : email_client_envoye,
                "email_support_envoye" : email_support_envoye,
            },
            status=status.HTTP_201_CREATED,
        )

# ==============================================================================
# MODULE 12 — I18N (traduction FR→EN de l'app Flutter via DeepL)
# ==============================================================================
# Voir api/services/deepl_translate.py pour le détail de l'intégration DeepL
# et la stratégie de cache. Cette vue est le SEUL point de contact entre le
# client Flutter et DeepL : la clé DEEPL_API_KEY reste côté serveur (voir
# settings.py pour l'explication complète + comment la configurer via .env).
class TraduireTextesView(APIView):
    """
    POST /api/i18n/traduire/
        {"textes": ["Accueil", "Paramètres", ...], "cible": "EN"}
        -> {"traductions": ["Home", "Settings", ...]}  (même ordre, même longueur)

    `AllowAny` volontairement : les écrans non authentifiés (connexion,
    inscription, OTP) doivent eux aussi pouvoir s'afficher en anglais dès le
    premier lancement. Le risque d'abus (proxy DeepL gratuit pour un tiers)
    est couvert par `ScopedRateThrottle` + `DEFAULT_THROTTLE_RATES["traduction"]`
    (settings.py) plutôt que par une authentification qui casserait l'usage
    légitime sur les écrans de login/inscription.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "traduction"

    MAX_TEXTES = 200
    LANGUES_AUTORISEES = {"EN", "FR"}

    def post(self, request):
        textes = request.data.get("textes")
        cible = (request.data.get("cible") or "EN").upper()

        if not textes or not isinstance(textes, list):
            raise ValidationError({"textes": "Requis : liste non vide de chaînes."})
        if len(textes) > self.MAX_TEXTES:
            raise ValidationError({"textes": f"Maximum {self.MAX_TEXTES} textes par requête."})
        if not all(isinstance(t, str) for t in textes):
            raise ValidationError({"textes": "Chaque élément doit être une chaîne."})
        if cible not in self.LANGUES_AUTORISEES:
            raise ValidationError({"cible": f"Langue cible non supportée : {cible}."})

        try:
            traductions = deepl_translate.traduire(textes, langue_cible=cible)
        except DeepLError as exc:
            logger.warning("TraduireTextesView: échec DeepL : %s", exc)
            return Response(
                {"detail": "Traduction momentanément indisponible."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        return Response({"traductions": traductions})
