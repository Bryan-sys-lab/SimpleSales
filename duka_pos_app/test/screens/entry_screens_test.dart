// End-to-end render checks for the five screens OUTSIDE the shell.
//
// These are the screens a shopkeeper meets before there is a session, and none of
// them can be exercised by a unit test: the question each one answers is whether
// it LAYS OUT. So the matrix is device x text scale x brightness — a splash that
// fits at 1.0x on a 360dp phone can still overflow at 2.0x, and a screen that
// only ever renders in light mode is a screen nobody has tested.
//
// `loadAppFonts` is not optional here: under the default Ahem test font every
// glyph is a fixed em-square, so the `x2.0` half of the matrix would pass
// vacuously while the real phone overflows.
//
// An earlier draft of this lived in `tool/`, which `flutter test` does not scan.
// A check that only runs when someone remembers to run it is not a check.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/screens/login_screen.dart';
import 'package:duka_pos/screens/onboarding_screen.dart';
import 'package:duka_pos/screens/owner_setup_screen.dart';
import 'package:duka_pos/screens/welcome_chooser_screen.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/harness.dart';

/// The providers the entry screens read: the session, and the boot gate that
/// decides which of them the router shows.
Widget _wrap(Widget child, AppState state) {
  return MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<AppState>.value(value: state),
      ChangeNotifierProvider<AppStageController>(
        create: (_) => AppStageController(state),
      ),
    ],
    child: child,
  );
}

/// A session with an owner and staff on the roster. The local PIN screen must
/// identify only the owner; staff use the separate shop-ID sign-in.
///
/// CALLED FROM `setUp`, never from inside `testWidgets`. sqflite's ffi backend
/// does real file I/O on a background isolate with real timers, while
/// `testWidgets` runs its body inside a FAKE async zone where those never
/// complete — so an `await` on a query inside a `testWidgets` hangs until the
/// harness kills the file. `setUp` runs outside that zone, so the seed lands and
/// the widget test then only ever reads already-loaded state.
Future<AppState> seedStaffRoster() async {
  await DatabaseHelper.instance.createOwner(
    Owner(
      id: 1,
      name: 'Shop Owner',
      pinHash: 'owner-hash',
      shopName: 'Mtaa Corner Shop',
      createdAt: DateTime(2026).toIso8601String(),
    ),
  );
  await DatabaseHelper.instance
      .addStaff(Staff(name: 'Amina', pinHash: 'x', role: 'admin'));
  await DatabaseHelper.instance
      .addStaff(Staff(name: 'Brian', pinHash: 'x', role: 'cashier'));
  final AppState state = AppState();
  await state.loadOwner();
  return state;
}

/// The PIN pad backed by the seeded owner, so the screen renders real content
/// without a database query inside the widget's lifecycle.
Widget _ownerLogin() => const LoginScreen();

