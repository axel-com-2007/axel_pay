// ============================================================
// ÉCRAN PARAMÈTRES & SUPPORT CLIENT
// ============================================================
// Cahier des charges 5. Écran 7 :
//  - Préférences (langue, notifications non-critiques)
//  - Demande de suppression/export des données (conformité ANTIC)
//  - FAQ interactive et dynamique
//  - Ouverture de ticket support / chat en direct
// RG-13 : les préférences de sécurité et de livraison de jeton ne
// sont jamais désactivables — le switch correspondant est verrouillé.
//
// Branché sur GET/PATCH /profile/, GET /compte/export/,
// POST /compte/desactiver/, POST /auth/logout/.
//
// ⚠️ `NotificationPreferencesView` est un stub côté serveur (le GET
// renvoie toujours `{}`, le PATCH ne persiste rien — cf. commentaire
// "TODO INTEGRATION" dans views.py). Les préférences ci-dessous restent
// donc gérées côté client uniquement pour l'instant ; un rafraîchissement
// de l'app les réinitialise. C'est signalé explicitement à l'écran plutôt
// que de laisser croire à une sauvegarde durable.
//
// Le "Support" (ticket/chat) et la FAQ n'ont aucun endpoint dédié dans
// `urls.py` : ils restent des maquettes d'interface, mais qui ne
// prétendent pas afficher de vraies données financières.
// ============================================================

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../api/api_exception.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../auth/login_screen.dart';

