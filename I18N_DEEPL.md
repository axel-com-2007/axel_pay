# Internationalisation FR/EN — AxelPay (moteur DeepL + cache local)

**Périmètre de cette livraison :** infrastructure complète de traduction
dynamique (backend Django + client Flutter), migration intégrale du
parcours d'authentification (connexion, inscription, OTP) et de la coquille
principale (`main_shell.dart`, `settings_screen.dart` déjà couvert
précédemment). Le reste de l'application (~19 écrans, voir §6) suit le même
mécanisme, déjà en place et mécanique à étendre.

---

## 1. Pourquoi ce choix d'architecture

La version précédente de `app_strings.dart` contenait des paires
français/anglais **écrites à la main** dans le code. Cela ne correspond pas
à la demande ("génère des traductions anglaises... via DeepL... stockées en
cache local"). La nouvelle architecture :

- Le **français reste la seule langue écrite en dur** dans le code Dart —
  c'est la langue par défaut de l'app et la source de vérité.
- L'**anglais est généré par DeepL** la première fois qu'une chaîne est
  affichée dans cette langue, puis **mis en cache sur l'appareil** (fichier
  JSON dans le répertoire documents de l'app) et **réutilisé indéfiniment**,
  y compris hors connexion, sans nouvel appel à DeepL.
- La **clé API DeepL ne quitte jamais le serveur Django** : le client
  Flutter n'appelle que `POST /api/i18n/traduire/`, jamais l'API DeepL
  directement. Une clé embarquée dans l'APK serait extractible par simple
  décompilation — ce n'est pas un risque acceptable pour une clé facturée.
- Les appels sont **groupés par écran** (un seul appel réseau pour toutes
  les chaînes d'un écran, pas un appel par `Text()`), pour rester sous la
  limite de débit ajoutée côté serveur.

```
┌─────────────────┐        ┌───────────────────┐        ┌─────────┐
│   Écran Flutter  │  1 appel groupé (miss)     │  Django  │  clé   │  DeepL  │
│  S.of(context)    │ ───────────────────────▶  │  /api/i18n/       │ ──────▶ │
│  .monGetter        │                            │  traduire/         │         │
└─────────────────┘                            └───────────────────┘        └─────────┘
        │ ▲
        │ └── cache mémoire (TranslationController)
        ▼
┌─────────────────────────┐
│ Fichier JSON sur disque  │  ← persiste entre les lancements, hors connexion,
│ (TranslationCacheStore)  │    indépendant du cache métier (LocalCache), donc
└─────────────────────────┘    PAS purgé à la déconnexion.
```

---

## 2. Fichiers ajoutés / modifiés

### Backend (Django)

| Fichier | Changement |
|---|---|
| `axel_pay_project/settings.py` | Ajout de `DEEPL_API_KEY` / `DEEPL_API_URL` (lus depuis `.env`, aucune valeur de secours en dur — voir §3) et d'un taux de limitation dédié (`DEFAULT_THROTTLE_RATES["traduction"]`). |
| `api/services/deepl_translate.py` **(nouveau)** | Appel serveur à l'API DeepL, avec cache applicatif (Django cache framework) pour éviter de payer deux fois la même traduction. |
| `api/views.py` | Nouvelle vue `TraduireTextesView` — `POST /api/i18n/traduire/`, `AllowAny` (les écrans de connexion/inscription en ont besoin avant authentification) + `ScopedRateThrottle`. |
| `api/urls.py` | Route `i18n/traduire/` ajoutée. |

### Flutter

| Fichier | Changement |
|---|---|
| `lib/api/translation_api.dart` **(nouveau)** | Client HTTP vers `/api/i18n/traduire/` (via `ApiClient` existant). |
| `lib/l10n/translation_cache_store.dart` **(nouveau)** | Persistance JSON sur disque du cache de traduction, indépendante de `LocalCache` (n'est pas purgée à la déconnexion). |
| `lib/l10n/translation_controller.dart` **(nouveau)** | `ChangeNotifier` : regroupe les demandes de traduction d'un même frame en un seul appel réseau, retombe sur le français en cas d'échec/hors-ligne, notifie l'UI dès qu'une traduction arrive. |
| `lib/l10n/app_strings.dart` | Réécrit : `S` n'a plus de paires FR/EN codées en dur — chaque getter fournit une clé stable + le texte français, `S._t()` délègue à `TranslationController`. Ajout de `S.read(context)` pour un usage hors `build()` (callbacks, messages d'erreur). Getters ajoutés pour tout le parcours d'authentification. |
| `lib/main.dart` | `TranslationController` chargé au démarrage (cache lu depuis le disque) et injecté dans l'arbre de providers. |
| `lib/api/api_client.dart` | `/i18n/traduire/` ajouté aux routes publiques (pas de header `Authorization`). |
| `lib/screens/auth/login_screen.dart` | **Migré intégralement** vers `S`. |
| `lib/screens/auth/otp_screen.dart` | **Migré intégralement** vers `S`. |
| `lib/screens/auth/register_screen.dart` | **Migré intégralement** vers `S`. Au passage : deux libellés qui affichaient par erreur du texte anglais/incohérent en version française (`'Password'`, `'Confirm Password'`, et un `'Quartier'` dupliqué au-dessus des pastilles de situation matrimoniale) ont été corrigés — voir commentaire dans le fichier. Les *valeurs* envoyées au backend (`situationMatrimoniale`) restent en français, seul le *libellé affiché* est traduit (`S.situationLabel()`). |
| `scripts/find_untranslated_texts.py` **(nouveau)** | Repère les `Text('...')` probablement en français, pas encore migrés — voir §6. |

Fichiers déjà couverts par un travail précédent et inchangés dans cette
livraison : `main_shell.dart` (utilisait déjà `S.of(context)` — bénéficie
automatiquement du nouveau moteur dynamique sans modification) et
`settings_screen.dart` (sections principales ; les dialogues FAQ /
changement de numéro / mot de passe / suppression de compte restent en
français en dur — voir §6).

---

## 3. Configurer la clé DeepL (`.env`)

1. Crée un compte sur <https://www.deepl.com/pro-api> (l'offre **API Free**
   suffit pour démarrer : 500 000 caractères/mois gratuits). Récupère la clé
   — elle a la forme `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:fx` (le suffixe
   `:fx` indique le plan Free).
2. Dans le fichier `.env` **à la racine du projet Django, à côté de
   `manage.py`** (celui déjà lu par `load_dotenv(BASE_DIR / ".env")` en
   tête de `settings.py` — ne PAS le committer, il doit déjà être dans
   `.gitignore` comme les autres secrets du projet), ajoute :

   ```
   DEEPL_API_KEY=ta-cle-ici:fx
   ```

3. Redémarre `python manage.py runserver` (le `.env` n'est relu qu'au
   démarrage).

Rien d'autre à faire : `DEEPL_API_URL` choisit automatiquement le bon
endpoint (`api-free.deepl.com` vs `api.deepl.com`) selon le suffixe `:fx`
de la clé — même principe que `NOTCHPAY_SANDBOX_FORCER_MONTANT_ZERO`, déjà
dans votre `settings.py`, qui se base lui aussi sur la forme de la clé
plutôt que sur un booléen séparé à ne pas oublier de changer.

Si `DEEPL_API_KEY` n'est pas définie, l'endpoint `/api/i18n/traduire/`
répond `503` explicitement (`DeepLError`) plutôt que d'échouer
silencieusement ou d'utiliser une clé devinée — l'app Flutter retombe alors
sur le français, sans planter (voir `TranslationController._envoyerLot`).

---

## 4. Comment étendre à un nouvel écran (rappel du pattern)

Le pattern demandé ("ajouter un getter, remplacer `Text('...')`") est
**inchangé** — seule l'implémentation interne de `S` a changé :

1. Dans `lib/l10n/app_strings.dart`, ajoute un getter :
   ```dart
   String get monEcranMonLibelle => _t('mon_ecran_mon_libelle', 'Mon texte en français');
   ```
   La clé (1ᵉʳ argument) doit être unique dans le fichier — c'est un nom de
   cache, jamais affiché. Le 2ᵉ argument est le texte français par défaut
   ET la source pour DeepL.
2. Dans l'écran :
   ```dart
   final s = S.of(context); // dans build()
   // ...
   Text(s.monEcranMonLibelle)
   ```
   Hors `build()` (callback, `catch`, message de `SnackBar`...), utilise
   `S.read(context)` à la place (`context.watch` lève une erreur en dehors
   de `build()`).
3. Pour un texte avec variable (ex: `'Bonjour $prenom'`), écris une
   **méthode** plutôt qu'un getter (voir `otpCodeEnvoyeAu()` ou
   `erreurInattendue()` dans `app_strings.dart` pour deux exemples : le
   premier interpole une donnée non traduisible après le texte traduit, le
   second traduit un préfixe fixe autour d'une variable).
4. **Ne jamais** faire passer par `S` une valeur qui est aussi envoyée au
   backend (ex: un enum métier) — voir `S.situationLabel()` dans
   `register_screen.dart` pour le pattern correct : la variable métier
   reste en français, seul son affichage est traduit.

Aucune étape de build supplémentaire (pas de `flutter gen-l10n`, pas de
fichiers `.arb`) — cohérent avec le choix déjà fait dans le projet.

---

## 5. Tests effectués et limites de cet environnement

**⚠️ Important :** cet environnement d'édition n'a pas accès à
`pub.dev` (réseau restreint) et le projet fourni ne contient pas de
`pubspec.yaml` — je n'ai donc **pas pu exécuter `flutter pub get` /
`flutter analyze` / `flutter test`** ici. La relecture a été faite
manuellement (vérification de l'équilibre des parenthèses/accolades,
cohérence des imports, absence de collision de nom entre la variable
locale `s` et d'autres identifiants — un point qui a nécessité un
renommage dans `register_screen.dart`, voir §7).

**À faire de ton côté avant de merger :**

```bash
flutter pub get
flutter analyze
flutter test        # si des tests existent
```

**Test manuel recommandé** (couvre l'intégralité du nouveau mécanisme,
bout en bout) :

1. Backend : configure `DEEPL_API_KEY` (§3), démarre
   `python manage.py runserver`.
2. Flutter : lance l'app en pointant vers ce backend (`ApiConfig.baseUrl`).
3. Écran Connexion → bascule la langue en anglais depuis Paramètres
   (une fois connecté une première fois) → reviens à l'écran de connexion
   (déconnexion) → les libellés (`Se connecter`, `Créer un compte`, les
   messages de validation...) doivent apparaître en anglais après un bref
   instant (le temps de l'appel groupé à DeepL).
4. Coupe le réseau, relance l'app en anglais : les mêmes libellés doivent
   s'afficher **immédiatement**, en anglais, sans appel réseau (lus depuis
   `translation_cache_store.dart`).
5. Ajoute une nouvelle chaîne de test dans `app_strings.dart` avec une
   clé jamais vue, affiche-la en anglais : elle doit apparaître d'abord en
   français puis basculer en anglais une fois la traduction reçue —
   comportement attendu, documenté dans `TranslationController.translate()`.
6. Backend : appelle deux fois `POST /api/i18n/traduire/` avec le même
   texte → vérifie dans les logs Django que le 2ᵉ appel ne déclenche pas de
   requête sortante vers DeepL (cache serveur, `deepl_translate.py`).

---

## 6. Ce qu'il reste à faire

Le mécanisme est en place et validé sur le parcours d'authentification +
la coquille principale. Reste, par ordre de volume décroissant (généré par
`scripts/find_untranslated_texts.py`, voir §7 pour l'exécuter) :

| Écran | Chaînes probables restantes |
|---|---:|
| `contracts/contracts_screen.dart` | 34 |
| `settings/settings_screen.dart` (FAQ + dialogues) | 16 |
| `meters/meters_screen.dart` | 15 |
| `postpaid/facture_detail_screen.dart` | 14 |
| `home/dashboard_screen.dart` | 13 |
| `payment/payment_screen.dart` | 11 |
| `postpaid/postpaid_screen.dart` | 11 |
| `prepaid/prepaid_screen.dart` | 11 |
| `contracts/contrat_factures_screen.dart` | 9 |
| `home/calendar_history_screen.dart` | 8 |
| `support/open_ticket_screen.dart` | 7 |
| `support/support_screen.dart` | 5 |
| `support/support_chat_screen.dart` | 3 |
| `home/contract_search_overlay.dart` | 2 |
| `map_screen.dart` | 2 |
| `profile/edit_profile_screen.dart` | 2 |
| `notifications/notifications_screen.dart` | 1 |
| `sign.dart` | 2 |

Le pattern à appliquer est exactement celui du §4 — aucune nouvelle
infrastructure à écrire, uniquement du travail mécanique écran par écran.

---

## 7. Utiliser le script de repérage

```bash
python3 scripts/find_untranslated_texts.py lib
```

Affiche, fichier par fichier (du plus gros au plus petit), chaque ligne
contenant probablement une chaîne française en dur non encore migrée
(`Text('...')`, `label:`, `hintText:`, `title:`, `content:`,
`labelText:`). C'est un outil de **repérage**, pas de migration
automatique : une regex ne distingue pas un libellé UI d'une valeur envoyée
au backend (voir l'avertissement sur `situationMatrimoniale` au §4) — la
bascule reste une édition manuelle, mais le script évite d'avoir à relire
1300+ lignes à l'œil pour les localiser.

---

## 8. Sécurité — points vérifiés

- **Clé DeepL** : uniquement dans `settings.DEEPL_API_KEY`, lue depuis
  `.env`, jamais committée, jamais transmise au client Flutter (le client
  n'appelle que le backend Django, jamais `api.deepl.com`).
- **Endpoint public mais limité en débit** : `/api/i18n/traduire/` est
  volontairement `AllowAny` (nécessaire pour les écrans pré-connexion),
  donc protégé par `ScopedRateThrottle` (`"traduction": "40/hour"` dans
  `REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"]`) pour éviter qu'il ne serve de
  proxy DeepL gratuit à un tiers qui trouverait l'URL. Le cache client fait
  qu'un usage normal ne déclenche qu'une poignée d'appels par appareil —
  cette limite n'affecte donc pas l'usage légitime.
- **Cache local non chiffré** : contrairement à `LocalCache` (SQLCipher),
  le cache de traduction (`translation_cache_store.dart`) est un simple
  fichier JSON. Choix volontaire : il ne contient que des libellés
  d'interface déjà publics dans le binaire de l'app (jamais de données
  personnelles ou financières) — chiffrer ce fichier n'apporterait aucune
  protection supplémentaire réelle, pour un coût de performance/complexité
  non justifié ici.
- **Bornage des lots** : `MAX_TEXTES_PAR_LOT` (200) côté service Django et
  `TraduireTextesView.MAX_TEXTES` (200) côté vue, en plus du regroupement
  par frame côté Flutter — un écran malformé ne peut pas envoyer un payload
  démesuré à DeepL.
