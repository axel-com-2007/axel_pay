# Comment insérer des images dans un projet Flutter (AxelPay)

Ce fichier zip contient déjà un exemple fonctionnel : les images
`assets/images/header_banner.jpg` (bandeau photo de l'écran d'inscription)
et `assets/images/home_illustration.png` (illustration en pied de page de
l'accueil) ont été extraites des maquettes que tu as fournies et sont
déjà câblées dans `register_screen.dart` et `dashboard_screen.dart` via
`Image.asset(...)`. Voici la méthode générale pour en ajouter d'autres.

## 1. Placer le fichier image dans le projet

Crée (ou réutilise) un dossier `assets/images/` à la racine du projet
(au même niveau que `pubspec.yaml`, PAS dans `lib/`) :

```
mon_projet/
├── pubspec.yaml
├── lib/
└── assets/
    └── images/
        ├── header_banner.jpg
        ├── home_illustration.png
        └── logo.png
```

## 2. Déclarer le dossier dans pubspec.yaml

Dans `pubspec.yaml`, sous la clé `flutter:`, ajoute (ou complète) la
section `assets:` :

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
```

⚠️ Attention à l'indentation YAML (2 espaces), et à ne pas dupliquer la
clé `flutter:` si ton `pubspec.yaml` en a déjà une — ajoute simplement
la ligne `assets:` dedans. Le zip fourni contient un `pubspec.yaml`
complet à titre d'exemple : si tu as déjà le tien, copie uniquement la
section `assets:`.

## 3. Récupérer les packages

Après toute modification de `pubspec.yaml`, lance :

```bash
flutter pub get
```

(Dans VS Code / Android Studio, un simple enregistrement du fichier
suffit généralement à déclencher cette commande automatiquement.)

## 4. Afficher l'image dans le code

```dart
Image.asset('assets/images/logo.png')
```

Options utiles :

```dart
Image.asset(
  'assets/images/header_banner.jpg',
  fit: BoxFit.cover,      // remplit le conteneur en conservant les proportions
  width: double.infinity,
  height: 190,
  errorBuilder: (context, error, stackTrace) => Container(
    color: Colors.grey.shade200, // repli si l'image manque
  ),
);
```

Pour un logo dans un cercle (comme l'avatar de l'écran d'accueil) :

```dart
CircleAvatar(
  radius: 26,
  backgroundImage: AssetImage('assets/images/logo.png'),
)
```

Pour des coins arrondis (comme le bandeau photo de l'inscription) :

```dart
ClipRRect(
  borderRadius: BorderRadius.circular(24),
  child: Image.asset('assets/images/header_banner.jpg', fit: BoxFit.cover),
)
```

## 5. Images réseau (URL) plutôt que fichiers locaux

Si l'image vient d'une API/CDN plutôt que d'un fichier livré avec l'app :

```dart
Image.network(
  'https://exemple.com/photo.jpg',
  fit: BoxFit.cover,
  loadingBuilder: (context, child, progress) =>
      progress == null ? child : const Center(child: CircularProgressIndicator()),
  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
)
```

## 6. Gérer plusieurs résolutions (écrans Retina / haute densité)

Flutter choisit automatiquement la bonne variante si tu organises les
fichiers ainsi (facultatif, utile pour des logos/icônes nets sur tous
les écrans) :

```
assets/images/logo.png       (résolution de base, 1x)
assets/images/2.0x/logo.png  (2x)
assets/images/3.0x/logo.png  (3x)
```

Le code reste le même : `Image.asset('assets/images/logo.png')`.

## 7. Où sont utilisées les images dans cette refonte ?

| Fichier                                   | Usage                                              |
|--------------------------------------------|-----------------------------------------------------|
| `assets/images/header_banner.jpg`         | Bandeau photo en tête de `register_screen.dart`     |
| `assets/images/home_illustration.png`     | Illustration décorative en pied de `dashboard_screen.dart` |

Les deux appels utilisent `errorBuilder` pour ne jamais planter l'app
si jamais l'asset n'est pas encore déclaré côté `pubspec.yaml` — le
temps que tu fasses `flutter pub get`.
