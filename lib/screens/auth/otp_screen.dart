// ============================================================
// ÉCRAN DE VÉRIFICATION OTP
// ============================================================
// Cahier des charges 5.1 : "Valide l'inscription via l'envoi et la
// saisie d'un code OTP à 6 chiffres reçu par SMS." Chaque chiffre a
// sa propre case, avec passage automatique au champ suivant — un
// classique des parcours OTP mobiles.
//
// Branché sur AuthService.verifyOtp() (POST /auth/verify-otp/).
// VerifyOTPView ne renvoie aucun token — seul LoginView en émet — donc
// si `motDePasse` est fourni (venant de RegisterScreen), on enchaîne
// automatiquement sur AuthService.login() pour éviter de redemander le
// mot de passe que l'utilisateur vient de saisir. Sans `motDePasse`
// (ex: réutilisation de cet écran pour confirmer un changement de
// numéro), on affiche juste une confirmation et on revient en arrière.
// ============================================================

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../api/auth_service.dart';
import '../../api/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/primary_button.dart';

class OtpScreen extends StatefulWidget {
  final String telephone;

  /// Mot de passe en clair, gardé UNIQUEMENT en mémoire le temps de ce
  /// flux, pour la connexion automatique post-vérification. `null` si
  /// cet écran est utilisé hors inscription (ex: changement de numéro).
  final String? motDePasse;

  const OtpScreen({super.key, required this.telephone, this.motDePasse});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());

  bool loading = false;
  int secondesAvantRenvoi = 60;
  final ShakeController _shakeCode = ShakeController();

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get code => controllers.map((c) => c.text).join();

  Future<void> _verifier() async {
    if (code.length != 6) {
      _showSnack('Saisissez les 6 chiffres reçus par SMS');
      _shakeCode.shake();
      return;
    }

    final auth = context.read<AuthService>();
    setState(() => loading = true);
    try {
      await auth.verifyOtp(telephone: widget.telephone, otp: code);

      final motDePasse = widget.motDePasse;
      if (motDePasse != null) {
        await auth.login(identifiant: widget.telephone, motDePasse: motDePasse);

        // Consentement RGPD (CDC 5.1/11.3) : ne peut être enregistré
        // qu'APRÈS la connexion, car POST /profile/consent/ exige
        // IsAuthenticated côté backend (RegisterView seul ne donne pas
        // de token). La case CGU a déjà été validée comme obligatoire
        // dans RegisterScreen avant d'arriver jusqu'ici — on trace donc
        // un GRANTED. Erreur volontairement absorbée : un échec de
        // journalisation ne doit pas bloquer un compte par ailleurs
        // créé et connecté avec succès (à surveiller côté logs serveur).
        try {
          await auth.recordConsent(action: 'GRANTED');
        } catch (e) {
          // Non bloquant — voir commentaire ci-dessus. On attrape TOUT
          // (pas seulement ApiException) : une erreur de parsing ou tout
          // autre souci inattendu ici ne doit jamais empêcher la
          // navigation vers MainShell puisque le login a déjà réussi.
          debugPrint('recordConsent a échoué (non bloquant) : $e');
        }

        // ⚠️ CORRECTIF NAVIGATION : `AuthGate` (main.dart) bascule bien
        // tout seul vers `MainShell` quand `auth.status` passe à
        // `authenticated`, MAIS uniquement à la RACINE de la pile de
        // navigation. Cet écran (`OtpScreen`) a été ouvert par
        // `Navigator.push` depuis `RegisterScreen`, lui-même poussé par
        // `Navigator.push` depuis `LoginScreen` : la pile réelle est
        // [AuthGate → RegisterScreen → OtpScreen]. Sans ce `popUntil`,
        // `MainShell` se substitue bien à `LoginScreen` tout en bas de
        // la pile, mais `RegisterScreen`/`OtpScreen` restent affichés
        // par-dessus et bloquent totalement la vue — d'où l'impression
        // que "rien ne se passe" après une connexion pourtant réussie.
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        if (!mounted) return;
        Navigator.of(context).pop();
        _showSnack('Compte vérifié. Vous pouvez maintenant vous connecter.');
      }
    } on ApiValidationException catch (e) {
      // Ex: "otp": "Code invalide ou expiré." (VerifyOTPView)
      _showSnack(e.firstMessage);
      _shakeCode.shake();
      for (final c in controllers) {
        c.clear();
      }
      FocusScope.of(context).requestFocus(focusNodes.first);
    } on ApiException catch (e) {
      _showSnack(e.message);
      _shakeCode.shake();
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
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Vérification')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Lottie.asset(
                  LottieAssets.password,
                  width: 120,
                  height: 120,
                  repeat: true,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Entrez le code reçu', style: AppTextStyles.h2),
              const SizedBox(height: 6),
              Text(
                'Un code à 6 chiffres a été envoyé au ${widget.telephone}',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 28),

              ShakeWidget(
                controller: _shakeCode,
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  return SizedBox(
                    width: 44,
                    child: TextField(
                      controller: controllers[i],
                      focusNode: focusNodes[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(counterText: ''),
                      onChanged: (value) {
                        if (value.isNotEmpty && i < 5) {
                          FocusScope.of(context).requestFocus(focusNodes[i + 1]);
                        }
                        if (value.isEmpty && i > 0) {
                          FocusScope.of(context).requestFocus(focusNodes[i - 1]);
                        }
                        setState(() {});
                      },
                    ),
                  );
                }),
                ),
              ),
              const SizedBox(height: 24),

              Center(
                child: TextButton(
                  // ⚠️ Pas de véritable endpoint de renvoi dans urls.py — un
                  // second appel à /auth/register/ échouerait (téléphone déjà
                  // utilisé). Ce bouton reste donc cosmétique tant qu'un
                  // endpoint dédié (ex: POST /auth/resend-otp/) n'existe pas
                  // côté backend. À brancher dès qu'il sera ajouté.
                  onPressed: secondesAvantRenvoi == 0
                      ? () => setState(() => secondesAvantRenvoi = 60)
                      : null,
                  child: Text(
                    secondesAvantRenvoi == 0
                        ? 'Renvoyer le code'
                        : 'Renvoyer le code (${secondesAvantRenvoi}s)',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(label: 'Valider', loading: loading, onPressed: _verifier),
            ],
          ),
        ),
      ),
    );
  }
}
