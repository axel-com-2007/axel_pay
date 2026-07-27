# Changelog — Optimisation du backend `api`

Cette passe a porté sur le contenu de `api.zip` : `models.py`, `serializers.py`,
`views.py`, `urls.py` (inchangé). Chaque point ci-dessous a été vérifié en
relisant l'intégralité des ~1700 lignes concernées, pas en survol.

## 🔴 Bugs bloquants / critiques

### 1. `models.py` ne pouvait pas être importé par Python
Le fichier était encodé en **Latin-1** (probablement issu d'un `inspectdb`
exécuté sur une base configurée en `LATIN1`/`SQL_ASCII`) au lieu d'UTF-8.
Résultat concret :
```
SyntaxError: (unicode error) 'utf-8' codec can't decode byte 0xe9 ...
```
Toute tentative de `python manage.py runserver`, `makemigrations`, ou même
`import api.models` échouait immédiatement. **C'était le bug n°1 à corriger**,
avant même de parler de performance. Reconverti en UTF-8, `db_table_comment`
contient à nouveau du texte français lisible ("Référentiel des adresses…"
au lieu de "R�f�rentiel des adresses…").

### 2. `WebhookPaiementView` plantait sur les vrais retries de l'agrégateur
`id_evenement_agregateur` porte une contrainte `unique=True`. Le code
calculait `deja_traite` puis appelait `WebhookLogs.objects.create(...)` **sans
condition** — y compris quand l'évènement était un doublon. Un vrai retry de
l'agrégateur (le scénario exact que RG-09/idempotence est censé absorber)
provoquait une `IntegrityError` et un 500, au lieu de l'acquittement silencieux
attendu. Remplacé par `get_or_create()`.

### 3. La vérification OTP n'en était pas une
```python
otp_attendu = otp_saisi  # placeholder
if otp_saisi != otp_attendu:  # toujours faux, donc toujours "valide"
```
**N'importe quel code à 6 chiffres était accepté.** Remplacé par un vrai
stockage en cache (`django.core.cache`, TTL 5 min, usage unique) via
`generate_and_cache_otp()` / `verify_and_consume_otp()`. Ne dépend d'aucun
service externe (fonctionne avec le cache local de Django en dev).

### 4. Mots de passe stockés et comparés en clair, ET renvoyés par l'API
Deux problèmes cumulés :
- `LoginView` comparait `mot_de_passe == user.mot_de_passe` en clair.
- `UsersSerializer` avec `fields = '__all__'` renvoyait le champ
  `mot_de_passe` (donc le futur hash) dans **chaque** réponse utilisant ce
  serializer : Register, Login, Profile, ChangePhoneNumberView,
  AdminUserManagementView, ExportDataView.

Corrigé via :
- `hash_password()` / `verify_password()` (Argon2id via
  `django.contrib.auth.hashers`, repli automatique sur PBKDF2 si
  `argon2-cffi` n'est pas installé — voir `requirements.txt`).
- `UsersSerializer.Meta.extra_kwargs = {'mot_de_passe': {'write_only': True}}`
  — le champ reste utilisable en écriture (nécessaire à
  `AdminUserManagementView`) mais n'est plus jamais sérialisé en sortie.
- Même correctif appliqué par cohérence à `ComptesTechniquesSerializer.cle_api_hash`
  (non branché sur une vue actuellement, mais corrigé pour éviter la même
  fuite si un jour utilisé).
- `ChangePhoneNumberView` et `DeleteAccountView` vérifient maintenant le vrai
  mot de passe au lieu d'accepter toute valeur non vide.
- `AdminUserManagementView.perform_create` hache désormais le mot de passe
  fourni par l'admin avant sauvegarde (le serializer accepte le champ en
  écriture mais ne le hache pas lui-même).

**Recommandation projet (hors périmètre de ce fichier)** : ajouter dans
`settings.py` :
```python
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
]
```
pour qu'Argon2id soit réellement utilisé (CDC 11.1) plutôt que le repli PBKDF2.

