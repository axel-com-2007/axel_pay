// ============================================================
// ASSISTANCE — APPELER / CHAT / AGENCE
// ============================================================
// Ouverte depuis l'icône assistance ajoutée à côté de la cloche de
// notification sur l'accueil. Propose 3 façons de joindre le support :
//  - Appeler un agent support (numéro copiable, pas d'intégration
//    téléphonique réelle disponible dans ce backend)
//  - Écrire un message à l'assistant de support IA (MODULE 10 backend,
//    `POST /support/chat/`) — cf. `SupportChatScreen`
//  - Passer à l'agence (ouvre la carte OpenStreetMap des agences Eneo)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../map_screen.dart';
import 'support_chat_screen.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String _numeroAgentSupport = '+237 233 42 12 12';

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<void> _copierNumero(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _numeroAgentSupport));
    if (!context.mounted) return;
    _showSnack(context, 'Numéro copié : $_numeroAgentSupport');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Assistance')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Comment pouvons-nous vous aider ?',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  SettingsTile(
                    icon: Icons.call_outlined,
                    iconColor: AppColors.primary,
                    title: 'Appeler un agent support',
                    subtitle: _numeroAgentSupport,
                    trailing: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textMuted),
                    onTap: () => _copierNumero(context),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  SettingsTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    iconColor: AppColors.secondaryGreenDark,
                    title: 'Écrire un message',
                    subtitle: 'Discuter avec l’assistant Eneo',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SupportChatScreen()),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  SettingsTile(
                    icon: Icons.storefront_outlined,
                    iconColor: AppColors.warning,
                    title: 'Passer à l’agence',
                    subtitle: 'Voir les agences Eneo sur la carte',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AgencyMapScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}