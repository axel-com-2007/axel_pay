# AxelPay — Notifications push (FCM) : installation

Ce paquet contient les fichiers **nouveaux ou modifiés**. Ton architecture
existante (auth Django/JWT, `ApiClient`, `UserDevices`, routes `devices/*`)
n'est **pas cassée** — voir `ANALYSE.md` pour le détail de ce qui existait
déjà et de ce qui a été ajouté/corrigé.

## 1. Flutter

### Fichiers à copier tels quels
```
flutter/lib/services/firebase_messaging_service.dart  →  lib/services/firebase_messaging_service.dart
flutter/lib/api/device_token_api.dart                 →  lib/api/device_token_api.dart
flutter/lib/main.dart                                  →  lib/main.dart          (remplace l'existant)
flutter/lib/api/auth_service.dart                      →  lib/api/auth_service.dart   (remplace l'existant)
flutter/web/firebase-messaging-sw.js                    →  web/firebase-messaging-sw.js
```

### À personnaliser avant de lancer
- **`web/firebase-messaging-sw.js`** : remplace les 6 valeurs
  `REPLACE_WITH_FIREBASE_OPTIONS_WEB_*` par les valeurs EXACTES de la
  section `web` dans ton `lib/firebase_options.dart` déjà généré.
- **`lib/services/firebase_messaging_service.dart`** : remplace
  `_webVapidKey` par ta clé VAPID publique — Console Firebase > Project
  Settings > Cloud Messaging > onglet "Web configuration" > "Web Push
  certificates" > génère/copie la "Key pair". Sans elle, `getToken()`
  renvoie `null` sur Chrome (le reste de l'app continue de fonctionner,
  juste sans push web).

### Android — canal de notification (recommandé)
Pour que le `channel_id: "axelpay_notifications"` envoyé par
`api/services/firebase.py` soit bien pris en compte visuellement, ajoute
dans `android/app/src/main/AndroidManifest.xml`, à l'intérieur de
`<application>` :
```xml
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="axelpay_notifications" />
```
Sans ça, Android utilise un canal par défaut générique — les push
fonctionnent quand même, c'est juste moins propre pour l'utilisateur
(pas de réglages fins possibles par catégorie dans les paramètres
Android).

### pubspec.yaml
Rien à ajouter : `firebase_core` et `firebase_messaging` sont déjà dans
ton `pubspec.yaml`.

## 2. Django

### Installation
```bash
pip install firebase-admin
```

### Fichier à copier
```
django/api/services/firebase.py  →  api/services/firebase.py
```

### settings.py — à ajouter
```python
FIREBASE_CREDENTIALS_PATH = os.environ.get(
    "FIREBASE_CREDENTIALS_PATH",
    BASE_DIR / "secrets" / "firebase-service-account.json",
)
```
Télécharge le fichier JSON depuis Console Firebase > Project Settings >
Service accounts > "Generate new private key", place-le à ce chemin
(crée le dossier `secrets/`), et **ajoute `secrets/` à ton
`.gitignore`** — ce fichier donne un accès complet à ton projet
Firebase, il ne doit jamais partir sur GitHub.

En production, préfère une variable d'environnement
`FIREBASE_CREDENTIALS_PATH` pointant vers un secret monté par ton
orchestrateur (pas le fichier committé).

### views.py — modifications
Ouvre `django/api/views_devices_patch.py` (fourni dans ce paquet) : il
contient les nouvelles versions de `DeviceRegisterView` (upsert au lieu
de create brut, qui plantait sur un token déjà connu) et une nouvelle
vue `DeviceUnregisterByTokenView`. Instructions de copier-coller
détaillées en tête du fichier.

### urls.py — modifications
Ouvre `django/api/urls_devices_patch.py` : import + une ligne de route à
ajouter. Instructions détaillées en tête du fichier.

### Envoyer une notification depuis n'importe quelle vue existante
```python
from .services.firebase import notifier_facture_disponible

# après création d'une facture, dans FacturesListView / la tâche qui
# génère les factures mensuelles, etc.
notifier_facture_disponible(
    user=facture.id_compteur.id_contrat.id_user,
    numero_facture=facture.numero_facture,
    montant_fcfa=facture.montant_fcfa,
    id_facture=facture.id_facture,
)
```
Fonctions prêtes à l'emploi dans `api/services/firebase.py` :
`notifier_facture_disponible`, `notifier_paiement_confirme`,
`notifier_facture_impayee`, `notifier_message_systeme`. Chacune renvoie
le nombre d'envois réussis (0 si l'utilisateur n'a aucun terminal actif
— pas une erreur, juste un no-op silencieux).

## 3. Vérification bout-en-bout

1. Lance le backend Django, connecte-toi depuis Flutter (Chrome, comme
   actuellement).
2. Vérifie dans les logs Flutter la ligne `🔥 FCM TOKEN : ...`.
3. Vérifie côté Django (shell ou admin) qu'une ligne `UserDevices` a été
   créée/mise à jour avec `statut = "Actif"` pour ton utilisateur.
4. Dans un shell Django :
   ```python
   from api.services.firebase import notifier_message_systeme
   from api.models import Users
   u = Users.objects.get(pk=1)  # ton utilisateur de test
   notifier_message_systeme(u, "Test", "Ça marche !")
   ```
5. La notification doit apparaître dans Chrome (onglet actif → foreground
   listener ; onglet en arrière-plan → service worker).

## 4. Sécurité — ce qui est déjà couvert

- Aucun token Firebase en dur dans le code Flutter (récupéré
  dynamiquement via `FirebaseMessagingService`).
- `DeviceRegisterView` et `DeviceUnregisterByTokenView` exigent
  `IsAuthenticated` (JWT Django existant, `UsersJWTAuthentication`) —
  aucune dépendance à Firebase Authentication.
- Un utilisateur ne peut désenregistrer que ses propres devices
  (`id_user=request.user` dans le filtre).
- Tokens invalides/désinstallés : `send_push_notification_to_user`
  désactive automatiquement le `UserDevices` correspondant sur
  `UnregisteredError`, pas de nettoyage manuel à prévoir.
