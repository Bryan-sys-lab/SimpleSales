import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/crash_log.dart';
import '../services/app_stage.dart';
import '../services/app_state.dart';
import '../services/auto_sync_service.dart';
import '../services/failure_recorder.dart';

/// The boot gate, as something the router can watch.
///
/// The old `RootRouter` was a `StatefulWidget` that decided which screen to show
/// with a `switch` — which meant a signed-out user could not be deep-linked to,
/// and the security-relevant ordering in [resolveAppStage] was re-evaluated by
/// hand on every build. Moving the stage to a [ChangeNotifier] lets the router
/// own it as a pure `redirect` over a snapshot, which is testable with no widget
/// tree at all.
///
/// It holds no navigation. It only reports what is true; where to go is
/// `appRedirect`'s problem.
class AppStageController extends ChangeNotifier {
  AppStageController(this._state) {
    // The router's `refreshListenable` is this controller, not [AppState].
    // Without forwarding [AppState] changes, a successful sign-in — which
    // updates [AppState] and calls its `notifyListeners` — never reaches the
    // router, so the redirect never re-runs and the user stays frozen on the
    // PIN pad or setup screen. Forwarding makes every session transition
    // observable to the guard immediately.
    _state.addListener(_onStateChanged);
  }

  final AppState _state;

  bool _loading = true;
  bool _databaseFailed = false;
  bool _onboardingComplete = false;

  /// Whether the till has already asked for its permissions.
  ///
  /// FALSE until the owner has been through the step and moved on. It is asked
  /// once per workspace: a permission the owner has already answered — granted
  /// OR refused — is a decision, and a till that asks again every morning is a
  /// till people learn to dismiss without reading.
  ///
  /// True before [boot] answers, so the pre-boot stage is not the permissions
  /// step: the stage is `loading` until then anyway.
  bool _permissionsAsked = true;

  /// The store the two flags above were read from, kept so a workspace switch
  /// can re-read them SYNCHRONOUSLY.
  ///
  /// A `redirect` that awaits is a redirect that can run twice, so the flags
  /// the guard reads have to be current values, not futures. SharedPreferences
  /// caches its instance after the first load, which makes a re-read a map
  /// lookup — and the lookup is the whole reason this field exists.
  SharedPreferences? _prefs;

  /// The workspace the two flags were last read for.
  String? _flagsReadFor;

  /// A change in [AppState] — sign-in, sign-out, or a SHOP SWITCH.
  ///
  /// The two walkthrough flags are stored per workspace, but `boot()` reads
  /// them exactly once, for whatever workspace was active at launch. Switching
  /// from shop A to shop B without re-reading left the guard answering with
  /// A's flags: shop B was either shoved back into an onboarding it had
  /// already finished, or skipped a walkthrough it had never seen. The switch
  /// itself notifies [AppState] (see `switchWorkspace`), so this is the one
  /// place that can see it coming.
  void _onStateChanged() {
    final SharedPreferences? prefs = _prefs;
    final String key = _state.workspaceKey;
    if (prefs != null && _flagsReadFor != key) {
      _flagsReadFor = key;
      _onboardingComplete = prefs.getBool('onboarding_completed_$key') ?? false;
      _permissionsAsked = prefs.getBool('permissions_asked_$key') ?? false;
    }
    notifyListeners();
  }

  AppChooserIntent _intent = AppChooserIntent.signIn;

  AppChooserIntent get intent => _intent;

  bool _disposed = false;

  /// Reads the local store once, at boot. Everything the redirect needs after
  /// this point is a synchronous getter, because a `redirect` that awaits is a
  /// redirect that can run twice.
  ///
  /// The disposal guard is load-bearing, not defensive boilerplate. `boot` awaits
  /// real I/O, and the tree that owns this controller can be torn down while those
  /// awaits are in flight — a widget test between cases, an app backgrounded and
  /// killed on a cold start, a hot restart. `notifyListeners()` on a disposed
  /// `ChangeNotifier` asserts in debug and is a no-op in release, which means the
  /// real device silently boots to a blank router with no explanation.
  Future<void> boot() async {
    try {
      await _state.loadOwner();
      await _state.loadRememberedStaff();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _flagsReadFor = _state.workspaceKey;
      _onboardingComplete =
          prefs.getBool('onboarding_completed_${_state.workspaceKey}') ?? false;
      // The permissions step is asked once. A till that has never been asked
      // has NOT been asked — the flag is only set when the owner has been
      // through the step and moved on.
      _permissionsAsked =
          prefs.getBool('permissions_asked_${_state.workspaceKey}') ?? false;
      if (_disposed) return;
      await AutoSyncService.start();
    } catch (error, stack) {
      debugPrint('Boot failed: $error\n$stack');
      failureRecorder.remember(
        kind: error is Error ? CrashKind.crash : CrashKind.error,
        message: 'Database boot failed: $error',
        stack: stack.toString(),
        operation: 'opening local workspace database',
      );
      if (_disposed) return;
      _databaseFailed = true;
    }
    if (_disposed) return;
    _loading = false;
    notifyListeners();
  }

  /// How long a retry waits before it gives up and says so.
  static const Duration retryTimeout = Duration(seconds: 15);

