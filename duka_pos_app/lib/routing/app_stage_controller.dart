import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_stage.dart';
import '../services/app_state.dart';
import '../services/auto_sync_service.dart';

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
    _state.addListener(notifyListeners);
  }

  final AppState _state;

  bool _loading = true;
  bool _databaseFailed = false;
  bool _onboardingComplete = false;
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
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _onboardingComplete =
          prefs.getBool('onboarding_completed_${_state.workspaceKey}') ?? false;
      if (_disposed) return;
      await AutoSyncService.start();
    } catch (error, stack) {
      // Never surfaced: an exception in the UI teaches a shopkeeper that their
      // data is gone. `DatabaseErrorScreen` says what actually happened and what
      // to do, and the crash reporter gets the detail.
      debugPrint('Boot failed: $error\n$stack');
      if (_disposed) return;
      _databaseFailed = true;
    }
    if (_disposed) return;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _state.removeListener(notifyListeners);
    _disposed = true;
    super.dispose();
  }

  /// The chooser's choice. Held here rather than as local state inside the
  /// chooser because the router resolves what the choice *leads to* — that is
  /// the whole reason the chooser exists.
  void choose(AppChooserIntent intent) {
    if (_disposed || _intent == intent) return;
    _intent = intent;
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
          chooserIntent: _intent,
        ),
        canManageStock: _state.canManageStock,
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
    required this.isAdmin,
  });

  final AppStage stage;

  /// Whether this session may see Inventory, Analytics and Reports. A cashier
  /// may not: those screens report the whole shop.
  final bool canManageStock;

  /// Whether this session may see Settings.
  final bool isAdmin;
}
