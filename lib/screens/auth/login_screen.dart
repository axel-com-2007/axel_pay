// ============================================================
// ÉCRAN DE CONNEXION
// ============================================================
// REFONTE — reprend fidèlement la maquette "new_page_sign" :
// carte blanche centrée, flottante, avec titre "AxelPay" en
// turquoise, sous-titre, champs simples et bouton "Se connecter"
// pleine largeur en turquoise. Branché sur AuthService pour un
// vrai appel à POST /auth/login/.
//
// Rappel cahier des charges (5.1) : verrouillage du compte 1h après 5
// tentatives échouées — cette règle est appliquée CÔTÉ SERVEUR
// (LoginView) et remonte ici sous forme d'ApiPermissionException. Pas
// de simulation locale : le compteur d'échecs vit en base, pas dans
// l'état du widget.
// ============================================================

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../api/auth_service.dart';
import '../../api/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/primary_button.dart';
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
      // Pas de Navigator.push ici : AuthGate (main.dart) observe
      // auth.status et affiche MainShell automatiquement dès que le
      // login réussit.
    } on ApiPermissionException catch (e) {
      // Compte verrouillé après 5 tentatives échouées (LoginView).
      _showSnack(e.message);
      _shakeCarte.shake();
    } on ApiValidationException catch (e) {
      // Identifiants invalides.
      _showSnack(e.firstMessage);
      _shakeCarte.shake();
    } on ApiException catch (e) {
      // Réseau, serveur, etc.
      _showSnack(e.message);
      _shakeCarte.shake();
    } catch (e) {
      // Filet de sécurité : erreur inattendue (ex: réponse serveur mal
      // formée). On affiche quelque chose plutôt que de rester bloqué
      // sans rien à l'écran.
      _showSnack('Erreur inattendue : $e');
      _shakeCarte.shake();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Stack(
          children: [
            // Motif décoratif discret en arrière-plan (identité visuelle)
            const _NetworkPattern(),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
                    child: FadeSlideIn(
                      offsetY: 24,
                      child: ShakeWidget(
                        controller: _shakeCarte,
                        child: Container(
                      padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ===== Illustration Lottie + logo / marque =====
                            Lottie.asset(
                              LottieAssets.login,
                              width: 140,
                              height: 140,
                              repeat: true,
                            ),
                            const Text('AxelPay', style: AppTextStyles.brand),
                            const SizedBox(height: 10),
                            const Text(
                              'Gérez vos factures et recharges Eneo',
                              style: AppTextStyles.bodyMuted,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 30),

                            // ===== Identifiant =====
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Adresse e-mail ou numéro de téléphone :',
                                  style: AppTextStyles.label),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: identifiantController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: 'ex: axel.mai@example.com',
                                fillColor: const Color(0xFFF4F6F5),
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.field),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Ce champ est obligatoire';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 22),

                            // ===== Mot de passe =====
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Mot de passe', style: AppTextStyles.label),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: passwordController,
                              obscureText: obscurePassword,
                              decoration: InputDecoration(
                                hintText: 'Entrez votre mot de passe',
                                fillColor: const Color(0xFFF4F6F5),
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.field),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePassword ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.black45,
                                  ),
                                  onPressed: () =>
                                      setState(() => obscurePassword = !obscurePassword),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Mot de passe requis';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 26),

                            PrimaryButton(
                              label: 'Se connecter',
                              loading: loading,
                              onPressed: _seConnecter,
                            ),
                            const SizedBox(height: 18),

                            GestureDetector(
                              onTap: () async {
                                final identifiant = identifiantController.text.trim();
                                if (identifiant.isEmpty) {
                                  _showSnack('Renseigne ton e-mail ou ton téléphone d\'abord.');
                                  return;
                                }
                                try {
                                  await context
                                      .read<AuthService>()
                                      .requestPasswordReset(identifiant: identifiant);
                                } on ApiException {
                                  // Réponse volontairement neutre côté backend :
                                  // on affiche le même message même en cas d'erreur.
                                }
                                if (!mounted) return;
                                _showSnack(
                                    'Si ce compte existe, des instructions ont été envoyées.');
                              },
                              child: const Text(
                                'Mot de passe oublié ?',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const RegisterScreen()),
                              ),
                              child: const Text(
                                'Créer un compte',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Motif géométrique discret (traits + points) en arrière-plan, très
/// proche de la texture "réseau" visible en fond des maquettes
/// fournies. Volontairement léger (faible opacité) pour ne pas nuire
/// à la lisibilité du formulaire.
class _NetworkPattern extends StatelessWidget {
  const _NetworkPattern();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _NetworkPainter(),
        ),
      ),
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
