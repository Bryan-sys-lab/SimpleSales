import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/ui/dialogs/manager_approval_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/harness.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DatabaseHelper.openInMemoryForTests();
  });

  testWidgets('probe no approvers', (tester) async {
    tester.useDevice(Device.medium);
    await tester.runAsync(() async {
      await DatabaseHelper.instance
          .addStaff(Staff(name: 'Amina', pinHash: '', role: 'cashier'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    final List<Staff>? staff =
        await tester.runAsync(() => DatabaseHelper.instance.getStaff());
    // ignore: avoid_print
    print('SEEDS staff=${staff?.length}');
    await tester.pumpApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                await showManagerApprovalSheet(context, purpose: 'p');
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final bool banner =
          find.byType(ManagerApprovalSheet).evaluate().isNotEmpty &&
              find.textContaining('Nobody can approve').evaluate().isNotEmpty;
      if (banner) {
        // ignore: avoid_print
        print('BANNER after ${i + 1} windows');
        return;
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
    }
    // ignore: avoid_print
    print('NO BANNER sheet=${find.byType(ManagerApprovalSheet).evaluate().length} '
        'spinners=${find.byType(CircularProgressIndicator).evaluate().length} '
        'anyText=${find.textContaining('Nobody').evaluate().length}');
  });
}
