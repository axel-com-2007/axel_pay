# -*- coding: utf-8 -*-
"""
===============================================================================
 api/services/notchpay.py — Intégration de l'agrégateur Mobile Money NotchPay
===============================================================================
Branché sur `InitierPaiementView` (paiement d'une facture postpayée / achat
de crédit prépayé, CDC 9) et sur `NotchPayWebhookView` (confirmation
serveur-à-serveur, CDC 9.2).

⚠️ MODE SANDBOX DE TEST (settings.NOTCHPAY_SANDBOX_FORCER_MONTANT_ZERO) :
Quand ce flag est actif (c'est le cas par défaut avec des clés `pk_test.` /
`sk_test.`), `initialiser_paiement()` envoie toujours `amount = 0` à
NotchPay, quel que soit le montant métier réel (`montant_fcfa`) passé en
paramètre. Cela permet de dérouler tout le parcours de paiement (push USSD,
webhook, génération de jeton STS) en sandbox sans dépendre d'un solde de
test suffisant côté opérateur Mobile Money, tout en conservant le VRAI
montant dans `Paiements.montant_fcfa` côté application (RG-07/RG-08).

Corollaire indispensable pour que RG-08 reste correct en sandbox : la
vérification du montant reçu par webhook (`NotchPayWebhookView`) doit
comparer ce montant au montant RÉELLEMENT ENVOYÉ à l'agrégateur (0 en
sandbox), PAS au montant métier — sinon chaque webhook de test déclencherait
à tort une alerte de fraude (RG-08). C'est le rôle de `montant_attendu_agregateur()`
ci-dessous, utilisée par les deux vues.

⚠️ Ne JAMAIS activer ce comportement en production (clés `pk_live.` /
`sk_live.`) : le flag se désactive de lui-même dans ce cas (voir settings.py),
mais si vous le pilotez explicitement via la variable d'environnement
NOTCHPAY_SANDBOX_ZERO_FCFA, pensez à la repasser à `false`.
===============================================================================
"""

import hashlib
import hmac
import logging

import requests
from django.conf import settings

logger = logging.getLogger(__name__)

# Canaux Mobile Money supportés par NotchPay pour le "direct charge" (push
# USSD sans redirection navigateur) sur le Cameroun.
CANAL_PAR_OPERATEUR = {
    "MTN_MOMO": "cm.mtn",
    "ORANGE_MONEY": "cm.orange",
}


class NotchPayError(Exception):
    """Erreur remontée par l'API NotchPay ou par un problème réseau."""


def montant_attendu_agregateur(montant_fcfa) -> float:
    """
    Renvoie le montant qui a dû être envoyé à NotchPay pour un paiement de
    `montant_fcfa` FCFA côté métier — 0 en mode sandbox de test, sinon le
    montant réel. À utiliser à la fois lors de l'initialisation ET lors de
    la vérification du webhook, pour que les deux valeurs restent cohérentes
    (cf. note de module ci-dessus).
    """
    if getattr(settings, "NOTCHPAY_SANDBOX_FORCER_MONTANT_ZERO", False):
        return 0
    # CORRECTIF : NotchPay rejette (422 "Invalid amount. XAF accept 0
    # fraction number") tout montant XAF non entier. `float(montant_fcfa)`
    # sérialisait en JSON avec une décimale (ex: 5075.0), même quand la
    # valeur métier est un nombre entier de FCFA. On force donc un int.
    return round(float(montant_fcfa))


