// Smoke test for the app root. Replaces the Flutter template counter test,
// which referenced a `MyApp` class this project never had.
//
// Scope is deliberately limited to the app's synchronous chrome (title, theme,
// debug banner). Asserting the first *screen* RootRouter picks is not possible
// here: that path awaits real sqlite I/O through sqflite_common_ffi, and
// `testWidgets` runs on a fake async clock, so any real file I/O awaited inside
// the widget tree never completes and RootRouter stays on its spinner.
// `database_helper_test.dart` exercises the schema and that boot path's data
// layer properly with plain `test()`, where real async works.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/main.dart';
import 'package:duka_pos/theme/app_theme.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Same ffi wiring as database_helper_test.dart: the real schema, no device.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DatabaseHelper.resetForTests();
  });

  testWidgets('app boots with the branded shell and no debug banner',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DukaPosApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Duka POS');
    expect(app.debugShowCheckedModeBanner, isFalse);
    // A theme regression (unreadable till, lost contrast) is a POS-blocking
    // bug, so pin the brand tokens rather than letting them change silently.
    // ThemeData itself is not compared: its `==` covers derived fields that
    // differ between two otherwise identical instances.
    final theme = app.theme!;
    expect(theme.colorScheme.primary, DukaColors.primary);
    expect(theme.scaffoldBackgroundColor, DukaColors.canvas);
  });

  testWidgets('boot shows a progress indicator instead of a blank frame',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DukaPosApp());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}