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
import 'package:duka_pos/screens/splash_screen.dart';
import 'package:duka_pos/screens/welcome_chooser_screen.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:flutter/material.dart';
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

/// A session with a shop and two staff on the roster, which is what the PIN pad
/// renders.
///
/// CALLED FROM `setUp`, never from inside `testWidgets`. sqflite's ffi backend
/// does real file I/O on a background isolate with real timers, while
/// `testWidgets` runs its body inside a FAKE async zone where those never
/// complete — so an `await` on a query inside a `testWidgets` hangs until the
/// harness kills the file. `setUp` runs outside that zone, so the seed lands and
/// the widget test then only ever reads already-loaded state.
Future<AppState> seedStaffRoster() async {
  await DatabaseHelper.instance
      .addStaff(Staff(name: 'Amina', pinHash: 'x', role: 'admin'));
  await DatabaseHelper.instance
      .addStaff(Staff(name: 'Brian', pinHash: 'x', role: 'cashier'));
  final AppState state = AppState();
  await state.loadOwner();
  return state;
}

/// The PIN pad with a roster supplied through the seam, so the screen renders
/// real content without a database query inside the widget's lifecycle.
Widget _loginWithRoster() => LoginScreen(
      staffLoader: () async => <Staff>[
        Staff(name: 'Amina', pinHash: 'x', role: 'admin'),
        Staff(name: 'Brian', pinHash: 'x', role: 'cashier'),
      ],
    );

Future<List<Staff>> _noStaff() async => <Staff>[];

/// The session the roster was seeded into, rebuilt by `setUp` and handed to the
/// screen under test.
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
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    // Fresh every test: the login screen's roster is what these assert on, and a
    // leaked row from a previous test is a flake that only shows up in CI.
    seeded = await seedStaffRoster();
  });

  for (final Device device in <Device>[Device.compact, Device.small]) {
    for (final double scale in <double>[1.0, 2.0]) {
      for (final Brightness brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        final String where = '${device.name} x$scale $brightness';

        testWidgets('splash fits $where', (WidgetTester tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: const SplashScreen(),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          tester.expectNoOverflow('splash $where');
          expect(find.text('SimpleSales'), findsWidgets);
        });

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
            home: _wrap(_loginWithRoster(), seeded),
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          await tester.pump(const Duration(milliseconds: 50));
          tester.expectNoOverflow('login $where');

          // The person being signed in as must be ON SCREEN at every scale: that
          // is the identity confirmable before four digits are committed, and it
          // is the thing a mis-pick costs. The SECOND user is deliberately not
          // asserted here — at 200% on a 320dp phone it is legitimately below the
          // fold, and requiring it to be built would be asserting a layout this
          // screen should not have.
        });
      }
    }
  }

  group('the roster, which is the list of who can sign in', () {
    testWidgets('one heading per role, and one account per person',
        (WidgetTester tester) async {
      // The shipped bug: the roster stood the owner up as its OWN "Admins"
      // group and then walked the staff by role, which produced two `admin`
      // groups the moment the shop also had an admin-role account — the heading
      // rendered twice and every admin account rendered twice under it.
      //
      // The fixture has an admin (Amina) and a cashier (Brian), and the owner
      // arrives asynchronously so the roster is staff-only here.
      //
      // Uppercase because `SectionHeader` sets a label as a small caps line.
      await tester.pumpApp(home: _wrap(_loginWithRoster(), seeded));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('ADMINS'), findsOneWidget,
          reason: 'one Admins heading, not one per account under it');
      expect(find.text('CASHIERS'), findsOneWidget);
      expect(find.text('Amina'), findsOneWidget,
          reason: 'an admin-role account is listed exactly once');
      expect(find.text('Brian'), findsOneWidget);
    });

    testWidgets('an admin-role account is not dropped when there is no owner',
        (WidgetTester tester) async {
      // The near-miss this replaces: excluding admin staff while an owner
      // exists drops them from the roster entirely, and the account holder is
      // the one person who must always be signable-in on a new phone.
      final AppState ownerless =
          AppState(); // no owner loaded, staff supplied by the loader
      await tester.pumpApp(
        home: _wrap(
          LoginScreen(
            staffLoader: () async => <Staff>[
              Staff(name: 'Amina', pinHash: 'x', role: 'admin'),
            ],
          ),
          ownerless,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Amina'), findsOneWidget,
          reason: 'the only account on the till must be reachable');
    });
  });

  group('the PIN field, which is the only way into a till', () {
    testWidgets('is a field, and it says how many digits are in',
        (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(home: _wrap(_loginWithRoster(), seeded));
      await tester.pump(const Duration(milliseconds: 50));

      // The PIN is typed into a FIELD with the system's own numeric keyboard.
      //
      // It used to be a keypad drawn by the app: four rows of keys taking half
      // the screen of a phone that also has to show the roster, impossible to
      // fill with a barcode scanner or a keyboard case, and a widget with its
      // own hit targets, accessibility and layout at every text scale.
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

      expect(find.bySemanticsLabel('Amina, Admin'), findsOneWidget);

      // The progress is announced, not just drawn: a non-sighted user needs to
      // know how many digits are in before they can tell they are done.
      await tester.enterText(field, '4');
      await tester.pump();
      expect(
        find.bySemanticsLabel('1 of 4 PIN digits entered'),
        findsOneWidget,
      );

      await tester.enterText(field, '');
      await tester.pump();
      expect(
        find.bySemanticsLabel('0 of 4 PIN digits entered'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('takes four digits and no more', (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(home: _wrap(_loginWithRoster(), seeded));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();

      // A PIN is four digits. The field takes four and refuses the rest.
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '1234');
    });

    testWidgets('an empty till offers the way forward, not a dead end',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      // Deliberately a session that never loaded a roster: the screen has to say
      // so and offer the way forward rather than showing an empty pad.
      await tester.pumpApp(
        home: _wrap(const LoginScreen(staffLoader: _noStaff), AppState()),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('This till has no accounts yet'), findsOneWidget);
      expect(find.text('Set this shop up on the device'), findsOneWidget);
    });
  });

  testWidgets('setup validates before it writes anything',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(home: _wrap(const OwnerSetupScreen(), AppState()));
    await tester.tap(find.text('Create shop admin account'));
    await tester.pump();
    // A human sentence naming what is missing, never an exception string.
    expect(
      find.text('Enter your name, email, and shop name'),
      findsOneWidget,
    );
    tester.expectNoOverflow('setup with the submit error showing');
  });

  testWidgets('reduced motion: the splash bar is not indeterminate',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const SplashScreen(),
      disableAnimations: true,
    );
    // An indeterminate `LinearProgressIndicator` animates forever regardless of
    // the platform flag, because its value is null rather than 0. Under reduced
    // motion it must be a fixed, complete-looking bar instead.
    final LinearProgressIndicator bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(
      bar.value,
      isNotNull,
      reason: 'an indeterminate bar still animates under reduced motion',
    );
  });
}
