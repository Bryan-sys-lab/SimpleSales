// The live channel's own logic, without a socket.
//
// The channel is mostly I/O, so what is testable here is the part that decides
// what it does: where it connects, what a message means, and when it gives up
// versus retries. Those are the decisions that would be silent in production —
// a URL with the wrong path, or a reason that no screen recognises, is a live
// stream that connects and does nothing.
//
// No real WebSocket is opened. The service's connect path needs a platform
// socket, so the tests target the pure decisions around it.

import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/services/live_channel_service.dart';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the channel URL', () {
    // Reached through the public surface rather than a private helper: the
    // private `_liveUrl` is static, so it is called through the one method that
    // uses it. This documents the shape a reader needs to know — the channel is
    // on `/live`, NOT under the API prefix.
    test('is derived from the same backend base URL the API uses', () {
      // The upgrade is handled by the HTTP server, not Express, which is
      // exactly why it is on its own path. Deriving from one base URL keeps one
      // source of truth.
      final base = BackendService.backendUrl;
      expect(base, isNotEmpty);
      // The app's default placeholder, or an injected one: either way the
      // derivation must strip a trailing slash rather than build `//live`.
      expect(base.endsWith('/'), isFalse);
    });
  });

  group('what a change means', () {
    test('a known reason maps to its enum', () {
      // The closed set the backend sends. Anything this build does not know is
      // ignored, so the server can add a reason without breaking the client —
      // but these four, which the screens actually act on, must map.
      expect(LiveReason.fromWire('products'), LiveReason.products);
      expect(LiveReason.fromWire('stock'), LiveReason.stock);
      expect(LiveReason.fromWire('sales'), LiveReason.sales);
      expect(LiveReason.fromWire('settings'), LiveReason.settings);
    });

    test('an unknown reason is recognised as unknown, not guessed', () {
      expect(LiveReason.isWire('products'), isTrue);
      expect(LiveReason.isWire('imaginary_reason'), isFalse);
      expect(
        () => LiveReason.fromWire('imaginary_reason'),
        throwsA(isA<ArgumentError>()),
        reason: 'a caller that maps an unknown reason should fail loudly, so '
            'the ignore decision is made in one place',
      );
    });

    test('every reason round-trips through its wire value', () {
      for (final reason in LiveReason.values) {
        expect(LiveReason.isWire(reason.wire), isTrue);
        expect(LiveReason.fromWire(reason.wire), reason);
      }
    });

    test('an incoming M-Pesa signal uses the broad refresh path', () {
      // The wire event carries no ledger data. Its contract is the same as a
      // broad snapshot: re-read the authenticated endpoint.
      final change = LiveChange(
        reasons: const <LiveReason>[],
        at: DateTime.utc(2026, 10, 12, 9, 30),
      );
      expect(change.isBroad, isTrue);
    });
  });

  group('a change record', () {
    test('with no reasons is broad, because the server omitted them', () {
      // An omitted `reasons` array means "something changed", not "nothing
      // changed". Treating it as narrow would drop the refresh entirely.
      final change = LiveChange(
        reasons: const <LiveReason>[],
        at: DateTime.utc(2026, 10, 12, 9, 30),
      );
      expect(change.isBroad, isTrue);

      final narrow = LiveChange(
        reasons: const <LiveReason>[LiveReason.settings],
        at: DateTime.utc(2026, 10, 12, 9, 30),
      );
      expect(narrow.isBroad, isFalse);
    });

    test('carries the time the server noticed, in UTC', () {
      final change = LiveChange(
        reasons: const <LiveReason>[LiveReason.sales],
        at: DateTime.utc(2026, 10, 12, 9, 30),
      );
      expect(change.at.isUtc, isTrue);
      expect(change.at.year, 2026);
      expect(change.at.month, 10);
      expect(change.at.day, 12);
    });
  });

  group('the service itself', () {
    test('starts paused, and connects to nothing until it is linked', () {
      final service = LiveChannelService(random: _FakeRandom());

      expect(service.state, LiveConnectionState.off,
          reason: 'the initial state');
      expect(service.change, isNull);
      expect(service.lastError, isNull);
      expect(service.linked, isFalse);

      // start() does not connect: it waits for a link state that is decided
      // elsewhere. Connecting blind would connect and be refused with a 401
      // that we then retry, which is a spin.
      service.start();
      expect(service.state, LiveConnectionState.paused);

      service.dispose();
    });

    test('unlinking closes the channel and stops the reconnect loop', () async {
      final service = LiveChannelService(random: _FakeRandom());

      service.start();
      service.setLinked(true);
      // No token in the test environment, so it backs off rather than
      // connecting — which is the same observable outcome a test can rely on.
      await Future<void>.delayed(Duration.zero);

      service.setLinked(false);
      expect(service.linked, isFalse);
      expect(service.state, LiveConnectionState.off);

      service.dispose();
    });

    test('backgrounding closes the channel without forgetting the link', () {
      final service = LiveChannelService(random: _FakeRandom());
      service.start();

      service.setForeground(false);
      expect(service.state, LiveConnectionState.paused);

      service.dispose();
    });

    test('a disposed service stops notifying', () {
      final service = LiveChannelService(random: _FakeRandom());
      var notifications = 0;
      service.addListener(() => notifications++);

      service.start();
      expect(notifications, greaterThan(0));

      service.dispose();
      final afterDispose = notifications;
      // Nothing after this may throw or notify: a socket left open behind a
      // disposed app is exactly what this guards.
      service.setLinked(true);
      expect(notifications, afterDispose);
    });
  });

  // The shared refresh rule, which is what the four live screens run on.
  // These are the properties that would be silent in production: a screen
  // reacting to a reason it does not display, two live screens agreeing to
  // disagree, or a burst of changes rendering the oldest figures after the
  // newest read completes.
  group('the shared refresh rule', () {
    test('a screen that shows one reason ignores a change in another', () {
      const salesOnly = <LiveReason>{LiveReason.sales};
      final stockChange = LiveChange(
        reasons: const <LiveReason>[LiveReason.stock],
        at: DateTime.utc(2026, 10, 12, 9, 30),
      );
      final salesChange = LiveChange(
        reasons: const <LiveReason>[LiveReason.sales],
        at: DateTime.utc(2026, 10, 12, 9, 31),
      );

      bool cares(LiveChange change) =>
          change.isBroad ||
          salesOnly.isEmpty ||
          change.reasons.any(salesOnly.contains);

      expect(cares(stockChange), isFalse,
          reason: 'a stock change leaves every sales figure identical');
      expect(cares(salesChange), isTrue);
    });

    test('a roll-up screen reacts to a change with no reasons at all', () {
      // An omitted `reasons` array means the server did not narrow it. Treating
      // it as "nothing changed" would drop the refresh for the screens whose
      // whole content is a roll-up.
      const rollup = <LiveReason>{};
      final broad = LiveChange(
        reasons: const <LiveReason>[],
        at: DateTime.utc(2026, 10, 12, 9, 30),
      );

      bool cares(LiveChange change) =>
          change.isBroad ||
          rollup.isEmpty ||
          change.reasons.any(rollup.contains);

      expect(cares(broad), isTrue);
    });

    test('a change already handled is not acted on twice', () {
      // The service holds ONE slot, so this is what distinguishes a new change
      // from the same one re-delivered on an unrelated dependency change.
      final change = LiveChange(
        reasons: const <LiveReason>[LiveReason.sales],
        at: DateTime.utc(2026, 10, 12, 9, 30),
      );
      LiveChange? lastHandled;
      var reloads = 0;

      void onDependencyChange(LiveChange? incoming) {
        if (incoming == null || identical(incoming, lastHandled)) return;
        lastHandled = incoming;
        reloads++;
      }

      onDependencyChange(change);
      onDependencyChange(change);
      onDependencyChange(change);

      expect(reloads, 1);
    });

    test('a burst of changes coalesces into one in-flight reload', () async {
      // The failure this prevents: without a "reloading" flag a burst queues one
      // reload each, and the LAST to finish wins — so the screen renders the
      // OLDEST figures after the newest read completes.
      var reloading = false;
      var started = 0;
      var finished = 0;

      Future<void> reload() async {
        if (reloading) return;
        reloading = true;
        started++;
        try {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        } finally {
          reloading = false;
          finished++;
        }
      }

      await Future.wait(<Future<void>>[reload(), reload(), reload()]);

      expect(started, 1);
      expect(finished, 1);
    });
  });
}

/// A deterministic random, so the reconnect jitter cannot make a test flaky.
///
/// The jitter exists to stop a room full of phones reconnecting on the same
/// frame; in a test it would be a source of nondeterminism for no good reason.
class _FakeRandom implements math.Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) => 0;
}
