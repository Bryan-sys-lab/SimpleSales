// The idle guard: signs a shared till out when nobody is using it.
//
// A till left signed in on the counter is open to anyone walking past — they
// can sell, adjust stock, or, in an owner session, reach Settings. So the shell
// holds a timer, the way a POS terminal does.
//
// THE BUG THIS REPLACES. The window was four minutes and the clock reset on a
// pointer event alone, so the till signed out people who were still working:
// serving a customer, walking to the stockroom, reading a report, or answering
// the phone with the app on the counter. And a barcode scanner — which types
// into a text field and produces no pointer events at all — would sign the till
// out mid-sale. Both look identical to a listener that only watches fingertips.
//
// Three signals therefore count as activity, because all three are the shop
// being used:
//
//   * a tap or a scroll,
//   * the app returning to the foreground, since answering a call is not
//     idleness and the interrupted work goes with the session,
//   * anything the shop records, which is the sale a scanner just rang up.
//
// The window itself has to be longer than the work. The timer cannot tell an
// unattended till from a cashier mid-conversation — both are silent to a
// pointer — so the only safe answer is a window long enough that silence is
// reasonably the till's own state.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/app_update_service.dart';
import '../services/live_channel_service.dart';
import '../services/telemetry_service.dart';

/// How long a signed-in till may sit untouched before it signs itself out.
///
/// The usual POS default, and short enough that a till left open over lunch is
/// signed out before the afternoon shift finds it. See the library comment.
const Duration kIdleTimeout = Duration(minutes: 15);

/// Signs the session out after [timeout] of no activity.
///
/// The timeout is a parameter rather than a private constant so a test can
/// drive the window with a fake clock instead of waiting fifteen minutes for a
/// bug to reproduce.
class IdleGuard extends StatefulWidget {
  const IdleGuard({
    required this.child,
    this.timeout = kIdleTimeout,
    super.key,
  });

  final Widget child;
  final Duration timeout;

  @override
  State<IdleGuard> createState() => _IdleGuardState();
}

class _IdleGuardState extends State<IdleGuard> with WidgetsBindingObserver {
  Timer? _timer;
  LiveChannelService? _channel;
  bool _wasIdle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reset();
    _channel = context.read<LiveChannelService>();
    _channel?.addListener(_reset);
  }

  @override
  void dispose() {
    _channel?.removeListener(_reset);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Coming back is the user arriving, not the user leaving, so the clock
        // starts from here rather than from when they went away. A phone call, a
        // pocketed screen, a photo of a barcode: none of them mean the till was
        // unattended, and the interrupted work went with the session.
        _reset();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        // And while the app is NOT in the foreground the window does not run at
        // all. The timer is measuring one thing — whether anybody is still using
        // this till — and a backgrounded app cannot answer that, so letting it
        // tick is the timer inventing a state. Twenty minutes of a phone call
        // used to end the session, and the guard would report the till as
        // unattended while its owner was standing right there holding it.
        _timer?.cancel();
        _timer = null;
    }
  }

  void _reset() {
    if (!mounted) return;
    if (_wasIdle) {
      telemetry.recordIdleEnd();
      _wasIdle = false;
    }
    _timer?.cancel();
    _timer = Timer(widget.timeout, () {
      if (!mounted) return;
      _wasIdle = true;
      telemetry.recordIdleStart();
      // An idle till is the right time to download an update silently, if the
      // owner has allowed automatic updates.
      unawaited(AppUpdateService().autoDownloadWhenIdle());
      // An idle sign-out is the same event as a deliberate one — same session
      // ended, same tokens to clear — so it goes through `signOut` rather than a
      // shortcut that would leave the online identity alive on the device. No
      // confirmation sheet: asking someone to confirm a timeout would defeat it,
      // and the till is secure again either way.
      context.read<AppState>().signOut();
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _reset(),
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      );
}
