// ============================================================
// CACHE LOCAL CHIFFRÉ — mode hors-ligne (cahier des charges §7.6)
// ============================================================
// "L'application embarque une mémoire cache locale, stockée de manière
// chiffrée sur le téléphone, qui conserve la dernière version connue du
// solde de crédit, des 12 dernières factures, de l'historique des
// recharges et des jetons déjà consultés."
//
// Choix technique : `sqflite_sqlcipher` plutôt que Hive/Realm.
//  - C'est l'option explicitement citée en premier par le cahier des
//    charges (§7.1 : "SQLite chiffré (SQLCipher) ou Hive/Realm").
//  - Le projet stocke déjà des secrets sensibles (JWT) via
//    `flutter_secure_storage` dans `token_storage.dart` : on réutilise
//    exactement le même mécanisme (Keychain iOS / Keystore Android) pour
//    la passphrase de chiffrement de la base, plutôt que d'introduire un
//    deuxième système de gestion de clés.
//  - Une seule table générique `cache_entries` (clé -> JSON + horodatage)
//    plutôt qu'un schéma relationnel dédié par écran : le contenu mis en
//    cache est déjà un JSON produit par `EneoRepository` (voir
//    `toCacheJson()` dans `models.dart`), donc un stockage clé/valeur
//    suffit et reste trivial à faire évoluer si un nouvel écran a besoin
//    d'offline (pas de migration de schéma à chaque ajout).
//
// Ajoute au pubspec.yaml (voir pubspec.yaml à la racine du projet) :
//   sqflite_sqlcipher: ^3.1.0
//   path_provider: ^2.1.0
//   path: ^1.9.0
// ============================================================

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Un instantané mis en cache : la donnée brute (déjà au format
/// `toCacheJson()` du modèle appelant) + l'horodatage de la dernière
/// synchronisation réseau réussie qui l'a produit.
class CacheSnapshot {
  final Map<String, dynamic> value;
  final DateTime updatedAt;
  const CacheSnapshot({required this.value, required this.updatedAt});
}

/// Cache clé/valeur chiffré, persistant entre les lancements de l'app.
///
/// Contrat volontairement minimal (3 méthodes), conformément à la
/// consigne : [saveSnapshot], [getSnapshot], [clear]. La logique de
/// "quand retomber sur le cache" (uniquement en cas d'absence réseau,
/// jamais en cas d'erreur serveur réelle) vit dans `EneoRepository`, pas
/// ici — cette classe ne connaît rien du domaine métier Eneo.
class LocalCache {
  LocalCache._internal();
  static final LocalCache instance = LocalCache._internal();

  static const _kPassphraseKey = 'eneo_cache_db_passphrase_v1';
  static const _kDbFileName = 'eneo_offline_cache.db';
  static const _kTable = 'cache_entries';

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    // Évite d'ouvrir la base en double si plusieurs appels concurrents
    // arrivent avant la fin de la première ouverture (ex: plusieurs
    // écrans qui se chargent en parallèle au démarrage).
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final passphrase = await _getOrCreatePassphrase();
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _kDbFileName);

    final db = await openDatabase(
      path,
      password: passphrase,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_kTable (
            cache_key   TEXT PRIMARY KEY,
            value_json  TEXT NOT NULL,
            updated_at  TEXT NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  /// Passphrase générée aléatoirement au tout premier accès et conservée
  /// dans le stockage sécurisé du système (jamais codée en dur, jamais
  /// écrite en clair sur le disque). Si l'utilisateur désinstalle l'app
  /// ou vide le Keystore/Keychain, la base chiffrée existante devient
  /// illisible : c'est un cache, pas une source de vérité, donc ce n'est
  /// pas un problème — [getSnapshot] renverra simplement `null` (ou
  /// l'ouverture échouera proprement, voir gestion d'erreur ci-dessous).
  Future<String> _getOrCreatePassphrase() async {
    final existing = await _secureStorage.read(key: _kPassphraseKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _generateRandomPassphrase();
    await _secureStorage.write(key: _kPassphraseKey, value: generated);
    return generated;
  }

  String _generateRandomPassphrase() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Enregistre (ou remplace) l'instantané associé à [key]. Ne lève
  /// jamais d'exception vers l'appelant : une écriture de cache qui
  /// échoue (disque plein, etc.) ne doit jamais faire planter un appel
  /// réseau par ailleurs réussi — elle est simplement journalisée.
  Future<void> saveSnapshot(String key, Map<String, dynamic> value) async {
    try {
      final db = await _database;
      await db.insert(
        _kTable,
        {
          'cache_key': key,
          'value_json': jsonEncode(value),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // Volontairement silencieux (cf. commentaire ci-dessus) — logué
      // pour le debug uniquement.
      // ignore: avoid_print
      print('[LocalCache] saveSnapshot("$key") a échoué : $e');
    }
  }

  /// Lit l'instantané associé à [key], ou `null` si absent OU si la base
  /// est illisible (première installation, cache jamais rempli, base
  /// corrompue/passphrase perdue...). Ne lève jamais d'exception : côté
  /// appelant (`EneoRepository`), `null` signifie simplement "impossible
  /// de servir une réponse hors-ligne pour cette donnée", ce qui doit
  /// alors remonter l'erreur réseau d'origine plutôt que planter.
  Future<CacheSnapshot?> getSnapshot(String key) async {
    try {
      final db = await _database;
      final rows = await db.query(
        _kTable,
        where: 'cache_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      return CacheSnapshot(
        value: jsonDecode(row['value_json'] as String) as Map<String, dynamic>,
        updatedAt: DateTime.tryParse(row['updated_at'] as String) ?? DateTime.now(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[LocalCache] getSnapshot("$key") a échoué : $e');
      return null;
    }
  }

  /// Purge intégrale du cache — appelée au logout / à la désactivation de
  /// compte (§7.6 : "purgé automatiquement lors de la déconnexion ou de
  /// la désactivation du compte, afin de ne laisser aucune donnée
  /// sensible résiduelle sur un appareil partagé ou perdu"). Voir le
  /// branchement dans `AuthService.logout()` / `_handleForcedLogout()`.
  Future<void> clear() async {
    try {
      final db = await _database;
      await db.delete(_kTable);
    } catch (e) {
      // ignore: avoid_print
      print('[LocalCache] clear() a échoué : $e');
    }
  }

  /// Politique de rétention locale (§7.6 : "limite le cache aux 12
  /// derniers mois, en cohérence avec l'historique affiché côté
  /// serveur"). Purge best-effort, à appeler en tâche de fond après une
  /// synchronisation réussie (voir `EneoRepository._cached`) — jamais de
  /// façon bloquante pour l'UI.
  Future<void> purgeOlderThan(Duration maxAge) async {
    try {
      final db = await _database;
      final seuil = DateTime.now().subtract(maxAge).toIso8601String();
      await db.delete(_kTable, where: 'updated_at < ?', whereArgs: [seuil]);
    } catch (e) {
      // ignore: avoid_print
      print('[LocalCache] purgeOlderThan() a échoué : $e');
    }
  }
}
