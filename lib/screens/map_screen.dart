// ============================================================
// CARTE DES AGENCES ENEO — OpenStreetMap
// ============================================================
// Ouvert depuis Accueil → Assistance → « Passer à l'agence ».
// Affiche :
//  - la position de l'utilisateur (si la localisation est autorisée) ;
//  - les agences Eneo sur la carte, sous forme de pins ;
//  - un panneau coulissant en bas listant les agences triées par
//    distance, avec une action « Itinéraire ».
//
// -----------------------------------------------------------------
// Comment rendre la liste des agences dynamique plus tard
// -----------------------------------------------------------------
// Pour l'instant, `_agencesEneo` ci-dessous est codée en dur avec les
// 3 agences fournies. Pour la connecter au backend :
//   1. Créer côté API un endpoint (ex: GET /agences) renvoyant pour
//      chaque agence : nom, adresse, latitude, longitude, téléphone.
//   2. Ajouter `Future<List<Agence>> fetchAgences()` dans
//      `lib/api/eneo_api_service.dart` (même schéma que les autres
//      appels de ce fichier).
//   3. Dans `_AgencyMapScreenState`, remplacer la constante par un
//      `List<Agence> _agences = []` alimenté dans `initState()` via
//      ce nouvel appel, avec un état de chargement (voir `ShimmerCard`
//      du design system) pendant la requête.
// Le reste de l'écran (tri par distance, pins, panneau, itinéraire)
// fonctionnera sans aucune autre modification.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';

/// Représente une agence Eneo affichée sur la carte.
class Agence {
  final String nom;
  final String adresse;
  final double latitude;
  final double longitude;
  final String? telephone;

  const Agence({
    required this.nom,
    required this.adresse,
    required this.latitude,
    required this.longitude,
    this.telephone,
  });

  LatLng get position => LatLng(latitude, longitude);
}

/// Agences affichées sur la carte.
/// TODO(backend): remplacer par un appel API — voir note en tête de fichier.
const List<Agence> _agencesEneo = [
  Agence(
    nom: 'Eneo Koumassi',
    adresse: 'Koumassi, Douala',
    latitude: 4.047585,
    longitude: 9.694022,
  ),
  Agence(
    nom: 'Eneo Dakar',
    adresse: 'Dakar, Douala',
    latitude: 4.026832,
    longitude: 9.735484,
  ),
  Agence(
    nom: 'Eneo Bonabéri',
    adresse: 'Bonabéri, Douala',
    latitude: 4.052169,
    longitude: 9.767876,
  ),
];

class AgencyMapScreen extends StatefulWidget {
  const AgencyMapScreen({super.key});

  @override
  State<AgencyMapScreen> createState() => _AgencyMapScreenState();
}

/// Alias conservé par prudence si l'ancien nom `GPSPage` était utilisé
/// ailleurs dans le projet (aucune référence trouvée à ce jour).
typedef GPSPage = AgencyMapScreen;

class _AgencyMapScreenState extends State<AgencyMapScreen> {
  final MapController _mapController = MapController();

  // Position par défaut (Douala) tant que le GPS n'est pas disponible.
  static const LatLng _centreParDefaut = LatLng(4.051056, 9.767868);

  Position? _position;
  bool _isLocating = false;
  String? _erreurLocalisation;
  Agence? _agenceSelectionnee;

