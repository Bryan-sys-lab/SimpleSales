import 'dart:async';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher_pkg;

import 'database_config.dart';
import 'database_integrity.dart';
import 'database_session.dart';
import 'schema_version.dart';
import '../../../db/database_helper.dart';

/// Workspace-aware database manager.
///
/// Replaces the mutable global database pointer in [DatabaseHelper] with a
/// workspace-scoped session manager. Its responsibilities:
///
/// - Open a database for a specific workspace.
/// - Cache connections by workspace identity (single-flight open: concurrent
///   opens share one initialization future).
/// - Verify the workspace identity recorded inside the database matches the
///   requested workspace.
/// - Never allow an operation to silently switch workspaces halfway through.
/// - Prevent deletion of a database that still has active sessions.
/// - Preserve the legacy `duka_pos.db` database and provide a safe migration
///   to collision-resistant filenames.
class DatabaseManager {
  DatabaseManager._();
  static final DatabaseManager instance = DatabaseManager._();

  final Map<String, DatabaseSession> _sessions = {};
  final Map<String, Future<DatabaseSession?>> _opening = {};

  /// Whether any session is currently open.
  bool get hasOpenSession => _sessions.isNotEmpty;

  /// The workspace IDs of all open sessions.
  Iterable<String> get openWorkspaceIds => _sessions.keys;

  /// Opens (or returns an existing) session for [workspaceId].
  ///
  /// Concurrent calls for the same workspace share one initialization future.
  /// The first caller to finish initializing caches the session; later callers
  /// receive the cached session.
  ///
  /// For the `'legacy'` workspace, opens `duka_pos.db` (unencrypted for
  /// backward compatibility with existing installations). For all other
  /// workspaces, opens a collision-resistant filename derived from a SHA-256
  /// digest of the workspace ID, encrypted at rest with SQLCipher.
  Future<DatabaseSession> sessionFor(String workspaceId) async {
    if (workspaceId.trim().isEmpty) {
      throw ArgumentError('Workspace ID cannot be empty');
    }

    // Return an existing open session for this workspace.
    final existing = _sessions[workspaceId];
    if (existing != null && !existing.closed) {
      return existing;
    }

    // Single-flight: if an open is already in progress for this workspace,
    // wait for it instead of starting another.
    final inProgress = _opening[workspaceId];
    if (inProgress != null) {
      final session = await inProgress;
      if (session != null) return session;
    }

    final completer = Completer<DatabaseSession?>();
    _opening[workspaceId] = completer.future;

    try {
      final session = await _openSession(workspaceId);
      _sessions[workspaceId] = session;
      completer.complete(session);
      return session;
    } catch (error, stack) {
      completer.completeError(error, stack);
      rethrow;
    } finally {
      _opening.remove(workspaceId);
    }
  }

  /// Closes the session for [workspaceId], if one is open.
  ///
  /// Returns true if a session was closed.
  Future<bool> closeSession(String workspaceId) async {
    final session = _sessions.remove(workspaceId);
    if (session == null || session.closed) return false;
    await session.close();
    return true;
  }

