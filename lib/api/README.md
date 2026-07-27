# Client API Eneo — Flutter ↔ Django

Client centralisé pour parler à ton backend `axel_pay_backend` depuis Flutter.

## 1. Copier les fichiers

Copie tout le dossier `lib/api/` dans ton projet Flutter existant (à côté de
ton `lib/main.dart`, par ex. `lib/api/...`).

## 2. Dépendances (`pubspec.yaml`)

```yaml
dependencies:
  dio: ^5.4.0
  flutter_secure_storage: ^9.0.0
```

Puis `flutter pub get`.

## 3. Configurer l'URL du backend

Dans `lib/api/api_config.dart`, ajuste `baseUrl` selon ton contexte :
- Émulateur Android → `http://10.0.2.2:8000/api`
- Simulateur iOS / web / desktop → `http://localhost:8000/api`
- Appareil physique → l'IP LAN de ta machine, ex. `http://192.168.1.42:8000/api`

Et dans `settings.py` (Django), pense à ajouter l'hôte à `ALLOWED_HOSTS` si
`DEBUG = False`, et à restreindre `CORS_ALLOW_ALL_ORIGINS` en prod.

## 4. Utilisation

```dart
import 'package:ton_app/api/eneo_api.dart';

final api = EneoApiService();

// Connexion — les tokens sont stockés automatiquement (secure storage)
try {
  final result = await api.login(identifiant: '699000000', motDePasse: 'monMotDePasse');
  print(result['user']);
} on ApiValidationException catch (e) {
  print(e.firstMessage); // ex: "Identifiants invalides."
} on ApiAuthException catch (e) {
  print(e.message);
}

// Récupérer les compteurs de l'utilisateur connecté
final compteurs = await api.listCompteurs();

// Achat de crédit prépayé
final transaction = await api.achatCredit(12, montantFcfa: 5000);
```

## 5. Session expirée / déconnexion automatique

Branche la redirection vers l'écran de login une seule fois, par ex. au
démarrage de l'app :

```dart
ApiClient.instance.onSessionExpired = () {
  // ex: avec go_router
  rootNavigatorKey.currentContext?.go('/login');
};
```

Ce callback est déclenché automatiquement quand un refresh token est
invalide/expiré/blacklisté (déconnexion forcée, cf. `RefreshTokenView` /
`LogoutView` côté Django).

## 6. Ce que le client gère déjà pour toi

- Attache `Authorization: Bearer <access>` sur toutes les routes sauf celles
  marquées `AllowAny` côté Django (register, login, verify-otp,
  password-reset, refresh, webhook paiement).
- Rafraîchit automatiquement le token d'accès sur une réponse 401 et rejoue
  la requête originale une seule fois (verrou anti-appels concurrents).
- Convertit chaque erreur DRF (400/401/403/404/409/5xx) en exception Dart
  typée (`ApiValidationException`, `ApiPermissionException`, etc.) au lieu de
  te laisser parser du JSON d'erreur à la main partout dans l'UI.
- Un seul fichier à connaître côté app : `eneo_api_service.dart`, qui expose
  une méthode par endpoint de `urls.py`, regroupées par module (auth,
  compteurs, factures, prépayé, paiements, notifications, admin,
  référentiels, RGPD).

## 7. Points d'attention côté backend (à garder en tête côté Flutter)

- Beaucoup de vues sont encore marquées `TODO INTEGRATION` côté serveur (SMS,
  génération PDF, appel agrégateur Mobile Money réel, chiffrement du jeton
  STS...) — les réponses JSON reflètent déjà la forme finale attendue, mais
  certains champs peuvent rester vides/`null` tant que ces intégrations ne
  sont pas branchées.
- `RefreshTokenView` ne renvoie que `{"access": ...}`, pas de nouveau refresh
  token (pas de rotation malgré `ROTATE_REFRESH_TOKENS = True` dans
  `settings.py`, qui ne s'applique qu'à la vue native de `simplejwt`, non
  utilisée ici). Le client Dart en tient compte.
- `DEBUG = True` et `CORS_ALLOW_ALL_ORIGINS = True` dans `settings.py` sont
  des réglages de dev — à changer avant toute mise en production.
