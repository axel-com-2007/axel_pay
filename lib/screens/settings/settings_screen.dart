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
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/auth_service.dart';
import '../../data/eneo_repository.dart';
import '../../l10n/app_locale_controller.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../auth/login_screen.dart';
import '../notifications/notifications_screen.dart';
import '../support/open_ticket_screen.dart';
import '../support/support_chat_screen.dart';

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
  /// Si `true`, ouvre directement le bottom sheet "Préférences de
  /// notification" au premier frame (juste après le montage de l'écran),
  /// sans attendre d'action de l'utilisateur. Utilisé par le raccourci
  /// "Activer rappel" de l'accueil, pour éviter un aller-retour inutile
  /// via l'écran Paramètres complet.
  final bool ouvrirNotificationsAuDemarrage;

  const SettingsScreen({super.key, this.ouvrirNotificationsAuDemarrage = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = EneoRepository();

  late Future<CachedResult<UserModel>> _profil;
  // ⚠️ i18n : `label`/`description` ci-dessous sont des champs hérités du
  // modèle `NotificationPrefModel`, remplis pour satisfaire le constructeur
  // mais JAMAIS affichés tels quels — l'affichage passe exclusivement par
  // `S.notifPrefLabel(cle)` / `S.notifPrefDescription(cle)` (voir
  // `_ouvrirNotifications` plus bas), qui mappent la `cle` (stable, jamais
  // traduite) vers le libellé dans la langue courante. Faux positifs
  // légitimes pour `find_untranslated_texts.py`.
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
    // Le bottom sheet ne dépend que de `prefs` (déjà initialisé plus haut)
    // et du `context` — pas besoin d'attendre `_profil` pour l'afficher.
    if (widget.ouvrirNotificationsAuDemarrage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ouvrirNotifications();
      });
    }
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
        final s = S.of(context);
        final langueActuelle =
            context.watch<LocaleController>().locale.languageCode == 'en'
                ? s.langueAnglais
                : s.langueFrancais;
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
                  SectionHeader(title: s.sectionPreferences),
                  const SizedBox(height: 6),
                  AppCard(
                    child: Column(
                      children: [
                        SettingsTile(
                          icon: Icons.language,
                          iconColor: AppColors.info,
                          title: s.langueTitre,
                          subtitle: langueActuelle,
                          onTap: _choisirLangue,
                        ),
                        const Divider(height: 1),
                        SettingsTile(
                          icon: Icons.notifications_none,
                          iconColor: AppColors.warning,
                          title: s.notificationsTitre,
                          subtitle: s.canauxActives(prefs.where((p) => p.active).length),
                          // Ouvre le MÊME écran que la cloche de l'accueil
                          // (`DashboardScreen._NotificationBell` →
                          // `NotificationsScreen`) : historique des
                          // notifications déjà envoyées, identique en tout
                          // point à celui du dashboard.
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                          ),
                          // Les préférences de canaux (switch sécurité,
                          // jeton, solde bas...) restent accessibles via
                          // cette icône dédiée, sans quitter le fil
                          // principal "voir mes notifications".
                          trailing: IconButton(
                            icon: const Icon(Icons.tune, size: 20, color: AppColors.textMuted),
                            tooltip: s.preferencesNotificationTooltip,
                            onPressed: _ouvrirNotifications,
                          ),
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
                  SectionHeader(title: s.sectionSecurite),
                  const SizedBox(height: 6),
                  AppCard(
                    child: Column(
                      children: [
                        SettingsTile(
                          icon: Icons.phone_iphone,
                          iconColor: AppColors.info,
                          title: s.changerNumeroTitre,
                          subtitle: user?.telephone ?? '',
                          onTap: () => _ouvrirChangementTelephone(user),
                        ),
                        const Divider(height: 1),
                        SettingsTile(
                          icon: Icons.lock_outline,
                          iconColor: AppColors.warning,
                          title: s.changerMotDePasseTitre,
                          subtitle: s.changerMotDePasseSousTitre,
                          onTap: () => _ouvrirChangementMotDePasse(user),
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
                  SectionHeader(title: s.sectionDonnees),
                  const SizedBox(height: 6),
                  AppCard(
                    child: Column(
                      children: [
                        SettingsTile(
                          icon: Icons.download_outlined,
                          iconColor: AppColors.success,
                          title: s.exporterDonneesTitre,
                          subtitle: s.exporterDonneesSousTitre,
                          onTap: _exporterDonnees,
                        ),
                        const Divider(height: 1),
                        SettingsTile(
                          icon: Icons.delete_outline,
                          iconColor: AppColors.danger,
                          title: s.supprimerCompteTitre,
                          subtitle: s.supprimerCompteSousTitre,
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
                  SectionHeader(title: s.sectionAideSupport),
                  const SizedBox(height: 6),
                  AppCard(
                    child: Column(
                      children: [
                        SettingsTile(
                          icon: Icons.support_agent,
                          iconColor: AppColors.primary,
                          title: s.ouvrirTicketTitre,
                          subtitle: s.ouvrirTicketSousTitre,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const OpenTicketScreen()),
                          ),
                        ),
                        const Divider(height: 1),
                        SettingsTile(
                          icon: Icons.chat_bubble_outline,
                          iconColor: AppColors.primary,
                          title: s.chatDirectTitre,
                          subtitle: s.chatDirectSousTitre,
                          // Ouvre le MÊME écran que l'icône assistance de
                          // l'accueil → "Écrire un message" (SupportScreen
                          // ouvre SupportChatScreen). On saute directement
                          // à l'écran de chat plutôt que de repasser par
                          // le menu Assistance, puisque l'intention de
                          // l'utilisateur est déjà explicite ici.
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SupportChatScreen()),
                          ),
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
                  SectionHeader(title: s.sectionFaq),
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
              label: Text(s.seDeconnecter, style: const TextStyle(color: AppColors.danger)),
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
    final s = S.read(context);
    final controller = context.read<LocaleController>();
    AppBottomSheet.show(
      context: context,
      title: s.langueTitre,
      isScrollControlled: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: LocaleController.supported.map((l) {
          final label = l.languageCode == 'en' ? s.langueAnglais : s.langueFrancais;
          return RadioListTile<String>(
            value: l.languageCode,
            groupValue: controller.locale.languageCode,
            title: Text(label),
            onChanged: (v) {
              controller.definirLangue(Locale(v!));
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }

  void _ouvrirNotifications() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final s = S.of(ctx);
          return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.parametresNotifPrefsTitre, style: AppTextStyles.h3),
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
                    title: Text(s.notifPrefLabel(p.cle)),
                    subtitle: Text(
                      p.obligatoire
                          ? '${s.notifPrefDescription(p.cle)} · ${s.parametresNotifToujoursActifSuffixe}'
                          : s.notifPrefDescription(p.cle),
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
        );
        },
      ),
    );
  }

  Future<void> _exporterDonnees() async {
    final s = S.read(context);
    // Attente : illustration database.json (au lieu d'un simple SnackBar),
    // dans une boîte de dialogue non-annulable pendant l'appel réseau.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        content: LottieLoader(size: 90, label: s.parametresExportPreparationLabel),
      ),
    );
    try {
      final export = await _repo.exportMyData();
      if (!mounted) return;
      Navigator.pop(context); // ferme la boîte de dialogue d'attente
      final emailEnvoye = export['email_envoye'] == true;
      final message = export['message'] as String? ??
          (emailEnvoye
              ? 'Vos données personnelles vous ont été envoyées par e-mail.'
              : 'Vos données personnelles ont été récupérées.');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Text(emailEnvoye ? S.read(context).exportEnvoye : S.read(context).exportPret),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset(
                LottieAssets.database,
                width: 96,
                height: 96,
                repeat: false,
                errorBuilder: (context, error, stack) => Icon(
                  emailEnvoye ? Icons.mark_email_read_outlined : Icons.inbox_outlined,
                  size: 56,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.read(context).fermer)),
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
    final s = S.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Text(s.parametresSupprimerCompteConfirmTitre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.parametresSupprimerCompteConfirmMessage),
            const SizedBox(height: 12),
            TextField(
              controller: motDePasseController,
              obscureText: true,
              decoration: InputDecoration(hintText: s.confirmerMotDePasseHint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.annuler)),
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
            child: Text(S.read(context).confirmer, style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _ouvrirChangementTelephone(UserModel? user) {
    final telephoneController = TextEditingController();
    final motDePasseController = TextEditingController();
    final s = S.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Text(s.parametresChangerNumeroDialogTitre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.parametresNumeroActuel(user?.telephone ?? ''), style: AppTextStyles.bodyMuted),
            const SizedBox(height: 12),
            TextField(
              controller: telephoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(hintText: s.parametresNouveauNumeroHint),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: motDePasseController,
              obscureText: true,
              decoration: InputDecoration(hintText: s.confirmerMotDePasseHint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.annuler)),
          TextButton(
            onPressed: () async {
              final nouveauTelephone = telephoneController.text.trim();
              final motDePasse = motDePasseController.text;
              Navigator.pop(ctx);
              try {
                await context.read<AuthService>().changePhoneNumber(
                      nouveauTelephone: nouveauTelephone,
                      motDePasseConfirmation: motDePasse,
                    );
                if (!mounted) return;
                setState(() => _profil = _repo.getProfile());
                _showSnack('Numéro mis à jour. Vérifiez le code envoyé par SMS si demandé.');
              } on ApiException catch (e) {
                if (!mounted) return;
                _showSnack(e.message);
              }
            },
            child: Text(S.read(context).confirmer),
          ),
        ],
      ),
    );
  }

  /// Réutilise le flux "mot de passe oublié" déjà existant côté backend
  /// (`PasswordResetRequestView` / `PasswordResetConfirmView`) : il n'existe
  /// pas d'endpoint dédié "changer mon mot de passe en étant connecté" dans
  /// la CDC — seule la procédure par code (SMS/e-mail) est spécifiée (5.1).
  void _ouvrirChangementMotDePasse(UserModel? user) {
    final identifiant = user?.telephone ?? user?.email ?? '';
    final codeController = TextEditingController();
    final nouveauMotDePasseController = TextEditingController();
    bool codeEnvoye = false;
    bool envoiEnCours = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final s = S.of(ctx);
          return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.parametresChangerMdpDialogTitre, style: AppTextStyles.h3),
              const SizedBox(height: 10),
              if (!codeEnvoye) ...[
                Text(
                  'Un code de vérification sera envoyé à $identifiant.',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: envoiEnCours
                        ? null
                        : () async {
                            setModalState(() => envoiEnCours = true);
                            try {
                              await context
                                  .read<AuthService>()
                                  .requestPasswordReset(identifiant: identifiant);
                              setModalState(() {
                                envoiEnCours = false;
                                codeEnvoye = true;
                              });
                            } on ApiException catch (e) {
                              setModalState(() => envoiEnCours = false);
                              if (!mounted) return;
                              _showSnack(e.message);
                            }
                          },
                    child: Text(envoiEnCours ? s.envoiEnCours : s.parametresRecevoirLeCodeBouton),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(hintText: s.parametresCodeRecuHint),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nouveauMotDePasseController,
                  obscureText: true,
                  decoration: InputDecoration(hintText: s.parametresNouveauMdpHint),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: envoiEnCours
                        ? null
                        : () async {
                            setModalState(() => envoiEnCours = true);
                            try {
                              await context.read<AuthService>().confirmPasswordReset(
                                    token: codeController.text.trim(),
                                    nouveauMotDePasse: nouveauMotDePasseController.text,
                                  );
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              _showSnack('Mot de passe mis à jour avec succès.');
                            } on ApiException catch (e) {
                              setModalState(() => envoiEnCours = false);
                              if (!mounted) return;
                              _showSnack(e.message);
                            }
                          },
                    child: Text(envoiEnCours ? s.parametresValidationEnCours : s.parametresValiderNouveauMdpBouton),
                  ),
                ),
              ],
            ],
          ),
        );
        },
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