/// The roles a person can sign in with, in one place.
///
/// Roles were bare strings compared with `==` across the app, which meant:
///
/// * nothing validated them, so a typo in the database silently produced a
///   person who could see everything;
/// * `canManageStock` was written as `currentRole != 'cashier'`, which grants
///   inventory *and* reports to any unrecognised value — fail-open on the
///   permission check, which is the wrong direction for every check except an
///   explicit "is not a cashier".
///
/// A single enum with an explicit capability set makes a new role require a
/// conscious decision about what it can do, instead of inheriting admin rights
/// by being spelled differently.
enum ShopRole {
  /// The account holder. Exactly one per shop, created during setup.
  admin('admin', 'Admin'),

  /// Everything except staff management and shop administration.
  manager('manager', 'Manager'),

  /// Sell and their own numbers. Nothing else.
  cashier('cashier', 'Cashier');

  const ShopRole(this.wire, this.label);

  /// The value stored in `staff.role`. A const class rather than an enum because
  /// the column is plain TEXT with no default, and the wire value must survive
  /// a rename of the Dart enum member.
  final String wire;

  /// What the sign-in screen and staff editor show.
  final String label;

  /// Whether this role may see the whole shop's numbers, not just their own.
  bool get seesAllSales => this != ShopRole.cashier;

  /// Whether this role may edit the catalogue, adjust stock and adjust prices.
  bool get canManageStock => this != ShopRole.cashier;

  /// Whether this role may see the analytics screen.
  bool get canSeeAnalytics => this != ShopRole.cashier;

  /// Whether this role may add, rename and remove staff, pair a printer, change
  /// the tax settings, back up or restore, and manage linked shops.
  ///
  /// This is the single gate for the Settings tab. A manager is documented as
  /// "Everything except staff management and shop administration," so only the
  /// owner may reach Settings. Restricting this to [admin] also keeps the shell
  /// app-bar from mislabeling a manager as "Owner" via `isOwner: state.isAdmin`.
  bool get canAdminister => this == ShopRole.admin;

  /// Whether this role may delete a product outright rather than deactivate it.
  ///
  /// Manager-only-on-purpose but false by construction: stock and price edits
  /// are day-to-day management, removing a product from the catalogue is not.
  bool get canDeleteProducts => this == ShopRole.admin;

  /// Whether this role may register a KRA device, which mints the signing keys
  /// every invoice from this shop is signed with.
  bool get canRegisterTaxIdentity => this == ShopRole.admin;

  /// Every role a shop may hand out.
  ///
  /// [admin] is excluded. The owner already holds it, and a second admin
  /// account is a deliberate act, not something offered in a dropdown next to
  /// 'cashier' where it can be picked by accident.
  static const List<ShopRole> assignable = [ShopRole.manager, ShopRole.cashier];

  /// Parses a stored role.
  ///
  /// An unrecognised value resolves to [cashier], the least-privileged role.
  /// That is the opposite of what `!= 'cashier'` did, and it is deliberate: a
  /// corrupted or future role string must not hand out management rights.
  static ShopRole parse(String? value) {
    final wire = (value ?? '').trim().toLowerCase();
    for (final role in ShopRole.values) {
      if (role.wire == wire) return role;
    }
    return ShopRole.cashier;
  }

  /// The owner of a shop. A shop has exactly one and it is not a staff row, so
  /// this is a distinct identity rather than a role value.
  static const ShopRole owner = ShopRole.admin;
}

/// Runtime capabilities that can be enabled per role or overridden per staff
/// member. Owners always retain every capability; the matrix only governs
/// manager and cashier sessions.
enum PermissionKey {
  viewProfit,
  processReturn,
  giveDiscount,
  recordExpense,
  receiveStock,
  adjustStock,
  stocktake,
  manageCustomers,
  sellOnCredit,
  openDrawerNoSale,
  exportData,
  manageSettings,
  viewReports,
  manageSuppliers,
  managePacks,
  viewCost,
  editPrice,
  voidOrCancel,
  manageStaff,
  manageTax,
  managePrinter,
  manageBackup,
  manageDevices,
  runStocktakeApply,
}

enum PermissionMode { allow, approval, deny }

extension PermissionKeyWire on PermissionKey {
  String get wire => switch (this) {
        PermissionKey.viewProfit => 'view_profit',
        PermissionKey.processReturn => 'process_return',
        PermissionKey.giveDiscount => 'give_discount',
        PermissionKey.recordExpense => 'record_expense',
        PermissionKey.receiveStock => 'receive_stock',
        PermissionKey.adjustStock => 'adjust_stock',
        PermissionKey.stocktake => 'stocktake',
        PermissionKey.manageCustomers => 'manage_customers',
        PermissionKey.sellOnCredit => 'sell_on_credit',
        PermissionKey.openDrawerNoSale => 'open_drawer_no_sale',
        PermissionKey.exportData => 'export_data',
        PermissionKey.manageSettings => 'manage_settings',
        PermissionKey.viewReports => 'view_reports',
        PermissionKey.manageSuppliers => 'manage_suppliers',
        PermissionKey.managePacks => 'manage_packs',
        PermissionKey.viewCost => 'view_cost',
        PermissionKey.editPrice => 'edit_price',
        PermissionKey.voidOrCancel => 'void_or_cancel',
        PermissionKey.manageStaff => 'manage_staff',
        PermissionKey.manageTax => 'manage_tax',
        PermissionKey.managePrinter => 'manage_printer',
        PermissionKey.manageBackup => 'manage_backup',
        PermissionKey.manageDevices => 'manage_devices',
        PermissionKey.runStocktakeApply => 'run_stocktake_apply',
      };

  String get label => wire.replaceAll('_', ' ');
}

const Map<String, Set<String>> defaultRolePermissions = {
  'manager': {
    'view_profit',
    'process_return',
    'give_discount',
    'record_expense',
    'receive_stock',
    'adjust_stock',
    'stocktake',
    'manage_customers',
    'sell_on_credit',
    'open_drawer_no_sale',
    'view_reports',
    'manage_suppliers',
    'manage_packs',
    'view_cost',
    'edit_price',
    'void_or_cancel',
    'run_stocktake_apply',
  },
  'cashier': {
    'process_return',
    'manage_customers',
  },
};

const Map<String, Set<String>> defaultApprovalPermissions = {
  'manager': <String>{},
  'cashier': <String>{'give_discount', 'record_expense', 'open_drawer_no_sale'},
};