const List<Map<String, String>> _faq = [
  {
    'q': 'Comment recharger mon compteur prépayé ?',
    'a': 'Rendez-vous dans l’onglet "Prépayé", saisissez un montant puis '
        'validez via Mobile Money. Le jeton apparaît dans l’historique '
        'une fois le paiement confirmé.',
  },
  {
    'q': 'Que faire si ma facture me semble incorrecte ?',
    'a': 'Ouvrez la facture concernée dans l’onglet "Postpayé" et utilisez '
        'le bouton "Anomalie" pour la signaler directement au support.',
  },
  {
    'q': 'Puis-je donner accès à mon compteur à un proche ?',
    'a': 'Oui, depuis l’onglet "Compteurs" via le bouton "Déléguer". La '
        'finalisation passe actuellement par le support Eneo.',
  },
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = EneoRepository();

  late Future<CachedResult<UserModel>> _profil;
  String langue = 'Français';
  final List<NotificationPrefModel> prefs = [
    NotificationPrefModel(
      cle: 'securite',
      label: 'Alertes de sécurité',
      description: 'Connexions inhabituelles, changement de mot de passe',
      active: true,
      obligatoire: true,
    ),
    NotificationPrefModel(
      cle: 'jeton',
      label: 'Livraison de jeton',
      description: 'Confirmation de chaque recharge prépayée',
      active: true,
      obligatoire: true,
    ),
    NotificationPrefModel(
      cle: 'solde_bas',
      label: 'Solde bas',
      description: 'Alerte quand votre crédit prépayé devient faible',
      active: true,
    ),
    NotificationPrefModel(
      cle: 'facture',
      label: 'Nouvelle facture',
      description: 'Notification à chaque émission de facture',
      active: true,
    ),
    NotificationPrefModel(
      cle: 'recap',
      label: 'Récapitulatif mensuel',
      description: 'Résumé de consommation en fin de mois',
      active: false,
    ),
  ];
  int? faqOuverte;

  @override
  void initState() {
    super.initState();
    _profil = _repo.getProfile();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CachedResult<UserModel>>(
      future: _profil,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: const [
              Row(
                children: [
                  ShimmerBox(width: 52, height: 52, borderRadius: BorderRadius.all(Radius.circular(26))),
                  SizedBox(width: 14),
                  Expanded(child: ShimmerBox(height: 18)),
                ],
              ),
              SizedBox(height: 24),
              ShimmerCard(titleWidth: 100),
              SizedBox(height: 20),
              ShimmerCard(titleWidth: 100),
            ],
          );
        }
        final user = snapshot.data?.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.surface,
                  child: Text(
                    user?.initiales ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.nomComplet ?? '', style: AppTextStyles.h3),
                      Text(user?.email ?? '', style: AppTextStyles.caption),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            FadeSlideIn(
              index: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Préférences'),
                  const SizedBox(height: 6),
                  AppCard(
                    child: Column(
                      children: [
                        SettingsTile(
                          icon: Icons.language,
                          iconColor: AppColors.info,
                          title: 'Langue',
                          subtitle: langue,
                          onTap: _choisirLangue,
                        ),
                        const Divider(height: 1),
                        SettingsTile(
                          icon: Icons.notifications_none,
                          iconColor: AppColors.warning,
                          title: 'Notifications',
                          subtitle: '${prefs.where((p) => p.active).length} canaux activés',
                          onTap: _ouvrirNotifications,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            FadeSlideIn(
              index: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Données & confidentialité'),
                  const SizedBox(height: 6),
                  AppCard(
                    child: Column(
                      children: [
                        SettingsTile(
                          icon: Icons.download_outlined,
                          iconColor: AppColors.success,
                          title: 'Exporter mes données',
                          subtitle: 'Recevoir une copie de vos données personnelles',
                          onTap: _exporterDonnees,
                        ),
                        const Divider(height: 1),
                        SettingsTile(
                          icon: Icons.delete_outline,
                          iconColor: AppColors.danger,
                          title: 'Supprimer mon compte',
                          subtitle: 'Conformité ANTIC — profil anonymisé, historique conservé',
                          onTap: _confirmerSuppression,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            FadeSlideIn(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Aide & support'),
                  const SizedBox(height: 6),
                  AppCard(
                    child: Column(
                      children: [
                        SettingsTile(
                          icon: Icons.support_agent,
                          iconColor: AppColors.primary,
                          title: 'Ouvrir un ticket',
                          subtitle: 'Notre équipe répond sous 24h ouvrées',
                          onTap: () => _showSnack('Ticket de support ouvert'),
                        ),
                        const Divider(height: 1),
                        SettingsTile(
                          icon: Icons.chat_bubble_outline,
                          iconColor: AppColors.primary,
                          title: 'Chat en direct',
                          subtitle: 'Discutez avec un conseiller AxelPay',
                          onTap: () => _showSnack('Ouverture du chat en direct…'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            FadeSlideIn(
              index: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'FAQ'),
                  const SizedBox(height: 6),
                  AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Column(
                children: List.generate(_faq.length, (i) {
                  final item = _faq[i];
                  final ouverte = faqOuverte == i;
                  return Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => faqOuverte = ouverte ? null : i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(item['q']!,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              ),
                              // Micro-interaction "clic" (une seule lecture,
                              // déclenchée à l'ouverture du volet FAQ).
                              LottieOneShot(
                                asset: LottieAssets.click,
                                trigger: ouverte,
                                size: 22,
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                ouverte ? Icons.remove : Icons.add,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (ouverte)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(item['a']!, style: AppTextStyles.bodyMuted),
                          ),
                        ),
                      if (i != _faq.length - 1) const Divider(height: 1),
                    ],
                  );
                }),
              ),
            ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            OutlinedButton.icon(
              onPressed: _seDeconnecter,
              icon: const Icon(Icons.logout, color: AppColors.danger),
              label: const Text('Se déconnecter', style: TextStyle(color: AppColors.danger)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: AppColors.danger),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _choisirLangue() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: ['Français', 'English'].map((l) {
          return RadioListTile<String>(
            value: l,
            groupValue: langue,
            title: Text(l),
            onChanged: (v) {
              setState(() => langue = v!);
              Navigator.pop(ctx);
            },
          );
        }).toList(),
      ),
    );
  }

  void _ouvrirNotifications() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Préférences de notification', style: AppTextStyles.h3),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Ces préférences ne sont pas encore sauvegardées côté '
                  'serveur — elles seront réinitialisées à la prochaine '
                  'ouverture de l’app.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 10),
              ...prefs.map((p) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.label),
                    subtitle: Text(
                      p.obligatoire ? '${p.description} · toujours actif' : p.description,
                      style: AppTextStyles.caption,
                    ),
                    value: p.active,
                    activeColor: AppColors.primary,
                    onChanged: p.obligatoire
                        ? null
                        : (v) => setModalState(() {
                              setState(() => p.active = v);
                            }),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exporterDonnees() async {
    // Attente : illustration database.json (au lieu d'un simple SnackBar),
    // dans une boîte de dialogue non-annulable pendant l'appel réseau.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: LottieLoader(size: 90, label: 'Préparation de votre export…'),
      ),
    );
    try {
      final export = await _repo.exportMyData();
      if (!mounted) return;
      Navigator.pop(context); // ferme la boîte de dialogue d'attente
      final nbCompteurs = (export['compteurs'] as List?)?.length ?? 0;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export prêt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset(
                LottieAssets.database,
                width: 96,
                height: 96,
                repeat: false,
                errorBuilder: (context, error, stack) =>
                    const Icon(Icons.inbox_outlined, size: 56, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Text(
                'Vos données personnelles ont été récupérées ($nbCompteurs compteur(s) '
                'inclus). Cette version ne propose pas encore l’envoi par e-mail — '
                'contactez le support si vous avez besoin d’un fichier téléchargeable.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // ferme la boîte de dialogue d'attente
      _showSnack(e.message);
    }
  }

  void _confirmerSuppression() {
    final motDePasseController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vos données de profil seront anonymisées. Votre historique financier '
              'restera archivé pour répondre aux obligations légales comptables.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motDePasseController,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Confirmez votre mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              final motDePasse = motDePasseController.text;
              Navigator.pop(ctx);
              try {
                await _repo.deactivateAccount(motDePasseConfirmation: motDePasse);
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              } on ApiException catch (e) {
                if (!mounted) return;
                _showSnack(e.message);
              }
            },
            child: const Text('Confirmer', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _seDeconnecter() async {
    try {
      await _repo.logout();
    } catch (_) {
      // Le stockage local est de toute façon nettoyé côté client
      // (cf. `EneoApiService.logout` : `finally { clear() }`).
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
