# Refonte frontend AxelPay — résumé des changements

Refonte visuelle complète du frontend Flutter, basée sur les 3 maquettes
fournies (connexion, création de compte, accueil).

## Fichiers modifiés

- `lib/theme/app_theme.dart`
  Nouvelle palette : turquoise `#17BFB8` (marque, boutons, onglet actif)
  + jaune doré `#F6C453` (carte d'accueil), fond clair neutre. Ajout
  d'un dégradé de marque (`AppColors.primaryGradient`), d'un style de
  texte `brand` pour le logo texte "AxelPay", et d'un thème pour la
  barre de navigation basse.

- `lib/screens/auth/login_screen.dart`
  Carte blanche flottante centrée, titre "AxelPay" en turquoise, champs
  gris clair arrondis, bouton plein largeur, liens "Mot de passe oublié"
  et "Créer un compte". Motif géométrique discret en arrière-plan
  (`_NetworkPattern`), fidèle à la texture des maquettes.

- `lib/screens/auth/register_screen.dart`
  Bandeau photo en tête avec badge "NEW AGENCY" (image réelle extraite
  de la maquette, voir `assets/images/header_banner.jpg`), champs en
  style "souligné" (sans fond), pastilles rondes turquoise pour la
  situation matrimoniale, case CGU encadrée, bouton "Créer mon compte",
  lien "Déjà un compte ?".

- `lib/screens/home/dashboard_screen.dart`
  Bulle de bienvenue turquoise "Bonjour, {prénom}" + avatar en dégradé,
  rangée d'icônes (support, sécurité, compteurs, etc.), boutons
  "Actualiser" / "Réorganiser", grande carte jaune doré avec bordure
  turquoise regroupant 3 raccourcis (Compteurs / Factures /
  Statistiques), illustration décorative en pied de page (image réelle
  extraite de la maquette, voir `assets/images/home_illustration.png`).
  Toute la logique métier existante (chargement profil/compteurs,
  gestion d'erreur, sélecteur de compteur, alerte suspendu, paiement)
  est conservée à l'identique.

- `lib/screens/home/main_shell.dart`
  Barre de navigation basse avec coins arrondis en haut et ombre douce,
  couleurs alignées sur le nouveau thème (turquoise).

- `pubspec.yaml`
  Ajout de la section `assets:` pour déclarer `assets/images/`.
  ⚠️ Si vous avez déjà un `pubspec.yaml`, ne remplacez pas le vôtre :
  copiez seulement la clé `assets:` dedans (voir `README_ASSETS.md`).

## Fichiers non modifiés (inchangés intentionnellement)

Tous les autres écrans (`otp_screen.dart`, `contracts_screen.dart`,
`meters_screen.dart`, `payment_screen.dart`, `postpaid_screen.dart`,
`prepaid_screen.dart`, `settings_screen.dart`), les widgets partagés
(`app_card.dart`, `primary_button.dart`, `status_badge.dart`) et toute
la couche API/données héritent automatiquement de la nouvelle palette
via `AppColors` / `AppTextStyles` / `AppTheme`, sans besoin d'y
toucher — c'est tout l'intérêt d'avoir un thème centralisé. Si tu veux
que je pousse la refonte visuelle sur ces écrans aussi (mêmes codes
couleur, cartes, badges), dis-le moi et je continue.

## Comment appliquer cette refonte à ton projet existant

1. Remplace ton dossier `lib/` par celui de ce zip (ou fusionne fichier
   par fichier si tu as fait des modifications locales entre-temps).
2. Copie le dossier `assets/images/` à la racine de ton projet.
3. Ajoute la section `assets:` de ce `pubspec.yaml` dans le tien.
4. `flutter pub get`, puis `flutter run`.

Voir `README_ASSETS.md` pour le détail complet sur la gestion des
images dans Flutter (ajout, affichage, images réseau, résolutions
multiples).
