import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../db/database_helper.dart';
import 'workspace_service.dart';
import 'backend_service.dart';

/// Holds who is currently signed in on this till. Deliberately not persisted
/// across app restarts — a shared shop device should always come back to the
/// lock screen, the same way a real POS terminal does, so a sale is never
/// attributed to whoever last used the phone rather than whoever is holding
/// it now.
class AppState extends ChangeNotifier {
  Owner? owner;
  String? currentStaffName;
  bool isOwnerSession = false;
  String currentRole = 'cashier';
  String workspaceKey = WorkspaceService.legacyKey;

  /// True when the local shop exists but has not yet been linked to a Keycloak
  /// identity. Selling stays fully available offline; this only drives the
  /// "verify online" reminder in Settings.
  bool identityLinkPending = false;

  Future<void> loadOwner() async {
    workspaceKey = await WorkspaceService.activeWorkspaceKey();
    await DatabaseHelper.instance.initializeWorkspace(workspaceKey);
    owner = await DatabaseHelper.instance.getOwner();
    identityLinkPending =
        owner != null && (await BackendService.tenantId) == null;
    notifyListeners();
  }

  void markIdentityLinked() {
    identityLinkPending = false;
    notifyListeners();
  }

  Future<void> switchWorkspace(String key) async {
    signOut();
    await WorkspaceService.setActiveWorkspace(key);
    await loadOwner();
  }

  void signIn(String name, {required bool asOwner, String role = 'cashier'}) {
    currentStaffName = name;
    isOwnerSession = asOwner;
    currentRole = asOwner ? 'admin' : role;
    notifyListeners();
  }

  void signOut() {
    currentStaffName = null;
    isOwnerSession = false;
    currentRole = 'cashier';
    notifyListeners();
  }

  bool get isSignedIn => currentStaffName != null;

  /// True only for the shop admin, i.e. the owner who set the till up. This is
  /// the gate on staff management and Settings; managers deliberately do not
  /// have it, so the owner stays the only person who can create or disable
  /// cashier accounts.
  bool get isAdmin => currentRole == 'admin';

  /// Managers get inventory and reports but never staff management. Checked as
  /// `currentRole != 'cashier'` at the call site rather than through a stored
  /// boolean so a new role cannot inherit manager rights by omission.
  bool get canManageStock => currentRole != 'cashier';

  void refresh() => notifyListeners();
}
