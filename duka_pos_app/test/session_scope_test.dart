// What a session change is, and who it reaches.
//
// Signing out used to blank the session in `AppState` and nothing else: the
// name went null, the id went null, the role fell back to cashier. Every
// screen kept whatever it had already read, and nothing told them the reader
// had changed. The router disposed the shell on a normal sign-out, so the bug
// hid — until a shell outlived a session, and the next person at the till was
// reading the previous person's dashboard.
//
// Two properties are pinned here:
//
//   * `AppState.sessionGeneration` — the one signal that a session began or
//     ended, and the thing every data-holding screen watches.
//   * An unresolved cashier sees NOTHING. `staffIdForCashier`'s null means "I
//     could not work out who this is", and the null a scoped query accepts
//     means "every row in the shop". Handing one straight to the other is how
//     a cashier ends up reading the whole shop's takings as their own.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/analytics.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/roles.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_workspace_key': 'legacy',
      'onboarding_completed_legacy': true,
    });
  });

  late DatabaseHelper db;
  late AppState state;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    await db.createOwner(Owner(
      id: 1,
      name: 'Test Owner',
      pinHash: 'test_pin_hash',
      email: 'owner@example.com',
      shopName: 'Test Shop',
      createdAt: DateTime.now().toIso8601String(),
    ));
    state = AppState();
    await state.loadOwner();
  });

  tearDown(() {
    DatabaseHelper.resetForTests();
  });

  group('session generation', () {
    test('a fresh session starts at zero', () {
      expect(state.sessionGeneration, 0);
    });

    test('notifications that are not a session change do not move it', () {
      // `refresh()` and the identity flags are the changes that fire most
      // often, and a counter that moved for them would reload every screen in
      // the shell on every theme toggle and banner dismissal.
      state.refresh();
      state.markIdentityLinked();
      expect(state.sessionGeneration, 0);
    });

    test('every sign-in advances it', () {
      state.signInAsOwner();
      expect(state.sessionGeneration, 1);

      state.signInAsStaff(Staff(id: 7, name: 'Amina', pinHash: 'x'));
      expect(state.sessionGeneration, 2);

      state.signIn('Restored', asOwner: false);
      expect(state.sessionGeneration, 3);
    });

    test('every sign-out advances it', () {
      state.signInAsStaff(Staff(id: 7, name: 'Amina', pinHash: 'x'));
      final int before = state.sessionGeneration;

      state.signOut();

      // Clearing the session is not a no-op for the screens: it is the event
      // they must react to, precisely because the data they hold was read for
      // the session that just ended.
      expect(state.sessionGeneration, greaterThan(before));
    });

    test('signing out and back in as the SAME person is still a new session',
        () {
      // A boolean would be wrong here: the flag would read "signed in" before
      // the sign-out and "signed in" after the sign-in, so a screen watching
      // it would keep the first session's figures. The counter cannot.
      final Staff amina = Staff(id: 7, name: 'Amina', pinHash: 'x');
      state.signInAsStaff(amina);
      expect(state.sessionGeneration, 1);

      state.signOut();
      state.signInAsStaff(amina);

      expect(state.sessionGeneration, 3);
      // And the session that follows a sign-out is least-privileged until a
      // real one arrives, so a screen reading it mid-transition sees a cashier
      // with nothing, never the person who just left.
      expect(state.isSignedIn, isTrue);
      expect(state.currentStaffId, 7);
    });

    test('a listener is told the session changed, with the new value readable',
        () {
      int? notified;
      state.addListener(() => notified = state.sessionGeneration);

      state.signInAsOwner();

      expect(notified, 1);
      // The value is on the notifier itself, so a screen that missed the
      // callback (an unmounted widget, a deferred one) still reads the truth.
      expect(state.sessionGeneration, notified);
    });
  });

  group('a cashier who cannot be resolved', () {
    test('an unknown or ambiguous name scopes to nobody, not to everybody', () {
      final roster = <Staff>[
        Staff(id: 7, name: 'Amina', pinHash: 'x'),
        Staff(id: 8, name: 'Joseph', pinHash: 'x'),
      ];

      // Resolved: the one id that matches, and only that one.
      expect(staffIdForCashierOrNobody(roster, 'Amina'), 7);
      // Unresolved in either direction — zero matches or two — reads as an id
      // no row has, which is the FAIL-CLOSED answer.
      expect(staffIdForCashierOrNobody(roster, 'Nobody'), kUnmatchedStaffId);
      expect(staffIdForCashierOrNobody(roster, null), kUnmatchedStaffId);
      expect(staffIdForCashierOrNobody(roster, '  '), kUnmatchedStaffId);
      expect(
        staffIdForCashierOrNobody(<Staff>[
          Staff(id: 1, name: 'Amina', pinHash: 'x'),
          Staff(id: 2, name: 'Amina', pinHash: 'x'),
        ], 'Amina'),
        kUnmatchedStaffId,
      );
    });

    test('an unresolved id is never null, because null means no filter', () {
      // The translation exists precisely so this cannot happen: the query
      // layer reads `staff_id = NULL` as "every row in the shop", so a cashier
      // with an unresolvable name would otherwise be shown the whole shop's
      // takings as their own.
      final int scoped = staffIdForCashierOrNobody(<Staff>[], 'Amina');
      expect(scoped, isNotNull);
      expect(scoped, lessThan(0));
    });

    test('the session’s own id comes before any name lookup', () {
      final roster = <Staff>[
        Staff(id: 7, name: 'Amina', pinHash: 'x'),
        Staff(id: 8, name: 'Joseph', pinHash: 'x'),
      ];

      // `signInAsStaff` carries the local staff row's id, which is the id the
      // ledger's `staff_id` holds — so it wins outright, even when the name
      // would resolve to somebody else.
      expect(
        ownStaffId(sessionStaffId: 7, staff: roster, staffName: 'Joseph'),
        7,
      );

      // A restored session has a name and no id, so the name is all there is.
      expect(
        ownStaffId(sessionStaffId: null, staff: roster, staffName: 'Amina'),
        7,
      );

      // And a session that resolves to nothing still scopes to nobody. This is
      // the dashboard's cashier bug in one line: the old code handed the
      // lookup's null straight to the query, where it meant "the whole shop".
      expect(
        ownStaffId(sessionStaffId: null, staff: roster, staffName: 'Nobody'),
        kUnmatchedStaffId,
      );
      expect(
        ownStaffId(sessionStaffId: null, staff: <Staff>[], staffName: 'Amina'),
        kUnmatchedStaffId,
      );
    });

    test('AppState never resolves a cashier to an unfiltered query', () {
      // A cashier with no roster row — a restored backup, a backend sign-in
      // that carried no local id — still scopes to nobody.
      state.signIn('Ghost', asOwner: false);
      expect(state.analyticsStaffId, kUnmatchedStaffId);

      state.signInAsStaff(Staff(id: 7, name: 'Amina', pinHash: 'x'));
      expect(state.analyticsStaffId, 7);

      // A manager and an owner see the shop: null is the correct answer there
      // and only there.
      state.signInAsStaff(
          Staff(id: 9, name: 'Mary', pinHash: 'x', role: 'manager'));
      expect(state.analyticsStaffId, isNull);

      state.signInAsOwner();
      expect(state.analyticsStaffId, isNull);
    });

    test('the ledger agrees: nobody scoped to -1 sees nothing', () async {
      final amina =
          await db.addStaff(Staff(id: null, name: 'Amina', pinHash: 'x'));
      final joseph =
          await db.addStaff(Staff(id: null, name: 'Joseph', pinHash: 'x'));
      await (await db.database).insert('sales', <String, Object?>{
        'staff_name': 'Amina',
        'staff_id': amina,
        'total': 1500,
        'profit': 500,
        'payment_method': 'cash',
        'created_at': DateTime.now().toIso8601String(),
        'payment_verified': 1,
      });
      await (await db.database).insert('sales', <String, Object?>{
        'staff_name': 'Joseph',
        'staff_id': joseph,
        'total': 2500,
        'profit': 800,
        'payment_method': 'cash',
        'created_at': DateTime.now().toIso8601String(),
        'payment_verified': 1,
      });

      final shop = await db.salesTotalsFor();
      final unmatched = await db.salesTotalsFor(staffId: kUnmatchedStaffId);

      // The shop has takings, so this is a real over-report risk, not a test
      // of an empty ledger.
      expect(shop.hasSales, isTrue);
      expect(shop.totalMinor, 4000);
      // And the unresolved cashier sees none of them.
      expect(unmatched.hasSales, isFalse);
      expect(unmatched.totalMinor, 0);
      expect(unmatched.transactions, 0);
    });
  });

  group('the role a session resolves to', () {
    test('an owner session is an admin, whatever came before it', () {
      // The reported symptom: a dashboard that read as "cashier" after the
      // owner had signed back in. The state below is what the greeting and
      // every capability are derived from, so it has to be right at sign-in
      // rather than whenever a screen happens to reload.
      state.signInAsStaff(
          Staff(id: 7, name: 'Amina', pinHash: 'x', role: 'cashier'));
      expect(state.isAdmin, isFalse);

      state.signOut();
      state.signInAsOwner();

      expect(state.isAdmin, isTrue);
      expect(state.currentRole, ShopRole.admin.wire);
      expect(state.seesAllSales, isTrue);
      expect(state.canManageStock, isTrue);
    });

    test('a manager session is a manager, not an admin', () {
      // The shell's app bar labels a manager with their own name and hides
      // Settings, so the role must not collapse to either neighbour.
      state.signInAsStaff(
          Staff(id: 9, name: 'Mary', pinHash: 'x', role: 'manager'));
      expect(state.isAdmin, isFalse);
      expect(state.canManageStock, isTrue);
      expect(state.seesAllSales, isTrue);
    });

    test('a signed-out session is a cashier with nothing', () {
      state.signInAsOwner();
      state.signOut();
      // Least-privileged while the router swaps the screen, so nothing that
      // reads the role in that frame sees admin rights.
      expect(state.role, ShopRole.cashier);
      expect(state.currentStaffName, isNull);
      expect(state.currentStaffId, isNull);
      expect(state.isAdmin, isFalse);
      expect(state.canManageStock, isFalse);
    });
  });
}
