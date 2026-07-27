// ============================================================
// ÉCRAN DE TEST — validation bout-en-bout de AuthService.login()
// ============================================================
//
// Volontairement minimal : deux TextField + un bouton. Aucune navigation,
// aucun style particulier. Le seul but est de valider en un seul appel :
//   - CORS (si testé sur Flutter web)
//   - l'URL de base (ApiConfig.baseUrl / 10.0.2.2 vs localhost vs IP LAN)
//   - la sérialisation JSON de la requête et de la réponse DRF
//   - le stockage du token (TokenStorage, via EneoApiService.login())
//
// À SUPPRIMER (ou juste ne plus router dessus) une fois que login_screen.dart
// (le vrai écran) est branché et fonctionne.
//
// Pour l'utiliser temporairement comme point d'entrée, dans main.dart :
//   home: const LoginTestScreen(),
// à la place de `const AuthGate()`.

import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../api/auth_service.dart';

class LoginTestScreen extends StatefulWidget {
  const LoginTestScreen({super.key});

  @override
  State<LoginTestScreen> createState() => _LoginTestScreenState();
}

class _LoginTestScreenState extends State<LoginTestScreen> {
  final _identifiantController = TextEditingController();
  final _motDePasseController = TextEditingController();

  // On instancie directement AuthService ici plutôt que de passer par
  // Provider/context.watch : ça isole totalement ce test de tout le reste
  // de l'app (pas besoin que ChangeNotifierProvider soit déjà en place dans
  // main.dart pour que ce test tourne).
  final _authService = AuthService();

  bool _isLoading = false;

  @override
  void dispose() {
    _identifiantController.dispose();
    _motDePasseController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);

    try {
      final user = await _authService.login(
        identifiant: _identifiantController.text.trim(),
        motDePasse: _motDePasseController.text,
      );

      // 1) Résultat en console — utile même sans regarder l'écran.
      debugPrint('LOGIN OK -> ${user.toString()}');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connecté : ${user.prenom} ${user.nom}')),
      );
    } on ApiValidationException catch (e) {
      debugPrint('LOGIN ERROR 400 -> ${e.fieldErrors}');
      _showError(e.firstMessage);
    } on ApiPermissionException catch (e) {
      debugPrint('LOGIN ERROR 403 -> ${e.message}');
      _showError(e.message);
    } on ApiException catch (e) {
      // Filet générique : réseau, 5xx, etc. — voir api_exception.dart pour
      // le détail des sous-types.
      debugPrint('LOGIN ERROR -> $e');
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur : $message')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test login (debug)')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _identifiantController,
              decoration: const InputDecoration(
                labelText: 'Téléphone ou e-mail',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _motDePasseController,
              decoration: const InputDecoration(
                labelText: 'Mot de passe',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Se connecter'),
            ),
          ],
        ),
      ),
    );
  }
}
