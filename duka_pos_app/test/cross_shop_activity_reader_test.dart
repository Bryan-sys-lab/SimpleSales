import 'dart:io';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/audit_log.dart';
import 'package:duka_pos/services/cross_shop_activity_reader.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Mock flutter_secure_storage so workspace key lookups work without a
    // platform keystore in a plain `flutter test` run.
    final fake = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        switch (call.method) {
          case 'read':
            return fake[args['key'] as String?];
          case 'write':
            final value = args['value'] as String?;
            if (value == null) {
              fake.remove(args['key'] as String);
            } else {
              fake[args['key'] as String] = value;
            }
            return null;
          case 'delete':
            fake.remove(args['key'] as String);
            return null;
          default:
            return null;
        }
      },
    );
    final dir = Directory('.dart_tool/sqflite_common_ffi/databases');
    if (dir.existsSync()) {
      for (final file in dir.listSync()) {
        if (file is File && file.path.endsWith('.db')) file.deleteSync();
      }
    }
  });

  setUp(() {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{
      WorkspaceService.registryKeyForTests: '{}',
    });
  });

  test('reads a bounded local page and continues after its stable cursor',
      () async {
    final key = 'activity-reader-${DateTime.now().microsecondsSinceEpoch}';
    await WorkspaceService.register(workspaceKey: key, shopName: 'Amina Duka');
    await DatabaseHelper.instance.switchWorkspace(key);
    for (var i = 0; i < 3; i++) {
      await DatabaseHelper.instance.recordAudit(AuditLogEntry(
        action: AuditAction.backupErased,
        entity: AuditEntity.backup,
        actorName: 'Amina',
        detail: 'row $i',
        createdAt: '2026-10-25T10:00:0$i.000Z',
      ));
    }

    final filters = CrossShopActivityFilters(
      from: DateTime.parse('2026-10-25T00:00:00Z'),
      to: DateTime.parse('2026-10-26T00:00:00Z'),
      type: 'activity',
      status: 'recorded',
    );
    final first = await CrossShopActivityReader.readLocal(
      filters,
      limitPerShop: 2,
    );
    expect(first.events, hasLength(2));
    expect(first.events.first.detail, contains('row 2'));
    expect(first.nextCursor, isNotNull);

    final second = await CrossShopActivityReader.readLocal(
      CrossShopActivityFilters(
        from: filters.from,
        to: filters.to,
        type: filters.type,
        status: filters.status,
        cursor: first.nextCursor,
      ),
      limitPerShop: 2,
    );
    expect(second.events, hasLength(1));
    expect(second.events.single.detail, contains('row 0'));
  });
}
