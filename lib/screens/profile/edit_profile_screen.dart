// ============================================================
// MODIFIER MON PROFIL
// ============================================================
// Ouvert depuis l'avatar (cercle bleu) du dashboard. Permet au client de
// modifier les informations de son profil qui ne dépendent pas d'un flux
// de vérification dédié (le téléphone passe par ChangePhoneNumberView,
// le mot de passe par le flux de réinitialisation par code — cf.
// SettingsScreen).
//
// Branché sur PATCH /api/profile/ (`ProfileView`, RetrieveUpdateAPIView).
// ============================================================

import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/eneo_repository.dart';
import '../../design_system/buttons/app_button.dart';
import '../../models/models.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final UserModel? user;

  const EditProfileScreen({super.key, this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = EneoRepository();

  late final TextEditingController _nomController;
  late final TextEditingController _prenomController;
  late final TextEditingController _quartierController;

  static const _situations = ['Célibataire', 'Marié(e)', 'Divorcé(e)', 'Veuf(ve)'];
  String? _situationMatrimoniale;

  bool _enregistrementEnCours = false;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _nomController = TextEditingController(text: user?.nom ?? '');
    _prenomController = TextEditingController(text: user?.prenom ?? '');
    _quartierController = TextEditingController(text: user?.quartier ?? '');
    final situationActuelle = user?.situationMatrimoniale;
    _situationMatrimoniale =
        (situationActuelle != null && _situations.contains(situationActuelle))
            ? situationActuelle
            : null;
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _quartierController.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enregistrementEnCours = true);
    try {
      final champs = <String, dynamic>{
        'nom': _nomController.text.trim(),
        'prenom': _prenomController.text.trim(),
        'quartier': _quartierController.text.trim(),
        if (_situationMatrimoniale != null)
          'situation_matrimoniale': _situationMatrimoniale,
      };
      await _repo.updateProfile(champs);
      if (!mounted) return;
      Navigator.pop(context, true); // signale au dashboard qu'il faut rafraîchir
    } on ApiValidationException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrementEnCours = false);
      _showSnack(e.firstMessage);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrementEnCours = false);
      _showSnack(e.message);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user?.initiales ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: 'Prénom',
                controller: _prenomController,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Le prénom est obligatoire.' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Nom',
                controller: _nomController,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Le nom est obligatoire.' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Quartier',
                hintText: 'Ex : Bonapriso',
                controller: _quartierController,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Situation matrimoniale', style: AppTextStyles.label),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _situations.map((option) {
                  final actif = option == _situationMatrimoniale;
                  return ChoiceChip(
                    label: Text(option),
                    selected: actif,
                    onSelected: (_) => setState(() => _situationMatrimoniale = option),
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
              ),
              const SizedBox(height: 12),
              AppCardInfo(
                text: 'Le numéro de téléphone et le mot de passe se modifient depuis '
                    'l\'écran Paramètres, avec vérification dédiée.',
              ),
              const SizedBox(height: 28),
              AppButton.primary(
                label: _enregistrementEnCours ? 'Enregistrement…' : 'Enregistrer',
                loading: _enregistrementEnCours,
                onPressed: _enregistrementEnCours ? null : _enregistrer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit encart informatif — évite de dépendre d'un widget partagé qui
/// n'existe pas déjà dans le design system pour ce cas précis.
class AppCardInfo extends StatelessWidget {
  final String text;
  const AppCardInfo({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTextStyles.caption)),
        ],
      ),
    );
  }
}