/// The seeded session, rebuilt by `setUp` and handed to the screen under test.
///
/// A widget must read the SAME `AppState` the seed loaded. A fresh `AppState()`
/// inside the test would have an empty roster, and the screen would correctly
/// render "no accounts yet" — the assertion would fail for a reason that has
/// nothing to do with layout.
late AppState seeded;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await loadAppFonts();
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
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    await DatabaseHelper.openInMemoryForTests();
    // Keep the owner/staff fixture isolated between layout and sign-in cases.
    seeded = await seedStaffRoster();
  });

  tearDown(() async {
    DatabaseHelper.resetForTests();
    await DatabaseHelper.closeForTests();
  });

  for (final Device device in <Device>[Device.compact, Device.small]) {
    for (final double scale in <double>[1.0, 2.0]) {
      for (final Brightness brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        final String where = '${device.name} x$scale $brightness';

        testWidgets('chooser fits $where', (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: _wrap(
              const WelcomeChooserScreen(
                shopName: 'Mtaa Corner Shop',
                hasShop: true,
              ),
              AppState(),
            ),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('chooser $where');
        });

        testWidgets('setup fits $where', (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: _wrap(
              const OwnerSetupScreen(isAdditionalShop: true),
              AppState(),
            ),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('setup $where');
        });

        testWidgets('onboarding fits $where, on every step',
            (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: _wrap(const OnboardingScreen(), AppState()),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('onboarding $where');

          // Each step is a DIFFERENT amount of content. Checking only step one is
          // how a two-paragraph step ships clipped.
          await tester.tap(find.text('Continue'));
          await tester.pump();
          tester.expectNoOverflow('onboarding step 2 $where');

          await tester.tap(find.text('Continue'));
          await tester.pump();
          tester.expectNoOverflow('onboarding import step $where');
        });

        testWidgets('login fits $where', (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: _wrap(_ownerLogin(), seeded),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          await tester.pump(const Duration(milliseconds: 50));
          tester.expectNoOverflow('login $where');

          expect(find.text('Shop Owner'), findsOneWidget);
        });
      }
    }
  }

  group('owner-only local PIN sign-in', () {
    testWidgets('does not present roster staff as login identities',
        (WidgetTester tester) async {
      await tester.pumpApp(home: _wrap(_ownerLogin(), seeded));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Shop Owner'), findsOneWidget);
      expect(find.text('Shop owner'), findsOneWidget);
      expect(find.text('Amina'), findsNothing);
      expect(find.text('Brian'), findsNothing);
    });

    testWidgets('staff rows do not unlock the local screen without an owner',
        (WidgetTester tester) async {
      await tester.pumpApp(
        home: _wrap(const LoginScreen(), AppState()),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('This till has no accounts yet'), findsOneWidget);
      expect(find.text('Amina'), findsNothing);
      expect(find.text('Brian'), findsNothing);
      expect(find.text('Sign in as staff'), findsOneWidget);
    });
  });

  group('owner PIN entry', () {
    testWidgets('is a field, and it says how many digits are in',
        (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(home: _wrap(_ownerLogin(), seeded));
      await tester.pump(const Duration(milliseconds: 50));

      // The PIN is typed into a FIELD with the system's own numeric keyboard.
      //
      // It used to be a keypad drawn by the app: a large custom control with
      // its own hit targets, accessibility, and layout at every text scale.
      final Finder field = find.byType(TextField);
      expect(field, findsOneWidget);

      // The keyboard is the system's, and it is a NUMBER keyboard.
      final TextField pin = tester.widget<TextField>(field);
      expect(pin.keyboardType, TextInputType.number);
      expect(pin.obscureText, isTrue);
      expect(pin.autofocus, isTrue);

      // A field, so it is the field's own size — the 44dp floor is the
      // framework's, not the app's.
      expect(tester.getSize(field).height, greaterThanOrEqualTo(44.0));

      expect(find.text('Shop Owner'), findsOneWidget);

      // The progress is announced, not just drawn: a non-sighted user needs to
      // know how many digits are in before they can tell they are done.
      await tester.enterText(field, '4');
      await tester.pump();
      expect(
        find.bySemanticsLabel('1 of 6 PIN digits entered'),
        findsOneWidget,
      );

      await tester.enterText(field, '');
      await tester.pump();
      expect(
        find.bySemanticsLabel('0 of 6 PIN digits entered'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('takes at most six digits', (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(home: _wrap(_ownerLogin(), seeded));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(TextField), '12345678');
      await tester.pump();

      // An owner PIN is six digits. The field takes six and refuses the rest.
      // The wrong-PIN flow may clear the field afterwards — that is the login
      // flow, not the six-digit limit under test here.
      final text =
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(text.length, lessThanOrEqualTo(6));
    });

    testWidgets('an empty till offers the way forward, not a dead end',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      // Staff rows exist in the database, but without an owner this route must
      // offer setup or the separate remote staff sign-in.
      await tester.pumpApp(
        home: _wrap(const LoginScreen(), AppState()),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('This till has no accounts yet'), findsOneWidget);
      // The same sentence the settings screen uses when a shop is missing on
      // this device — one phrasing for one situation, so the two screens do
      // not describe the same fix in two ways.
      expect(
          find.text('Set this shop up on this device first'), findsOneWidget);
    });
  });

  testWidgets('setup validates before it writes anything',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(home: _wrap(const OwnerSetupScreen(), AppState()));
    await tester.tap(find.text('Continue to email verification'));
    await tester.pump();
    // A human sentence naming what is missing, never an exception string.
    expect(
      find.text('Enter your name, email, and shop name'),
      findsOneWidget,
    );
    tester.expectNoOverflow('setup with the submit error showing');
  });
}
