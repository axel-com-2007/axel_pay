// ============================================================
// HISTORIQUE DES NOTIFICATIONS (CDC MODULE 6)
// ============================================================
// Ouvert en tapant sur la cloche de notification de l'accueil
// (`DashboardScreen._NotificationBell`). Doit TOUJOURS s'ouvrir, même
// si la liste est vide — c'est le comportement attendu d'un centre de
// notifications (pas de blocage sur "aucune donnée").
//
// Branché sur GET /notifications/ (`NotificationHistoriqueView`,
// `StandardResultsSetPagination`, 20/page) via
// `EneoRepository.getNotifications`. Les préférences (quels canaux
// activer) se règlent séparément depuis Paramètres > Notifications
// (`SettingsScreen._ouvrirNotifications`) — cet écran-ci n'affiche que
// l'historique déjà envoyé.
//
// ⚠️ Pas de cache hors-ligne ici (contrairement aux factures/tokens) :
// aucune valeur documentée dans le CDC à consulter l'historique de
// notifications sans réseau. Une coupure affiche donc une erreur
// explicite avec bouton "Réessayer", jamais une liste vide trompeuse.
// Idem, aucun endpoint "marquer comme lu" n'existe côté backend : l'état
// lu/non-lu affiché reflète strictement ce que le serveur a déjà
// enregistré (`statut`/`date_lecture`), pas une action locale.
// ============================================================

import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../shared/widgets/app_loader.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _repo = EneoRepository();
  final _scrollController = ScrollController();

  // États possibles : chargement initial (_chargement == true, _erreur ==
  // null), erreur (_erreur != null), ou liste chargée (même vide) dans
  // `_notifications`.
  bool _chargement = true;
  String? _erreur;
  final List<NotificationModel> _notifications = [];
  String? _next;
  bool _chargementSuite = false;

  @override
  void initState() {
    super.initState();
    _chargerPremierePage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_next == null || _chargementSuite || _chargement) return;
    // Déclenche le chargement de la page suivante un peu avant d'atteindre
    // le bas, pour un défilement fluide (pas d'à-coup visible).
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _chargerPageSuivante();
    }
  }

  Future<void> _chargerPremierePage() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final page = await _repo.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications
          ..clear()
          ..addAll(page.notifications);
        _next = page.next;
        _chargement = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  Future<void> _chargerPageSuivante() async {
    final next = _next;
    if (next == null) return;
    setState(() => _chargementSuite = true);
    try {
      final page = await _repo.getNotifications(pageUrl: next);
      if (!mounted) return;
      setState(() {
        _notifications.addAll(page.notifications);
        _next = page.next;
        _chargementSuite = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _chargementSuite = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_chargement) {
      return ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => const ShimmerCard(titleWidth: 160),
      );
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 40),
              const SizedBox(height: 14),
              Text(_erreur!, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: _chargerPremierePage,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _chargerPremierePage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_none_rounded,
                          color: AppColors.textMuted, size: 48),
                      const SizedBox(height: 14),
                      const Text(
                        'Aucune notification pour le moment.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _chargerPremierePage,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _notifications.length + (_next != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= _notifications.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: AppLoader.small()),
            );
          }
          return _NotificationTile(notification: _notifications[index]);
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  const _NotificationTile({required this.notification});

  IconData get _icone {
    switch (notification.canal) {
      case 'WhatsApp':
        return Icons.chat_bubble_outline_rounded;
      case 'SMS':
        return Icons.sms_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color get _couleur {
    if (notification.echec) return AppColors.danger;
    switch (notification.criticite) {
      case NiveauCriticiteNotification.critique:
        return AppColors.danger;
      case NiveauCriticiteNotification.info:
        return AppColors.info;
      case NiveauCriticiteNotification.normal:
        return AppColors.primary;
    }
  }

  String get _dateRelative {
    final diff = DateTime.now().difference(notification.dateEnvoi);
    if (diff.inMinutes < 1) return 'À l’instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    final d = notification.dateEnvoi;
    String jj(int n) => n.toString().padLeft(2, '0');
    return '${jj(d.day)}/${jj(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final lue = notification.estLue;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: _couleur.withOpacity(0.12), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(_icone, color: _couleur, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.objet,
                        style: TextStyle(
                          fontWeight: lue ? FontWeight.w600 : FontWeight.w800,
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!lue) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notification.contenu,
                  style: AppTextStyles.bodyMuted,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_dateRelative, style: AppTextStyles.caption),
                    if (notification.echec) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Échec d’envoi',
                        style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
