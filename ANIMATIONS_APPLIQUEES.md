# Animations appliquées sur AxelPay

Boîte à outils centrale : `lib/widgets/animations/animations.dart`
(100% Flutter SDK — **aucune dépendance à ajouter** au pubspec.yaml).

## Widgets partagés (impact sur toute l'app)
- `AppCard` → effet ressort (scale 0.97) au toucher + support `heroTag` optionnel.
- `PrimaryButton` / `SecondaryButton` → même effet ressort.
- `StatusBadge` → halo turquoise/rouge pulsant automatique sur les statuts
  "impayée", "suspendu", "échoué".

## Écran par écran
- **Dashboard** : squelette Shimmer au chargement, apparition en cascade
  des sections (`FadeSlideIn`), solde affiché en compteur animé
  (`AnimatedCounter`).
- **Contrats** (`contracts_screen.dart`) : squelette Shimmer, liste de
  contrats en cascade.
- **Factures d'un contrat** (`contrat_factures_screen.dart`) : squelette
  Shimmer, liste de factures en cascade.
- **Compteurs** (`meters_screen.dart`) : squelette Shimmer, listes
  compteurs + délégations en cascade.
- **Postpayé** (`postpaid_screen.dart`) : squelette Shimmer, liste de
  factures en cascade.
- **Prépayé** (`prepaid_screen.dart`) : squelette Shimmer, historique de
  transactions en cascade, solde en compteur animé.
- **Paiement** (`payment_screen.dart`) : bouton remplacé par un slider
  "glisser pour payer" (`SwipeToConfirm`, avec réinitialisation
  automatique en cas d'erreur), secousse (`ShakeWidget`) sur le message
  d'erreur, confettis (`ConfettiBurst`) + icône qui rebondit à l'écran de
  succès.
- **Connexion** (`login_screen.dart`) : carte de connexion qui secoue en
  cas d'identifiants invalides, apparition en fondu/glissé à l'ouverture.
- **Inscription** (`register_screen.dart`) : formulaire qui secoue en cas
  d'erreur (CGU non cochées, validation serveur), pastilles de situation
  matrimoniale avec effet ressort.
- **OTP** (`otp_screen.dart`) : secousse sur code invalide.
- **Paramètres** (`settings_screen.dart`) : squelette Shimmer, sections en
  cascade.
- **Navigation principale** (`main_shell.dart`) : transition douce type
  "shared axis" (fondu + léger glissement) entre les onglets Accueil /
  Contrats / Paramètres, via `AxisSwitcher`.

## Non couvert (choix volontaire)
- Illustrations Lottie/Rive : nécessitent des assets `.json`/`.riv` que
  je n'ai pas — le point d'intégration est prêt (`lottie`/`rive`) mais
  pas branché faute de fichiers sources.
- `Hero` : le support est ajouté dans `AppCard` (`heroTag`) mais pas
  encore câblé sur un couple liste→détail précis ; dis-moi quel
  parcours tu veux (ex: vignette de compteur → écran prépayé/postpayé)
  et je le branche.
