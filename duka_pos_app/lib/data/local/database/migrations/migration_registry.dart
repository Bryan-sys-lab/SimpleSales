import 'package:flutter/foundation.dart' show visibleForTesting;

import '../schema_version.dart';
import 'migration.dart';
import 'v081_outbox_table.dart';

/// Registry of schema migrations.
///
/// Migrations are verified to be unique, ordered, and contiguous from the
/// first registry-managed version (81) upward. Historical migrations (v1–v80)
/// remain under the historical migration path in [DatabaseHelper] and are not
/// part of this registry.
///
/// The registry is the single source of truth for new schema changes. When a
/// new migration is needed, add it here with the next version number and never
/// reuse or edit a previous version.
class MigrationRegistry {
  MigrationRegistry._();
  static final MigrationRegistry instance = MigrationRegistry._();

  final List<Migration> _migrations = [];

  /// Registers all built-in migrations. Call once at app bootstrap.
  void initialize() {
    register(Migration081());
  }

  /// Registers [migration]. Throws if the version is already registered or if
  /// the versions are not contiguous starting at 81.
  void register(Migration migration) {
    _migrations.add(migration);
    _validate();
  }

  /// Returns the migration for [version], or null if none is registered.
  Migration? migrationFor(int version) {
    try {
      return _migrations.firstWhere((m) => m.toVersion == version);
    } on StateError {
      return null;
    }
  }

  /// Returns all registered migrations in version order.
  List<Migration> get migrations => List.unmodifiable(_migrations);

  /// The highest registered version, or null if no migrations are registered.
  int? get maxVersion =>
      _migrations.isEmpty ? null : _migrations.last.toVersion;

  /// Verifies that all registered migrations are unique, ordered, and
  /// contiguous from `SchemaVersion.firstRegistryManaged` upward.
  void _validate() {
    if (_migrations.isEmpty) return;

    final sorted = List<Migration>.from(_migrations)
      ..sort((a, b) => a.toVersion.compareTo(b.toVersion));

    // Check for duplicates.
    final versions = <int>{};
    for (final m in sorted) {
      if (!versions.add(m.toVersion)) {
        throw StateError(
            'Duplicate migration version ${m.toVersion} registered');
      }
    }

    // Check contiguity starting at firstRegistryManaged.
    final first = SchemaVersion.firstRegistryManaged;
    for (var i = 0; i < sorted.length; i++) {
      final expected = first + i;
      if (sorted[i].toVersion != expected) {
        throw StateError(
            'Migration versions must be contiguous from $first; '
            'expected $expected at index $i, got ${sorted[i].toVersion}');
      }
    }
  }

  /// Test-only: clears all registered migrations.
  @visibleForTesting
  static void resetForTests() {
    instance._migrations.clear();
  }
}
