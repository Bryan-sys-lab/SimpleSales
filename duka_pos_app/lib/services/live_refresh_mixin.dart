// One live-refresh rule for every screen that shows live figures.
//
// The dashboard, analytics and portfolio all show numbers that change when
// another terminal makes a sale, and all three used to answer that question
// their own way — the dashboard with a bespoke `didChangeDependencies`, the
// other two not at all. Three copies of a rule that decides when a screen
// re-reads is three places for that rule to drift, and the drift is silent:
// one screen refreshes on a `settings` change it does not display, another
// misses a `stock` change it does.
//
// So the rule lives here once:
//
//   * a screen declares WHICH reasons it actually displays, and gets no
//     rebuild for the ones it does not;
//   * a screen re-reads only while it is the visible tab, because the shell
//     keeps every tab alive and an invisible screen refreshing is work with
//     no visible effect;
//   * a missed, duplicated or late change costs nothing, because the
//     re-read is the same one the screen already performs on entry. The live
//     channel is a signal, never a second source of truth.
//   * the re-read is a no-op when one is already in flight, so a burst of
//     changes coalesces into one reload instead of a queue.
library;

import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'live_channel_service.dart';

/// Adds live re-reading to a `State`.
///
/// A screen implements [reloadFromLive] and supplies [liveReasons]. Nothing
/// else is needed: the mixin owns the subscription, the visibility check, the
/// de-duplication and the frame deferral.
mixin LiveRefresh<T extends StatefulWidget> on State<T> {
  /// The last change already acted on.
  ///
  /// The service holds ONE slot, so this is what tells "this is a new change"
  /// from "this is the same change delivered again" — a distinction that
  /// otherwise causes an extra reload on every unrelated dependency change.
  LiveChange? _lastHandledChange;

  /// Whether this tab was visible the last time dependencies changed.
  bool _liveWasActive = true;

  /// Whether a reload is already running.
  ///
  /// Without this, a burst of changes queues one reload each, and the last one
  /// to finish wins — so the screen can render the OLDEST figures after the
  /// newest read completes. Coalescing is the only correct outcome.
  bool _liveReloading = false;

  /// The reasons this screen actually displays.
  ///
  /// Only these trigger a reload. An empty list means the screen reacts to
  /// everything, which is right for a screen whose content is a roll-up rather
  /// than one reason's figures.
  Set<LiveReason> get liveReasons;

  /// Re-reads whatever the screen shows.
  ///
  /// Called on entry, on the tab becoming visible, and on a live change. It
  /// must be safe to call concurrently — the mixin serialises it.
  Future<void> reloadFromLive();

  /// Whether this tab is currently the visible one.
  ///
  /// Overridden by a screen hosted in the indexed-stack shell, where
  /// `TickerMode` is the honest "am I showing" signal. Defaults to true so the
  /// mixin works for a screen pushed outside a shell.
  bool get liveIsVisible => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final active = liveIsVisible;
    if (active && !_liveWasActive) {
      // Deferred, because a dependency change arrives mid-build and a reload
      // that setStates from here would rebuild during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_liveReload());
      });
    }
    _liveWasActive = active;

    final change = context.watch<LiveChannelService>().change;
    if (change == null || identical(change, _lastHandledChange)) return;
    _lastHandledChange = change;

    if (!active) return;
    if (!_cares(change)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_liveReload());
    });
  }

  /// Whether this screen cares about [change] at all.
  bool _cares(LiveChange change) {
    // A change with no reasons means the server did not narrow it, so it is
    // treated as broad rather than as "nothing changed".
    if (change.isBroad) return true;
    if (liveReasons.isEmpty) return true;
    return change.reasons.any(liveReasons.contains);
  }

  Future<void> _liveReload() async {
    if (!mounted) return;
    if (_liveReloading) return;
    _liveReloading = true;
    try {
      await reloadFromLive();
    } finally {
      _liveReloading = false;
    }
  }
}
