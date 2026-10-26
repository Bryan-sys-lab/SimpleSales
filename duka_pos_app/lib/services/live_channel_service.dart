// The till's live change stream, client side.
//
// WHAT THIS IS FOR
// A shop with a phone and a counter has two people: one selling, one watching
// the dashboard. Before this, the watching one refreshed by hand, or by
// pull-to-refresh, or not at all. The backend's `/live` channel tells this
// device when something it cares about changed, and the screen re-reads.
//
// WHAT IT DELIBERATELY IS NOT
// It is not the transport for the ledger. Every message is a SIGNAL; the data
// behind it is fetched from the same HTTP endpoints a pull-to-refresh uses, so
// a stream and a refresh can never disagree about what a shop sold. That is
// also why a dropped connection costs nothing — the next connect re-reads.
//
// WHY THE RECONNECT IS AGGRESSIVE
// A till on a phone drops off the network constantly, and a channel that gives
// up stays dead. The backoff here is capped low and jittered, and it resets on
// a successful message, so a shop that walks out of coverage reconnects within
// seconds of returning rather than after a minute of silence.
//
// WHY IT NEVER CONNECTS UNLESS LINKED
// An unlinked shop has no session and no tenant, so there is nothing to
// subscribe to; and connecting anyway would have the server close the socket
// with a 401 that we then retry. The connection is gated on exactly the
// conditions under which it is meaningful.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart' show IOWebSocketChannel;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'backend_service.dart';
import 'app_release.dart';
import 'oidc_service.dart';

/// What changed, as far as the phone is concerned.
///
/// A subset of the backend's closed set, mapped to what a Flutter screen
/// actually re-reads. A reason this build does not recognise is ignored rather
/// than surfaced, so the server can add one without breaking the client.
enum LiveReason {
  products('products'),
  stock('stock'),
  sales('sales'),
  settings('settings');

  const LiveReason(this.wire);

  final String wire;

  static LiveReason fromWire(String? value) {
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    throw ArgumentError.value(value, 'value', 'not a live reason');
  }

  static bool isWire(String? value) => values.any((r) => r.wire == value);
}

/// A change the stream reported, ready for a screen to act on.
@immutable
class LiveChange {
  const LiveChange({required this.reasons, required this.at});

  /// Empty means "something changed, re-read everything you show".
  final List<LiveReason> reasons;

  /// When the backend noticed it, UTC.
  final DateTime at;

  bool get isBroad => reasons.isEmpty;
}

/// State of the connection, for a status affordance.
enum LiveConnectionState { off, connecting, connected, paused }

/// Owns the live channel.
///
/// A `ChangeNotifier` rather than a stream of streams, because the app's own
/// state layer is `provider` + `ChangeNotifier` and a second paradigm for one
/// feature would be more machinery than the feature worth. A caller listens
/// with `context.watch<LiveChannelService>().changes`.
class LiveChannelService extends ChangeNotifier {
  LiveChannelService({math.Random? random}) : _random = random ?? math.Random();

  /// Never poll faster than this once connected.
  static const Duration _reconnectBase = Duration(seconds: 2);

  /// The cap, deliberately low: a shop returning from a dead spot should
  /// reconnect in seconds, not after a minute of quiet.
  static const Duration _reconnectCap = Duration(seconds: 20);

  /// How long a quiet connection is treated as alive.
  ///
  /// The server pings more often than this, so exceeding it means the socket is
  /// dead in a way nothing told us about — which is the case where a stale
  /// "connected" badge would lie.
  static const Duration _silentBeforeReconnect = Duration(seconds: 90);

  final math.Random _random;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _incoming;
  Timer? _reconnectTimer;
  Timer? _silenceTimer;

  LiveConnectionState _state = LiveConnectionState.off;
  LiveConnectionState get state => _state;

  /// The most recent change, replaced on each message.
  ///
  /// A single slot rather than a stream: a screen that re-reads does not want a
  /// queue of changes that arrived while it was busy, it wants the latest one.
  LiveChange? _change;
  LiveChange? get change => _change;

  PlatformAnnouncement? _platformAnnouncement;

