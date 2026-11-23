import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import 'backend_service.dart';

class CommercialContributionService {
  CommercialContributionService._();

  static final Random _random = Random.secure();

  static String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }

  static Future<Map<String, Object?>?> prepareMonthlyBatch({
    required DateTime periodStartUtc,
  }) async {
    final grant =
        await DatabaseHelper.instance.getActiveCommercialConsentGrant();
    if (grant == null) return null;
    final end = DateTime.utc(
      periodStartUtc.year,
      periodStartUtc.month + 1,
      1,
    );
    final db = await DatabaseHelper.instance.database;
    final sales = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS transaction_count,
        COALESCE(SUM(subtotal_minor), 0) AS gross_minor,
        COALESCE(SUM(order_discount_minor), 0) AS discount_minor,
        COALESCE(SUM(vat_minor), 0) AS tax_minor
      FROM sales
      WHERE payment_verified = 1
        AND created_at >= ? AND created_at < ?
      ''',
      [periodStartUtc.toIso8601String(), end.toIso8601String()],
    );
    final row = sales.single;
    final transactionCount = (row['transaction_count'] as num).toInt();
    if (transactionCount == 0) return null;
    final gross = (row['gross_minor'] as num).toInt();
    final discount = (row['discount_minor'] as num).toInt();
    final tax = (row['tax_minor'] as num).toInt();
    final net = gross - discount - tax;

    final profile = await db.query('shop_profile', limit: 1);
    final appProfile =
        profile.isEmpty ? 'duka' : profile.first['profile'] as String;
    final batch = <String, Object?>{
      'batch_id': _uuid(),
      'schema_version': 'ci-contribution-v1',
      'dictionary_version': '2.0.0',
      'period': {
        'from_utc': periodStartUtc.toIso8601String(),
        'to_utc': end.toIso8601String(),
        'grain': 'month',
        'reporting_timezone': 'Africa/Nairobi',
      },
      'app_profile': appProfile,
      'scope_codes': grant.scopes,
      'dimensions': {
        'unit_scheme': 'local',
        'unit_code': 'unknown',
        'currency': 'KES',
      },
      'metrics': {
        'transaction_count': transactionCount,
        'gross_sales_minor': gross,
        'discount_minor': discount,
        'refund_minor': 0,
        'net_sales_ex_tax_minor': net < 0 ? 0 : net,
        'tax_collected_minor': tax,
      },
      'quality': {
        'sale_line_coverage': 1.0,
        'stock_tracking_coverage': null,
      },
    };
    return batch;
  }

  static Future<bool> enqueueMonthlyBatch({
    required DateTime periodStartUtc,
  }) async {
    final batch = await prepareMonthlyBatch(periodStartUtc: periodStartUtc);
    if (batch == null) return false;
    final grant =
        await DatabaseHelper.instance.getActiveCommercialConsentGrant();
    if (grant == null) return false;
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'commercial_contribution_queue',
      {
        'batch_uuid': batch['batch_id'] as String,
        'scope_codes_json': jsonEncode(batch['scope_codes']),
        'payload_json': jsonEncode(batch),
        'status': 'queued',
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  static Future<int> uploadQueued({int limit = 50}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'commercial_contribution_queue',
      where: 'status = ?',
      whereArgs: ['queued'],
      orderBy: 'created_at_utc ASC',
      limit: limit,
    );
    var uploaded = 0;
    for (final row in rows) {
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      await BackendService.submitCommercialContributionBatch(payload);
      await db.update(
        'commercial_contribution_queue',
        {
          'status': 'accepted',
          'last_attempt_at_utc':
              DateTime.now().toUtc().toIso8601String(),
        },
        where: 'batch_uuid = ?',
        whereArgs: [row['batch_uuid']],
      );
      uploaded++;
    }
    return uploaded;
  }
}
