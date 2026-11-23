import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/profile/commercial_consent.dart';
import 'package:duka_pos/services/commercial_contribution_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    await DatabaseHelper.openInMemoryForTests();
  });

  test('dedicated queue produces no batch without an active grant', () async {
    final enqueued = await CommercialContributionService.enqueueMonthlyBatch(
      periodStartUtc: DateTime.utc(2026, 10),
    );
    expect(enqueued, isFalse);
  });

  test('active grant queues a coarse period aggregate and never an owner ID',
      () async {
    await DatabaseHelper.instance.saveCommercialConsentGrant(
      CommercialConsentGrant(
        grantUuid: 'c33b2cb2-8c19-4bb4-9e7d-14bd6fe26c52',
        status: 'active',
        scopes: const ['product_demand', 'digitisation_metrics'],
        noticeVersion: 'commercial-notice-v1-draft',
        noticeDigest:
            'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        schemaVersion: 'commercial-contribution-v1',
        dictionaryVersion: 'duka-pos-data-dictionary-v2',
        appVersion: '100+100',
        captureMethod: 'in_app_affirmative',
        authorityEvidence: 'owner',
        effectiveAtUtc: '2026-10-01T00:00:00Z',
      ),
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert('sales', {
      'staff_name': 'Amina',
      'total': 5000,
      'profit': 1000,
      'payment_method': 'cash',
      'amount_tendered': 5000,
      'change_given': 0,
      'created_at': '2026-10-10T10:00:00Z',
      'subtotal_minor': 5000,
      'order_discount_minor': 500,
      'vat_minor': 0,
      'taxable_minor': 5000,
      'payment_verified': 1,
      'etims_status': 'not_required',
      'document_type': 'sale',
    });

    final batch =
        await CommercialContributionService.prepareMonthlyBatch(
      periodStartUtc: DateTime.utc(2026, 10),
    );
    expect(batch, isNotNull);
    expect(batch!.containsKey('tenant_id'), isFalse);
    expect(batch.containsKey('customer_name'), isFalse);
    expect(batch['metrics'], isA<Map>());
    expect((batch['metrics'] as Map)['transaction_count'], 1);
  });

  test('withdrawal purges queued unsent contribution batches', () async {
    await DatabaseHelper.instance.saveCommercialConsentGrant(
      CommercialConsentGrant(
        grantUuid: 'b44c2cb2-8c19-4bb4-9e7d-14bd6fe26c52',
        status: 'active',
        scopes: const ['product_demand'],
        noticeVersion: 'commercial-notice-v1-draft',
        noticeDigest:
            'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        schemaVersion: 'commercial-contribution-v1',
        dictionaryVersion: 'duka-pos-data-dictionary-v2',
        appVersion: '100+100',
        captureMethod: 'in_app_affirmative',
        authorityEvidence: 'owner',
        effectiveAtUtc: '2026-10-01T00:00:00Z',
      ),
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert('commercial_contribution_queue', {
      'batch_uuid': '7d2a7b6a-6d74-4d4b-a5d5-0c5b5b5b5b5b',
      'scope_codes_json': '["product_demand"]',
      'payload_json': '{}',
      'status': 'queued',
      'created_at_utc': '2026-10-01T00:00:00Z',
    });
    await DatabaseHelper.instance.withdrawCommercialConsentGrants();
    expect(
      await db.query(
        'commercial_contribution_queue',
        where: "status = 'queued'",
      ),
      isEmpty,
    );
  });
}
