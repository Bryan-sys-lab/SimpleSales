/// Telemetry: what the phone records about its own use, so the app can tell
/// when a till is idle, how often it is opened, and whether a shop is drifting
/// away.
///
/// Three rules, copied from [CrashLog]:
///
/// 1. IT NEVER BLOCKS. Recording an event happens after the fact and swallows
///    its own errors. A till that cannot sell must not be stalled by analytics.
/// 2. IT IS BOUNDED AND SELF-DELETING. The event list keeps its newest
///    [kMaxStoredEvents] rows and drops the rest on write, so a phone left on a
///    shelf cannot fill storage with telemetry.
/// 3. IT CARRIES NO SECRETS. Route names, feature names and timestamps only —
///    no PINs, no tokens, no sale amounts, no customer data.
///
/// ## What "idle" means here
///
/// A till is idle when no one has touched it for [kIdleWindow]. The
/// [IdleGuard] already signs the session out after that window; this service
/// records *when* the idle started and ended so churn analytics can tell a
/// shop that has gone quiet from one that is simply closed for the weekend.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The most recent telemetry events are kept. Older ones are dropped on write,
/// so a phone left on a shelf cannot fill storage.
const int kMaxStoredEvents = 200;

/// A till is idle when no one has touched it for this long. Matches
/// [IdleGuard.kIdleTimeout] so the two services agree about what "idle" is.
const Duration kIdleWindow = Duration(minutes: 15);

/// The date a shop was last seen active, used by [ChurnAnalytics] for its
/// streak and churn-risk calculations.
const String _kLastActiveDate = 'telemetry_last_active_date';

/// Consecutive days the shop has been active, used for the Duolingo-style
/// streak.
const String _kStreakCount = 'telemetry_streak_count';

/// Total number of app opens (sessions) ever recorded.
const String _kTotalSessions = 'telemetry_total_sessions';

/// Whether the owner has allowed automatic updates (download + install when
/// the till is idle).
const String _kAutoUpdateEnabled = 'telemetry_auto_update_enabled';

/// The most recent telemetry events, as a JSON array of maps.
const String _kEvents = 'telemetry_events';

/// One recorded event: what happened, when, and where.
@immutable
class TelemetryEvent {
  const TelemetryEvent({
    required this.name,
    required this.at,
    this.route,
    this.detail,
  });

  final String name;
  final DateTime at;
  final String? route;
  final String? detail;

  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'at': at.toIso8601String(),
        if (route != null) 'route': route,
        if (detail != null) 'detail': detail,
      };

  static TelemetryEvent fromMap(Map<String, dynamic> m) => TelemetryEvent(
        name: m['name'] as String,
        at: DateTime.tryParse(m['at'] as String? ?? '') ?? DateTime.now(),
        route: m['route'] as String?,
        detail: m['detail'] as String?,
      );
}

/// Owns recording telemetry and exposing the derived facts churn analytics
/// needs.
///
/// A `ChangeNotifier` so screens can watch it, and a singleton so any part of
/// the app can record an event without plumbing a dependency through
/// constructors.
class TelemetryService extends ChangeNotifier {
  TelemetryService() {
    _load();
  }

  /// The shared preferences instance, loaded lazily on first use.
  SharedPreferences? _prefs;

  DateTime? _lastActiveDate;
  DateTime? get lastActiveDate => _lastActiveDate;

  int _streakCount = 0;
  int get streakCount => _streakCount;

  int _totalSessions = 0;
  int get totalSessions => _totalSessions;

  bool _autoUpdateEnabled = false;
  bool get autoUpdateEnabled => _autoUpdateEnabled;

  /// Whether the till is currently idle: no activity for [kIdleWindow].
  ///
  /// Derived from the last recorded event: if the newest event is older than
  /// the window, the till is idle.
  bool get isIdle {
    final last = _events.isEmpty ? null : _events.last.at;
    if (last == null) return false;
    return DateTime.now().difference(last) >= kIdleWindow;
  }

  /// The most recent events, newest first.
  final List<TelemetryEvent> _events = <TelemetryEvent>[];
  List<TelemetryEvent> get events => List.unmodifiable(_events);

  Future<SharedPreferences> get _prefsFuture =>
      _prefs != null ? Future.value(_prefs!) : SharedPreferences.getInstance();

