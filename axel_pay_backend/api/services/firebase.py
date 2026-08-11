# -*- coding: utf-8 -*-
"""
===============================================================================
 api/services/firebase.py — Envoi de notifications push (Firebase Admin SDK)
===============================================================================
Suit le même pattern que les autres intégrations du dossier
`api/services/` (notchpay.py, orange_sms.py) : un module de service isolé,
sans dépendance sur DRF, appelé depuis views.py (Module 6 — Notifications,
CDC 10).

Ce module NE FAIT PAS d'authentification Firebase (rappel : l'auth de
l'app reste 100% Django/JWT, cf. authentication.py — Firebase ne sert
QUE pour FCM).

Installation :
    pip install firebase-admin

Configuration attendue dans settings.py :

    FIREBASE_CREDENTIALS_PATH = os.environ.get(
        "FIREBASE_CREDENTIALS_PATH",
        BASE_DIR / "secrets" / "firebase-service-account.json",
    )

Le fichier JSON de compte de service se télécharge depuis Console
Firebase > Project Settings > Service accounts > "Generate new private
key". ⚠️ Ne JAMAIS committer ce fichier — ajoute-le à .gitignore et
distribue-le via variable d'environnement / secret manager en prod.
===============================================================================
"""

from __future__ import annotations

import logging
from typing import Iterable

import firebase_admin
from django.conf import settings
from firebase_admin import credentials, messaging

logger = logging.getLogger(__name__)

_app: firebase_admin.App | None = None


def _get_app() -> firebase_admin.App:
    """
    Initialise l'app Firebase Admin une seule fois par process (worker
    Gunicorn/uWSGI) — `firebase_admin.initialize_app()` lève une exception
    si appelée deux fois sur la même app par défaut.
    """
    global _app
    if _app is not None:
        return _app

    try:
        _app = firebase_admin.get_app()
    except ValueError:
        cred = credentials.Certificate(str(settings.FIREBASE_CREDENTIALS_PATH))
        _app = firebase_admin.initialize_app(cred)

    return _app


class PushNotificationError(Exception):
    """Erreur remontée par l'Admin SDK Firebase ou par une configuration
    manquante (FIREBASE_CREDENTIALS_PATH absent/introuvable)."""


def send_push_notification(
    token: str,
    title: str,
    body: str,
    data: dict | None = None,
) -> str:
    """
    Envoie une notification push à UN terminal donné.

    Paramètres
    ----------
    token : le `fcm_token` stocké dans `UserDevices` (voir models.py).
    title, body : contenu affiché dans la notification système.
    data : payload additionnel (toujours des `str` — FCM l'exige), lu par
        `FirebaseMessagingService.onMessageTap` côté Flutter pour la
        navigation (ex: {"type": "facture_disponible", "id_facture": "..."}).

    Retourne l'identifiant du message Firebase (utile pour le logging /
    debug), ou lève [PushNotificationError] si Firebase rejette l'appel
    pour une raison AUTRE qu'un token invalide/expiré (ce cas précis est
    géré silencieusement par [_desactiver_device_si_token_invalide],
    appelé automatiquement par [send_push_notification_to_user]).

    ⚠️ Ne fait PAS le nettoyage du device en cas de token invalide ici :
    cette fonction bas niveau n'a pas accès à l'ORM `UserDevices` par
    design (séparation service Firebase / logique métier Django). Utilise
    [send_push_notification_to_user] pour bénéficier du nettoyage
    automatique.
    """
    app = _get_app()

    # FCM exige des chaînes pour TOUTES les valeurs de `data` (pas d'int,
    # de bool ou de None) — normalisation défensive pour éviter un rejet
    # silencieux côté Firebase sur un type inattendu.
    normalized_data = {str(k): str(v) for k, v in (data or {}).items()}

    message = messaging.Message(
        token=token,
        notification=messaging.Notification(title=title, body=body),
        data=normalized_data,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="axelpay_notifications",
                default_sound=True,
            ),
        ),
        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(sound="default", badge=1),
            ),
        ),
        webpush=messaging.WebpushConfig(
            notification=messaging.WebpushNotification(title=title, body=body),
        ),
    )

    try:
        message_id = messaging.send(message, app=app)
        logger.info("Push envoyé (token=%s..., message_id=%s)", token[:12], message_id)
        return message_id
    except messaging.UnregisteredError:
        # Token désinstallé/expiré côté client — remonté tel quel, c'est à
        # l'appelant (send_push_notification_to_user) de désactiver le
        # UserDevices correspondant.
        raise
    except messaging.SenderIdMismatchError:
        raise
    except firebase_admin.exceptions.FirebaseError as exc:
        logger.error("Échec envoi push (token=%s...) : %s", token[:12], exc)
        raise PushNotificationError(str(exc)) from exc


