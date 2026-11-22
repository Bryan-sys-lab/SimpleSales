import 'package:duka_pos/profile/business_context.dart';
import 'package:duka_pos/profile/business_context_editor.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/db/database_helper.dart';
import 'package:material_ui/material_ui.dart';
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

  testWidgets('business details editor renders at phone width', (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push<bool>(MaterialPageRoute(
                    builder: (_) => BusinessContextEditor(
                      initial: const BusinessContext(),
                      profile: ShopProfile.fashion,
                    ),
                  )),
                  child: const Text('Open business details'),
                )))));
    await tester.tap(find.text('Open business details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fashion'), findsOneWidget);
    expect(find.text('Primary activity (KeSIC)'), findsOneWidget);
    await tester.tap(find.text('Primary activity (KeSIC)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
        find.byType(TextField).last, '477110');
    await tester.pump();
    const activityLabel = '477110 · Retail sale of articles of clothing';
    expect(find.text(activityLabel), findsOneWidget);
    await tester.tap(find.text(activityLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(activityLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
