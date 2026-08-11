# -*- coding: utf-8 -*-
"""
===============================================================================
 api/services/ai_support.py — Assistant de support IA (écran "Assistance")
===============================================================================
Branché sur `SupportChatView` (MODULE 10 de `views.py`), lui-même appelé
depuis l'écran "Écrire un message" de `support_screen.dart`.

Appel HTTP direct à l'API Google Gemini via `requests` : aucun SDK
supplémentaire requis pour un appel synchrone simple.

⚠️ Clé API : `GEMINI_API_KEY` doit être définie dans l'environnement
(.env, jamais commitée — même convention que `MOBILE_MONEY_WEBHOOK_SECRET`
dans settings.py). Sans elle, `repondre()` lève `AiSupportError`
immédiatement.

⚠️ Périmètre volontairement limité : cet assistant RÉPOND à des questions
à partir du contexte du client (lecture seule), il n'exécute jamais
d'action (pas de paiement, remboursement, ouverture/résolution de litige).
Ces actions restent exclusivement du ressort des vues dédiées.
===============================================================================
"""

import logging

import requests
from django.conf import settings

logger = logging.getLogger(__name__)

# Utilisation du modèle rapide et performant Gemini 2.5 Flash
MODELE_GEMINI = "gemini-3.5-flash"
GEMINI_API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODELE_GEMINI}:generateContent"
MAX_TOKENS_REPONSE = 600

# Balise que l'IA doit ajouter en fin de réponse quand la situation dépasse
# ce qu'un assistant automatique peut résoudre (retirée avant renvoi au client).
BALISE_ESCALADE = "[ESCALADE]"


class AiSupportError(Exception):
    """Clé API absente, erreur réseau, ou refus de l'API Gemini."""


def _construire_prompt_systeme(contexte: dict) -> str:
    """
    Construit le prompt système à partir du contexte RÉEL du client
    connecté (cf. `_construire_contexte_support` dans views.py).
    """
    contrats = contexte.get("contrats") or []
    contrats_txt = "\n".join(
        f"  - Contrat {c['numero']} (statut : {c['statut']})" for c in contrats
    ) or "  - Aucun contrat rattaché à ce compte."

    litiges = contexte.get("litiges_ouverts") or []
    litiges_txt = "\n".join(
        f"  - {l['id']} (niveau {l['niveau']}, statut {l['statut']}) : {l['description']}"
        for l in litiges
    ) or "  - Aucun litige ouvert actuellement."

    return (
        "Tu es l'assistant de support client d'Eneo (distributeur d'électricité "
        "au Cameroun), intégré à l'application mobile de gestion de contrats, "
        "factures et recharges prépayées. Réponds toujours en français, de "
        "façon brève, concrète et rassurante.\n\n"
        "Dossier du client actuellement connecté (base-toi UNIQUEMENT sur ces "
        "informations réelles ; ne devine et n'invente jamais un numéro, un "
        "montant ou un statut qui n'y figure pas) :\n"
        f"- Prénom : {contexte.get('prenom') or 'Client'}\n"
        "- Contrats :\n"
        f"{contrats_txt}\n"
        f"- Factures impayées : {contexte.get('nombre_factures_impayees', 0)} "
        f"(total {contexte.get('total_impaye_fcfa', 0):.0f} FCFA)\n"
        "- Litiges en cours :\n"
        f"{litiges_txt}\n\n"
        "Règles impératives :\n"
        "- Ne révèle et ne devine jamais un mot de passe, un jeton de recharge "
        "complet, ou un numéro Mobile Money.\n"
        "- Tu ne peux TOI-MÊME initier aucun paiement, remboursement, ni "
        "ouvrir/résoudre un litige : oriente le client vers l'écran "
        "correspondant de l'application, ou vers un agent humain si la "
        "situation le dépasse.\n"
        "- Si la demande nécessite une action humaine (remboursement contesté, "
        "fraude suspectée, situation non couverte par le dossier ci-dessus), "
        f"termine IMPÉRATIVEMENT ta réponse par la balise {BALISE_ESCALADE} "
        "seule sur sa propre ligne, après ta réponse au client."
    )


def _convertir_messages_pour_gemini(messages: list) -> list:
    """
    Convertit la liste de messages de l'application au format attendu par Gemini :
    - 'user' reste 'user'
    - 'assistant' devient 'model'
    - le texte est placé dans la structure [{'text': ...}]
    """
    contents_gemini = []
    for msg in messages:
        role = "model" if msg.get("role") == "assistant" else "user"
        contents_gemini.append({
            "role": role,
            "parts": [{"text": msg.get("content", "")}]
        })
    return contents_gemini


def repondre(messages: list, contexte: dict):
    """
    Envoie l'historique `messages` à l'API Gemini avec le prompt système
    construit à partir de `contexte`.

    Retourne un tuple `(texte_reponse, escalade_recommandee)`.
    Lève `AiSupportError` si la clé API n'est pas configurée, si l'appel
    réseau échoue, ou si l'API refuse la requête.
    """
    cle_api = getattr(settings, "GEMINI_API_KEY", None)

    if not cle_api:
        raise AiSupportError("GEMINI_API_KEY non configurée côté serveur.")

    payload = {
        "system_instruction": {
            "parts": [{"text": _construire_prompt_systeme(contexte)}]
        },
        "contents": _convertir_messages_pour_gemini(messages),
        "generationConfig": {
            "maxOutputTokens": MAX_TOKENS_REPONSE,
            "temperature": 0.3,
        }
    }

    headers = {
        "Content-Type": "application/json",
        "x-goog-api-key": cle_api,
    }

    try:
        resp = requests.post(
            GEMINI_API_URL,
            json=payload,
            headers=headers,
            timeout=30,
        )
    except requests.RequestException as exc:
        raise AiSupportError(
            f"Erreur réseau lors de l'appel à l'assistant IA : {exc}"
        ) from exc

    if resp.status_code >= 400:
        raise AiSupportError(
            f"L'API Gemini a refusé la requête ({resp.status_code}) : {resp.text}"
        )

    data = resp.json()

    try:
        candidates = data.get("candidates", [])

        if not candidates:
            raise AiSupportError(
                "Aucun candidat de réponse renvoyé par Gemini."
            )

        parts = candidates[0].get("content", {}).get("parts", [])

        texte = "".join(
            part.get("text", "")
            for part in parts
        ).strip()

    except (IndexError, AttributeError) as exc:
        raise AiSupportError(
            f"Format de réponse Gemini inattendu : {data}"
        ) from exc

    escalade_recommandee = BALISE_ESCALADE in texte

    if escalade_recommandee:
        texte = texte.replace(BALISE_ESCALADE, "").strip()

    if not texte:
        raise AiSupportError(
            "Réponse vide de l'API Gemini."
        )

    return texte, escalade_recommandee