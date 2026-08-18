// ============================================================
// POINT D'ENTRÉE DE L'APPLICATION AXELPAY
// ============================================================

import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/auth_service.dart';
import 'api/device_token_api.dart';
import 'l10n/app_locale_controller.dart';
import 'l10n/translation_controller.dart';
import 'services/firebase_messaging_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/main_shell.dart'; // chemin réel, cf. import dans login_screen.dart
import 'theme/app_theme.dart';
import 'widgets/animations/animations.dart';

/// Type de terminal envoyé à Django (`type_appareil`) — Web ajouté par
/// rapport à la version initiale pour coller au support "Android et Web"
/// demandé pour ce service.
String _currentDeviceType() {
  // kIsWeb n'est pas réimporté ici pour éviter un import supplémentaire :
  // `identical(0, 0.0)` est le test compile-time classique, mais le plus
  // lisible reste `foundation.kIsWeb`. Utilisé directement dans le
  // service FCM ; ici on se contente de deux valeurs suffisantes pour le
  // test actuel (Chrome) et Android — ajouter 'ios' quand tu testeras sur
  // iPhone.
  return identical(0, 0.0) ? 'web' : 'android';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final authService = AuthService();

  // Sélecteur "Langue" de SettingsScreen : charge la langue déjà choisie
  // (si l'utilisateur en a sélectionné une lors d'une session précédente)
  // AVANT `runApp`, pour éviter un flash "français puis anglais" au tout
  // premier frame.
  final localeController = LocaleController();
  await localeController.charger();

  // Cache de traduction DeepL (voir l10n/translation_controller.dart) :
  // charge sur disque les traductions déjà obtenues lors de sessions
  // précédentes, AVANT `runApp`, pour que l'anglais s'affiche
  // immédiatement si l'utilisateur a déjà basculé la langue par le passé
  // — même hors connexion, sans nouvel appel à DeepL.
  final translationController = TranslationController();
  await translationController.charger();

  // --- Firebase Cloud Messaging ---
  // `onToken` est déclenché à l'initialisation ET à chaque rotation de
  // token (`onTokenRefresh`). On n'envoie le token à Django QUE si une
  // session est active : pas d'intérêt à enregistrer un device pour un
  // utilisateur non connecté (la route `/devices/` exige
  // `IsAuthenticated` côté backend, l'appel échouerait silencieusement
  // sinon — voir le try/catch absorbant dans DeviceTokenApi).
  await FirebaseMessagingService.instance.setupFirebaseMessaging(
    onToken: (token) {
      if (authService.isAuthenticated) {
        DeviceTokenApi.instance.registerToken(
          fcmToken: token,
          deviceType: _currentDeviceType(),
        );
      }
    },
    onMessageTap: (payload) {
      // TODO NAVIGATION : brancher ici la navigation vers l'écran
      // pertinent selon payload.data, ex :
      //   if (payload.data['type'] == 'facture_disponible') {
      //     navigatorKey.currentState?.pushNamed(
      //       '/factures/${payload.data['id_facture']}',
      //     );
      //   }
      debugPrint('👉 Notification tapée : ${payload.data}');
    },
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: localeController),
        ChangeNotifierProvider.value(value: translationController),
      ],
      child: const MyApp(),
    ),
  );

  // Vérifie la session existante après le lancement. Si une session est
  // déjà valide (app relancée alors que l'utilisateur était connecté),
  // AuthService.initialize() enregistre lui-même le token FCM courant —
  // voir le bloc ajouté dans auth_service.dart.
  authService.initialize();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // `context.watch` : reconstruit MaterialApp (donc les délégués de
    // localisation Material/Cupertino intégrés — dates, "OK"/"Annuler"
    // des pickers système, etc.) dès que `LocaleController.definirLangue`
    // est appelé depuis le sélecteur de `settings_screen.dart`.
    final locale = context.watch<LocaleController>().locale;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AxelPay',
      theme: AppTheme.theme,
      // Clamp text scale factor : évite le texte démesuré sur tablettes/desktop
      // qui agrandissent automatiquement la typographie système.
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.of(context).textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.15,
            ),
          ),
          child: child!,
        );
      },
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // On ne pointe plus directement vers LoginScreen : AuthGate décide de
      // l'écran à afficher selon l'état de la session.
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
