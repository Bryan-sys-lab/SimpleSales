import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../db/database_helper.dart';
import 'oidc_service.dart';
import 'roles.dart';
import 'workspace_service.dart';
import 'backend_service.dart';

/// Holds who is currently signed in on this till. Deliberately not persisted
/// across app restarts — a shared shop device should always come back to
/// the lock screen, the same way a real POS terminal does, so a sale is never
/// attributed to whoever last used the phone rather than whoever is holding
/// it now.
class AppState extends ChangeNotifier {
  Owner? owner;
  String? currentStaffName;
  bool isOwnerSession = false;
  String workspaceKey = WorkspaceService.legacyKey;

  /// The signed-in person's role.
  ///
  /// Stored as the enum rather than a raw string. Every capability below is
  /// derived from it, so a role that arrives from the database, from the owner
  /// row, or from a future sign-in path cannot accidentally disagree with what
  /// the screens decide to show.
  ShopRole _role = ShopRole.cashier;

  /// The staff row behind the current session.
  ///
  /// Needed for analytics and ledger attribution: role-based scoping filters on
  /// `staff_id`, not on a display name, so the id has to survive sign-in. An
  /// owner session has no staff row and reports everything.
  int? currentStaffId;

  /// True when the local shop exists but has not yet been linked to an
  /// online identity. Selling stays fully available offline; this only drives the
  /// "verify online" reminder in Settings.
  bool identityLinkPending = false;

  ShopRole get role => _role;

  /// The role as stored, for the one call site that writes it back to a row.
  String get currentRole => _role.wire;

  bool _disposed = false;

  /// Whether this session has been torn down.
  ///
  /// Exists because [loadOwner] awaits real I/O and its caller — the boot gate —
  /// can be disposed while those awaits are in flight. `notifyListeners()` on a
  /// disposed `ChangeNotifier` asserts in debug and silently does nothing in
  /// release, so without this the symptom on a device is a router that never
  /// resolves and a blank screen with no error anywhere.
  bool get isDisposed => _disposed;

  Future<void> loadOwner() async {
    workspaceKey = await WorkspaceService.activeWorkspaceKey();
    await DatabaseHelper.instance.initializeWorkspace(workspaceKey);
    owner = await DatabaseHelper.instance.getOwner();
    if (_disposed) return;
    identityLinkPending =
        owner != null && (await BackendService.tenantId) == null;
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void markIdentityLinked() {
    identityLinkPending = false;
    notifyListeners();
  }

  /// Moves to another shop on this device.
  ///
  /// The session is dropped *after* the database has been repointed, not
  /// before. Sign-out notifies listeners, so signing out first made the router
  /// rebuild once with the new shop's name and the old shop still loaded — a
  /// PIN pad for the shop the user was just leaving, for one frame. Reading
  /// after writing means the intermediate state is a coherent "signed out of
  /// the shop you are now in", which is the only state that was ever true.
  Future<void> switchWorkspace(String key) async {
    await WorkspaceService.setActiveWorkspace(key);
    currentStaffName = null;
    currentStaffId = null;
    isOwnerSession = false;
    _role = ShopRole.cashier;
    await loadOwner();
  }

  /// Signs in as the shop owner.
  Future<void> signInAsOwner({int? staffId}) async {
    final shop = owner;
    if (shop == null) return;
    currentStaffName = shop.name;
    currentStaffId = staffId;
    isOwnerSession = true;
    _role = ShopRole.admin;
    notifyListeners();
  }

  /// Signs in as a member of staff.
  void signInAsStaff(Staff staff) {
    currentStaffName = staff.name;
    currentStaffId = staff.id;
    isOwnerSession = false;
    // A name that is not a known role resolves to cashier rather than to
    // manager. See [ShopRole.parse].
    _role = ShopRole.parse(staff.role);
    notifyListeners();
  }

  /// Signs in using a raw role string.
  ///
  /// Kept for call sites that hold only a name and a role, such as a restored
  /// backup. Resolves through [ShopRole.parse], so an unexpected value is
  /// least-privileged.
  void signIn(String name, {required bool asOwner, String role = 'cashier'}) {
    currentStaffName = name;
    currentStaffId = null;
    isOwnerSession = asOwner;
    _role = asOwner ? ShopRole.admin : ShopRole.parse(role);
    notifyListeners();
  }

  /// Ends the local session on this till.
  ///
  /// Synchronous and immediate, because the caller is a UI callback and the
  /// person standing at the till needs the PIN pad now — waiting on a network
  /// round trip to end a *local* session would be a worse answer than a good
  /// one delivered late.
  ///
  /// Online sign-out is therefore started but not awaited: [tearDownOnlineSession]
  /// clears the stored OIDC tokens and ends the online session. A till
  /// that only ever works offline has nothing to tear down and this is a no-op.
  ///
  /// Deliberately does **not** touch the open shift or the till's float. A shift
  /// belongs to the shop, not to the session: ending a session must not silently
  /// close a shift with money still in the drawer. [openShiftId] is what lets a
  /// caller warn about that case before it happens.
  void signOut() {
    currentStaffName = null;
    currentStaffId = null;
    isOwnerSession = false;
    _role = ShopRole.cashier;
    notifyListeners();
    unawaited(tearDownOnlineSession());
  }

  /// Ends the online session and forgets the tokens.
  ///
  /// Split out from [signOut] so the network teardown can also be awaited
  /// deliberately — by a "sign out everywhere" path, or a test — without making
  /// the everyday local sign-out block on the network.
  ///
  /// Never throws. The local session is already gone by the time this runs, and a
  /// failed end-session must not leave the app wedged signed-in-looking or
  /// surface an error to someone who has already walked away from the till.
  Future<void> tearDownOnlineSession() async {
    try {
      await OidcService.logout();
    } catch (_) {
      // Intentionally swallowed — see above.
    }
  }

  /// The open shift belonging to the signed-in person, or null.
  ///
  /// Null when nobody is signed in, or when the signed-in person is an owner with
  /// no roster row — an owner cannot hold a shift until they are on the roster,
  /// which the shift screen offers to arrange.
  ///
  /// Read by the sign-out flow so it can say "you have an open shift" *before*
  /// ending the session, which is the only moment the warning is actionable.
  Future<Shift?> openShiftId() async {
    final id = currentStaffId;
    if (id == null) return null;
    return DatabaseHelper.instance.getOpenShift(id);
  }

  bool get isSignedIn => currentStaffName != null;

  /// Whether the signed-in person holds admin rights.
  ///
  /// True for the owner and for any staff account created with the admin role,
  /// which is the decision that was made: a shop can now delegate full admin
  /// rights without handing over the owner account and its PIN.
  bool get isAdmin => _role.canAdminister;

  /// Inventory, stock and price edits.
  bool get canManageStock => _role.canManageStock;

  /// The whole shop's numbers rather than only this person's own.
  bool get seesAllSales => _role.seesAllSales;

  /// Removing a product from the catalogue outright.
  bool get canDeleteProducts => _role.canDeleteProducts;

  /// Registering this shop's KRA device.
  bool get canRegisterTaxIdentity => _role.canRegisterTaxIdentity;

  /// The staff id to scope analytics by, or null when every row is in scope.
  ///
  /// Null for an owner session and for a manager, because both see the shop.
  /// A cashier gets their own id, and `null` is never used to mean "unknown" —
  /// a cashier's queries must be narrow, so an unresolved cashier scopes to
  /// nobody rather than to everybody.
  int? get analyticsStaffId => seesAllSales ? null : (currentStaffId ?? -1);

  void refresh() => notifyListeners();
}
