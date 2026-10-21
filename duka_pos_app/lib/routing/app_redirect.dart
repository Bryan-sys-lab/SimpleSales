import 'routes.dart';
import '../services/app_stage.dart';
import 'app_stage_controller.dart';

/// The app's only navigation guard.
///
/// PURE: it reads an [AppStageSnapshot] and a location, and returns a location
/// or `null`. No I/O, no `context.go`, no reading a provider, no awaiting. That
/// is not stylistic — `redirect` runs on every navigation and can run repeatedly,
/// so a guard with a side effect is a guard that fires the side effect twice.
///
/// Three rules, in this order:
///
/// 1. **Boot first.** A splash, a broken database, or no session outranks
///    everything. A signed-out user reaching a deep link must land on the PIN
///    pad, not on a dashboard that failed to load its data.
/// 2. **Then the session.** Signed in and sitting on a door screen goes home;
///    signed out and sitting anywhere else goes to the door.
/// 3. **Then the role.** A cashier who reaches `/settings` by a stale deep link
///    goes to the dashboard. The tab bar already hides it, but the URL does not.
///
/// Loop-freedom: every branch either returns `null` (allow) or returns a
/// location whose own stage check will return `null` on the next pass. The
/// `location == canonical` early return makes the common case explicit rather
/// than relying on that argument holding.
String? appRedirect({
  required AppStageSnapshot snapshot,
  required String location,
}) {
  // 1. The boot gate. Nothing else is evaluated until the local store is
  //    readable, because every later answer depends on it.
  final String? gate = switch (snapshot.stage) {
    AppStage.loading => Routes.splash,
    AppStage.databaseFailed => Routes.recovery,
    _ => null,
  };
  if (gate != null) {
    if (location == gate) return null;
    return gate;
  }

  final bool signedIn = snapshot.stage == AppStage.ready ||
      snapshot.stage == AppStage.onboarding ||
      snapshot.stage == AppStage.permissions;

  // 2. The session door.
  if (!signedIn) {
    // Allow sign-in and staff login as valid unauthenticated routes.
    if (location == Routes.login || location == Routes.staffLogin) return null;

    final String door = switch (snapshot.stage) {
      AppStage.chooser => Routes.welcome,
      AppStage.signingIn =>
        Routes.welcome, // Sign-out lands on chooser, not PIN pad
      AppStage.settingUp => Routes.setup,
      AppStage.onboarding ||
      AppStage.permissions ||
      AppStage.ready =>
        Routes.dashboard,
      _ => Routes.welcome,
    };
    return location == door ? null : door;
  }

  // 3. Signed in: any door screen is stale.
  const Set<String> doors = <String>{
    Routes.splash,
    Routes.recovery,
    Routes.welcome,
    Routes.login,
    Routes.setup,
  };
  if (doors.contains(location)) return Routes.dashboard;

  // A finished walkthrough is stale the moment the stage flips to ready.
  if (snapshot.stage == AppStage.ready && location == Routes.onboarding) {
    return Routes.dashboard;
  }

  // So is a finished permissions step.
  if (snapshot.stage == AppStage.ready && location == Routes.permissions) {
    return Routes.dashboard;
  }

  // 4. The walkthrough is guidance, not a gate — but an admin who has not seen
  //    it is the only one who should be held on it.
  if (snapshot.stage == AppStage.onboarding) {
    if (!snapshot.isAdmin) return Routes.dashboard;
    return location == Routes.onboarding ? null : Routes.onboarding;
  }

  // 5. The permissions step — guidance, not a gate, and admin-only like the
  //    walkthrough it follows.
  //
  //    It is never allowed to strand somebody: a cashier goes straight to the
  //    dashboard, and the step's own "Continue" is always there, so the only
  //    way past it is through it.
  if (snapshot.stage == AppStage.permissions) {
    if (!snapshot.isAdmin) return Routes.dashboard;
    return location == Routes.permissions ? null : Routes.permissions;
  }

  // 6. Role gating on the branch itself.
  // The shift sub-route is explicitly NOT in this set: it reconciles the
  // signed-in person's own till and is reachable from the dashboard's "Open
  // Shift" card for cashiers too. Only the full-shop branches are gated.
  final bool stockBranch = location.startsWith(Routes.inventory) ||
      (location.startsWith(Routes.analytics) && location != Routes.shift) ||
      location == Routes.reports;
  if (stockBranch && !snapshot.canManageStock) return Routes.dashboard;

  if (location.startsWith(Routes.settings) && !snapshot.isAdmin) {
    return Routes.dashboard;
  }

  return null;
}
