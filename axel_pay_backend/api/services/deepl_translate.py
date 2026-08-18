# -*- coding: utf-8 -*-
"""
===============================================================================
 api/services/deepl_translate.py — Traduction FR→EN via DeepL (i18n Flutter)
===============================================================================
Utilisé par `TraduireTextesView` (api/views.py) uniquement. La clé DeepL
(`settings.DEEPL_API_KEY`) ne quitte JAMAIS le serveur : l'app Flutter
n'appelle que `/api/i18n/traduire/`, jamais l'API DeepL directement — c'est
le principal intérêt de ce module (cf. demande "sécurise la clé API" :
une clé embarquée dans l'APK Flutter serait extractible par simple
décompilation, une clé côté Django ne l'est pas).

Deux niveaux de cache pour limiter le volume d'appels facturés par DeepL :
  1. Côté Flutter (voir lib/l10n/translation_controller.dart) : cache
     persistant sur le téléphone, c'est le niveau qui compte le plus
     (chaque phrase n'est traduite QU'UNE SEULE FOIS par installation).
  2. Ici, `django.core.cache` (niveau processus, LocMemCache par défaut,
     donc perdu au redémarrage du serveur — volontairement minimal) :
     évite de payer deux fois la même traduction si deux utilisateurs
     différents déclenchent la même chaîne avant d'avoir leur propre
     cache local (ex: juste après une mise à jour de l'app qui ajoute une
     nouvelle chaîne). Pour une vraie persistance multi-redémarrage,
     remplacer par un cache Redis/Memcached configuré dans CACHES, ou un
     modèle Django dédié — hors périmètre ici.
===============================================================================
"""

import hashlib
import logging

import requests
from django.conf import settings
from django.core.cache import cache

logger = logging.getLogger(__name__)

# DeepL limite la taille d'un lot ; on borne aussi côté vue (voir views.py)
# mais on re-vérifie ici en dernier rempart si ce module est appelé
# directement (tests, script de migration...).
MAX_TEXTES_PAR_LOT = 200

# Durée de cache serveur (secondes) — 30 jours : les chaînes de l'app
# changent rarement plus vite que ça, et le cache Flutter prend de toute
# façon le relais dès le premier appel réussi sur chaque appareil.
CACHE_TTL_SECONDES = 60 * 60 * 24 * 30


class DeepLError(Exception):
    """Erreur de traduction (clé absente, DeepL indisponible, quota...)."""


def _cache_key(texte: str, langue_cible: str) -> str:
    # Hash plutôt que le texte brut en clé : évite tout souci de longueur
    # de clé / caractères spéciaux avec le backend de cache configuré.
    empreinte = hashlib.sha256(texte.encode("utf-8")).hexdigest()
    return f"deepl:{langue_cible.lower()}:{empreinte}"


def traduire(textes: list[str], langue_cible: str = "EN") -> list[str]:
    """
    Traduit une liste de textes source (français) vers `langue_cible`
    ("EN" ou "FR"), dans l'ordre, en réutilisant le cache serveur pour
    les textes déjà vus et en n'appelant DeepL que pour le reste.

    Lève `DeepLError` si la clé n'est pas configurée ou si l'appel DeepL
    échoue (réseau, quota dépassé, réponse invalide).
    """
    if not textes:
        return []
    if len(textes) > MAX_TEXTES_PAR_LOT:
        raise DeepLError(
            f"Lot de {len(textes)} textes trop volumineux (max {MAX_TEXTES_PAR_LOT})."
        )
    if not settings.DEEPL_API_KEY:
        raise DeepLError(
            "DEEPL_API_KEY non configurée côté serveur (voir .env / SETUP)."
        )

    resultats: list[str | None] = [None] * len(textes)
    a_traduire: list[tuple[int, str]] = []  # (index dans `textes`, texte)

    for i, texte in enumerate(textes):
        if not texte or not texte.strip():
            resultats[i] = texte
            continue
        cached = cache.get(_cache_key(texte, langue_cible))
        if cached is not None:
            resultats[i] = cached
        else:
            a_traduire.append((i, texte))

    if a_traduire:
        try:
            response = requests.post(
                settings.DEEPL_API_URL,
                headers={"Authorization": f"DeepL-Auth-Key {settings.DEEPL_API_KEY}"},
                data={
                    "text": [texte for _, texte in a_traduire],
                    "target_lang": langue_cible,
                    "source_lang": "FR",
                    # Préserve la structure des chaînes techniques (ex:
                    # interpolations Flutter déjà résolues côté client
                    # avant l'appel, donc pas de balises ici) — DeepL gère
                    # nativement la ponctuation/majuscules françaises.
                    "preserve_formatting": "1",
                },
                timeout=10,
            )
        except requests.RequestException as exc:
            logger.warning("DeepL indisponible : %s", exc)
            raise DeepLError(f"Impossible de joindre DeepL : {exc}") from exc

        if response.status_code != 200:
            logger.warning(
                "DeepL a répondu %s : %s", response.status_code, response.text[:300]
            )
            raise DeepLError(
                f"DeepL a répondu {response.status_code} (quota dépassé, clé "
                "invalide, ou requête malformée)."
            )

        try:
            traductions = response.json()["translations"]
        except (KeyError, ValueError) as exc:
            raise DeepLError(f"Réponse DeepL inattendue : {exc}") from exc

        if len(traductions) != len(a_traduire):
            raise DeepLError("Réponse DeepL incohérente (nombre de traductions).")

        for (index, texte_source), traduction in zip(a_traduire, traductions):
            texte_traduit = traduction["text"]
            resultats[index] = texte_traduit
            cache.set(
                _cache_key(texte_source, langue_cible),
                texte_traduit,
                CACHE_TTL_SECONDES,
            )

    return resultats  # type: ignore[return-value]
