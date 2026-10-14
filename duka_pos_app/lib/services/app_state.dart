import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../db/database_helper.dart';
import 'analytics.dart';
import 'failure_recorder.dart';
import 'oidc_service.dart';
import 'roles.dart';
import 'staff_credential_cache.dart';
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

  /// True once the online identity has been *verified* — the emailed code was
  /// presented and the backend said so.
  ///
  /// Distinct from [identityLinkPending]: a linked-but-unverified shop is the
  /// one state that needs chasing, because verification is what turns on
  /// auto-backups, analytics and auto-update. Loaded from storage rather than
  /// derived, because the backend is the authority on it and a phone that has
  /// just verified itself must not have to go online again to find that out.
  bool identityVerified = false;

  /// Preference key for this WORKSPACE's [identityVerified].
  ///
  /// Scoped by workspace key, not a single global key: a device can hold
  /// several shops, and one global preference meant shop B inherited shop A's
  /// verification — offering the auto-sync switch, switched on, for a shop that
  /// never presented an emailed code and holds no session.
  static String identityVerifiedKeyFor(String workspaceKey) =>
      'profile_email_verified@$workspaceKey';

  /// The single global key the flag used to live under.
  ///
  /// Read once, as a fallback, so a shop that verified before the flag was
  /// scoped keeps its state instead of being asked to verify again. Absent
  /// afterwards it has already been adopted.
  static const _legacyIdentityVerifiedKey = 'profile_email_verified';

  /// The last staff username that signed in on this till, persisted across
  /// restarts so the staff-login screen can prefill it.
  String? rememberedStaffUsername;

  /// The last staff id that signed in on this till, persisted across restarts
  /// so the credential cache can be keyed correctly.
  int? rememberedStaffId;

  /// Advances by one on every sign-in and every sign-out.
  ///
  /// The counter exists because a session is a *fact about the data a screen
  /// has already read*, and nothing else says so. The router swaps the shell
  /// out on a normal sign-out, which disposes every branch screen and so makes
  /// their snapshots die with the session — but that is a property the
  /// navigation HAPPENS to have, not one any screen can rely on: an idle
  /// timeout, a future overlay PIN pad, or a shell that survives a redirect
  /// all leave the screens alive holding the finished session's figures. A
  /// screen that watches this number reloads for whoever is standing at the
  /// till NOW, and — the part that matters — clears what it held for whoever
  /// was standing there before.
  ///
  /// A counter rather than a bool or a nullable name: two consecutive sessions
  /// belonging to the same person (sign out, sign back in) still change it, and
  /// an int cannot be half-set.
  int _sessionGeneration = 0;

  /// The current value. Watched by the shell screens through [sessionGeneration].
  int get sessionGeneration => _sessionGeneration;

  /// Marks the session as changed. Called beside every notification that
  /// alters who is signed in, because `notifyListeners` alone tells a listener
  /// THAT something changed and never WHAT.
  void _advanceSession() {
    _sessionGeneration++;
  }

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
    try {
      final prefs = await SharedPreferences.getInstance();
      final String key = identityVerifiedKeyFor(workspaceKey);
      var verified = prefs.getBool(key) ?? false;
      if (!verified) {
        // One-time adoption of the pre-scoping global flag. Only ever on the
        // shop that is loading, and only when that shop has nothing of its own
        // yet, so shop B still does not inherit shop A's verification.
        if (prefs.getBool(_legacyIdentityVerifiedKey) ?? false) {
          verified = true;
          await prefs.setBool(key, true);
        }
      }
      identityVerified = verified;
    } catch (_) {
      // SharedPreferences is unavailable in some test environments; an
      // unverified shop is the safe answer, and the settings banner will
      // simply offer the flow again.
      identityVerified = false;
    }
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

  /// Records that the emailed code was presented and accepted.
  ///
  /// Persisted, not derived from being logged in: the flag gates work the
  /// phone does on its own, and an app that forgot it had verified itself
  /// after a restart would quietly stop backing up.
  Future<void> markIdentityVerified() async {
    identityVerified = true;
    identityLinkPending = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(identityVerifiedKeyFor(workspaceKey), true);
    } catch (_) {
      // The in-memory flag still lets this session use the features; the
      // next start will offer verification again rather than lose anything.
    }
    notifyListeners();
  }

  Future<void> rememberStaff(Staff staff) async {
    rememberedStaffUsername = staff.username ?? staff.name;
    rememberedStaffId = staff.id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'remembered_staff_username', rememberedStaffUsername!);
      if (staff.id != null) {
        await prefs.setInt('remembered_staff_id', staff.id!);
      }
    } catch (_) {
      // SharedPreferences is unavailable in some test environments; the
      // in-memory fields above are enough for the app to function.
    }
    notifyListeners();
  }

  Future<void> loadRememberedStaff() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      rememberedStaffUsername = prefs.getString('remembered_staff_username');
      rememberedStaffId = prefs.getInt('remembered_staff_id');
    } catch (_) {
      // SharedPreferences is unavailable in some test environments; leave
      // the in-memory fields null.
    }
    notifyListeners();
  }

  Future<void> clearRememberedStaff() async {
    rememberedStaffUsername = null;
    rememberedStaffId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('remembered_staff_username');
      await prefs.remove('remembered_staff_id');
    } catch (_) {
      // SharedPreferences is unavailable in some test environments; the
      // in-memory fields above are enough.
    }
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
    _advanceSession();
    unawaited(clearRememberedStaff());
    // Tear down the previous shop's online identity too. Like signOut, this
    // must not block the workspace switch — the tokens are cleared in the
    // background and the local session is already gone.
    unawaited(tearDownOnlineSession());
    await loadOwner();
  }

  /// Signs in as the shop owner.
  void signInAsOwner({int? staffId}) {
    final shop = owner;
    if (shop == null) return;
    currentStaffName = shop.name;
    currentStaffId = staffId;
    isOwnerSession = true;
    _role = ShopRole.admin;
    _advanceSession();
    failureRecorder.context.actorName = shop.name;
    unawaited(clearRememberedStaff());
    notifyListeners();
  }

  /// Signs in as a member of staff.
  void signInAsStaff(Staff staff) {
    currentStaffName = staff.name;
    currentStaffId = staff.id;
    isOwnerSession = false;
    failureRecorder.context.actorName = staff.name;
    // A name that is not a known role resolves to cashier rather than to
    // manager. See [ShopRole.parse].
    _role = ShopRole.parse(staff.role);
    _advanceSession();
    unawaited(rememberStaff(staff));
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
    _advanceSession();
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
    _advanceSession();
    unawaited(clearRememberedStaff());
    notifyListeners();
    // The offline staff credential cache goes too.
    //
    // It holds a PBKDF2 hash of every staff PIN plus each username in the
    // clear, and `login_screen` verifies against it as a fallback after
    // `AuthService.verifyPin` fails. Leaving it populated means the next person
    // at the till can sign in as whoever was here before, which is precisely
    // what ending a session is supposed to stop.
    //
    // Its own doc has always claimed "cleared on sign-out"; nothing did it, and
    // the account-deletion erasure had to learn the cache existed the hard way.
    unawaited(StaffCredentialCache.clearAll());
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
  int? get analyticsStaffId =>
      seesAllSales ? null : (currentStaffId ?? kUnmatchedStaffId);

  void refresh() => notifyListeners();
}
