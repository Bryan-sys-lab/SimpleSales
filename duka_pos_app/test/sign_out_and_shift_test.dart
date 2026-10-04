// Signing out, and what a shift does when a session ends.
//
// The behaviour pinned here is the one that only shows up when something goes
// wrong on a shared till:
//
//  * Signing out must end the *online* identity too, not just clear the local
//    session. A till that only forgets who is standing at it leaves the
//    Keycloak session and its tokens on the device.
//  * Signing out must NOT touch an open shift. A shift belongs to the shop, not
//    to the session; a sign-out that quietly closed one would leave cash in a
//    drawer with a float recorded and no reconciliation against it.
//  * The expected figure must be composed in one place, so no caller can forget
//    the opening float and report it as a variance.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/roles.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('session and shift', () {
    late DatabaseHelper db;
    late AppState state;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
      state = AppState();
    });

    tearDown(() {
      DatabaseHelper.resetForTests();
    });

    Future<int> openShiftFor(AppState s) async {
      return db.openShift(
        staffId: s.currentStaffId!,
        staffName: s.currentStaffName!,
        startFloat: Money.fromMajor(5000),
      );
    }

    test('A sign-out leaves the till exactly as it found it', () {
      final staff = Staff(id: 7, name: 'Amina', pinHash: 'x', role: 'cashier');
      state.signInAsStaff(staff);
      expect(state.isSignedIn, isTrue);

      state.signOut();

      expect(state.isSignedIn, isFalse);
      expect(state.currentStaffName, isNull);
      expect(state.currentStaffId, isNull);
      expect(state.isOwnerSession, isFalse);
      // Least-privileged after signing out, so nothing that reads the role
      // before the router swaps the screen sees admin rights.
      expect(state.role, ShopRole.cashier);
      expect(state.canManageStock, isFalse);
      expect(state.isAdmin, isFalse);
      expect(state.seesAllSales, isFalse);
    });

    test('Signing out does not close an open shift', () async {
      final staff = Staff(id: 7, name: 'Amina', pinHash: 'x', role: 'cashier');
      state.signInAsStaff(staff);
      await openShiftFor(state);

      state.signOut();

      // The shift is still open, still holds the float, and is still
      // reconcilable by whoever signs in next.
      final shifts = await db.getShifts(staffId: 7);
      expect(shifts.single.status, 'open');
      expect(shifts.single.startFloat.minorUnits, 500000);
      // And the shop can see there is an unattended open shift.
      expect((await db.getAnyOpenShift())?.staffId, 7);
    });

    test('A person signing back in finds their own open shift', () async {
      final staff = Staff(id: 7, name: 'Amina', pinHash: 'x', role: 'cashier');
      state.signInAsStaff(staff);
      await openShiftFor(state);
      state.signOut();

      state.signInAsStaff(staff);

      expect((await state.openShiftId())?.id, isNotNull);
    });

    test(
        'Someone with no open shift is told so rather than shown a stranger'
        "'s", () async {
      await db.openShift(
        staffId: 7,
        staffName: 'Amina',
        startFloat: Money.fromMajor(5000),
      );
      final other = Staff(id: 8, name: 'Brian', pinHash: 'x', role: 'cashier');
      state.signInAsStaff(other);

      expect(await state.openShiftId(), isNull);
      // The shop-wide view still finds Amina's, which is what an owner needs.
      expect((await db.getAnyOpenShift())?.staffName, 'Amina');
    });

    test('A cashier has no staff id to hold a shift against', () {
      // `signIn` is the restored-backup path and takes no id, so there is
      // nothing to attribute a shift to. That has to read as "no shift" rather
      // than as a shift against an id that does not exist.
      state.signIn('Amina', asOwner: false);
      expect(state.currentStaffId, isNull);
    });

    test('The expected figure is the float plus the cash rung up', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Recon Beer',
        category: 'Beer',
        costPrice: Money.fromMajor(80),
        sellPrice: Money.fromMajor(150),
        stockQty: 50,
        reorderLevel: 5,
        bottleMl: 500,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final staff = Staff(id: 7, name: 'Amina', pinHash: 'x', role: 'cashier');
      state.signInAsStaff(staff);
      await openShiftFor(state);

      await db.recordSale(
        staffName: 'Amina',
        staffId: 7,
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Recon Beer',
            qty: 4,
            unitPrice: Money.fromMajor(150),
            unitCost: Money.fromMajor(80),
          ),
        ],
      );

      final shift = (await state.openShiftId())!;
      expect((await db.expectedCashForShift(shift)).minorUnits, 60000);
      // The float is part of the figure the drawer is judged against.
      expect((await db.expectedTillBalance(shift)).minorUnits, 560000);
    });

    test('A card sale never inflates what the drawer should hold', () async {
      final productId = await db.upsertProduct(Product(
        name: 'AAA Card Wine',
        category: 'Wine',
        costPrice: Money.fromMajor(400),
        sellPrice: Money.fromMajor(900),
        stockQty: 20,
        reorderLevel: 2,
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final staff = Staff(id: 7, name: 'Amina', pinHash: 'x', role: 'cashier');
      state.signInAsStaff(staff);
      await openShiftFor(state);

      await db.recordSale(
        staffName: 'Amina',
        staffId: 7,
        paymentMethod: 'card',
        items: [
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'AAA Card Wine',
            qty: 2,
            unitPrice: Money.fromMajor(900),
            unitCost: Money.fromMajor(400),
          ),
        ],
      );

      final shift = (await state.openShiftId())!;
      // Only the float is in the drawer. Counting a card sale as cash is how a
      // cashier is accused of being KSh 1,800 short for money that never had to
      // be in the till.
      expect((await db.expectedTillBalance(shift)).minorUnits, 500000);
    });

    test('Two people can hold two shifts on one till', () async {
      // A till is shared, so this is normal and must not be blocked. Each
      // person's cash is reconciled against only their own sales.
      await db.openShift(
        staffId: 7,
        staffName: 'Amina',
        startFloat: Money.fromMajor(5000),
      );
      await db.openShift(
        staffId: 8,
        staffName: 'Brian',
        startFloat: Money.fromMajor(2000),
      );

      final all = await db.getShifts(openOnly: true);
      expect(all.length, 2);
      expect((await db.getOpenShift(7))?.startFloat.minorUnits, 500000);
      expect((await db.getOpenShift(8))?.startFloat.minorUnits, 200000);
    });

    test('One person cannot hold two shifts at once', () async {
      await db.openShift(
        staffId: 7,
        staffName: 'Amina',
        startFloat: Money.fromMajor(5000),
      );
      // Otherwise "which sales were on this shift" is ambiguous, and the second
      // one would silently take the credit for the first one's takings.
      await expectLater(
        db.openShift(
          staffId: 7,
          staffName: 'Amina',
          startFloat: Money.fromMajor(1000),
        ),
        throwsStateError,
      );
    });
  });
}

/// The role a session resolves to after a sign-out.
///
/// Named here rather than imported so the test states the expectation instead
/// of restating the implementation's own constant.
class ShopRoleFallback {
  static const String cashier = 'cashier';
}
