/// Configuration centrale du client API.
///
/// Un seul endroit à modifier quand tu changes d'environnement (dev local,
/// staging, prod) ou l'adresse de ton serveur Django.
///
/// ⚠️ Rappel Flutter : depuis un émulateur Android, `localhost` ne pointe pas
/// vers ta machine hôte. Utilise `10.0.2.2` (émulateur Android),
/// `localhost` (simulateur iOS / web / desktop), ou l'IP LAN de ta machine
/// pour un appareil physique (les deux doivent être sur le même réseau).
enum ApiEnvironment { dev, staging, prod }

class ApiConfig {
  ApiConfig._();

  static ApiEnvironment environment = ApiEnvironment.dev;

  static String get baseUrl {
    switch (environment) {
      case ApiEnvironment.dev:
        // Backend Django lancé en local (`python manage.py runserver 0.0.0.0:8000`)
        return  'http://localhost:8000/api';
        // 'http://192.168.1.230:8000/api' à remettre après les tests
      case ApiEnvironment.staging:
        return 'https://staging.eneo-app.example.com/api';
      case ApiEnvironment.prod:
        return 'https://api.eneo-app.example.com/api';
    }
  }

  /// Timeouts réseau — le backend fait parfois des appels lents (agrégateurs
  /// Mobile Money, génération PDF...), on laisse un peu de marge.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