  /// The newest platform announcement delivered over the live channel. Reading
  /// consumes it so a rebuild cannot show the same message twice.
  PlatformAnnouncement? takePlatformAnnouncement() {
    final announcement = _platformAnnouncement;
    _platformAnnouncement = null;
    return announcement;
  }

  /// A message from the server the UI should show, if anything went wrong.
  String? _lastError;
  String? get lastError => _lastError;

  bool _linked() => _lastKnownLinked;
  bool _lastKnownLinked = false;

  /// Whether the app is in the foreground.
  ///
  /// A backgrounded app keeps the socket open for nothing: Android may kill the
  /// process at any point, and a shop on a counter does not need live refresh
  /// while the screen is off. Returning to the foreground reconnects.
  bool _foreground = true;
  bool _disposed = false;

  bool get linked => _lastKnownLinked;

  /// Starts the channel. Safe to call more than once.
  ///
  /// Does not connect immediately: [setLinked] decides that, and it is called
  /// by the composition root as soon as the app knows whether this shop is
  /// linked. Starting blind would connect and be refused.
  void start() {
    if (_disposed) return;
    if (_state == LiveConnectionState.off) {
      _state = LiveConnectionState.paused;
      notifyListeners();
    }
    _maybeConnect();
  }

  /// Tells the channel whether this shop is linked, and (re)acts on it.
  void setLinked(bool linked) {
    if (_disposed) return;
    final changed = _lastKnownLinked != linked;
    _lastKnownLinked = linked;
    if (changed && !_disposed) notifyListeners();
    if (!linked) {
      _close();
      _setState(LiveConnectionState.off);
      return;
    }
    _maybeConnect();
  }

  void setForeground(bool foreground) {
    if (_disposed) return;
    _foreground = foreground;
    if (!foreground) {
      _close();
      _setState(LiveConnectionState.paused);
      return;
    }
    _maybeConnect();
  }

