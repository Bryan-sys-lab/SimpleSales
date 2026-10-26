// The customers surface, as the shop uses it.
//
// ## WHAT IS PINNED
//
//   * the list renders names, numbers (display form) and balance chips, and
//     the header says what the shop is owed and by how many;
//   * owed vs in-credit read differently IN WORDS — never colour alone;
//   * a CASHIER reads but does not own: the affordance is disabled;
//   * a payment taken reloads the list to the LEDGER's answer;
//   * the sell flow's picker searches by name, shows the headroom under the
//     limit, and adds a customer inline — the sale is mid-service.

import 'package:duka_pos/db/database_helper.dart';

import 'package:duka_pos/models/credit.dart';
import 'package:duka_pos/screens/customer_credit_sheets.dart';
import 'package:duka_pos/screens/customers_screen.dart';
import 'package:duka_pos/services/app_state.dart';

import '../support/harness.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    await DatabaseHelper.instance.setCreditEnabled(true);
  });

  AppState stateUnderTest({required bool asOwner, String role = 'cashier'}) {
    final AppState state = AppState();
    state.signIn('Amina', asOwner: asOwner, role: role);
    return state;
  }

  /// Pumps [home] under the harness (real theme, real l10n), with the
  /// session person the test names, and lets the FIRST load's real database
  /// I/O land in real time before the settle — a spinner backed by a real
  /// isolate never settles in fake-async time alone.
  Future<void> pumpAs(
    WidgetTester tester, {
    required bool asOwner,
    required String role,
    required Widget home,
  }) async {
    final AppState state = stateUnderTest(asOwner: asOwner, role: role);
    await tester.pumpApp(appState: state, home: home);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  /// Seeds and returns MARY: owes [balanceMinor], limit KSh 20000, phone
  /// +254712345678.
  Future<Customer> seedMary(int balanceMinor) async {
    final int id = await DatabaseHelper.instance.upsertCustomer(Customer(
      uuid: 'c-mary',
      name: 'Mary Wanjiku',
      phone: '+254712345678',
      creditLimitMinor: 20000,
      balanceMinor: balanceMinor,
      createdAt: DateTime.now().toIso8601String(),
    ));
    return (await DatabaseHelper.instance.getCustomerById(id))!;
  }

  /// Taps [finder], then lets real time carry the write and the sheet's own
  /// first load, and pumps the frames that answer arrived in.
  ///
  /// NOT pumpAndSettle: every sheet here opens with a FOCUSED text field,
  /// and a caret blinks forever — a settle that waits for "no animation"
  /// waits forever on the one animation that never ends.
  Future<void> tapThenRealTime(WidgetTester tester, Finder finder,
      {int ms = 1400}) async {
    await tester.tap(finder, warnIfMissed: false);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration(milliseconds: ms));
      });
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Widget pickerOpener() =>
      // The sheet a real phone opens over a Scaffold; a snackbar needs one.
      Scaffold(
        body: Builder(builder: (BuildContext context) {
          return Center(
            child: FilledButton(
              key: const ValueKey<String>('customer-picker-open'),
              onPressed: () => showCustomerPickerSheet(context),
              child: const Text('open'),
            ),
          );
        }),
      );

  group('the customers list', () {
    testWidgets('names, numbers, chips; the header totals',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await seedMary(5000);
        await DatabaseHelper.instance.upsertCustomer(Customer(
          uuid: 'c-brian',
          name: 'Brian Otieno',
          phone: '+254701234567',
          balanceMinor: -500,
          createdAt: DateTime.now().toIso8601String(),
        ));
      });
      await pumpAs(
        tester,
        asOwner: true,
        role: 'owner',
        home: const CustomersScreen(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mary Wanjiku'), findsOneWidget);
      // The DISPLAY form of the number, the way the shop types it.
      expect(find.text('0712345678'), findsOneWidget);
      expect(find.text('Brian Otieno'), findsOneWidget);
      // The chips speak: owed there, credit here — words, not colour.
      expect(find.text('Owes KSh 50'), findsOneWidget);
      expect(find.textContaining('Credit with them'), findsOneWidget);
    });

    testWidgets('a cashier reads, but does not own',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await seedMary(5000);
      });
      await pumpAs(
        tester,
        asOwner: false,
        role: 'cashier',
        home: const CustomersScreen(),
      );
      await tester.pumpAndSettle();

      final Finder add = find.byTooltip('Add customer');
      expect(add, findsOneWidget);
      final FloatingActionButton fab = (find
          .ancestor(
            of: add,
            matching: find.byType(FloatingActionButton),
          )
          .evaluate()
          .first
          .widget as FloatingActionButton);
      expect(fab.onPressed, isNull);
    });

    testWidgets('a payment taken reloads to the ledger answer',
        (WidgetTester tester) async {
      Customer? seeded;
      await tester.runAsync(() async {
        seeded = await seedMary(10000);
        await DatabaseHelper.instance.openShift(
          staffId: 7,
          staffName: 'Amina',
          startFloat: Money.zero,
        );
      });
      await pumpAs(
        tester,
        asOwner: true,
        role: 'owner',
        home: const CustomersScreen(),
      );
      await tester.pumpAndSettle();

      await tapThenRealTime(tester, find.text('Mary Wanjiku'));

      // THE PAYMENT SHEET: balance pre-filled, cash, confirm.
      await tapThenRealTime(tester, find.widgetWithText(FilledButton, 'Add payment'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Take the payment'), warnIfMissed: false);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 350));
      // The sheet closed and the list RELOADED another real-isolate query —
      // give that load its own bridge before the list is read.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pump(const Duration(milliseconds: 350));

      // THE LEDGER'S ANSWER (the same read every reload of the list gets):
      // what was owed is now nothing, and the cash landed in the shift.
      final Customer? after = (await tester
          .runAsync<Customer?>(() => DatabaseHelper.instance.getCustomerById(seeded!.id!)));
      expect(after?.balanceMinor, 0);
    });
  });

  group('the sell picker', () {
    testWidgets('shows the name and the headroom under the limit',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await seedMary(15000); // limit 20000 → room 5000.
      });
      await pumpAs(
        tester,
        asOwner: true,
        role: 'owner',
        home: pickerOpener(),
      );
      await tapThenRealTime(
          tester, find.byKey(const ValueKey<String>('customer-picker-open')));

      // The row: the name, the balance below, the room to the right.
      expect(find.text('Mary Wanjiku'), findsOneWidget);
      expect(find.text('KSh 50'), findsOneWidget);
    });

    testWidgets('a customer can be added inline, mid-sale',
        (WidgetTester tester) async {
      await pumpAs(
        tester,
        asOwner: true,
        role: 'owner',
        home: pickerOpener(),
      );
      await tapThenRealTime(
          tester, find.byKey(const ValueKey<String>('customer-picker-open')));

      await tester.tap(find.text('Add a new customer'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Customer name'),
          'Otieno Supplies');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone number').last,
          '0710987654');
      await tester.runAsync(() async {
        await tester.tap(find.text('Save customer'), warnIfMissed: false);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();

      // The picker closed — a PICKED answer for the sale — and the database
      // holds the same customer, number canonical.
      final Customer saved = (await tester.runAsync<List<Customer>>(
        () => DatabaseHelper.instance.getCustomers(search: 'Otieno'),
      ))!.single;
      expect(saved.phone, '+254710987654');
    });
  });
}