def send_push_notification_to_user(user, title: str, body: str, data: dict | None = None) -> int:
    """
    Envoie une notification push à TOUS les terminaux actifs d'un
    utilisateur (`UserDevices.statut == "Actif"`, `id_user=user`).

    C'est la fonction à appeler depuis views.py pour les cas métier
    (facture disponible, confirmation paiement, rappel facture impayée,
    message système — voir Module 6, CDC 10).

    Gère automatiquement le nettoyage RG-xx des tokens invalides :
    un `UnregisteredError` désactive silencieusement le `UserDevices`
    correspondant (`statut = "Inactif"`) au lieu de continuer à taper
    dans le vide à chaque notification future.

    Retourne le nombre d'envois réussis.
    """
    # Import différé pour éviter toute dépendance circulaire entre
    # services/ et models.py au chargement du module.
    from ..models import UserDevices

    devices = UserDevices.objects.filter(id_user=user, statut="Actif")
    succès = 0

    for device in devices:
        try:
            send_push_notification(device.fcm_token, title, body, data)
            succès += 1
        except (messaging.UnregisteredError, messaging.SenderIdMismatchError):
            logger.warning(
                "Token FCM invalide pour id_device=%s (user=%s) — désactivation.",
                device.id_device,
                getattr(user, "id_user", user),
            )
            device.statut = "Inactif"
            device.save(update_fields=["statut"])
        except PushNotificationError:
            # Erreur transitoire (réseau, quota Firebase...) : on NE
            # désactive PAS le device, un prochain envoi pourra réussir.
            continue

    return succès


def send_push_notification_to_tokens(
    tokens: Iterable[str], title: str, body: str, data: dict | None = None
) -> messaging.BatchResponse:
    """
    Envoi groupé multicast — utile pour un message système diffusé à un
    grand nombre de terminaux (ex: maintenance planifiée) sans boucler un
    par un. Limite Firebase : 500 tokens par appel ; découpe en lots côté
    appelant si besoin.
    """
    app = _get_app()
    normalized_data = {str(k): str(v) for k, v in (data or {}).items()}

    message = messaging.MulticastMessage(
        tokens=list(tokens),
        notification=messaging.Notification(title=title, body=body),
        data=normalized_data,
    )

    try:
        return messaging.send_multicast(message, app=app)
    except firebase_admin.exceptions.FirebaseError as exc:
        logger.error("Échec envoi push multicast : %s", exc)
        raise PushNotificationError(str(exc)) from exc


# ---------------------------------------------------------------------------
# Raccourcis métier — un par cas d'usage listé dans la demande initiale.
# Centralise le TEXTE des notifications ici plutôt que de le disperser dans
# chaque vue de views.py : un seul endroit à modifier pour changer un
# libellé, et ça reste cohérent avec le pattern déjà utilisé pour
# `masquer_telephone` etc. dans serializers.py.
# ---------------------------------------------------------------------------

def notifier_facture_disponible(user, numero_facture: str, montant_fcfa, id_facture: str) -> int:
    return send_push_notification_to_user(
        user,
        title="Nouvelle facture disponible",
        body=f"Votre facture {numero_facture} de {montant_fcfa} FCFA est disponible.",
        data={"type": "facture_disponible", "id_facture": id_facture},
    )


def notifier_paiement_confirme(user, montant_fcfa, id_paiement: str) -> int:
    return send_push_notification_to_user(
        user,
        title="Paiement confirmé",
        body=f"Votre paiement de {montant_fcfa} FCFA a été confirmé avec succès.",
        data={"type": "paiement_confirme", "id_paiement": id_paiement},
    )


def notifier_facture_impayee(user, numero_facture: str, date_limite: str, id_facture: str) -> int:
    return send_push_notification_to_user(
        user,
        title="Rappel : facture impayée",
        body=f"Votre facture {numero_facture} arrive à échéance le {date_limite}.",
        data={"type": "facture_impayee", "id_facture": id_facture},
    )


def notifier_message_systeme(user, title: str, body: str) -> int:
    return send_push_notification_to_user(
        user,
        title=title,
        body=body,
        data={"type": "message_systeme"},
    )
