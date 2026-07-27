# AxelPay — Frontend mobile (Flutter)

Frontend **client uniquement** (pas de back-office) de l'application Eneo,
construit à partir du cahier des charges fourni et du style visuel des
écrans `sign.dart` / `main.dart` déjà en place. Toutes les données sont
**des données de test (mock)**, en attendant le branchement sur l'API
réelle — conformément à la stratégie de repli décrite en section 2.6 du
cahier des charges.

## ⚙️ Installation

Ce dossier contient uniquement le code Dart (`lib/`) et la configuration
des dépendances (`pubspec.yaml`). Il ne contient **pas** les dossiers de
plateforme (`android/`, `ios/`, `web/`), qui sont des fichiers générés.

**Si vous partez d'un dossier vide :**
```bash
flutter create axelpay
# puis copiez le contenu de ce zip par-dessus (en écrasant lib/ et pubspec.yaml)
cd axelpay
flutter pub get
flutter run
```

**Si vous avez déjà un projet Flutter existant** (celui d'où viennent
`main.dart` / `sign.dart`) : remplacez simplement le dossier `lib/` et le
fichier `pubspec.yaml` par ceux de ce zip, puis :
```bash
flutter pub get
flutter run
```

## 🗂️ Structure

```
lib/
├── main.dart                        Point d'entrée (MaterialApp + thème)
├── theme/app_theme.dart             Couleurs, textes, styles centralisés
├── models/models.dart               Modèles (User, Compteur, Facture, ...)
├── data/mock_data.dart              Données de test utilisées partout
├── widgets/                         Composants réutilisables (bouton,
│                                     carte, badge de statut, tuile de
│                                     paramètre...)
└── screens/
    ├── auth/
    │   ├── login_screen.dart        Écran 1 — Connexion
    │   ├── register_screen.dart     Écran 1 — Inscription
    │   └── otp_screen.dart          Écran 1 — Vérification OTP
    ├── home/
    │   ├── main_shell.dart          Navigation par onglets (bottom nav)
    │   └── dashboard_screen.dart    Écran 2 — Accueil multi-compteurs
    ├── postpaid/postpaid_screen.dart  Écran 3 — Factures (postpayé)
    ├── prepaid/prepaid_screen.dart    Écran 4 — Crédit (prépayé)
    ├── payment/payment_screen.dart    Écran 5 — Tunnel Mobile Money
    ├── meters/meters_screen.dart      Écran 6 — Compteurs & délégations
    └── settings/settings_screen.dart  Écran 7 — Paramètres & support
```

## 🧭 Parcours utilisateur

```
LoginScreen ──(Créer un compte)──> RegisterScreen ──> OtpScreen ──┐
     │                                                             │
     └────────────────────(Se connecter)─────────────────────────┴──> MainShell
                                                                          │
                        ┌─────────────────────────────────────────────┼─────────────────────────────┐
                        ▼                                             ▼                             ▼
                 DashboardScreen                               MetersScreen                  SettingsScreen
                (sélecteur de compteur)                    (profil, compteurs,             (préférences, RGPD,
                        │                                    délégation d'accès)              FAQ, support)
          ┌─────────────┴─────────────┐
          ▼                           ▼
   PostpaidScreen               PrepaidScreen
   (factures, graphe,           (jauge, achat de
   signalement, reçu PDF)       crédit, jeton STS)
          │                           │
          └───────────┬───────────────┘
                       ▼
               PaymentScreen
        (récap, MTN/Orange, attente,
             succès/échec)
```

## 🎨 Choix visuels

- Palette reprise de l'écran de connexion existant (beige clair `#FCF9ED`,
  doré `#FFE5B4`, cyan `#00B8E6`, cartes bleu clair `#D3EFF6`).
- L'écran **Paramètres** et l'en-tête du profil (**Compteurs**)
  s'inspirent des captures d'écran des Paramètres Windows fournies en
  référence : grand avatar centré avec identité en dessous, et liste
  d'options avec icône colorée + titre + sous-titre + chevron.

## 🔌 Brancher l'API réelle plus tard

Toutes les données mock sont centralisées dans `lib/data/mock_data.dart`.
Pour brancher le vrai backend (FastAPI/Django décrit en section 7 du
cahier des charges), il suffit de remplacer les appels à ces constantes
par des appels à une couche `services/api.dart` (à créer), sans toucher
à la structure des écrans — les modèles (`lib/models/models.dart`) sont
déjà alignés sur le schéma de données de la section 8.

## ⚠️ Ce que ce livrable ne couvre pas

- Aucun appel réseau réel (pas de `http`/`dio`), conformément à la
  demande : **frontend uniquement**.
- Pas de back-office administrateur (hors périmètre client).
- Pas de persistance / cache local chiffré (SQLite/Hive) : à ajouter
  lors du branchement réel pour le mode hors-ligne (section 7.6).
- Pas de dossiers `android/` / `ios/` (générés par `flutter create`).
