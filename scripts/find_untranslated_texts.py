#!/usr/bin/env python3
"""
find_untranslated_texts.py — repère les `Text('...')` / `Text("...")`
probablement en français en dur, pas encore migrés vers `S.of(context)`
(voir lib/l10n/app_strings.dart et I18N_DEEPL.md).

Usage :
    python3 scripts/find_untranslated_texts.py [dossier_lib]

Par défaut, scanne `lib/`. Affiche, par fichier, chaque ligne contenant un
`Text(` (ou `label:`, `hintText:`, `title:`... — voir PARAM_KEYS) suivi
directement d'une chaîne littérale, TRIÉ pour mettre en haut les fichiers
avec le plus d'occurrences (les écrans "gros morceaux" à migrer en
premier).

Limites volontaires (c'est un outil de REPÉRAGE, pas un migrateur
automatique — une regex ne comprend pas le contexte Dart) :
  - Ignore les chaînes qui ressemblent à des clés techniques, des URLs,
    des chemins d'assets, ou qui ne contiennent aucune lettre accentuée
    ni mot français courant : beaucoup de faux positifs resteraient sinon
    (noms de variables, valeurs d'enum, styles...).
  - Ne modifie AUCUN fichier. Toute migration reste une édition manuelle
    (ajouter le getter dans app_strings.dart, remplacer le Text() dans
    l'écran) — c'est un choix délibéré : une chaîne envoyée telle quelle
    au backend (ex: valeurs d'enum comme `situationMatrimoniale`) ne doit
    JAMAIS être traduite, seul un humain peut le distinguer de manière
    fiable.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Mots/particules français courants : sert uniquement à FILTRER le bruit
# (variables anglaises, valeurs techniques...), pas à décider quoi migrer.
FR_HINTS = re.compile(
    r"\b(le|la|les|un|une|des|du|de|et|ou|est|vous|votre|mon|ma|mes|"
    r"votre|nos|pour|avec|dans|sur|par|ce|cette|ces|au|aux|à|"
    r"veuillez|merci|erreur|compte|numéro|téléphone|adresse|mot de passe)\b",
    re.IGNORECASE,
)
ACCENTS = re.compile(r"[àâäéèêëïîôöùûüçÀÂÄÉÈÊËÏÎÔÖÙÛÜÇ]")

STRING_LITERAL = re.compile(r"""(['"])((?:(?!\1).)*)\1""")

# Lignes à ignorer d'office (imports, commentaires, styles, assets...).
IGNORE_LINE = re.compile(
    r"^\s*(//|import |part |package:|assets/|http)", re.IGNORECASE
)

TARGET_KEYS = ("Text(", "label:", "hintText:", "title:", "content:", "labelText:")


def looks_french(text: str) -> bool:
    if len(text) < 3:
        return False
    if ACCENTS.search(text):
        return True
    if FR_HINTS.search(text):
        return True
    return False


def scan_file(path: Path) -> list[tuple[int, str]]:
    hits: list[tuple[int, str]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return hits

    for i, line in enumerate(lines, start=1):
        if IGNORE_LINE.match(line):
            continue
        if "S.of(context)" in line or "S.read(context)" in line:
            continue  # déjà migrée sur cette ligne
        if not any(key in line for key in TARGET_KEYS):
            continue
        for _, content in STRING_LITERAL.findall(line):
            if looks_french(content):
                hits.append((i, line.strip()))
                break
    return hits


def main() -> None:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("lib")
    if not root.exists():
        print(f"Dossier introuvable : {root}", file=sys.stderr)
        sys.exit(1)

    results: dict[Path, list[tuple[int, str]]] = {}
    for path in sorted(root.rglob("*.dart")):
        hits = scan_file(path)
        if hits:
            results[path] = hits

    if not results:
        print("Aucune chaîne française en dur détectée (ou tout est déjà migré). 🎉")
        return

    total = sum(len(v) for v in results.values())
    print(f"{total} occurrence(s) probable(s) dans {len(results)} fichier(s) :\n")

    for path, hits in sorted(results.items(), key=lambda kv: -len(kv[1])):
        print(f"── {path} ({len(hits)}) " + "─" * max(0, 40 - len(str(path))))
        for line_no, content in hits:
            snippet = content if len(content) <= 100 else content[:97] + "..."
            print(f"   L{line_no:>4}: {snippet}")
        print()


if __name__ == "__main__":
    main()
