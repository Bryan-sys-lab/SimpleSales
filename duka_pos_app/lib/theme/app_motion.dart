import 'package:flutter/material.dart';

/// Duration ROLES and curve slots. Not numbers a widget invents.
///
/// Five roles, because five is what this app actually spends. A seventh role
/// nobody uses is a role nobody has thought about.
///
/// This app's motion dial is 3 of 10 (dense and fast). That shows up here as
/// short durations and one strong curve: a POS screen should acknowledge a
/// commit, not perform it. Every one of these collapses to
/// [Duration.zero] under `MediaQuery.disableAnimationsOf` — see [resolveMotion].
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    required this.instant,
    required this.fast,
    required this.normal,
    required this.slow,
    required this.feedbackBrief,
    required this.feedbackExtended,
    required this.skeletonDelay,
    required this.skeletonShimmer,
    required this.enter,
    required this.exit,
    required this.emphasized,
  });

  /// A press state and a chip toggle. Below the threshold where motion is
  /// readable as motion at all.
  final Duration instant;

  /// The workhorse: a row expanding, a value crossfading.
  final Duration fast;

  /// A screen transition, a sheet sliding up.
  final Duration normal;

  /// Reserved for the one celebratory moment (a completed sale), which must be
  /// skippable and must never block input.
  final Duration slow;

  /// How long a transient message stays up for a reader with no assistive
  /// navigation running. Five seconds is the platform default and is not long
  /// enough to read a sentence.
  final Duration feedbackBrief;

  /// The same message, for a screen-reader or switch-access user. Thirty seconds
  /// is not a punishment: it is the minimum for an announcement to land before
  /// the message dismisses itself.
  final Duration feedbackExtended;

  /// How long a load must be running before a skeleton appears.
  ///
  /// A behavioural THRESHOLD, not a duration of anything the user sees — the point
  /// is to not show it. Suppressing it here means a read that resolves in 80ms
  /// never flashes a grey placeholder.
  final Duration skeletonDelay;

  /// One pass of the skeleton shimmer. Long enough to read as motion rather than
  /// as a flicker.
  final Duration skeletonShimmer;

  /// Decelerating. Responsive: something arriving should arrive fast and settle.
  final Curve enter;

  /// Accelerating. Something leaving should leave decisively.
  final Curve exit;

  /// The standard curve for a state change that both leaves and arrives.
  ///
  /// A strong custom curve rather than a CSS built-in: `Curves.easeOut` spends
  /// too long in the middle and reads as mush on a 150ms transition.
  final Curve emphasized;

  /// The one place a widget asks "should this animate?".
  ///
  /// Collapses to `Duration.zero` — never to a shorter duration or a softer
  /// curve. A user who asked the OS to stop animations asked for stop, and a
  /// gentler animation is still an animation they cannot turn off.
  ///
  /// Note this is a top-level function, not a method on the extension: the flag
  /// comes from `MediaQuery`, which is an inherited widget with
  /// correct-by-construction invalidation. Routing it through a provider would
  /// trade a compiler-guaranteed rebuild for a frame of staleness.
  static Duration resolve(BuildContext context, Duration role) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : role;

  /// The curve for a transition that must still read as motion but with no
  /// elapsed time. `Curves.linear` is the honest pairing for `Duration.zero`:
  /// any curve at zero duration is a lie about the easing.
  static Curve resolveCurve(BuildContext context, Curve curve) =>
      MediaQuery.disableAnimationsOf(context) ? Curves.linear : curve;

  /// The one motion scale, identical in both brightnesses.
  static const AppMotion standard = AppMotion(
    instant: Duration(milliseconds: 90),
    fast: Duration(milliseconds: 150),
    normal: Duration(milliseconds: 220),
    slow: Duration(milliseconds: 320),
    feedbackBrief: Duration(seconds: 5),
    feedbackExtended: Duration(seconds: 30),
    skeletonDelay: Duration(milliseconds: 250),
    skeletonShimmer: Duration(milliseconds: 1100),
    enter: Curves.easeOutCubic,
    exit: Curves.easeInCubic,
    // cubic-bezier(0.23, 1, 0.32, 1) — the "expressive" standard curve.
    emphasized: Cubic(0.23, 1, 0.32, 1),
  );

  /// Reads the scale for the ambient theme.
  static AppMotion of(BuildContext context) =>
      Theme.of(context).extension<AppMotion>() ?? standard;

  @override
  AppMotion copyWith({
    Duration? instant,
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Duration? feedbackBrief,
    Duration? feedbackExtended,
    Duration? skeletonDelay,
    Duration? skeletonShimmer,
    Curve? enter,
    Curve? exit,
    Curve? emphasized,
  }) {
    return AppMotion(
      instant: instant ?? this.instant,
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
      feedbackBrief: feedbackBrief ?? this.feedbackBrief,
      feedbackExtended: feedbackExtended ?? this.feedbackExtended,
      skeletonDelay: skeletonDelay ?? this.skeletonDelay,
      skeletonShimmer: skeletonShimmer ?? this.skeletonShimmer,
      enter: enter ?? this.enter,
      exit: exit ?? this.exit,
      emphasized: emphasized ?? this.emphasized,
    );
  }

  /// Snaps durations (a half-faded 110ms theme change is a state no screen was
  /// laid out for) and interpolates the curves as their control points.
  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) {
    if (other is! AppMotion) return this;
    return AppMotion(
      instant: instant,
      fast: fast,
      normal: normal,
      slow: slow,
      feedbackBrief: feedbackBrief,
      feedbackExtended: feedbackExtended,
      skeletonDelay: skeletonDelay,
      skeletonShimmer: skeletonShimmer,
      enter: t < 0.5 ? enter : other.enter,
      exit: t < 0.5 ? exit : other.exit,
      emphasized: t < 0.5 ? emphasized : other.emphasized,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppMotion &&
          other.instant == instant &&
          other.fast == fast &&
          other.normal == normal &&
          other.slow == slow &&
          other.feedbackBrief == feedbackBrief &&
          other.feedbackExtended == feedbackExtended &&
          other.skeletonDelay == skeletonDelay &&
          other.skeletonShimmer == skeletonShimmer &&
          other.enter == enter &&
          other.exit == exit &&
          other.emphasized == emphasized;

  @override
  int get hashCode => Object.hash(
        instant,
        fast,
        normal,
        slow,
        feedbackBrief,
        feedbackExtended,
        skeletonDelay,
        skeletonShimmer,
        enter,
        exit,
        emphasized,
      );
}
