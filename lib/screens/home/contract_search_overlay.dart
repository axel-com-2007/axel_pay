// ============================================================
// RECHERCHE ÉTENDUE — LOUPE DE LA BARRE DE RECHERCHE (ACCUEIL)
// ============================================================
// Au clic sur la loupe de la barre de recherche du dashboard, la boîte
// de recherche s'allonge verticalement et le reste de la page passe en
// arrière-plan flouté. Dans l'espace créé, 8 contrats sont suggérés à
// l'utilisateur ; au clic sur l'un d'eux, l'overlay se ferme et le
// contrat choisi devient le contrat affiché en page d'accueil (retour
// à l'état normal).
// ============================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';

/// Nombre de contrats suggérés dans l'espace déplié de la recherche.
const int _nbContratsSuggeres = 8;

class ContractSearchOverlay {
  ContractSearchOverlay._();

  /// Ouvre l'overlay et renvoie le contrat choisi (ou `null` si annulé).
  static Future<ContratModel?> show(BuildContext context) {
    return showGeneralDialog<ContratModel>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Rechercher un contrat',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 8 * curved.value,
                sigmaY: 8 * curved.value,
              ),
              child: Container(color: Colors.black.withOpacity(0.18 * curved.value)),
            ),
            _ExtendedSearchBox(progress: curved.value),
          ],
        );
      },
    );
  }
}

class _ExtendedSearchBox extends StatefulWidget {
  final double progress;
  const _ExtendedSearchBox({required this.progress});

  @override
  State<_ExtendedSearchBox> createState() => _ExtendedSearchBoxState();
}

class _ExtendedSearchBoxState extends State<_ExtendedSearchBox> {
  final _repo = EneoRepository();
  final _controller = TextEditingController();
  late Future<List<ContratModel>> _suggestions;

  @override
  void initState() {
    super.initState();
    _suggestions = _repo.getContrats(limit: _nbContratsSuggeres);
  }

  void _relancerRecherche(String texte) {
    setState(() {
      _suggestions = _repo.getContrats(
        search: texte.trim().isEmpty ? null : texte.trim(),
        limit: _nbContratsSuggeres,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hauteur cible une fois entièrement déplié (barre + 8 suggestions).
    const double hauteurRepliee = 56;
    const double hauteurDepliee = 470;
    final hauteur = hauteurRepliee + (hauteurDepliee - hauteurRepliee) * widget.progress;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 90, 20, 0),
        child: Opacity(
          opacity: widget.progress,
          child: Material(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.field),
            elevation: 0,
            child: Container(
            height: hauteur,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.field),
              boxShadow: AppShadows.floating,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: hauteurRepliee,
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      const Icon(Icons.search, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          onChanged: _relancerRecherche,
                          decoration: const InputDecoration(
                            hintText: 'Rechercher un numéro de contrat',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                Expanded(
                  child: FutureBuilder<List<ContratModel>>(
                    future: _suggestions,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: LottieLoader(size: 48));
                      }
                      final contrats = snapshot.data ?? const [];
                      if (contrats.isEmpty) {
                        return const Center(
                          child: Text('Aucun contrat trouvé', style: AppTextStyles.bodyMuted),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: contrats.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                        itemBuilder: (context, i) {
                          final ct = contrats[i];
                          return ListTile(
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.description_outlined,
                                  color: AppColors.primary, size: 18),
                            ),
                            title: Text(ct.numeroContrat,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            subtitle: Text(ct.statutLabel, style: AppTextStyles.caption),
                            onTap: () => Navigator.of(context).pop(ct),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          ),  // closes Material
        ),
      ),
    );
  }
}