  @override
  void initState() {
    super.initState();
    // Tentative silencieuse de localisation à l'ouverture de l'écran :
    // si elle échoue, la carte reste utilisable (centrée sur Douala)
    // et l'utilisateur peut réessayer via le bouton dédié.
    _obtenirPosition(afficherErreurs: false);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<Agence> get _agencesTriees {
    final liste = [..._agencesEneo];
    if (_position != null) {
      liste.sort((a, b) => _distanceMetres(a).compareTo(_distanceMetres(b)));
    }
    return liste;
  }

  double _distanceMetres(Agence agence) {
    if (_position == null) return 0;
    return Geolocator.distanceBetween(
      _position!.latitude,
      _position!.longitude,
      agence.latitude,
      agence.longitude,
    );
  }

  String _formatDistance(Agence agence) {
    final metres = _distanceMetres(agence);
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _obtenirPosition({bool afficherErreurs = true}) async {
    setState(() {
      _isLocating = true;
      _erreurLocalisation = null;
    });

    try {
      final serviceActif = await Geolocator.isLocationServiceEnabled();
      if (!serviceActif) {
        throw 'Les services de localisation sont désactivés sur votre téléphone.';
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Permission de localisation refusée.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Localisation bloquée — activez-la dans les réglages du téléphone.';
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _position = position;
        _isLocating = false;
      });

      _mapController.move(LatLng(position.latitude, position.longitude), 14);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      setState(() {
        _isLocating = false;
        _erreurLocalisation = message;
      });
      if (afficherErreurs) _showSnack(message);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _centrerSur(Agence agence) {
    setState(() => _agenceSelectionnee = agence);
    _mapController.move(agence.position, 15);
  }

  /// Copie les coordonnées de l'agence dans le presse-papiers.
  /// Solution simple ne nécessitant aucune nouvelle dépendance : pour
  /// ouvrir directement Google/Apple Maps en un tap, ajouter le package
  /// `url_launcher` puis lancer
  /// `https://www.google.com/maps/dir/?api=1&destination=lat,lng`.
  Future<void> _copierItineraire(Agence agence) async {
    final coords = '${agence.latitude},${agence.longitude}';
    await Clipboard.setData(ClipboardData(text: coords));
    if (!mounted) return;
    _showSnack('Coordonnées copiées : collez-les dans votre application Maps.');
  }

  @override
  Widget build(BuildContext context) {
    final userLatLng = _position != null
        ? LatLng(_position!.latitude, _position!.longitude)
        : null;
    final hauteurPanneau = MediaQuery.of(context).size.height * 0.32;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Agences Eneo'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: userLatLng ?? _centreParDefaut,
              initialZoom: 12.5,
              onTap: (_, __) => setState(() => _agenceSelectionnee = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.eneo.axelpay',
                maxZoom: 19,
              ),
              MarkerLayer(
                markers: [
                  if (userLatLng != null)
                    Marker(
                      point: userLatLng,
                      width: 46,
                      height: 46,
                      child: const _UserLocationDot(),
                    ),
                  for (final agence in _agencesEneo)
                    Marker(
                      point: agence.position,
                      width: 48,
                      height: 56,
                      child: _AgencyPin(
                        selectionnee: _agenceSelectionnee == agence,
                        onTap: () => _centrerSur(agence),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Bandeau supérieur : nombre d'agences + action de localisation.
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _TopInfoBar(
              nombreAgences: _agencesEneo.length,
              isLocating: _isLocating,
              onRefresh: () => _obtenirPosition(),
            ),
          ),

          // Message d'erreur de localisation (facultatif, non bloquant).
          if (_erreurLocalisation != null && !_isLocating)
            Positioned(
              top: 66,
              left: 16,
              right: 16,
              child: _LocationErrorBanner(
                message: _erreurLocalisation!,
                onRetry: () => _obtenirPosition(),
              ),
            ),

          // Bouton flottant : recentrer sur ma position.
          Positioned(
            right: 16,
            bottom: hauteurPanneau + 16,
            child: _MyLocationButton(
              isLoading: _isLocating,
              onPressed: () => _obtenirPosition(),
            ),
          ),

          // Panneau bas coulissant : liste des agences triées par distance.
          _AgencyListSheet(
            agences: _agencesTriees,
            selectionnee: _agenceSelectionnee,
            connuePosition: _position != null,
            formatDistance: _formatDistance,
            onSelect: _centrerSur,
            onDirections: _copierItineraire,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// COMPOSANTS VISUELS DE L'ÉCRAN
// ============================================================

/// Point bleu façon "ma position" (Google Maps), pulsation légère.
class _UserLocationDot extends StatelessWidget {
  const _UserLocationDot();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryBlue.withOpacity(0.15),
          ),
        ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryBlue,
            border: Border.all(color: AppColors.white, width: 3),
            boxShadow: AppShadows.soft,
          ),
        ),
      ],
    );
  }
}

/// Pin d'agence (goutte + badge éclair Eneo), agrandi et vert
/// quand sélectionné.
class _AgencyPin extends StatelessWidget {
  final bool selectionnee;
  final VoidCallback onTap;

  const _AgencyPin({required this.selectionnee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final couleur = selectionnee ? AppColors.secondaryGreen : AppColors.primaryBlue;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: selectionnee ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: SizedBox(
          width: 48,
          height: 56,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Icon(Icons.location_on, size: 48, color: couleur),
              Positioned(
                top: 7,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bolt, size: 14, color: couleur),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bandeau flottant en haut de la carte : compteur d'agences + action
/// de localisation (spinner pendant la recherche).
class _TopInfoBar extends StatelessWidget {
  final int nombreAgences;
  final bool isLocating;
  final VoidCallback onRefresh;

  const _TopInfoBar({
    required this.nombreAgences,
    required this.isLocating,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined, size: 18, color: AppColors.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$nombreAgences agence${nombreAgences > 1 ? 's' : ''} Eneo',
              style: AppTextStyles.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isLocating)
            const Padding(
              padding: EdgeInsets.all(2),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBlue),
              ),
            )
          else
            InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.my_location, size: 20, color: AppColors.primaryBlue),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bandeau d'erreur discret (localisation refusée/désactivée), avec
/// action "Réessayer" — n'empêche jamais d'utiliser la carte.
class _LocationErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LocationErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.field),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: AppTextStyles.bodyMuted)),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Réessayer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Bouton flottant circulaire "recentrer sur ma position".
class _MyLocationButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _MyLocationButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.white,
        boxShadow: AppShadows.floating,
      ),
      child: IconButton(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primaryBlue),
              )
            : const Icon(Icons.my_location, color: AppColors.primaryBlue),
      ),
    );
  }
}