  /// Tries the database again, and reports whether it worked.
  ///
  /// The recovery screen was a dead end without this. It told the owner their
  /// data could not be opened and then offered no way to find out whether that
  /// was still true — and the condition is often temporary: a full disk
  /// freed, a restored backup, a different working directory after an update.
  /// A screen that can only report a failure is a screen that has given up.
  ///
  /// The stage stays on the recovery screen until the attempt ANSWERS. It
  /// does not clear the failure the moment the retry starts, because that
  /// would navigate the owner away from the screen while the question is still
  /// open — and if the retry then fails, they would be on the chooser with no
  /// idea why.
  Future<bool> retry() async {
    if (_disposed) return false;
    try {
      // Bounded, because opening the database is file I/O on a phone that may
      // be the very thing that is broken. A retry that waits forever is a
      // spinner that never stops: a dead end with an animation on it. Fifteen
      // seconds is an order of magnitude longer than a healthy open takes.
      await _state.loadOwner().timeout(retryTimeout);
      await _state.loadRememberedStaff();
      if (_disposed) return false;
      _databaseFailed = false;
      notifyListeners();
      return true;
    } catch (error, stack) {
      debugPrint('Retry failed: $error\n$stack');
      failureRecorder.remember(
        kind: error is Error ? CrashKind.crash : CrashKind.error,
        message: 'Database retry failed: $error',
        stack: stack.toString(),
        operation: 'retrying local workspace database',
      );
      if (_disposed) return false;
      _databaseFailed = true;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _disposed = true;
    super.dispose();
  }

  /// The chooser's choice. Held here rather than as local state inside the
  /// chooser because the router resolves what the choice *leads to* — that is
  /// the whole reason the chooser exists.
  void choose(AppChooserIntent intent) {
    if (_disposed) return;
    // Always notify even if the intent is the same. A user pressing "Sign in"
    /// when it's already the current intent still needs the router to re-evaluate
    /// and navigate to the login screen. The redirect uses the intent to decide
    /// whether the stage is [AppStage.chooser] or [AppStage.signingIn].
    _intent = intent;
    notifyListeners();
  }

  /// Abandons the flow the chooser chose, returning it to its starting state.
  ///
  /// This is what the setup screen's Back button calls, and it is the reason
  /// Back works at all.
  ///
  /// The stage is DERIVED from the intent, not stored beside it — see
  /// `resolveAppStage`: with a shop present and nobody signed in, an
  /// `addShop` intent resolves to `AppStage.settingUp`, and the guard then
  /// sends anything that is not `/setup` back to `/setup`. So a Back button
  /// that only navigates is a no-op in the literal sense: the guard
  /// immediately sends the user forward again, and they watch the screen
  /// they just left reappear.
  ///
  /// Resetting the intent to `signIn` re-derives the stage to `signingIn`,
  /// whose door is `/welcome` — so the same navigation that was refused is
  /// now the guard's own answer. The fix is to change the state the guard
  /// reads, not the guard.
  void abandonChoice() {
    if (_disposed) return;
    if (_intent == AppChooserIntent.signIn) return;
    _intent = AppChooserIntent.signIn;
    notifyListeners();
  }

  /// Marks the walkthrough done. The preference is written before the stage
  /// flips, so a crash between the two leaves the walkthrough showing again
  /// rather than skipping it forever.
  Future<void> completeOnboarding() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'onboarding_completed_${_state.workspaceKey}',
      true,
    );
    if (_disposed) return;
    _onboardingComplete = true;
    notifyListeners();
  }

  /// Records that the owner has been asked for the till's permissions.
  ///
  /// Called when they move on, whether they granted anything or not: the
  /// question was asked, and asking it again every morning is worse than
  /// asking it once.
  Future<void> completePermissions() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'permissions_asked_${_state.workspaceKey}',
      true,
    );
    if (_disposed) return;
    _permissionsAsked = true;
    notifyListeners();
  }

  /// Everything the redirect reads, captured as a value.
  ///
  /// A redirect must be a pure function of a snapshot, never of live widgets or
  /// an in-flight future. This is that snapshot.
  /// The guard too: the router reads this while it may be tearing down.
  bool get isDisposed => _disposed;

  AppStageSnapshot get snapshot => AppStageSnapshot(
        stage: resolveAppStage(
          isLoading: _loading,
          hasDatabaseFailure: _databaseFailed,
          hasShop: _state.owner != null,
          isSignedIn: _state.isSignedIn,
          isAdmin: _state.isAdmin,
          onboardingComplete: _onboardingComplete,
          permissionsAsked: _permissionsAsked,
          chooserIntent: _intent,
        ),
        canManageStock: _state.canManageStock,
        canViewReports: _state.canViewReports,
        isAdmin: _state.isAdmin,
      );
}

/// An immutable read of the routing-relevant facts.
///
/// Taken as a value so a redirect can be driven from a test with four booleans
/// instead of a booted database.
@immutable
class AppStageSnapshot {
  const AppStageSnapshot({
    required this.stage,
    required this.canManageStock,
    this.canViewReports = false,
    required this.isAdmin,
  });

  final AppStage stage;

  /// Whether this session may see Inventory, Analytics and Reports. A cashier
  /// may not: those screens report the whole shop.
  final bool canManageStock;

  final bool canViewReports;

  /// Whether this session may see Settings.
  final bool isAdmin;
}