  Future<void> _maybeConnect() async {
    if (_disposed) return;
    if (!_linked() || !_foreground) return;
    if (_channel != null) return;
    if (_reconnectTimer?.isActive ?? false) return;

    // The session is read BEFORE the state is changed, and its failure is
    // contained. Two reasons this ordering matters:
    //
    //   * A keystore that is unavailable (no platform, a storage error) throws
    //     here, and an unhandled throw from a `void`-returning path would take
    //     the zone down — the same reason `signOut` swallows its teardown.
    //   * Reading it before `connecting` means a failure leaves the state as it
    //     was, rather than stuck claiming a connection attempt that never ran.
    final String? token;
    try {
      // The ONE credential: the Keycloak access token. The server's live
      // channel verifies it against the identity server's own signing keys,
      // and accepts nothing else.
      token = await OidcService.accessToken;
    } on Object catch (_) {
      _scheduleReconnect();
      return;
    }

    if (_disposed) return;
    _setState(LiveConnectionState.connecting);

    if (token == null || token.isEmpty) {
      // No session: nothing to subscribe as. Back off rather than spin, so an
      // unlinked-or-signed-out shop does not retry every frame.
      _scheduleReconnect();
      return;
    }

    final url = _liveUrl();
    if (url == null) {
      // No backend configured. Offline-only builds are legitimate, so this is
      // a silent off rather than an error the owner has to see.
      _setState(LiveConnectionState.off);
      return;
    }

    try {
      // `IOWebSocketChannel`, not the abstract `WebSocketChannel`: only the
      // platform implementation accepts `headers`, and the bearer token has to
      // travel in the handshake — the backend reads it from the upgrade request,
      // so there is no second chance to send it once the socket is open.
      //
      // `pingInterval` is left to the server: it pings more often than our own
      // silence timer, and two pingers on one socket is noise for no gain.
      final channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        headers: <String, dynamic>{'Authorization': 'Bearer $token'},
      );
      _attach(channel);
    } on Object catch (error) {
      _lastError = '$error';
      _scheduleReconnect();
    }
  }

  void _attach(WebSocketChannel channel) {
    _channel = channel;
    _resetSilenceTimer();
    _incoming = channel.stream.listen(
      _onMessage,
      onError: (Object error) {
        _lastError = '$error';
        _teardownAndReconnect();
      },
      onDone: _teardownAndReconnect,
      cancelOnError: true,
    );
    _setState(LiveConnectionState.connected);
  }

  void _onMessage(dynamic raw) {
    _resetSilenceTimer();
    if (raw is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      // A frame the client cannot parse is still a live server; ignore it and
      // wait for the next one.
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final type = decoded['type'];
    if (type == 'stale' || type == 'snapshot') {
      _recordChange(decoded);
    } else if (type == 'mpesa_incoming') {
      // The backend deliberately sends only a signal for an incoming payment;
      // the screen re-reads the authenticated list endpoint, just like every
      // other live refresh. Treat it as broad so older tills do not need a new
      // reason enum merely to stay current.
      _recordChange(<String, dynamic>{
        'reasons': const <String>[],
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    } else if (type == 'platform_announcement') {
      _platformAnnouncement =
          PlatformAnnouncement.tryParse(decoded['announcement']);
    } else if (type == 'error') {
      _lastError = decoded['error'] as String?;
    }
    // 'pong' and anything else: nothing to do beyond keeping the timer reset.
    notifyListeners();
  }

  void _recordChange(Map<String, dynamic> message) {
    final raw = message['reasons'];
    final reasons = <LiveReason>[];
    if (raw is List) {
      for (final value in raw) {
        if (value is String && LiveReason.isWire(value)) {
          reasons.add(LiveReason.fromWire(value));
        }
      }
    }
    final at = DateTime.tryParse(message['at'] as String? ?? '');
    _change = LiveChange(
      reasons: reasons,
      at: (at ?? DateTime.now()).toUtc(),
    );
  }

  /// Asks the server for a fresh snapshot now.
  ///
  /// The server replies through the same read the HTTP endpoint uses, so this is
  /// a request for a re-read, not a different source of truth.
  void requestRead({List<LiveReason>? reasons}) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(<String, dynamic>{
      'type': 'read',
      if (reasons != null) 'reasons': reasons.map((r) => r.wire).toList(),
    }));
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silentBeforeReconnect, () {
      // No message, including a ping, for this long: the socket is dead even
      // though nothing said so. Reconnect rather than sit on a dead "connected".
      _teardownAndReconnect();
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final attempts = _attempt;
    _attempt++;
    final millis = math.min(
      _reconnectCap.inMilliseconds,
      _reconnectBase.inMilliseconds * (1 << math.min(attempts, 5)),
    );
    // Jitter, so a shop full of phones that dropped together does not reconnect
    // in lockstep and hammer the server on the same frame.
    final jittered = millis * (0.75 + _random.nextDouble() * 0.5);
    _reconnectTimer = Timer(Duration(milliseconds: jittered.round()), () {
      if (_disposed) return;
      _maybeConnect();
    });
    _setState(LiveConnectionState.paused);
  }

  int _attempt = 0;

  void _teardownAndReconnect() {
    _close();
    _scheduleReconnect();
  }

  /// Drops the socket and its listeners without scheduling anything.
  void _close() {
    _incoming?.cancel();
    _incoming = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    // The sink is closed, not the channel, so the server sees a close frame
    // rather than an abrupt TCP reset it has to log.
    channel.sink.close().catchError((Object _) {});
  }

  void _setState(LiveConnectionState next) {
    if (_disposed) return;
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  /// The channel's absolute URL, or null when this build has no backend.
  ///
  /// The channel is on `/live`, NOT under the API prefix: the upgrade is handled
  /// by the HTTP server rather than Express, which is precisely why it is on its
  /// own path. Deriving it from the same base URL keeps the one source of truth.
  static String? _liveUrl() {
    if (BackendService.backendUrl.isEmpty) return null;
    final base = BackendService.backendUrl.replaceAll(RegExp(r'/+$'), '');
    final scheme = base.startsWith('wss://') || base.startsWith('ws://')
        ? base
        : base
            .replaceFirst(RegExp(r'^https://'), 'wss://')
            .replaceFirst(RegExp(r'^http://'), 'ws://');
    return '$scheme/live';
  }

  @override
  void dispose() {
    _disposed = true;
    _incoming?.cancel();
    _reconnectTimer?.cancel();
    _silenceTimer?.cancel();
    final channel = _channel;
    _channel = null;
    channel?.sink.close().catchError((Object _) {});
    super.dispose();
  }
}