def initialiser_paiement(*, reference, montant_fcfa, email, telephone, operateur, description=""):
    """
    Initialise une transaction NotchPay puis déclenche le push USSD direct
    (`/payments/{reference}/actions`) sur le canal Mobile Money choisi.

    - `reference` : notre `Paiements.id_paiement`, transmis à NotchPay comme
      référence externe — permet de retrouver/vérifier la transaction sans
      avoir à stocker l'identifiant NotchPay en base (cf. `verifier_transaction`).
    - `montant_fcfa` : montant métier réel (RG-07). Le montant réellement
      envoyé à NotchPay est calculé par `montant_attendu_agregateur()`.

    Retourne un dict {montant_envoye_fcfa, reference, authorization_url, raw}.
    Lève `NotchPayError` en cas de refus de l'API ou de problème réseau —
    à charge de l'appelant de marquer le paiement "Échoué" en conséquence.
    """
    montant_envoye = montant_attendu_agregateur(montant_fcfa)

    headers = {
        "Authorization": settings.NOTCHPAY_PUBLIC_KEY,
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    payload = {
        "amount": montant_envoye,
        "currency": "XAF",
        "email": email,
        "phone": telephone,
        "reference": reference,
        "description": description or "Paiement Eneo",
        "callback": settings.NOTCHPAY_CALLBACK_URL,
    }

    try:
        resp = requests.post(
            f"{settings.NOTCHPAY_BASE_URL}/payments/initialize",
            json=payload,
            headers=headers,
            timeout=15,
        )
    except requests.RequestException as exc:
        raise NotchPayError(f"Erreur réseau lors de l'initialisation NotchPay : {exc}") from exc

    if resp.status_code >= 400:
        raise NotchPayError(f"NotchPay a refusé l'initialisation ({resp.status_code}) : {resp.text}")

    data = resp.json()
    transaction_data = data.get("transaction") or data.get("data") or data

    # Déclenchement du push USSD direct sur le canal Mobile Money choisi,
    # pour éviter une redirection navigateur (le CDC 9.1 décrit un push USSD
    # direct, pas un checkout hébergé). Un échec ici n'est PAS bloquant :
    # NotchPay peut aussi router automatiquement selon le numéro fourni, et
    # `authorization_url` reste un filet de secours utilisable côté client
    # si le direct-charge n'est pas disponible pour ce canal/pays.
    canal = CANAL_PAR_OPERATEUR.get(operateur)
    if canal:
        try:
            requests.post(
                f"{settings.NOTCHPAY_BASE_URL}/payments/{reference}/actions",
                json={"channel": canal, "phone": telephone},
                headers=headers,
                timeout=15,
            )
        except requests.RequestException as exc:
            logger.warning("Échec du direct-charge NotchPay (reference=%s) : %s", reference, exc)

    return {
        "montant_envoye_fcfa": montant_envoye,
        "reference": reference,
        "authorization_url": transaction_data.get("authorization_url"),
        "raw": data,
    }


def verifier_transaction(reference: str) -> dict:
    """Interroge NotchPay pour connaître le statut réel d'une transaction (fallback si le webhook n'arrive jamais)."""
    headers = {"Authorization": settings.NOTCHPAY_PRIVATE_KEY, "Accept": "application/json"}
    try:
        resp = requests.get(
            f"{settings.NOTCHPAY_BASE_URL}/payments/{reference}",
            headers=headers,
            timeout=15,
        )
    except requests.RequestException as exc:
        raise NotchPayError(f"Erreur réseau lors de la vérification NotchPay : {exc}") from exc
    if resp.status_code >= 400:
        raise NotchPayError(f"Vérification NotchPay échouée ({resp.status_code}) : {resp.text}")
    return resp.json()


def verifier_signature_webhook(corps_brut: bytes, signature_recue: str) -> bool:
    """
    Vérifie la signature HMAC-SHA256 d'un webhook NotchPay (en-tête
    `x-notchpay-signature`) à partir du corps BRUT de la requête (pas du
    JSON re-sérialisé, qui ne matcherait pas forcément octet pour octet) et
    de la clé de hachage NotchPay (CDC 9.2). Comparaison à temps constant
    pour éviter une attaque par timing (même précaution que pour l'OTP et le
    webhook générique existant).
    """
    if not signature_recue:
        return False
    secret = getattr(settings, "NOTCHPAY_HASH_KEY", None)
    if not secret:
        return False
    signature_attendue = hmac.new(
        key=secret.encode("utf-8"),
        msg=corps_brut,
        digestmod=hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(signature_attendue, signature_recue)