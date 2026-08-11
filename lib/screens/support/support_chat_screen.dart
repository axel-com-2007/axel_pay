// ============================================================
// CHAT AVEC L'ASSISTANT DE SUPPORT IA (MODULE 10)
// ============================================================
// Remplace le stub "Chat en direct — bientôt disponible" de
// `support_screen.dart`. Branché sur `POST /support/chat/`
// (`SupportChatView`) : l'assistant répond à partir du dossier réel du
// client connecté (contrats, factures impayées, litiges ouverts).
//
// L'historique de conversation est tenu ICI, côté client (pas de
// persistance : si l'utilisateur quitte l'écran, la conversation est
// perdue — comme un vrai chat de support qu'on recommence à zéro). Le
// serveur ne garde aucun état entre deux appels : on lui renvoie
// l'historique complet à chaque tour.
//
// Si l'assistant juge la situation hors de sa portée
// (`escalade_recommandee: true`), on affiche un bandeau proposant
// d'appeler un agent — sans jamais agir automatiquement à la place de
// l'utilisateur (pas d'ouverture de litige ni d'appel déclenché seul).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api/api_exception.dart';
import '../../data/eneo_repository.dart';
import '../../theme/app_theme.dart';

class _ChatMessage {
  final String role; // 'user' ou 'assistant'
  final String contenu;
  final bool escaladeRecommandee;
  const _ChatMessage({required this.role, required this.contenu, this.escaladeRecommandee = false});
}

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _repo = EneoRepository();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  static const String _numeroAgentSupport = '+237 233 42 12 12';

  final List<_ChatMessage> _historique = [
    const _ChatMessage(
      role: 'assistant',
      contenu: 'Bonjour 👋 Je suis l’assistant Eneo. Posez-moi une question sur '
          'votre facture, votre recharge ou un paiement — je réponds à partir de votre dossier.',
    ),
  ];
  bool _envoiEnCours = false;
  String? _erreur;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollVersLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _envoyer() async {
    final texte = _controller.text.trim();
    if (texte.isEmpty || _envoiEnCours) return;

    setState(() {
      _historique.add(_ChatMessage(role: 'user', contenu: texte));
      _controller.clear();
      _envoiEnCours = true;
      _erreur = null;
    });
    _scrollVersLeBas();

    // Le message d'accueil statique n'est jamais envoyé au serveur (ce
    // n'est pas un vrai tour de conversation, juste un texte d'accueil
    // affiché localement) — on ne transmet que les tours user/assistant
    // effectivement échangés avec l'API.
    final messagesApi = _historique
        .skip(1)
        .map((m) => {'role': m.role, 'content': m.contenu})
        .toList();

    try {
      final reponse = await _repo.supportChat(messagesApi);
      if (!mounted) return;
      setState(() {
        _historique.add(_ChatMessage(
          role: 'assistant',
          contenu: reponse['reponse'] as String? ?? '',
          escaladeRecommandee: reponse['escalade_recommandee'] as bool? ?? false,
        ));
        _envoiEnCours = false;
      });
      _scrollVersLeBas();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // On retire le message utilisateur raté n'aurait pas de sens ici :
        // on préfère le laisser visible et afficher l'erreur juste après,
        // avec un bouton pour réessayer le même envoi.
        _erreur = e.message;
        _envoiEnCours = false;
      });
    }
  }

  Future<void> _copierNumero() async {
    await Clipboard.setData(const ClipboardData(text: _numeroAgentSupport));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Numéro copié : $_numeroAgentSupport'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Assistant Eneo')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: _historique.length + (_envoiEnCours ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _historique.length) {
                    return const _BulleTypingIndicator();
                  }
                  return _BulleMessage(message: _historique[index], onAppelerAgent: _copierNumero);
                },
              ),
            ),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_erreur!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            _ZoneSaisie(
              controller: _controller,
              envoiEnCours: _envoiEnCours,
              onEnvoyer: _envoyer,
            ),
          ],
        ),
      ),
    );
  }
}

class _BulleMessage extends StatelessWidget {
  final _ChatMessage message;
  final VoidCallback onAppelerAgent;
  const _BulleMessage({required this.message, required this.onAppelerAgent});

  @override
  Widget build(BuildContext context) {
    final estUtilisateur = message.role == 'user';
    return Column(
      crossAxisAlignment: estUtilisateur ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: estUtilisateur ? AppColors.primary : AppColors.primaryBlueLight,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(estUtilisateur ? 14 : 4),
              bottomRight: Radius.circular(estUtilisateur ? 4 : 14),
            ),
          ),
          child: Text(
            message.contenu,
            style: TextStyle(
              color: estUtilisateur ? Colors.white : AppColors.textPrimary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
        if (!estUtilisateur && message.escaladeRecommandee)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: onAppelerAgent,
              icon: const Icon(Icons.call_outlined, size: 16),
              label: const Text('Appeler un agent support'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ),
      ],
    );
  }
}

class _BulleTypingIndicator extends StatelessWidget {
  const _BulleTypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryBlueLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox(
          width: 28,
          height: 12,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoneSaisie extends StatelessWidget {
  final TextEditingController controller;
  final bool envoiEnCours;
  final VoidCallback onEnvoyer;
  const _ZoneSaisie({required this.controller, required this.envoiEnCours, required this.onEnvoyer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !envoiEnCours,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onEnvoyer(),
              decoration: InputDecoration(
                hintText: 'Écrivez votre message…',
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: envoiEnCours ? null : onEnvoyer,
            icon: const Icon(Icons.arrow_upward_rounded),
            style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
