// ============================================================
// OUVRIR UN TICKET DE SUPPORT (module 11 backend)
// ============================================================
// Formulaire réel (sujet + description + catégorie + priorité) branché
// sur POST /api/support/tickets/ouvrir/ (`OuvrirTicketView`). Le serveur :
//   - crée un litige de Niveau 1 en base ;
//   - envoie un e-mail HTML de confirmation au client, avec la fiche du
//     ticket jointe en PDF (document que le client peut imprimer/garder) ;
//   - envoie un e-mail au support avec le dossier complet du client.
// ============================================================

import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/eneo_repository.dart';
import '../../design_system/buttons/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../theme/app_theme.dart';

class OpenTicketScreen extends StatefulWidget {
  const OpenTicketScreen({super.key});

  @override
  State<OpenTicketScreen> createState() => _OpenTicketScreenState();
}

class _OpenTicketScreenState extends State<OpenTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = EneoRepository();

  final _sujetController = TextEditingController();
  final _descriptionController = TextEditingController();

  static const _categories = ['Facturation', 'Recharge', 'Technique', 'Paiement', 'Autre'];
  static const _priorites = ['Normale', 'Haute', 'Urgente'];

  String _categorie = 'Autre';
  String _priorite = 'Normale';
  bool _envoiEnCours = false;

  @override
  void dispose() {
    _sujetController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _envoiEnCours = true);
    try {
      final resultat = await _repo.ouvrirTicket(
        sujet: _sujetController.text.trim(),
        description: _descriptionController.text.trim(),
        categorie: _categorie,
        priorite: _priorite,
      );
      if (!mounted) return;
      setState(() => _envoiEnCours = false);
      await _afficherConfirmation(resultat);
    } on ApiValidationException catch (e) {
      if (!mounted) return;
      setState(() => _envoiEnCours = false);
      _showSnack(e.firstMessage);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _envoiEnCours = false);
      _showSnack(e.message);
    }
  }

  Future<void> _afficherConfirmation(Map<String, dynamic> resultat) async {
    final ticketId = resultat['ticket_id'] as String? ?? '';
    final emailEnvoye = resultat['email_client_envoye'] == true;
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text('Ticket ouvert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Numéro de ticket : $ticketId', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            Text(
              emailEnvoye
                  ? 'Un e-mail de confirmation vient de vous être envoyé, avec la fiche '
                    'de votre ticket au format PDF en pièce jointe. Notre équipe répond '
                    'sous 24h ouvrées.'
                  : 'Votre ticket a bien été enregistré, mais l’envoi de l’e-mail de '
                    'confirmation a échoué. Notre équipe traitera votre demande sous '
                    '24h ouvrées.',
              style: AppTextStyles.bodyMuted,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // ferme la boîte de dialogue
              Navigator.pop(context, true); // revient à l'écran précédent
            },
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Ouvrir un ticket')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Décrivez votre problème, notre équipe vous répond sous 24h ouvrées. '
                'Vous recevrez un e-mail de confirmation avec votre ticket en PDF.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 20),
              AppTextField(
                label: 'Sujet',
                hintText: 'Ex : Facture de janvier incorrecte',
                controller: _sujetController,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Le sujet est obligatoire.';
                  if (value.length > 200) return 'Maximum 200 caractères.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Description',
                hintText: 'Décrivez votre problème en détail (20 caractères minimum)…',
                controller: _descriptionController,
                maxLines: 6,
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'La description est obligatoire.';
                  if (value.length < 20) return 'Minimum 20 caractères pour une description utile.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Catégorie', style: AppTextStyles.label),
              ),
              const SizedBox(height: 8),
              _ChoixPuces(
                options: _categories,
                selection: _categorie,
                onSelected: (v) => setState(() => _categorie = v),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Priorité', style: AppTextStyles.label),
              ),
              const SizedBox(height: 8),
              _ChoixPuces(
                options: _priorites,
                selection: _priorite,
                onSelected: (v) => setState(() => _priorite = v),
              ),
              const SizedBox(height: 28),
              AppButton.primary(
                label: _envoiEnCours ? 'Envoi…' : 'Envoyer le ticket',
                loading: _envoiEnCours,
                onPressed: _envoiEnCours ? null : _soumettre,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoixPuces extends StatelessWidget {
  final List<String> options;
  final String selection;
  final ValueChanged<String> onSelected;

  const _ChoixPuces({
    required this.options,
    required this.selection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final actif = option == selection;
        return ChoiceChip(
          label: Text(option),
          selected: actif,
          onSelected: (_) => onSelected(option),
          selectedColor: AppColors.primary.withOpacity(0.15),
          labelStyle: TextStyle(
            color: actif ? AppColors.primaryDark : AppColors.textSecondary,
            fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
          ),
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: actif ? AppColors.primary : AppColors.divider),
          ),
        );
      }).toList(),
    );
  }
}