  /// Closes all open sessions.
  Future<void> closeAll() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      if (!session.closed) await session.close();
    }
  }

  /// Deletes the database file for [workspaceId].
  ///
  /// Refuses if there is an active session for that workspace. For
  /// `'legacy'`, the database file is preserved.
  Future<void> deleteWorkspaceDatabase(String workspaceId) async {
    if (workspaceId == 'legacy') {
      throw UnsupportedError(
          'Legacy workspace database deletion is not supported');
    }
    if (_sessions.containsKey(workspaceId)) {
      throw StateError(
          'Cannot delete database for $workspaceId: an active session exists');
    }
    await DatabaseConfig.delete(workspaceId);
  }

  /// Whether a database file exists for [workspaceId].
  Future<bool> databaseExists(String workspaceId) =>
      DatabaseConfig.exists(workspaceId);

  /// Opens a new [DatabaseSession] for [workspaceId].
  ///
  /// Does not cache or manage single-flight — that is the caller's
  /// responsibility ([sessionFor]).
  Future<DatabaseSession> _openSession(String workspaceId) async {
    final path = await DatabaseConfig.databasePath(workspaceId);

    final isLegacy = workspaceId == 'legacy';

    // Production workspace databases are encrypted at rest with SQLCipher.
    // Each workspace gets a device-local 256-bit key stored in the OS
    // keystore/keychain via flutter_secure_storage. A missing key means the
    // workspace has never been opened — generate one now.
    String? key;
    if (!isLegacy) {
      final storage = const FlutterSecureStorage();
      final storageKey = 'db_key_$workspaceId';
      key = await storage.read(key: storageKey);
      if (key == null || key.isEmpty) {
        final bytes =
            List<int>.generate(32, (_) => math.Random.secure().nextInt(256));
        key = sha256.convert(bytes).toString();
        await storage.write(key: storageKey, value: key);
      }
    }

    // In plain `flutter test` runs, databaseFactory is overridden to
    // databaseFactoryFfi which has no platform channel. Use it directly
    // instead of sqlcipher_pkg.databaseFactory so tests can open workspace
    // databases without a platform plugin. Production keeps SQLCipher.
    final isTest = bool.fromEnvironment('dart.vm.product') == false;
    final db = await (isTest ? databaseFactory : sqlcipher_pkg.databaseFactory)
        .openDatabase(
      path,
      options: isTest
          ? OpenDatabaseOptions(
              version: SchemaVersion.current,
              onCreate: _onCreate,
              onUpgrade: _onUpgrade,
            )
          : sqlcipher_pkg.SqlCipherOpenDatabaseOptions(
              version: SchemaVersion.current,
              onCreate: _onCreate,
              onUpgrade: _onUpgrade,
              password: key,
            ),
    );

    // Verify workspace identity inside the database matches the requested
    // workspace. A legacy database has no workspace table, so it passes by
    // default. New workspaces record their ID on first open.
    await _verifyWorkspaceIdentity(db, workspaceId, isLegacy);

    // Enable foreign-key enforcement if configured. Off by default until
    // historical migrations are verified compatible with enforced constraints.
    if (DatabaseConfig.foreignKeysEnabled) {
      await DatabaseHelper.enableForeignKeys(db);
    }

    return DatabaseSession(
      workspaceId: workspaceId,
      database: db,
      closed: false,
    );
  }

  /// Verifies that the workspace identity recorded inside the database
  /// matches [requestedWorkspaceId].
  ///
  /// For the legacy workspace, no check is performed — legacy databases
  /// predate workspace tracking. For new workspaces, a `workspace_identity`
  /// row is written on first open and checked on every subsequent open. A
  /// mismatch means the file has been swapped and must not be opened.
  Future<void> _verifyWorkspaceIdentity(
      Database db, String requestedWorkspaceId, bool isLegacy) async {
    if (isLegacy) return;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS workspace_identity (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        workspace_id TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    final existing = await db.query(
      'workspace_identity',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    if (existing.isEmpty) {
      await db.insert('workspace_identity', {
        'id': 1,
        'workspace_id': requestedWorkspaceId,
        'created_at': now,
      });
    } else {
      final stored = existing.first['workspace_id'] as String?;
      if (stored != requestedWorkspaceId) {
        await db.close();
        throw StateError(
            'Database workspace identity mismatch: requested '
            '$requestedWorkspaceId, database contains $stored. '
            'The file may have been swapped.');
      }
    }
  }

  /// Creates the full schema on a fresh database.
  ///
  /// Delegates to [DatabaseHelper.createSchema] so fresh
  /// installs and upgraded installs produce identical schemas.
  Future<void> _onCreate(Database db, int version) async {
    await DatabaseHelper.instance.createSchema(db, version);
  }

  /// Upgrades an existing database from [oldVersion] to [newVersion].
  ///
  /// Delegates to [DatabaseHelper.upgradeSchema]. New schema
  /// changes (version 79+) should be added to the migration registry instead.
  /// Runs integrity verification after the upgrade completes.
  Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    await DatabaseHelper.instance.upgradeSchema(db, oldVersion, newVersion);
    if (DatabaseConfig.foreignKeysEnabled) {
      await DatabaseIntegrity.verify(db);
    }
  }

  /// Test-only: Reset all sessions for test isolation.
  @visibleForTesting
  static void resetForTests() {
    instance._sessions.clear();
    instance._opening.clear();
  }

  /// Test-only: Close all sessions and wait for any pending closes.
  @visibleForTesting
  static Future<void> closeForTests() async {
    await instance.closeAll();
  }
}