/// Panneau coulissant listant les agences triées par distance.
class _AgencyListSheet extends StatelessWidget {
  final List<Agence> agences;
  final Agence? selectionnee;
  final bool connuePosition;
  final String Function(Agence) formatDistance;
  final ValueChanged<Agence> onSelect;
  final ValueChanged<Agence> onDirections;

  const _AgencyListSheet({
    required this.agences,
    required this.selectionnee,
    required this.connuePosition,
    required this.formatDistance,
    required this.onSelect,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.18,
      maxChildSize: 0.7,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            boxShadow: [
              BoxShadow(color: AppColors.cardShadow, blurRadius: 20, offset: Offset(0, -6)),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.greyMedium,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Agences les plus proches', style: AppTextStyles.h3),
                    if (!connuePosition)
                      Text('Position inconnue', style: AppTextStyles.caption),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: agences.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final agence = agences[index];
                    return FadeSlideIn(
                      index: index,
                      child: _AgencyListItem(
                        agence: agence,
                        distance: connuePosition ? formatDistance(agence) : null,
                        selectionnee: selectionnee == agence,
                        onTap: () => onSelect(agence),
                        onDirections: () => onDirections(agence),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Une ligne de la liste des agences : icône, nom, adresse, distance,
/// action "Itinéraire".
class _AgencyListItem extends StatelessWidget {
  final Agence agence;
  final String? distance;
  final bool selectionnee;
  final VoidCallback onTap;
  final VoidCallback onDirections;

  const _AgencyListItem({
    required this.agence,
    required this.distance,
    required this.selectionnee,
    required this.onTap,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selectionnee ? AppColors.primaryBlueLight : AppColors.greyBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selectionnee ? AppColors.primaryBlue.withOpacity(0.35) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bolt, color: AppColors.primaryBlue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(agence.nom, style: AppTextStyles.label),
                  const SizedBox(height: 2),
                  Text(
                    agence.adresse,
                    style: AppTextStyles.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (distance != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryGreenLight,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      distance!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondaryGreenDark,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: onDirections,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_outlined, size: 16, color: AppColors.primaryBlue),
                        SizedBox(width: 3),
                        Text(
                          'Itinéraire',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}