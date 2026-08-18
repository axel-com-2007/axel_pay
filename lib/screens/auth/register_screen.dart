// ============================================================
// ÉCRAN D'INSCRIPTION
// ============================================================
// REFONTE — reprend fidèlement la maquette "new_page_creation_compte" :
// bandeau photo en tête avec badge "NEW AGENCY", titre "AxelPay" en
// turquoise, champs en style "soulignés" (sans fond), pastilles rondes
// pour la situation matrimoniale, case CGU encadrée, bouton plein
// "Créer mon compte" et lien "Déjà un compte ?".
//
// Cahier des charges 5.1 :
//  - Champs obligatoires : Nom, Prénom, Téléphone (+237), E-mail,
//    Quartier, Situation matrimoniale, Mot de passe renforcé.
//  - Case CGU obligatoire (consentement RGPD horodaté/versionné,
//    cf. User_Consent_Logs en section 8).
//  - Mot de passe renforcé : 12 caractères minimum, majuscule,
//    minuscule, chiffre, caractère spécial (règle 11.1).
//
// Branché sur AuthService.register() (POST /auth/register/). Le mot de
// passe est transmis en mémoire à OtpScreen pour permettre une connexion
// automatique juste après la vérification OTP — RegisterView ne renvoie
// aucun token, seul LoginView en émet (voir commentaire dans OtpScreen).
//
// ⚠️ Consentement RGPD (POST /profile/consent/, UserConsentView) : cet
// endpoint exige IsAuthenticated côté backend, alors que l'utilisateur
// n'a pas encore de token à ce stade (register ne connecte pas). Le
// consentement ne peut donc être enregistré qu'APRÈS la connexion
// automatique dans OtpScreen — pas ici. C'est une limitation du backend
// actuel à garder en tête, pas un oubli de cet écran.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/auth_service.dart';
import '../../api/api_exception.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/primary_button.dart';
import '../../design_system/responsive/responsive_utils.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final nomController = TextEditingController();
  final prenomController = TextEditingController();
  final telephoneController = TextEditingController(text: '+237');
  final emailController = TextEditingController();
  final quartierController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String situationMatrimoniale = 'Célibataire';
  bool cguAcceptees = false;
  bool obscurePassword = true;
  bool loading = false;
  final ShakeController _shakeForm = ShakeController();

  static const situations = [
    'Célibataire',
    'Marié(e)',
    'Divorcé(e)',
    'Veuf / Veuve',
  ];

  @override
  void dispose() {
    nomController.dispose();
    prenomController.dispose();
    telephoneController.dispose();
    emailController.dispose();
    quartierController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    final s = S.read(context);
    if (value == null || value.length < 12) {
      return s.registerMdp12CaracteresMin;
    }
    final hasUpper = value.contains(RegExp(r'[A-Z]'));
    final hasLower = value.contains(RegExp(r'[a-z]'));
    final hasDigit = value.contains(RegExp(r'[0-9]'));
    final hasSpecial = value.contains(RegExp(r'[!@#\$&*~%^()\-_=+]'));
    if (!hasUpper || !hasLower || !hasDigit || !hasSpecial) {
      return s.registerMdpComplexite;
    }
    return null;
  }

  Future<void> _sInscrire() async {
    if (!_formKey.currentState!.validate()) return;
    if (!cguAcceptees) {
      _showSnack(S.read(context).registerCguObligatoire);
      _shakeForm.shake();
      return;
    }

    final auth = context.read<AuthService>();
    final telephone = telephoneController.text.trim();
    final motDePasse = passwordController.text;

    setState(() => loading = true);
    try {
      await auth.register(
        nom: nomController.text.trim(),
        prenom: prenomController.text.trim(),
        telephone: telephone,
        email: emailController.text.trim(),
        motDePasse: motDePasse,
        situationMatrimoniale: situationMatrimoniale,
        quartier: quartierController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          // Le mot de passe est transmis pour permettre la connexion
          // automatique après vérification OTP (voir otp_screen.dart).
          builder: (_) => OtpScreen(telephone: telephone, motDePasse: motDePasse),
        ),
      );
    } on ApiValidationException catch (e) {
      // Ex: "telephone": "Ce numéro est déjà utilisé." (RegisterView)
      _showSnack(e.firstMessage);
      _shakeForm.shake();
    } on ApiException catch (e) {
      _showSnack(e.message);
      _shakeForm.shake();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Form(
          key: _formKey,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: context.isDesktop
                    ? AppBreakpoints.maxFormWidth + 80
                    : context.isTablet
                        ? AppBreakpoints.maxFormWidth
                        : double.infinity,
              ),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== Bandeau photo + badge "NEW AGENCY" =====
              // Voir README_ASSETS.md : image ajoutée via pubspec.yaml puis
              // affichée avec Image.asset('assets/images/header_banner.jpg').
              const _HeaderBanner(),

              ShakeWidget(
                controller: _shakeForm,
                child: FadeSlideIn(
                  offsetY: 18,
                  child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.isDesktop ? 40 : context.isTablet ? 32 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Center(child: Text('AxelPay', style: AppTextStyles.brand)),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        s.authTagline,
                        style: AppTextStyles.bodyMuted,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 28),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _UnderlineField(
                            label: s.registerPrenomLabel,
                            controller: prenomController,
                            hint: 'Axel',
                            validator: _required,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _UnderlineField(
                            label: s.registerNomLabel,
                            controller: nomController,
                            hint: 'Mai',
                            validator: _required,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    _UnderlineField(
                      label: s.registerTelephoneLabel,
                      controller: telephoneController,
                      hint: '+237 6XX XXX XXX',
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || !v.startsWith('+237') || v.trim().length < 13) {
                          return s.registerTelephoneFormatInvalide;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),

                    _UnderlineField(
                      label: s.registerQuartierLabel,
                      controller: quartierController,
                      hint: 'ex: Bonamoussadi, Douala',
                      validator: _required,
                    ),
                    const SizedBox(height: 22),

                    _UnderlineField(
                      label: s.registerEmailLabel,
                      controller: emailController,
                      hint: 'vous@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || !v.contains('@')) return s.registerEmailInvalide;
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),

                    // NOTE i18n : ce libellé affichait par erreur "Quartier"
                    // au-dessus des pastilles de situation matrimoniale
                    // (copier/coller avec le champ Quartier ci-dessus,
                    // corrigé au passage — cf. registerSituationMatrimonialeLabel).
                    Text(s.registerSituationMatrimonialeLabel, style: AppTextStyles.label),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 14,
                      runSpacing: 12,
                      children: situations.map((valeur) {
                        final selected = valeur == situationMatrimoniale;
                        return _StatusCircleChip(
                          label: s.situationLabel(valeur),
                          selected: selected,
                          onTap: () => setState(() => situationMatrimoniale = valeur),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 26),

                    _UnderlineField(
                      label: s.registerMotDePasseLabel,
                      controller: passwordController,
                      hint: 'Min. 12 caractères, Aa1!',
                      obscureText: obscurePassword,
                      validator: _validatePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () => setState(() => obscurePassword = !obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 22),

                    _UnderlineField(
                      label: s.registerConfirmMotDePasseLabel,
                      controller: confirmPasswordController,
                      hint: s.registerConfirmMotDePasseHint,
                      obscureText: obscurePassword,
                      validator: (v) {
                        if (v != passwordController.text) return s.registerMotsDePasseDifferents;
                        return null;
                      },
                    ),
                    const SizedBox(height: 26),

                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                      onTap: () => setState(() => cguAcceptees = !cguAcceptees),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.divider),
                          borderRadius: BorderRadius.circular(AppRadius.field),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              cguAcceptees ? Icons.check_circle : Icons.circle_outlined,
                              color: cguAcceptees ? AppColors.primary : AppColors.textMuted,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                s.registerCguLabel,
                                style: AppTextStyles.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        s.registerPolitiqueConfidentialite,
                        style: AppTextStyles.caption,
                      ),
                    ),
                    const SizedBox(height: 28),

                    PrimaryButton(
                      label: s.registerBouton,
                      loading: loading,
                      onPressed: _sInscrire,
                    ),
                    const SizedBox(height: 20),

                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              s.registerDejaUnCompte,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? S.read(context).authChampRequis : null;
}

/// Bandeau photo en tête d'écran avec badge "NEW AGENCY", tel que dans
/// la maquette fournie. L'image est chargée depuis les assets du
/// projet — voir README_ASSETS.md pour la marche à suivre complète.
class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(AppRadius.banner),
              bottomRight: Radius.circular(AppRadius.banner),
            ),
            child: Image.asset(
              'assets/images/header_banner.jpg',
              fit: BoxFit.cover,
              // Si l'asset n'est pas encore déclaré dans pubspec.yaml,
              // on retombe sur un dégradé turquoise plutôt que de planter.
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.secondaryGreen,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8),
                ],
              ),
              child: const Text(
                'NEW AGENCY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Champ "souligné" (sans fond), fidèle au style de la maquette
/// d'inscription : libellé au-dessus, simple trait fin en dessous.
class _UnderlineField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _UnderlineField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: hint,
            filled: false,
            isDense: true,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.only(bottom: 10),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.divider),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.divider),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary, width: 1.6),
            ),
            errorBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.danger),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pastille ronde utilisée pour la situation matrimoniale, reprenant
/// le style "cercles turquoise" de la maquette (plein quand
/// sélectionné, dégradé plus clair sinon).
class _StatusCircleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusCircleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 78,
        height: 78,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.primary : AppColors.primary.withOpacity(0.35),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 10)]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
