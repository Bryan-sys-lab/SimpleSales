import 'package:sqflite/sqflite.dart';

/// A single schema migration from version `fromVersion` to `toVersion`.
///
/// Migrations added to the registry start at version 79 (the first version
/// not covered by the historical migration path). Each migration is immutable
/// once released — never edit a migration after it has shipped, because a
/// shop's phone may be several versions behind.
abstract class Migration {
  /// The schema version this migration brings the database to.
  int get toVersion;

  /// The schema version this migration upgrades from.
  int get fromVersion => toVersion - 1;

  /// Applies the migration to [db].
  ///
  /// All changes must succeed or fail together — use a transaction.
  Future<void> migrate(DatabaseExecutor db);
}

/// A no-op migration placeholder used when a version gap needs to be reserved.
class NoOpMigration extends Migration {
  NoOpMigration._(int toVersion) : _toVersion = toVersion;

  final int _toVersion;

  @override
  int get toVersion => _toVersion;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    // No schema change — reserved version.
  }
}