  /// Record an event. Never throws: failures are swallowed so a till can keep
  /// selling even if telemetry cannot write.
  void record({
    required String name,
    DateTime? at,
    String? route,
    String? detail,
  }) {
    final event = TelemetryEvent(
      name: name,
      at: at ?? DateTime.now(),
      route: route,
      detail: detail,
    );
    _events.insert(0, event);
    if (_events.length > kMaxStoredEvents) {
      _events.removeRange(kMaxStoredEvents, _events.length);
    }
    // ignore: unawaited_futures
    _persistEvent(event);
    _maybeUpdateActivity();
    notifyListeners();
  }

  /// Record that the app was opened (a new session began).
  void recordAppOpen({String? route}) {
    _totalSessions++;
    // ignore: unawaited_futures
    _persistInt(_kTotalSessions, _totalSessions);
    record(name: 'app_open', route: route);
  }

  /// Record that the app was closed or backgrounded.
  void recordAppClose({String? route}) {
    record(name: 'app_close', route: route);
  }

  /// Record that a screen was viewed.
  void recordScreenView(String route) {
    record(name: 'screen_view', route: route);
  }

  /// Record that a feature was used (a button tapped, a form submitted).
  void recordFeatureUse(String feature, {String? detail}) {
    record(
      name: 'feature_use',
      detail: '$feature${detail != null ? ': $detail' : ''}',
    );
  }

  /// Record that a sale was recorded. This counts as activity for idle
  /// purposes even if no pointer event fired (a barcode scanner rings up a
  /// sale without a tap).
  void recordSaleRecorded() {
    record(name: 'sale_recorded');
  }

  /// Record that the till went idle (no activity for [kIdleWindow]).
  void recordIdleStart() {
    record(name: 'idle_start');
  }

  /// Record that the till became active again after being idle.
  void recordIdleEnd() {
    record(name: 'idle_end');
  }

  /// Whether the owner has allowed automatic updates.
  set autoUpdateEnabled(bool value) {
    if (_autoUpdateEnabled == value) return;
    _autoUpdateEnabled = value;
    // ignore: unawaited_futures
    _persistBool(_kAutoUpdateEnabled, value);
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await _prefsFuture;
    _prefs = prefs;
    _lastActiveDate = _parseDate(prefs.getString(_kLastActiveDate));
    _streakCount = prefs.getInt(_kStreakCount) ?? 0;
    _totalSessions = prefs.getInt(_kTotalSessions) ?? 0;
    _autoUpdateEnabled = prefs.getBool(_kAutoUpdateEnabled) ?? false;

    final raw = prefs.getStringList(_kEvents) ?? <String>[];
    for (final encoded in raw) {
      try {
        _events.add(TelemetryEvent.fromMap(
            jsonDecode(encoded) as Map<String, dynamic>));
      } on Object {
        // A corrupt event is skipped, not fatal.
      }
    }
    notifyListeners();
  }

  Future<void> _persistEvent(TelemetryEvent event) async {
    final prefs = await _prefsFuture;
    final existing = prefs.getStringList(_kEvents) ?? <String>[];
    final encoded = <String>[jsonEncode(event.toMap())];
    encoded.addAll(existing.take(kMaxStoredEvents - 1));
    await prefs.setStringList(_kEvents, encoded);
  }

  Future<void> _persistInt(String key, int value) async {
    final prefs = await _prefsFuture;
    await prefs.setInt(key, value);
  }

  Future<void> _persistBool(String key, bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(key, value);
  }

  /// Recalculate streak and last-active date from the recorded events, and
  /// persist them. Called whenever an event is written.
  Future<void> _maybeUpdateActivity() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // The last active date is the date of the most recent event.
    final last = _events.isNotEmpty ? _events.first.at : null;
    if (last != null) {
      final lastDate = DateTime(last.year, last.month, last.day);
      if (_lastActiveDate == null || lastDate.isAfter(_lastActiveDate!)) {
        _lastActiveDate = lastDate;
        await _persistString(_kLastActiveDate, last.toIso8601String());
      }
    }

    // Streak: consecutive days with at least one event. If the last event was
    // today or yesterday, the streak continues; otherwise it resets to 1.
    if (_lastActiveDate != null) {
      final diff = today.difference(_lastActiveDate!).inDays;
      if (diff <= 1) {
        _streakCount = diff == 0 ? _streakCount : _streakCount + 1;
      } else {
        _streakCount = 1;
      }
      await _persistInt(_kStreakCount, _streakCount);
    }
    notifyListeners();
  }

  Future<void> _persistString(String key, String value) async {
    final prefs = await _prefsFuture;
    await prefs.setString(key, value);
  }

  DateTime? _parseDate(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }
}

/// The singleton. Every part of the app that records telemetry uses this one
/// instance so events are never split across two stores.
final TelemetryService telemetry = TelemetryService();
