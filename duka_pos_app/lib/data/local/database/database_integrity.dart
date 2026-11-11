import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import 'package:sqflite/sqflite.dart';

/// Database integrity verification.
///
/// Runs after migrations and restores to confirm the database is in a
/// consistent, verifiable state. Includes foreign-key checks and financial
/// event ledger integrity verification.
class DatabaseIntegrity {
  DatabaseIntegrity._();

  /// Runs all integrity checks on [db].
  ///
  /// Throws [StateError] if any check fails. Callers should treat this as a
  /// fatal condition — the database must not be used until the issue is
  /// resolved.
  static Future<void> verify(Database db) async {
    await _verifyForeignKeys(db);
    await _verifyFinancialEventLedger(db);
  }

  /// Runs `PRAGMA foreign_key_check` and reports any violations.
  static Future<void> _verifyForeignKeys(Database db) async {
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      throw StateError(
          'Foreign-key integrity violation: ${violations.length} orphaned '
          'references found');
    }
  }

  /// Verifies the financial event ledger's hash-chain integrity.
  ///
  /// Each financial event's `integrity_hash` must chain to the previous event's
  /// hash. A break in the chain means a financial event was tampered with or
  /// partially written.
  static Future<void> _verifyFinancialEventLedger(Database db) async {
    final events = await db.query(
      'financial_events',
      orderBy: 'id ASC',
    );

    String? previousHash;
    for (final event in events) {
      final currentHash = event['integrity_hash'] as String?;
      if (currentHash == null || currentHash.isEmpty) {
        throw StateError(
            'Financial event ${event['id']} has no integrity hash');
      }

      final expectedHash = _computeEventHash(
        previousHash,
        event['event_type'] as String?,
        event['source_type'] as String?,
        event['source_id'] as int?,
        event['occurred_at_utc'] as String?,
      );

      if (currentHash != expectedHash) {
        throw StateError(
            'Financial event ledger integrity broken at event '
            '${event['id']}');
      }

      previousHash = currentHash;
    }
  }

  /// Computes the integrity hash for a financial event.
  static String _computeEventHash(
    String? previousHash,
    String? eventType,
    String? sourceType,
    int? sourceId,
    String? occurredAtUtc,
  ) {
    final buffer = StringBuffer();
    buffer.write(previousHash ?? '');
    buffer.write('|');
    buffer.write(eventType ?? '');
    buffer.write('|');
    buffer.write(sourceType ?? '');
    buffer.write('|');
    buffer.write(sourceId ?? '');
    buffer.write('|');
    buffer.write(occurredAtUtc ?? '');
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }
}
