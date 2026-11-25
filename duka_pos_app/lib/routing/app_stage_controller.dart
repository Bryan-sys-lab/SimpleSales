import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/crash_log.dart';
import '../services/app_stage.dart';
import '../services/app_state.dart';
import '../profile/shop_profile.dart';
import '../services/auto_sync_service.dart';
import '../services/failure_recorder.dart';
import '../services/backend_service.dart';

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
  // A first open can include a one-time migration of a large local database.
  static const Duration startupTimeout = Duration(minutes: 5);
  static const Duration defaultRetryTimeout = startupTimeout;

  AppStageController(
    this._state, {
    Duration bootTimeout = startupTimeout,
    Duration retryTimeout = defaultRetryTimeout,
  })  : _bootTimeout = bootTimeout,
        _retryTimeout = retryTimeout {
    // The router's `refreshListenable` is this controller, not [AppState].
    // Without forwarding [AppState] changes, a successful sign-in — which
    // updates [AppState] and calls its `notifyListeners` — never reaches the
    // router, so the redirect never re-runs and the user stays frozen on the
    // PIN pad or setup screen. Forwarding makes every session transition
    // observable to the guard immediately.
    _state.addListener(_onStateChanged);
  }

  final AppState _state;
  final Duration _bootTimeout;
  final Duration _retryTimeout;

  bool _loading = true;
  bool _databaseFailed = false;
  bool _onboardingComplete = false;
  bool _subscriptionRequired = false;
  String? _subscriptionRefreshFor;

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
      _readCachedSubscription(prefs, key);
    }
    if (_state.isSignedIn && _subscriptionRefreshFor != key) {
      _subscriptionRefreshFor = key;
      unawaited(refreshSubscription());
    }
    notifyListeners();
  }

  String _subscriptionKey(String workspace) =>
      'subscription_entitlement@$workspace';

  void _readCachedSubscription(SharedPreferences prefs, String workspace) {
    final String prefix = _subscriptionKey(workspace);
    final bool? allowed = prefs.getBool('$prefix.allowed');
    if (allowed == null) {
      // No server decision has been cached for this shop on this device yet.
      // Keep access gated until the shop entitlement can be verified.
      _subscriptionRequired = true;
      return;
    }
    final String? end = prefs.getString('$prefix.period_end');
    final DateTime? periodEnd = end == null ? null : DateTime.tryParse(end);
    _subscriptionRequired = !allowed ||
        (periodEnd != null && !periodEnd.isAfter(DateTime.now().toUtc()));
  }

  /// Refreshes the server entitlement for the active shop and stores it per
  /// workspace. Owners and staff read the same tenant-scoped decision using
  /// their own session. Network failures deliberately retain the last known state:
  /// offline selling remains available, while the backend still enforces the
  /// entitlement on every protected remote operation.
  Future<void> refreshSubscription() async {
    if (_disposed || !_state.isSignedIn) return;
    final String workspace = _state.workspaceKey;
    try {
      final SubscriptionEntitlement? entitlement =
          await BackendService.fetchSubscriptionEntitlement();
      if (_disposed || entitlement == null) return;
      final SharedPreferences prefs =
          _prefs ??= await SharedPreferences.getInstance();
      final String prefix = _subscriptionKey(workspace);
      await prefs.setBool('$prefix.allowed', entitlement.allowed);
      if (entitlement.currentPeriodEnd == null) {
        await prefs.remove('$prefix.period_end');
      } else {
        await prefs.setString(
            '$prefix.period_end', entitlement.currentPeriodEnd!);
      }
      if (_disposed || workspace != _state.workspaceKey) return;
      final DateTime? periodEnd = entitlement.currentPeriodEnd == null
          ? null
          : DateTime.tryParse(entitlement.currentPeriodEnd!);
      _subscriptionRequired = !entitlement.allowed ||
          (periodEnd != null && !periodEnd.isAfter(DateTime.now().toUtc()));
      notifyListeners();
    } catch (_) {
      // Keep the cached decision. The API remains the final authority.
    }
  }

  AppChooserIntent _intent = AppChooserIntent.signIn;

  AppChooserIntent get intent => _intent;

  bool _disposed = false;
  final Completer<void> _disposedSignal = Completer<void>();

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
      await _restoreStartupStateBeforeDeadline();
    } catch (error, stack) {
      debugPrint('Boot failed: $error\n$stack');
      failureRecorder.remember(
        kind: error is Error ? CrashKind.crash : CrashKind.error,
        message: 'Workspace startup failed: $error',
        stack: stack.toString(),
        operation: 'restoring local workspace',
      );
      if (_disposed) return;
      _databaseFailed = true;
    }
    if (_disposed) return;
    _loading = false;
    notifyListeners();
    if (!_databaseFailed) unawaited(_startAutoSync());
  }

  Future<void> _restoreStartupStateBeforeDeadline() async {
    final Completer<void> timeout = Completer<void>();
    final Timer timer = Timer(
      _bootTimeout,
      () => timeout.completeError(
        TimeoutException('Workspace startup timed out', _bootTimeout),
      ),
    );
    try {
      await Future.any<void>(<Future<void>>[
        _restoreStartupState(),
        timeout.future,
        _disposedSignal.future,
      ]);
    } finally {
      timer.cancel();
    }
  }

  Future<void> _restoreStartupState() async {
    if (kIsWeb) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _flagsReadFor = _state.workspaceKey;
      _onboardingComplete = true;
      _permissionsAsked = true;
      _subscriptionRequired = false;
      await _state.loadOwner();
      await _state.loadRememberedStaff();
      return;
    }
    await _state.loadOwner();
    await _state.loadRememberedStaff();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _flagsReadFor = _state.workspaceKey;
    _onboardingComplete =
        prefs.getBool('onboarding_completed_${_state.workspaceKey}') ?? false;
    _permissionsAsked =
        prefs.getBool('permissions_asked_${_state.workspaceKey}') ?? false;
    _readCachedSubscription(prefs, _state.workspaceKey);
  }

  Future<void> _startAutoSync() async {
    try {
      await AutoSyncService.start();
    } catch (error, stack) {
      debugPrint('Automatic backup scheduling failed: $error\n$stack');
      failureRecorder.remember(
        kind: CrashKind.warning,
        message: 'Automatic backup scheduling failed: $error',
        stack: stack.toString(),
        operation: 'starting automatic backup scheduling',
      );
    }
  }

  /// How long a retry waits before it gives up and says so.
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
      // be the very thing that is broken. The recovery screen must not become
      // another spinner that never stops.
      await _state.loadOwner().timeout(_retryTimeout);
      await _state.loadRememberedStaff();
      if (_disposed) return false;
      _databaseFailed = false;
      notifyListeners();
      unawaited(_startAutoSync());
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
    if (!_disposedSignal.isCompleted) _disposedSignal.complete();
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
        shopProfile: _state.shopProfile,
        subscriptionRequired: _subscriptionRequired,
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
    required this.shopProfile,
    this.subscriptionRequired = false,
  });

  final AppStage stage;

  /// Whether this session may see Inventory, Analytics and Reports. A cashier
  /// may not: those screens report the whole shop.
  final bool canManageStock;

  final bool canViewReports;

  /// Whether this session may see Settings.
  final bool isAdmin;

  /// Active shop profile; drives profile-specific route availability.
  final ShopProfile shopProfile;

  /// Whether the shop's subscription or voucher is expired or otherwise
  /// inactive. The redirect uses this synchronously; the controller refreshes
  /// it asynchronously from the backend.
  final bool subscriptionRequired;
}
