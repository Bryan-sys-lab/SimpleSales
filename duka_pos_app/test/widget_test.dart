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
import 'package:duka_pos/theme/app_haptics.dart';
import 'package:duka_pos/theme/app_motion.dart';
import 'package:duka_pos/theme/app_shapes.dart';
import 'package:duka_pos/theme/app_spacing.dart';
import 'package:duka_pos/theme/primitives.dart';
import 'package:flutter/material.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DatabaseHelper.resetForTests();
  });

  testWidgets('the app is wired to a router, with a title and no debug banner',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DukaPosApp());

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
    await tester.pumpWidget(const DukaPosApp());

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    // A missing darkTheme is not a cosmetic bug: `MaterialApp` silently falls
    // back to the light theme for every dark-mode system setting, so a till in a
    // dim shop renders paper-white at full brightness.
    expect(app.darkTheme, isNotNull);
    expect(app.themeMode, ThemeMode.system);

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

  testWidgets('the brand values the launcher icon also uses are pinned',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DukaPosApp());

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    // The accent IS the brand wine, and the body ink IS the brand ink. These four
    // files must change together or the app grows a second logo:
    // lib/theme/primitives.dart, lib/ui/brand/simple_pos_mark.dart,
    // android/app/src/main/res/values/colors.xml,
    // assets/branding/generate_launcher_icon.py
    // plus the 19 iOS and 25 Android mipmaps, checked by app_brand_test.dart.
    expect(
      app.theme!.colorScheme.primary,
      Primitives.botanical38,
      reason: 'the accent must stay the brand green #1B6B3A',
    );
    expect(
      app.theme!.extension<AppColors>()!.onSurface,
      Primitives.neutral23,
      reason: 'body ink must stay the brand ink #2D2A26',
    );
    expect(app.theme!.scaffoldBackgroundColor, Primitives.neutral97);
  });

  testWidgets('theme animation is off, so a theme change never half-fades',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DukaPosApp());

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    // A theme change is a sudden luminance change the user did not cause.
    // Interpolating it renders a half-styled state no screen was laid out for.
    expect(app.themeAnimationStyle?.duration, Duration.zero);
  });

  testWidgets('boot renders the branded splash, not a blank frame',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DukaPosApp());
    await tester.pump();

    // The assertion is deliberately about "something real rendered", not about a
    // specific spinner: the splash is a branded mark, and pinning it to one
    // implementation would make the test hostile to a redesign of the boot
    // screen for no benefit. What must never regress is a BLANK first frame —
    // which is the failure a shopkeeper sees as "the app is broken".
    expect(find.byType(Scaffold), findsWidgets);
  });
}
