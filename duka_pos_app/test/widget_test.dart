// Smoke test for the app root.
//
// The original version asserted `colorScheme.primary == DukaColors.primary`.
// `DukaColors` no longer exists: the palette is now two hand-authored slots
// behind a ThemeExtension, and the test was asserting a single derived field.
//
// What this file is FOR now is the one thing a smoke test can still catch that
// nothing else does: that `MaterialApp.router` is wired, that BOTH themes are
// supplied, and that the theme animation is off. A theme regression that leaves
// the till unreadable is a POS-blocking bug, so the brand values stay pinned —
// but they are pinned through the token layer now, which is where a change
// belongs.
//
// Scope is deliberately limited to the app's synchronous chrome. Asserting the
// first SCREEN the router resolves is not possible here: that path awaits real
// sqlite I/O through sqflite_common_ffi, and `testWidgets` runs on a fake async
// clock, so awaited file I/O inside the widget tree never completes.
// `database_helper_test.dart` exercises that path properly with plain `test()`.

import 'package:duka_pos/app_brand.dart';
import 'package:duka_pos/main.dart';
import 'package:duka_pos/theme/app_colors.dart';
import 'package:duka_pos/theme/appearance_controller.dart';
import 'package:duka_pos/theme/app_haptics.dart';
import 'package:duka_pos/theme/app_motion.dart';
import 'package:duka_pos/theme/app_shapes.dart';
import 'package:duka_pos/theme/app_spacing.dart';
import 'package:duka_pos/theme/primitives.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Same ffi wiring as database_helper_test.dart: the real schema, no device.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppearanceController appearance;

  DukaPosApp appUnderTest() => DukaPosApp(
        appearance: appearance,
        bootOnStart: false,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DatabaseHelper.resetForTests();
    appearance = AppearanceController(await SharedPreferences.getInstance());
  });

  testWidgets('the app is wired to a router, with a title and no debug banner',
      (WidgetTester tester) async {
    await tester.pumpWidget(appUnderTest());

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, SimplePosBrand.appName);
    expect(app.debugShowCheckedModeBanner, isFalse);

    // The router, not a `home:`. A second `MaterialApp` or a nested `Navigator`
    // would fragment deep links and back-button behaviour.
    expect(app.routerConfig, isNotNull);
    expect(app.home, isNull);
  });

  testWidgets('BOTH themes are supplied, and each carries every extension',
      (WidgetTester tester) async {
    await tester.pumpWidget(appUnderTest());

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    // A missing darkTheme is not a cosmetic bug: `MaterialApp` silently falls
    // back to the light theme for every dark-mode system setting, so a till in a
    // dim shop renders paper-white at full brightness.
    expect(app.darkTheme, isNotNull);
    expect(app.themeMode, appearance.themeMode);

    for (final (String name, ThemeData? theme) in <(String, ThemeData?)>[
      ('light', app.theme),
      ('dark', app.darkTheme),
    ]) {
      expect(theme, isNotNull, reason: name);
      expect(theme!.extension<AppColors>(), isNotNull, reason: name);
      expect(theme.extension<AppShapes>(), isNotNull, reason: name);
      expect(theme.extension<AppSpacing>(), isNotNull, reason: name);
      expect(theme.extension<AppMotion>(), isNotNull, reason: name);
      expect(theme.extension<HapticTheme>(), isNotNull, reason: name);
    }
  });

  testWidgets('application colors use the current palette tokens',
      (WidgetTester tester) async {
    await tester.pumpWidget(appUnderTest());

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(
      app.theme!.colorScheme.primary,
      Primitives.forest,
      reason: 'primary actions use the forest-green brand token',
    );
    expect(
      app.theme!.extension<AppColors>()!.onSurface,
      Primitives.textInk,
      reason: 'body text uses the specified primary ink',
    );
    expect(app.theme!.scaffoldBackgroundColor, Colors.transparent);
  });

  testWidgets('theme animation is off, so a theme change never half-fades',
      (WidgetTester tester) async {
    await tester.pumpWidget(appUnderTest());

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    // A theme change is a sudden luminance change the user did not cause.
    // Interpolating it renders a half-styled state no screen was laid out for.
    expect(app.themeAnimationStyle?.duration, Duration.zero);
  });

  testWidgets('startup route renders app chrome before storage boot',
      (WidgetTester tester) async {
    await tester.pumpWidget(appUnderTest());
    await tester.pump();

    // Keep this smoke test on synchronous app chrome. Database boot is covered
    // by database tests using the real async test environment.
    expect(find.byType(Scaffold), findsWidgets);
  });
}
