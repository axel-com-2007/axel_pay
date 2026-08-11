# Analyse de l'architecture existante (avant modification)

## Ce qui existait déjà et n'a PAS été touché
- Authentification 100% Django/JWT (`UsersJWTAuthentication`,
  `SIMPLE_JWT`) — Firebase Authentication n'est utilisé nulle part,
  conforme à la contrainte donnée.
- `ApiClient` (Flutter) : singleton Dio, intercepteur JWT, refresh
  automatique sur 401 — réutilisé tel quel par `DeviceTokenApi`, aucune
  nouvelle instance Dio créée.
- Modèle `UserDevices` (Django, `managed=False`, table déjà en base) :
  `id_device, fcm_token (unique), type_appareil, statut,
  date_enregistrement, date_derniere_activite, id_user (FK Users)`.
  Aucun champ ajouté/renommé — les migrations sur une table
  `managed=False` ne créent ni ne modifient le schéma réel de toute
  façon.
- `UserDevicesSerializer`, `DeviceRegisterView`, `DeviceUnregisterView`,
  routes `devices/` et `devices/<id>/desenregistrer/` dans `urls.py`.

## Ce qui a été ajouté ou corrigé
| Fichier | Changement | Pourquoi |
|---|---|---|
| `lib/services/firebase_messaging_service.dart` | Nouveau | Le `setupFirebaseMessaging()` actuel dans `main.dart` ne gérait ni le background, ni le tap, ni la rotation de token (`onTokenRefresh`) — juste foreground + un `print()`. |
| `lib/api/device_token_api.dart` | Nouveau | Aucune façade n'existait pour envoyer le token à Django. |
| `lib/main.dart` | Modifié | Branche le nouveau service ; le `print`-only `setupFirebaseMessaging()` local est retiré. |
| `lib/api/auth_service.dart` | Modifié | Ajout de l'enregistrement/désenregistrement du token FCM aux points d'entrée/sortie de session (`login`, `logout`, `initialize`) — c'est le seul endroit du projet où l'on est garanti d'avoir un JWT valide en main. |
| `web/firebase-messaging-sw.js` | Nouveau | Absent du projet — sans lui, Flutter Web ne reçoit aucune notification hors focus (silencieux, pas d'erreur visible). |
| `api/services/firebase.py` | Nouveau | Aucune intégration Firebase Admin SDK n'existait côté Django — `send_push_notification` était uniquement demandé, jamais implémenté. |
| `api/views_devices_patch.py` | Patch de `DeviceRegisterView` | La version existante (`CreateAPIView` brut) plante sur un `IntegrityError` si le même `fcm_token` est ré-envoyé (cas fréquent : réinstall, `onTokenRefresh`, plusieurs comptes sur le même appareil) — remplacé par un upsert explicite. |
| `api/views_devices_patch.py` | Nouvelle vue `DeviceUnregisterByTokenView` | La route existante `devices/<id_device>/desenregistrer/` exige de connaître `id_device`, que le client Flutter n'a jamais. Le client ne connaît que son propre token. |
| `api/urls_devices_patch.py` | Ajout d'une route | Pour brancher `DeviceUnregisterByTokenView`. |

## Ce qui reste à ta charge (hors périmètre de ce paquet)
- `settings.py` : ajout de `FIREBASE_CREDENTIALS_PATH` (voir `SETUP.md`)
  — ce fichier n'était pas dans l'archive fournie, impossible de le
  modifier directement sans risquer d'écraser une config existante que
  je ne connais pas (variables d'environnement, `INSTALLED_APPS`, etc.).
- Le fichier JSON de compte de service Firebase (à télécharger toi-même
  depuis la Console Firebase).
- Le VAPID key et les valeurs `firebaseConfig` dans le service worker
  Web (copiées depuis ton `firebase_options.dart` déjà généré).
- Le déclenchement des notifications métier (`notifier_facture_disponible`
  etc.) depuis les vues Django concernées (création de facture,
  confirmation de paiement...) — je fournis les fonctions prêtes à
  l'emploi, mais je n'ai pas modifié `InitierPaiementView` /
  `NotchPayWebhookView` / la logique de génération des factures pour ne
  pas toucher à du code métier sensible (paiements) sans validation
  explicite de ta part.
