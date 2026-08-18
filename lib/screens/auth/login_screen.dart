// ============================================================
// ÉCRAN DE CONNEXION — RESPONSIVE
// ============================================================
// Adaptatif sur tous les écrans :
//   • mobile  : carte centrée pleine largeur (comportement d'origine)
//   • tablet  : carte blanche contrainte à 480 px, centrée
//   • desktop : layout 2 colonnes — illustration à gauche, formulaire
//               dans une carte à droite
// ============================================================

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../api/auth_service.dart';
import '../../api/api_exception.dart';
import '../../design_system/responsive/responsive_utils.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/primary_button.dart';
import '../../shared/widgets/app_text_field.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController identifiantController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool loading = false;
  final ShakeController _shakeCarte = ShakeController();

  @override
  void dispose() {
    identifiantController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _seConnecter() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    setState(() => loading = true);

    try {
      await auth.login(
        identifiant: identifiantController.text.trim(),
        motDePasse: passwordController.text,
      );
    } on ApiPermissionException catch (e) {
      _showSnack(e.message);
      _shakeCarte.shake();
    } on ApiValidationException catch (e) {
      _showSnack(e.firstMessage);
      _shakeCarte.shake();
    } on ApiException catch (e) {
      _showSnack(e.message);
      _shakeCarte.shake();
    } catch (e) {
      if (mounted) _showSnack(S.read(context).erreurInattendue('$e'));
      _shakeCarte.shake();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Stack(
          children: [
            const _NetworkPattern(),
            SafeArea(
              child: ResponsiveLayout(
                mobile: _MobileLogin(
                  formKey: _formKey,
                  identifiantController: identifiantController,
                  passwordController: passwordController,
                  obscurePassword: obscurePassword,
                  loading: loading,
                  shakeCarte: _shakeCarte,
                  onTogglePassword: () =>
                      setState(() => obscurePassword = !obscurePassword),
                  onLogin: _seConnecter,
                  onShowSnack: _showSnack,
                ),
                tablet: _TabletLogin(
                  formKey: _formKey,
                  identifiantController: identifiantController,
                  passwordController: passwordController,
                  obscurePassword: obscurePassword,
                  loading: loading,
                  shakeCarte: _shakeCarte,
                  onTogglePassword: () =>
                      setState(() => obscurePassword = !obscurePassword),
                  onLogin: _seConnecter,
                  onShowSnack: _showSnack,
                ),
                desktop: _DesktopLogin(
                  formKey: _formKey,
                  identifiantController: identifiantController,
                  passwordController: passwordController,
                  obscurePassword: obscurePassword,
                  loading: loading,
                  shakeCarte: _shakeCarte,
                  onTogglePassword: () =>
                      setState(() => obscurePassword = !obscurePassword),
                  onLogin: _seConnecter,
                  onShowSnack: _showSnack,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// FORMULAIRE PARTAGÉ
// ────────────────────────────────────────────────────────────
class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.identifiantController,
    required this.passwordController,
    required this.obscurePassword,
    required this.loading,
    required this.shakeCarte,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onShowSnack,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController identifiantController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool loading;
  final ShakeController shakeCarte;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final void Function(String) onShowSnack;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gap = AppResponsiveSpacing.fieldGap(context);

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo Lottie + titre
          Lottie.asset(
            LottieAssets.login,
            width: context.isDesktop ? 120 : 140,
            height: context.isDesktop ? 120 : 140,
            repeat: true,
          ),
          Text(
            'AxelPay',
            style: AppResponsiveText.brand(context)
                .copyWith(color: AppColors.primaryBlue),
          ),
          const SizedBox(height: 8),
          Text(
            s.authTagline,
            style: AppTextStyles.bodyMuted,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: gap + 8),

          // Identifiant
          AppTextField(
            label: s.loginIdentifiantLabel,
            controller: identifiantController,
            keyboardType: TextInputType.emailAddress,
            hintText: s.loginIdentifiantHint,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return s.authChampObligatoire;
              return null;
            },
          ),
          SizedBox(height: gap),

          // Mot de passe
          AppTextField(
            label: s.loginMotDePasseLabel,
            controller: passwordController,
            obscureText: obscurePassword,
            hintText: s.loginMotDePasseHint,
            suffixIcon: IconButton(
              icon: Icon(
                obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.black45,
              ),
              onPressed: onTogglePassword,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return s.loginMotDePasseRequis;
              return null;
            },
          ),
          SizedBox(height: gap + 4),

          PrimaryButton(
            label: s.loginBouton,
            loading: loading,
            onPressed: onLogin,
          ),
          const SizedBox(height: 16),

          // Mot de passe oublié
          GestureDetector(
            onTap: () async {
              final identifiant = identifiantController.text.trim();
              if (identifiant.isEmpty) {
                onShowSnack(S.read(context).loginRenseigneIdentifiantDabord);
                return;
              }
              try {
                await context
                    .read<AuthService>()
                    .requestPasswordReset(identifiant: identifiant);
              } on ApiException {
                // Réponse neutre côté backend.
              }
              if (context.mounted) {
                onShowSnack(S.read(context).loginResetInstructionsEnvoyees);
              }
            },
            child: Text(
              s.loginMotDePasseOublie,
              style: TextStyle(
                fontSize: AppResponsiveText.scale(context, 13),
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Créer un compte
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RegisterScreen()),
            ),
            child: Text(
              s.loginCreerUnCompte,
              style: TextStyle(
                fontSize: AppResponsiveText.scale(context, 13),
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// MOBILE — carte centrée pleine largeur (comportement d'origine)
// ────────────────────────────────────────────────────────────
class _MobileLogin extends StatelessWidget {
  const _MobileLogin({
    required this.formKey,
    required this.identifiantController,
    required this.passwordController,
    required this.obscurePassword,
    required this.loading,
    required this.shakeCarte,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onShowSnack,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController identifiantController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool loading;
  final ShakeController shakeCarte;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final void Function(String) onShowSnack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: FadeSlideIn(
            offsetY: 24,
            child: ShakeWidget(
              controller: shakeCarte,
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: _LoginForm(
                  formKey: formKey,
                  identifiantController: identifiantController,
                  passwordController: passwordController,
                  obscurePassword: obscurePassword,
                  loading: loading,
                  shakeCarte: shakeCarte,
                  onTogglePassword: onTogglePassword,
                  onLogin: onLogin,
                  onShowSnack: onShowSnack,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// TABLET — carte contrainte à 480 px, centrée
// ────────────────────────────────────────────────────────────
class _TabletLogin extends StatelessWidget {
  const _TabletLogin({
    required this.formKey,
    required this.identifiantController,
    required this.passwordController,
    required this.obscurePassword,
    required this.loading,
    required this.shakeCarte,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onShowSnack,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController identifiantController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool loading;
  final ShakeController shakeCarte;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final void Function(String) onShowSnack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
        child: FadeSlideIn(
          offsetY: 24,
          child: ShakeWidget(
            controller: shakeCarte,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.maxFormWidth),
              child: Container(
                padding: const EdgeInsets.fromLTRB(36, 44, 36, 40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 40,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: _LoginForm(
                  formKey: formKey,
                  identifiantController: identifiantController,
                  passwordController: passwordController,
                  obscurePassword: obscurePassword,
                  loading: loading,
                  shakeCarte: shakeCarte,
                  onTogglePassword: onTogglePassword,
                  onLogin: onLogin,
                  onShowSnack: onShowSnack,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// DESKTOP — 2 colonnes : branding gauche | formulaire droite
// ────────────────────────────────────────────────────────────
class _DesktopLogin extends StatelessWidget {
  const _DesktopLogin({
    required this.formKey,
    required this.identifiantController,
    required this.passwordController,
    required this.obscurePassword,
    required this.loading,
    required this.shakeCarte,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onShowSnack,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController identifiantController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool loading;
  final ShakeController shakeCarte;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final void Function(String) onShowSnack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Colonne branding ──────────────────────────────────
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            child: const _BrandingPanel(),
          ),
        ),

        // ── Colonne formulaire ────────────────────────────────
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: FadeSlideIn(
                offsetY: 24,
                child: ShakeWidget(
                  controller: shakeCarte,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: AppBreakpoints.maxFormWidth),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(40, 48, 40, 44),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: _LoginForm(
                        formKey: formKey,
                        identifiantController: identifiantController,
                        passwordController: passwordController,
                        obscurePassword: obscurePassword,
                        loading: loading,
                        shakeCarte: shakeCarte,
                        onTogglePassword: onTogglePassword,
                        onLogin: onLogin,
                        onShowSnack: onShowSnack,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// Panneau de branding (desktop gauche)
// ────────────────────────────────────────────────────────────
class _BrandingPanel extends StatelessWidget {
  const _BrandingPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 36,
              backgroundColor: Colors.white24,
              child: Icon(Icons.bolt, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 32),
            const Text(
              'AxelPay',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Gérez vos factures d électricité\nen toute simplicité.',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white.withOpacity(0.85),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            _FeatureRow(
              icon: Icons.flash_on,
              text: 'Paiement en quelques secondes',
            ),
            const SizedBox(height: 16),
            _FeatureRow(
              icon: Icons.notifications_active_outlined,
              text: 'Alertes avant coupure',
            ),
            const SizedBox(height: 16),
            _FeatureRow(
              icon: Icons.history,
              text: 'Historique complet de vos contrats',
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// Motif géométrique de fond (identique à l'original)
// ────────────────────────────────────────────────────────────
class _NetworkPattern extends StatelessWidget {
  const _NetworkPattern();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(child: CustomPaint(painter: _NetworkPainter())),
    );
  }
}

class _NetworkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.primary.withOpacity(0.06)
      ..strokeWidth = 1;
    final dotPaint = Paint()..color = AppColors.primary.withOpacity(0.10);

    final points = <Offset>[
      Offset(size.width * 0.85, size.height * 0.06),
      Offset(size.width * 0.95, size.height * 0.14),
      Offset(size.width * 0.78, size.height * 0.18),
      Offset(size.width * 0.10, size.height * 0.10),
      Offset(size.width * 0.05, size.height * 0.30),
      Offset(size.width * 0.90, size.height * 0.85),
      Offset(size.width * 0.15, size.height * 0.92),
    ];

    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        if ((points[i] - points[j]).distance < size.width * 0.35) {
          canvas.drawLine(points[i], points[j], linePaint);
        }
      }
    }
    for (final p in points) {
      canvas.drawCircle(p, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
