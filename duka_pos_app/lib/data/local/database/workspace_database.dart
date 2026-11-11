import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher_pkg;

import 'database_config.dart';
import 'schema_version.dart';

/// Thrown when the stored SQLCipher key cannot open the existing database
/// file. The database file is preserved; callers should offer a restore-from-
/// backup path rather than silently creating an empty replacement.
class DatabaseKeyMismatchException implements Exception {
  const DatabaseKeyMismatchException(this.message);

  final String message;

  @override
  String toString() => 'DatabaseKeyMismatchException($message)';
}

/// Serialises moving this singleton to another shop.
///
/// Held for a whole operation, not for a single switch, so that a caller
/// which must walk several shops (the cross-shop activity read) can keep the
/// database still for as long as it is looking.
class _AsyncGate {
  Future<void> _drain = Future<void>.value();

  /// Runs [body], waiting for anything already queued.
  Future<T> run<T>(Future<T> Function() body) {
    final result = Completer<T>();
    _drain = _drain.then((_) async {
      try {
        result.complete(await body());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}

/// Singleton that owns the live workspace database connection.
///
/// All workspace-scoped connection state (`_db`, `_workspaceKey`,
/// `_databaseGeneration`) lives here. [DatabaseHelper] remains the public
/// compatibility facade and delegates connection lifecycle to this class.
///
/// Migration callbacks (`_onCreate`/`_onUpgrade`) live on [DatabaseHelper]
/// (they reference the historical migration helpers) and are supplied via
/// [configureMigrations] so this class never imports [DatabaseHelper].
class WorkspaceDatabase {
  WorkspaceDatabase._internal();
  static final WorkspaceDatabase instance = WorkspaceDatabase._internal();

  Database? _db;
  String _workspaceKey = 'legacy';
  int _databaseGeneration = 0;

  /// Serialises workspace switches so a cross-shop tour can never race a switch.
  final _AsyncGate _workspaceGate = _AsyncGate();

  Future<void> Function(Database, int)? _onCreate;
  Future<void> Function(Database, int, int)? _onUpgrade;

  /// Supplies the migration callbacks owned by [DatabaseHelper].
  void configureMigrations({
    required Future<void> Function(Database, int) onCreate,
    required Future<void> Function(Database, int, int) onUpgrade,
  }) {
    _onCreate = onCreate;
    _onUpgrade = onUpgrade;
  }

  /// Whether a database handle is currently open.
  bool get hasOpenDatabase => _db != null;

  /// The shop this singleton is currently pointed at.
  String get currentWorkspaceKey => _workspaceKey;

  /// The open SQLite database handle for the current workspace.
  ///
  /// Lazily initializes via [_initDb]. A reset or workspace switch that happens
  /// while the filesystem database is opening is detected via the generation
  /// counter and the stale handle is discarded.
  Future<Database> get database async {
    while (true) {
      final existing = _db;
      if (existing != null) return existing;
      final generation = _databaseGeneration;
      final opened = await _initDb();
      if (generation != _databaseGeneration) {
        await opened.close();
        continue;
      }
      final current = _db;
      if (current != null) {
        await opened.close();
        return current;
      }
      _db = opened;
      return opened;
    }
  }

  /// Moves the database to [workspaceKey], holding the workspace gate.
  Future<void> initializeWorkspace(String workspaceKey) =>
      _workspaceGate.run(() => _pointAtWorkspace(workspaceKey));

  /// Moves the database to [workspaceKey], holding the workspace gate.
  Future<void> switchWorkspace(String workspaceKey) =>
      initializeWorkspace(workspaceKey);

  /// Moves the database WITHOUT taking the workspace gate.
  ///
  /// Valid only for a caller that already holds the gate, obtained through
  /// [withWorkspaceGate].
  Future<void> switchWorkspaceHoldingGate(String workspaceKey) =>
      _pointAtWorkspace(workspaceKey);

  Future<void> _pointAtWorkspace(String workspaceKey) async {
    if (workspaceKey.trim().isEmpty) {
      throw ArgumentError.value(workspaceKey, 'workspaceKey');
    }
    if (_db != null && _workspaceKey == workspaceKey) return;
    _databaseGeneration++;
    await _db?.close();
    _db = null;
    _workspaceKey = workspaceKey;
  }

  /// Runs [body] holding the workspace gate.
  Future<T> withWorkspaceGate<T>(Future<T> Function() body) =>
      _workspaceGate.run(body);

  /// OS-backed secure storage for per-workspace SQLCipher keys.
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Prefix for workspace database keys in secure storage.
  static const _dbKeyPrefix = 'db_key_';

  /// Guards test teardown so the last in-memory handle finishes closing.
  static Future<void>? _pendingTestClose;

  /// Generates a random 256-bit key, stores it keyed by workspace, and returns it.
  static Future<String> _ensureWorkspaceKey(String workspaceKey) async {
    final storageKey = '$_dbKeyPrefix$workspaceKey';
    final existing = await _secureStorage.read(key: storageKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final key = _generateKey();
    await _secureStorage.write(key: storageKey, value: key);
    return key;
  }

  /// Returns the stored key for a workspace, or null if none has been created.
  static Future<String?> readWorkspaceKey(String workspaceKey) async {
    final storageKey = '$_dbKeyPrefix$workspaceKey';
    return _secureStorage.read(key: storageKey);
  }

  /// Rotates the workspace database key: generates a new one and stores it.
  static Future<void> rotateWorkspaceKey(String workspaceKey) async {
    final storageKey = '$_dbKeyPrefix$workspaceKey';
    await _secureStorage.delete(key: storageKey);
    await _ensureWorkspaceKey(workspaceKey);
  }

  /// Deletes a workspace's database key. Used only when the database file is
  /// also being deleted, so a key is never orphaned from its data.
  static Future<void> _deleteWorkspaceKey(String workspaceKey) async {
    final storageKey = '$_dbKeyPrefix$workspaceKey';
    await _secureStorage.delete(key: storageKey);
  }

  /// Cryptographically random 256-bit key, hex-encoded.
  static String _generateKey() {
    final bytes =
        List<int>.generate(32, (_) => math.Random.secure().nextInt(256));
    return sha256.convert(bytes).toString();
  }

  /// Opens (or reopens) the database for the current workspace.
  ///
  /// Production workspace databases are encrypted at rest with SQLCipher.
  /// Each workspace gets a device-local 256-bit key stored in the OS
  /// keystore/keychain via flutter_secure_storage. The filename is derived
  /// from [DatabaseConfig.databaseFileName] (SHA-256) so filenames are
  /// collision-resistant.
  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final databasePath =
        path.join(dbPath, DatabaseConfig.databaseFileName(_workspaceKey));

    final key = await _ensureWorkspaceKey(_workspaceKey);
    final onCreate = _onCreate;
    final onUpgrade = _onUpgrade;
    if (onCreate == null || onUpgrade == null) {
      throw StateError(
          'WorkspaceDatabase migration callbacks not configured; call '
          'configureMigrations before opening the database.');
    }

    try {
      final isTest = kDebugMode;
      return await (isTest ? databaseFactory : sqlcipher_pkg.databaseFactory)
          .openDatabase(
        databasePath,
        options: isTest
            ? OpenDatabaseOptions(
                version: SchemaVersion.current,
                onCreate: onCreate,
                onUpgrade: onUpgrade,
              )
            : sqlcipher_pkg.SqlCipherOpenDatabaseOptions(
                version: SchemaVersion.current,
                onCreate: onCreate,
                onUpgrade: onUpgrade,
                password: key,
              ),
      );
    } on Object catch (_) {
      final file = File(databasePath);
      if (!(await file.exists())) rethrow;
      throw DatabaseKeyMismatchException(
        'Cannot open encrypted workspace database for $_workspaceKey. '
        'The stored key does not match the database file. Restore from a '
        'portable backup or contact support.',
      );
    }
  }

  /// The file path a workspace's database lives at, computed using
  /// [DatabaseConfig.databaseFileName] (SHA-256) so filenames are
  /// collision-resistant.
  static Future<String> databasePathFor(String workspaceKey) async {
    final dir = await getDatabasesPath();
    return path.join(dir, DatabaseConfig.databaseFileName(workspaceKey));
  }

  /// Deletes one failed workspace database after its registry entry has been
  /// removed. The target is an exact workspace-derived path; broad database
  /// deletion is deliberately not exposed.
  static Future<void> deleteWorkspace(String workspaceKey) async {
    if (workspaceKey.trim().isEmpty || workspaceKey == 'legacy') return;
    await instance._workspaceGate.run(() async {
      if (instance._workspaceKey == workspaceKey && instance._db != null) {
        await instance._db!.close();
        instance._db = null;
      }
      await databaseFactory.deleteDatabase(await databasePathFor(workspaceKey));
      await _deleteWorkspaceKey(workspaceKey);
    });
  }

  // ── Test helpers (delegated to by DatabaseHelper) ─────────────────────

  /// Test-only: Reset the singleton instance for test isolation.
  static void resetForTests() {
    final Database? previous = instance._db;
    instance._db = null;
    instance._databaseGeneration++;
    instance._workspaceKey = 'legacy';
    _pendingTestClose = previous?.close();
  }

  /// Test-only: Wait for any pending database close to finish.
  static Future<void> closeForTests() async {
    await _pendingTestClose;
    _pendingTestClose = null;
  }

  /// Test-only: opens an existing database *file* at the current schema
  /// version, running the real migration callbacks supplied by the caller.
  static Future<Database> openExistingForUpgradeTests(
    String path, {
    required Future<void> Function(Database, int) onCreate,
    required Future<void> Function(Database, int, int) onUpgrade,
  }) async {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: SchemaVersion.current,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
      ),
    );
  }

  /// Test-only: a fresh, isolated in-memory instance with the real schema.
  static Future<Database> openInMemoryForTests({
    required Future<void> Function(Database, int) onCreate,
  }) async {
    await _pendingTestClose;
    _pendingTestClose = null;
    await instance._workspaceGate.run(() async {});
    instance._workspaceKey = 'legacy';
    final uniqueMemoryPath =
        'file:duka_test_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=private';
    instance._db = await databaseFactory.openDatabase(
      uniqueMemoryPath,
      options: OpenDatabaseOptions(
          version: SchemaVersion.current, onCreate: onCreate),
    );
    return instance._db!;
  }
}
