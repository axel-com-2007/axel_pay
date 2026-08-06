# -*- coding: utf-8 -*-
"""
===============================================================================
 api/services/orange_sms.py — Envoi de SMS via l'API Orange SMS (CDC 10)
===============================================================================
Utilisé pour l'OTP d'inscription/changement de numéro (`RegisterView`,
`ChangePhoneNumberView`) et, à terme, pour le canal SMS de la cascade
Push → WhatsApp → SMS (matrice de criticité, CDC 10).

Fonctionnement : l'API Orange SMS repose sur OAuth2 "client credentials" —
on échange `ORANGE_SMS_CLIENT_ID`/`ORANGE_SMS_CLIENT_SECRET` contre un jeton
d'accès de courte durée, mis en cache pour éviter une authentification à
chaque SMS envoyé, puis on poste le message sur
`/smsmessaging/v1/outbound/{senderAddress}/requests`.

⚠️ `ORANGE_SMS_CLIENT_SECRET` n'a aucune valeur de secours dans settings.py
(le secret transmis était masqué) : tant que la variable d'environnement
n'est pas positionnée, `envoyer_sms` lève `OrangeSmsError` explicitement au
lieu de tenter un appel voué à l'échec.
===============================================================================
"""

import base64
import logging

import requests
from django.conf import settings
from django.core.cache import cache

logger = logging.getLogger(__name__)

TOKEN_URL = "https://api.orange.com/oauth/v3/token"
SMS_CACHE_KEY = "orange_sms_access_token"


class OrangeSmsError(Exception):
    """Erreur de configuration, d'authentification ou d'envoi côté Orange SMS."""


def _obtenir_jeton_acces() -> str:
    jeton_en_cache = cache.get(SMS_CACHE_KEY)
    if jeton_en_cache:
        return jeton_en_cache

    client_id = getattr(settings, "ORANGE_SMS_CLIENT_ID", None)
    client_secret = getattr(settings, "ORANGE_SMS_CLIENT_SECRET", None)
    if not client_id or not client_secret:
        raise OrangeSmsError(
            "ORANGE_SMS_CLIENT_ID / ORANGE_SMS_CLIENT_SECRET non configurés "
            "(variable d'environnement manquante)."
        )

    identifiants = base64.b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode("ascii")
    try:
        resp = requests.post(
            TOKEN_URL,
            headers={
                "Authorization": f"Basic {identifiants}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            data={"grant_type": "client_credentials"},
            timeout=15,
        )
    except requests.RequestException as exc:
        raise OrangeSmsError(f"Erreur réseau lors de l'authentification Orange SMS : {exc}") from exc

    if resp.status_code >= 400:
        raise OrangeSmsError(f"Authentification Orange SMS refusée ({resp.status_code}) : {resp.text}")

    data = resp.json()
    jeton = data.get("access_token")
    duree_vie = int(data.get("expires_in", 3600))
    # Marge de sécurité de 60s pour ne jamais utiliser un jeton expiré de
    # justesse entre la lecture du cache et l'appel réel.
    cache.set(SMS_CACHE_KEY, jeton, timeout=max(duree_vie - 60, 30))
    return jeton


def envoyer_sms(telephone: str, message: str) -> None:
    """
    Envoie un SMS via l'API Orange SMS. `telephone` au format international
    (ex: "+237690000000") — converti en `tel:+237690000000` pour l'API.

    Lève `OrangeSmsError` en cas d'échec (configuration manquante, auth
    refusée, envoi refusé) — à l'appelant de décider s'il s'agit d'un point
    bloquant (ex: OTP) ou d'un simple avertissement journalisé (ex: relance
    de facture, où d'autres canaux de la cascade prennent le relais).
    """
    sender = getattr(settings, "ORANGE_SMS_SENDER_ADDRESS", None)
    if not sender:
        raise OrangeSmsError("ORANGE_SMS_SENDER_ADDRESS non configuré (variable d'environnement manquante).")

    jeton = _obtenir_jeton_acces()
    telephone_normalise = telephone if telephone.startswith("tel:") else f"tel:{telephone}"
    sender_normalise = sender if sender.startswith("tel:") else f"tel:{sender}"

    payload = {
        "outboundSMSMessageRequest": {
            "address": [telephone_normalise],
            "senderAddress": sender_normalise,
            "outboundSMSTextMessage": {"message": message},
        }
    }

    try:
        resp = requests.post(
            f"https://api.orange.com/smsmessaging/v1/outbound/{sender_normalise}/requests",
            json=payload,
            headers={
                "Authorization": f"Bearer {jeton}",
                "Content-Type": "application/json",
            },
            timeout=15,
        )
    except requests.RequestException as exc:
        raise OrangeSmsError(f"Erreur réseau lors de l'envoi du SMS : {exc}") from exc

    if resp.status_code >= 400:
        raise OrangeSmsError(f"Envoi du SMS refusé par Orange ({resp.status_code}) : {resp.text}")

    logger.info("SMS Orange envoyé à %s.", telephone)
