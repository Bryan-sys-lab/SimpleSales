import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Configuration for a workspace-scoped SQLite database.
class DatabaseConfig {
  DatabaseConfig._();

  /// Computes a collision-resistant filename for a workspace.
  ///
  /// Uses SHA-256 of the exact workspace identifier so that `shop/a` and
  /// `shop_a` cannot collide. The legacy `'legacy'` workspace keeps its
  /// original `duka_pos.db` name for backward compatibility.
  static String databaseFileName(String workspaceId) {
    if (workspaceId.trim().isEmpty) {
      throw ArgumentError('Workspace ID cannot be empty');
    }

    if (workspaceId == 'legacy') {
      return 'duka_pos.db';
    }

    final digest = sha256.convert(utf8.encode(workspaceId)).toString();
    return 'duka_pos_$digest.db';
  }

  /// Returns the full path to a workspace's database file.
  static Future<String> databasePath(String workspaceId) async {
    final dir = await getDatabasesPath();
    return path.join(dir, databaseFileName(workspaceId));
  }

  /// Returns true if a database file exists for the given workspace.
  static Future<bool> exists(String workspaceId) async {
    final file = File(await databasePath(workspaceId));
    return await file.exists();
  }

  /// Deletes the database file for a workspace.
  static Future<void> delete(String workspaceId) async {
    if (workspaceId == 'legacy') {
      throw UnsupportedError(
          'Legacy workspace database deletion is not supported here');
    }
    final file = File(await databasePath(workspaceId));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Whether foreign-key enforcement is enabled for production connections.
  ///
  /// Disabled by default. Historical migrations (notably the v11 money
  /// migration that rebuilds tables while dependents reference them) must be
  /// verified compatible before enabling. Do not flip this to `true` without
  /// testing upgrades from real historical databases.
  static const bool foreignKeysEnabled = false;

  /// Whether the database is encrypted at rest (SQLCipher).
  static const bool encrypted = true;
}
