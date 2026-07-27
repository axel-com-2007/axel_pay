// ============================================================
// POINT D'ENTRÉE DE L'APPLICATION AXELPAY
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/main_shell.dart'; // chemin réel, cf. import dans login_screen.dart
import 'theme/app_theme.dart';
import 'screens/auth/login_test_screen.dart';
import 'widgets/animations/animations.dart';

void main() {
  final authService = AuthService();

  runApp(
    ChangeNotifierProvider.value(
      value: authService,
      child: const MyApp(),
    ),
  );

  // Lancé en arrière-plan après le premier affichage : vérifie s'il existe
  // déjà une session valide (refresh token en storage) et met à jour
  // authService.status en conséquence.
  authService.initialize();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AxelPay',
      theme: AppTheme.theme,
      // On ne pointe plus directement vers LoginScreen : AuthGate décide de
      // l'écran à afficher selon l'état de la session.
      // remettre home: const AuthGate() après le test
      home: const AuthGate(),
      
    );
  }
}

/// Écran-relais qui observe [AuthService.status] et affiche :
///  - un loader tant que la session n'a pas été vérifiée (`unknown`,
///    pendant que `initialize()` tourne en fond) ;
///  - [LoginScreen] si aucune session valide (`unauthenticated`) ;
///  - [MainShell] si une session valide existe déjà, y compris juste après
///    un login réussi — pas besoin de `Navigator.push` manuel, ce widget se
///    reconstruit tout seul dès que `status` change (voir `login_screen.dart`).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthService>().status;

    switch (status) {
      case AuthStatus.unknown:
        return const Scaffold(
          body: LottieLoader(),
        );
      case AuthStatus.authenticated:
        return const MainShell();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
    }
  }
}
