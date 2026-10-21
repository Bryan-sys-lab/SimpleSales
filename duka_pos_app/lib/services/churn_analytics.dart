/// Churn analytics: Duolingo-style streaks and churn risk.
///
/// A shop that opens the till every day builds a streak. A shop that goes
/// silent is at risk of churn. This service turns the raw telemetry recorded
/// by [TelemetryService] into a churn-risk score and a streak the owner can
/// see, so the app can nudge a quiet shop back before it leaves.
///
/// ## Churn risk (0.0 to 1.0)
///
/// Higher means more likely to stop using the app. It is a blend of:
///
///   * **Streak length** — a long streak means the habit is built; a short or
///     zero streak means the habit has not formed.
///   * **Days since last active** — a shop silent for a week is riskier than
///     one that is silent for a day.
///   * **Session frequency** — a shop that opens once a month is riskier than
///     one that opens daily.
///
/// The three are weighted so a long streak protects against a single quiet
/// day, but a long silence overrides even a long streak.
library;

import 'package:flutter/foundation.dart';

import 'telemetry_service.dart';

/// How risky a shop's churn is, in words a screen can show.
enum ChurnRisk {
  none('none', 'Not at risk', 'The shop is active.'),
  low('low', 'Low risk', 'Keep it up — the streak is building.'),
  medium('medium', 'Medium risk', 'Has not been seen in a few days.'),
  high('high', 'High risk', 'Has been quiet for a while.');

  const ChurnRisk(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;
}

/// The churn analysis: streak, days since last active, risk level, and what
/// to say to the shop.
@immutable
class ChurnAnalysis {
  const ChurnAnalysis({
    required this.streakDays,
    required this.daysSinceLastActive,
    required this.totalSessions,
    required this.risk,
    required this.score,
  });

  /// Consecutive days the shop has been active.
  final int streakDays;

  /// Calendar days since the shop last opened the app.
  final int daysSinceLastActive;

  /// Total app opens ever recorded.
  final int totalSessions;

  /// The churn risk level.
  final ChurnRisk risk;

  /// The raw risk score, 0.0 (safe) to 1.0 (likely to churn).
  final double score;

  /// What to say to the shop, matched to the risk level.
  String get message => switch (risk) {
        ChurnRisk.none => 'Still going — keep the streak alive.',
        ChurnRisk.low => 'A few quiet days. The streak is still yours.',
        ChurnRisk.medium =>
          'It has been a while. The till is ready when you are.',
        ChurnRisk.high => 'We have missed you. The till is still here.',
      };

  /// Whether the shop should be nudged to come back (medium or high risk).
  bool get shouldNudge => risk.index >= ChurnRisk.medium.index;
}

/// Turns telemetry into a churn analysis.
///
/// Pure: no network, no database, just the events and the clock. A test can
/// drive it with a fixed date instead of waiting for real time to pass.
class ChurnAnalytics {
  ChurnAnalytics({this.now});

  /// The clock to use. Defaults to the real clock; a test can substitute a
  /// fixed one so churn risk is deterministic.
  final DateTime? now;

  DateTime get _now => now ?? DateTime.now();

  /// Analyse [telemetry] and return the churn picture.
  ChurnAnalysis analyse(TelemetryService telemetry) {
    final lastActive = telemetry.lastActiveDate;
    final streak = telemetry.streakCount;
    final sessions = telemetry.totalSessions;

    final daysSince = lastActive == null
        ? 999
        : _now
            .difference(
                DateTime(lastActive.year, lastActive.month, lastActive.day))
            .inDays;

    // --- Score (0.0 to 1.0) ---
    //
    // Streak component: a long streak lowers risk. Streak of 7+ is near-zero
    // streak risk; streak of 0 or 1 is full streak risk.
    final streakRisk =
        streak >= 7 ? 0.0 : (1.0 - (streak / 7.0).clamp(0.0, 1.0));

    // Silence component: days since last active. A week of silence is
    // significant risk; a month is near-certain churn.
    final silenceRisk = (daysSince / 30.0).clamp(0.0, 1.0);

    // Frequency component: total sessions. A shop that has opened once is
    // riskier than one that has opened a hundred times.
    final frequencyRisk =
        sessions >= 50 ? 0.0 : (1.0 - (sessions / 50.0).clamp(0.0, 1.0));

    // Weighted: silence matters most (a silent shop is gone), then streak,
    // then frequency. Weights sum to 1.0.
    final score =
        (silenceRisk * 0.5) + (streakRisk * 0.3) + (frequencyRisk * 0.2);

    // --- Risk level ---
    final risk = switch (score) {
      var s when s < 0.25 => ChurnRisk.none,
      var s when s < 0.50 => ChurnRisk.low,
      var s when s < 0.75 => ChurnRisk.medium,
      _ => ChurnRisk.high,
    };

    return ChurnAnalysis(
      streakDays: streak,
      daysSinceLastActive: daysSince,
      totalSessions: sessions,
      risk: risk,
      score: score,
    );
  }
}
