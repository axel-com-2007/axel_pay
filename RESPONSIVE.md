# AxelPay — Système Responsive

## Vue d'ensemble

L'application s'adapte automatiquement à **tous les écrans** grâce à un système de breakpoints centralisé dans `lib/design_system/responsive/responsive_utils.dart`.

---

## Breakpoints

| Catégorie | Largeur      | Appareils cibles                          |
|-----------|-------------|------------------------------------------|
| `mobile`  | < 600 px    | Téléphones (portrait et paysage)         |
| `tablet`  | 600–1023 px | Tablettes, grands téléphones             |
| `desktop` | ≥ 1024 px   | PC, Mac, navigateurs web, TV             |

---

## Ce qui change par écran

### Navigation (`main_shell.dart`)
| Mobile | Tablette | Desktop |
|--------|----------|---------|
| `NavigationBar` en bas | `NavigationRail` latéral (icônes seules) | `NavigationRail` étendu (icônes + labels) |

### Écran de connexion (`login_screen.dart`)
| Mobile | Tablette | Desktop |
|--------|----------|---------|
| Carte centrée pleine largeur | Carte centrée ≤ 480 px | Split 2 colonnes : branding ⬅ formulaire |

### Dashboard (`dashboard_screen.dart`)
| Mobile | Tablette | Desktop |
|--------|----------|---------|
| Padding 20 px | Padding 24 px | Contenu centré ≤ 1200 px, padding 32 px |

### Inscription, Paramètres, Contrats
- Padding horizontal augmenté progressivement
- Contenu centré et contraint en largeur sur desktop

---

## API publique

### Extensions `BuildContext`
```dart
context.isMobile     // bool — largeur < 600
context.isTablet     // bool — 600 ≤ largeur < 1024
context.isDesktop    // bool — largeur ≥ 1024
context.screenType   // ScreenType.mobile | .tablet | .desktop
context.screenWidth  // double
context.screenHeight // double
context.sw(0.5)      // 50 % de la largeur d'écran
context.sh(0.3)      // 30 % de la hauteur
context.pagePadding  // EdgeInsets adapté au breakpoint
context.gridColumns  // 1 (mobile) / 2 (tablet) / 3 (desktop)
```

### Widget `ResponsiveLayout`
```dart
ResponsiveLayout(
  mobile:  MobileWidget(),
  tablet:  TabletWidget(),   // optionnel — mobile utilisé si absent
  desktop: DesktopWidget(),  // optionnel — mobile utilisé si absent
)
```

### Valeur scalaire responsive
```dart
final padding = Responsive.value<double>(
  context,
  mobile:  16,
  tablet:  24,
  desktop: 32,
);
```

### Texte scalé
```dart
// Taille adaptée selon le breakpoint (×1.10 tablette, ×1.20 desktop)
AppResponsiveText.scale(context, 14)  // → 14 / 15.4 / 16.8

// Styles complets
AppResponsiveText.brand(context)
AppResponsiveText.h1(context)
AppResponsiveText.h2(context)
AppResponsiveText.body(context)
```

### Centrage avec largeur max
```dart
ResponsiveCenter(
  maxWidth: AppBreakpoints.maxContentWidth, // 1200 px par défaut
  child: MyContent(),
)

ConstrainedPageBody(
  child: MyContent(),
  scrollable: true, // wraps in SingleChildScrollView
)
```

### Grille adaptative
```dart
ResponsiveGrid(
  mobileColumns:  1,
  tabletColumns:  2,
  desktopColumns: 3,
  children: myCards,
)
```

---

## Constantes

```dart
AppBreakpoints.tablet          // 600
AppBreakpoints.desktop         // 1024
AppBreakpoints.maxContentWidth // 1200 — largeur max du contenu principal
AppBreakpoints.maxFormWidth    // 480  — largeur max des formulaires
AppBreakpoints.maxCardWidth    // 540  — largeur max d'une carte en grille
```

---

## Comment utiliser dans un nouvel écran

```dart
import '../../design_system/responsive/responsive_utils.dart';

class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ConstrainedPageBody(          // ← gère padding + maxWidth
        scrollable: true,
        child: ResponsiveGrid(            // ← grille 1/2/3 colonnes
          children: myCards,
        ),
      ),
    );
  }
}
```

---

## Règles à respecter

1. **Ne jamais coder de `EdgeInsets` en dur** pour les paddings de page → utiliser `context.pagePadding` ou `AppResponsiveSpacing`.
2. **Ne jamais utiliser de `fontSize` en dur** dans les textes importants → utiliser `AppResponsiveText.scale(context, taille)`.
3. **Toujours tester** à 360 px (petit Android), 768 px (iPad), 1280 px (laptop).
4. Le `textScaler` est **clampé à ±15 %** dans `main.dart` pour éviter les débordements systèmes.
