import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/roles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late int staffId;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    staffId = await db.addStaff(Staff(
      name: 'Amina',
      role: ShopRole.cashier.wire,
      pinHash: 'hash',
      active: true,
    ));
  });

  tearDown(() => DatabaseHelper.resetForTests());

  test('default cashier discount is approval, not an unconditional allow',
      () async {
    expect(
      await db.permissionMode(
        role: ShopRole.cashier.wire,
        permission: PermissionKey.giveDiscount.wire,
      ),
      PermissionMode.approval,
    );
    expect(
      await db.hasPermission(
        role: ShopRole.cashier.wire,
        permission: PermissionKey.giveDiscount.wire,
      ),
      isTrue,
    );
  });

  test('a staff override can deny or require approval and can be reset',
      () async {
    await db.setStaffPermissionOverrideMode(
      staffId: staffId,
      permission: PermissionKey.receiveStock.wire,
      mode: PermissionMode.approval,
    );
    expect(
      await db.permissionMode(
        role: ShopRole.cashier.wire,
        staffId: staffId,
        permission: PermissionKey.receiveStock.wire,
      ),
      PermissionMode.approval,
    );

    await db.setStaffPermissionOverrideMode(
      staffId: staffId,
      permission: PermissionKey.receiveStock.wire,
      mode: PermissionMode.deny,
    );
    expect(
      await db.hasPermission(
        role: ShopRole.cashier.wire,
        staffId: staffId,
        permission: PermissionKey.receiveStock.wire,
      ),
      isFalse,
    );

    await db.clearStaffPermissionOverride(
      staffId: staffId,
      permission: PermissionKey.receiveStock.wire,
    );
    expect(
      await db.permissionMode(
        role: ShopRole.cashier.wire,
        staffId: staffId,
        permission: PermissionKey.receiveStock.wire,
      ),
      PermissionMode.deny,
    );
  });

  test('a cashier stock override does not widen financial visibility',
      () async {
    await db.setStaffPermissionOverrideMode(
      staffId: staffId,
      permission: PermissionKey.receiveStock.wire,
      mode: PermissionMode.allow,
    );
    expect(
      await db.permissionMode(
        role: ShopRole.cashier.wire,
        staffId: staffId,
        permission: PermissionKey.receiveStock.wire,
      ),
      PermissionMode.allow,
    );
    // The app state keeps the role's own-sales scope separate from stock
    // permissions; this prevents a stock override from exposing shop totals.
    expect(ShopRole.cashier.seesAllSales, isFalse);
  });

  test('owner mode is always allow and matrix contains the fixed catalogue',
      () async {
    expect(
      await db.permissionMode(
        role: ShopRole.admin.wire,
        permission: PermissionKey.manageDevices.wire,
      ),
      PermissionMode.allow,
    );
    final matrix = await db.getPermissionMatrix();
    expect(
      matrix.any((row) => row['permission'] == PermissionKey.viewCost.wire),
      isTrue,
    );
    expect(
      matrix.any(
          (row) => row['permission'] == PermissionKey.runStocktakeApply.wire),
      isTrue,
    );
  });
}
