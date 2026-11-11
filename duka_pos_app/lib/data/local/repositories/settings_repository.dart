import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';

/// Repository for shop settings.
///
/// Manages persistence of key-value settings in the `shop_settings` table.
/// Settings are simple key-value pairs, so individual operations are
/// idempotent and safe — but when a settings change is part of a larger
/// business operation (e.g. enabling credit alongside a sale), the
/// transaction-aware variants should be used inside a database transaction.
class SettingsRepository {
  SettingsRepository._();
  static final SettingsRepository instance = SettingsRepository._();

  /// Creates (or verifies) the `shop_settings` and `receipt_counters` tables.
  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS shop_settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS receipt_counters (
      key TEXT PRIMARY KEY NOT NULL,
      value INTEGER NOT NULL
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS shop_profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      profile TEXT NOT NULL DEFAULT 'duka',
      updated_at TEXT NOT NULL
    )''');
  }

  // ── Setting key constants ──────────────────────────────────────────

  static const String vatRate = 'vat_rate_percent';
  static const String tillCode = 'till_code';
  static const String taxRuleId = 'tax_rule_id';
  static const String taxRuleVersion = 'tax_rule_version';
  static const String creditEnabled = 'credit_enabled';
  static const String creditDefaultLimitMinor = 'credit_default_limit_minor';
  static const String creditLimitMode = 'credit_limit_mode';
  static const String creditCashiersAllowed = 'credit_cashiers_allowed';
  static const String discountsEnabled = 'discounts_enabled';
  static const String expenseApprovalLimitMinor = 'expense_approval_limit_minor';

  // ── Transaction-aware variants ─────────────────────────────────────

  /// Reads a setting within an existing transaction. No commit happens here.
  Future<String?> getSettingInTransaction(Transaction txn, String key) async {
    final rows = await txn.query('shop_settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final value = rows.first['value'];
    return value is String ? value : value?.toString();
  }

  /// Writes a setting within an existing transaction. No commit happens here.
  Future<void> setSettingInTransaction(
      Transaction txn, String key, String? value) async {
    if (value == null) {
      await txn.delete('shop_settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await txn.insert('shop_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<String?> getSetting(String key) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('shop_settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final value = rows.first['value'];
    return value is String ? value : value?.toString();
  }

  Future<void> setSetting(String key, String? value) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await setSettingInTransaction(txn, key, value);
    });
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('shop_settings');
    return {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
  }
}
