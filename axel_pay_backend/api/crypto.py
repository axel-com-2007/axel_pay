# -*- coding: utf-8 -*-
"""
===============================================================================
 crypto.py — Chiffrement applicatif du jeton de recharge STS (CDC 5.3/9,
 point 1 de l'audit du 24/07/2026).
===============================================================================
Avant ce correctif, `WebhookPaiementView._finaliser_recharge` stockait le
jeton STS à 20 chiffres EN CLAIR dans `TransactionsPrepayees.token_genere`
(commentaire "placeholder — chiffrer en prod"). Le jeton STS est une donnée
directement monétisable (quiconque le lit peut créditer un compteur) : une
fuite de la base (dump, requête non autorisée, sauvegarde mal protégée...)
exposait donc tous les jetons délivrés.

Ce module fournit :
    - `encrypt_token(valeur_claire)`  : chiffre une chaîne avant écriture en
      base (`tx.token_genere = encrypt_token(token)`).
    - `decrypt_token(valeur_chiffree)`: déchiffre pour réaffichage au client
      (utilisé par `TransactionsPrepayeesSerializer`, donc par
      `TokenHistoriqueView` et par tout endroit qui sérialise une
      transaction prépayée, ex: `AchatCreditView`, `ExportDataView`).

Algorithme : AES-256-GCM (chiffrement authentifié — hazmat, PAS Fernet, dont
le mode interne est AES-128-CBC + HMAC : la CDC demande explicitement de
l'AES-256). La clé de 32 octets (256 bits) est lue depuis
`settings.TOKEN_ENCRYPTION_KEY` (jamais codée en dur ici) ; voir settings.py
pour la provenance de cette clé (variable d'environnement en production).

Chaque appel à `encrypt_token` génère un nonce (IV) aléatoire de 12 octets,
concaténé au ciphertext puis encodé en base64 urlsafe : c'est cette chaîne
unique qui est stockée. Un nonce différent à chaque chiffrement est
indispensable en mode GCM (rejouer le même nonce avec la même clé casse les
garanties d'authenticité/confidentialité du mode).
"""

import base64
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from django.conf import settings

_NONCE_SIZE = 12  # 96 bits, taille recommandée pour AES-GCM


def _get_key_bytes():
    """
    Récupère et valide la clé AES-256 (32 octets) depuis les settings.
    Accepte soit des octets bruts (32 octets exactement), soit une chaîne
    encodée en base64 standard qui décode vers 32 octets — pour rester
    tolérant sur la façon dont l'opérateur a configuré la variable
    d'environnement.
    """
    key = getattr(settings, "TOKEN_ENCRYPTION_KEY", None)
    if not key:
        raise RuntimeError(
            "settings.TOKEN_ENCRYPTION_KEY n'est pas configurée : impossible "
            "de chiffrer/déchiffrer un jeton STS. Définissez la variable "
            "d'environnement TOKEN_ENCRYPTION_KEY (32 octets encodés en "
            "base64) avant de démarrer l'application en production."
        )
    if isinstance(key, str):
        key = key.encode("utf-8")
    if len(key) != 32:
        try:
            decode_tentative = base64.b64decode(key, validate=True)
        except Exception:
            decode_tentative = None
        if decode_tentative and len(decode_tentative) == 32:
            key = decode_tentative
    if len(key) != 32:
        raise RuntimeError(
            "TOKEN_ENCRYPTION_KEY doit représenter exactement 32 octets "
            "(256 bits) pour de l'AES-256, après décodage éventuel en base64."
        )
    return key


def encrypt_token(valeur_claire):
    """
    Chiffre `valeur_claire` (le jeton STS en clair) avec AES-256-GCM et
    renvoie une chaîne base64 urlsafe (nonce || ciphertext || tag) prête à
    être stockée dans `TransactionsPrepayees.token_genere`.
    Renvoie None si `valeur_claire` est None (pas de jeton à chiffrer).
    """
    if valeur_claire is None:
        return None
    cle = _get_key_bytes()
    aesgcm = AESGCM(cle)
    nonce = os.urandom(_NONCE_SIZE)
    ciphertext = aesgcm.encrypt(nonce, str(valeur_claire).encode("utf-8"), None)
    return base64.urlsafe_b64encode(nonce + ciphertext).decode("utf-8")


def decrypt_token(valeur_chiffree):
    """
    Déchiffre une valeur produite par `encrypt_token`. Renvoie None si
    `valeur_chiffree` est vide, ou si le déchiffrement échoue (mauvaise clé,
    donnée corrompue, tag d'authentification invalide) — on ne lève jamais
    d'exception ici : c'est à l'appelant (le serializer) de décider quoi
    afficher en repli (cf. TransactionsPrepayeesSerializer.get_token_genere).
    """
    if not valeur_chiffree:
        return None
    cle = _get_key_bytes()
    aesgcm = AESGCM(cle)
    try:
        brut = base64.urlsafe_b64decode(str(valeur_chiffree).encode("utf-8"))
        nonce, ciphertext = brut[:_NONCE_SIZE], brut[_NONCE_SIZE:]
        clair = aesgcm.decrypt(nonce, ciphertext, None)
        return clair.decode("utf-8")
    except Exception:
        return None