## 🟠 Failles de contrôle d'accès

Plusieurs vues du module Compteurs/Prépayé ne vérifiaient pas que
l'utilisateur avait un droit actif sur le compteur/la facture demandée :

- `SignalerAnomalieFactureView.post` — aucune vérification (n'importe quel
  utilisateur authentifié pouvait ouvrir un litige sur une facture d'un autre
  client en devinant/énumérant son `id_facture`).
- `FactureStatutView.get` — même absence de vérification.
- `AlerteSoldeBasView.post` — aucune vérification (contrairement à son
  propre `get`, qui la faisait).

Les trois ont été corrigées avec le même helper `user_has_access_to_compteur()`
déjà utilisé ailleurs dans le fichier, pour rester cohérent.

## 🟡 Bug fonctionnel

`ConsommationGraphView` : son propre docstring annonce une série construite
"sur la base des factures (postpayé) et/ou des transactions de recharge
(prépayé) selon le type de compteur", mais le code ne lisait jamais que
`FacturesPostpayees` — un compteur prépayé recevait donc toujours une série
vide. Ajout de la branche manquante sur `compteur.type_compteur`.

`SoldeCreditView` : `.aggregate(total=None)` ne calculait rien (paramètre
invalide) et le résultat n'était de toute façon pas utilisé — la réponse
renvoyait des chaînes `"TODO_..."` en dur. Remplacé par un vrai
`.aggregate(total=Sum("valeur_kwh"))`, qui donne au moins le total de crédit
acheté (le calcul du solde *disponible*, qui suppose de connaître la
consommation réelle, reste un TODO légitime tant que l'IoT/API Eneo n'est pas
branché — on ne peut pas l'inventer côté backend).

## 🟢 Performance / bonnes pratiques

- **Nouveau helper `user_has_access_to_compteur(user, id_compteur)`** :
  remplace le motif répété (~8 occurrences) `int(id_compteur) not in
  list(get_delegated_compteur_ids(user))`, qui matérialisait toute la liste
  des compteurs accessibles en mémoire Python pour ne tester qu'une seule
  appartenance. Le nouveau helper traduit le contrôle en une requête SQL
  `EXISTS(...)` unique.
- **Pagination** (`pagination.py`, `StandardResultsSetPagination`, 20/page)
  ajoutée sur les listes potentiellement illimitées : `AuditLogsListView`,
  `WebhookLogsListView`, `TokenHistoriqueView`, `NotificationHistoriqueView`,
  `LitigeListView`, `FacturesListView`. Les tables Append-Only (RG-04, RG-09,
  RG-12) ne sont par construction jamais purgées : sans pagination, ces
  endpoints auraient fini par sérialiser des tables entières en une seule
  réponse.
- **`select_for_update()`** ajouté dans `AchatCreditView` (verrouille la ligne
  `Compteurs`) et `InitierPaiementView` (verrouille la ligne `Facture`/
  `TransactionPrepayee` référencée) : protection anti-double-dépense réelle
  en attendant le verrou distribué Redis (toujours `TODO INTEGRATION`, utile
  en environnement multi-instance).
- **`IsCompteTechnique`** : nouvelle classe de permission, remplace la
  vérification de rôle codée en dur dans `AlerteTechniqueCompteurView`, pour
  rester cohérent avec `IsAdminSupport`/`IsAdminFinancier`/
  `IsAdminTechnicien`/`IsAgentTerrain` déjà présentes.

## Ce qui reste volontairement en `TODO INTEGRATION`

Conformément à la note d'architecture du fichier d'origine, tout ce qui
dépend d'un service externe non fourni reste marqué comme tel : émission de
JWT réelle (nécessite un backend d'authentification custom + settings.py,
hors périmètre de ce zip), appel réel aux agrégateurs Mobile Money, appel
réel à l'API/IoT Eneo, envoi SMS/WhatsApp, verrou Redis distribué,
génération de PDF (WeasyPrint/ReportLab), calcul du taux de pénétration
client (donnée externe à Eneo).
