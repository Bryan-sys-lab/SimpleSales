import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The moments a haptic can acknowledge.
///
/// An enum rather than a bare `String` at the call site: a typo in a string
/// would be a silent no-op at runtime, discovered by a user noticing their till
/// stopped buzzing.
enum HapticEvent {
  /// A value changed but nothing was written.
  select,

  /// A write landed.
  commit,

  /// Input refused.
  reject,

  /// A task completed.
  success,

  /// A genuinely rare moment — a shift closing balanced. Reached from at most one
  /// place in the app.
  milestone,
}

/// The haptic event map: a named slot per *event*, never an intensity at a call
/// site.
///
/// A call site says which moment happened (`AppHaptics.of(context).fire(
/// HapticEvent.commit)`); this class decides what that means in vibrations.
/// Scattering `HapticFeedback.mediumImpact()` through features is how an app
/// starts buzzing — intensities creep upward because each new moment "needs" to
/// be felt more than the last.
///
/// The intensity ceiling per event is deliberate and is the reason the map
/// exists:
///
/// | Slot        | Verb             | Meaning                                    |
/// |-------------|------------------|--------------------------------------------|
/// | `select`    | selectionClick   | A value changed but nothing was written      |
/// | `commit`    | lightImpact      | A write landed                              |
/// | `reject`    | lightImpact      | Input refused. Never `heavyImpact` — punishing a user for a mistake the UI could have prevented is not feedback, it's a scolding. |
/// | `success`   | mediumImpact     | A task completed                            |
/// | `milestone` | heavyImpact      | Reserved for a genuinely rare moment.       |
@immutable
class HapticTheme extends ThemeExtension<HapticTheme> {
  const HapticTheme({
    required this.select,
    required this.commit,
    required this.reject,
    required this.success,
    required this.milestone,
    required this.enabled,
  });

  /// Fires [HapticFeedback.selectionClick]. Never null.
  final Future<void> Function() select;

  /// Fires [HapticFeedback.lightImpact]. Never null.
  final Future<void> Function() commit;

  /// Fires [HapticFeedback.lightImpact]. Never null.
  final Future<void> Function() reject;

  /// Fires [HapticFeedback.mediumImpact]. Never null.
  final Future<void> Function() success;

  /// Fires [HapticFeedback.heavyImpact]. Never null, and called from at most one
  /// place in the app.
  final Future<void> Function() milestone;

  /// The single central gate. Every platform has its own coarse system-haptics
  /// setting, but a till operator who finds vibration distracting needs an
  /// in-app switch too — and it must be one gate, not a flag each call site
  /// remembers to check.
  final bool enabled;

  /// Fires one slot, at most, on the frame a state actually changed.
  ///
  /// Never call this from an animation listener, an `onEnd` callback, or a loop
  /// over items in a coalesced gesture: those three places turn one event into a
  /// rattle.
  void fire(HapticEvent event) {
    if (!enabled) return;
    switch (event) {
      case HapticEvent.select:
        select();
      case HapticEvent.commit:
        commit();
      case HapticEvent.reject:
        reject();
      case HapticEvent.success:
        success();
      case HapticEvent.milestone:
        milestone();
    }
  }

  /// Reads the map for the ambient theme.
  ///
  /// The fallback is the same value both `ThemeData`s carry — verified in
  /// `theme_token_test.dart` — so it is a constant, not an untested default.
  static HapticTheme of(BuildContext context) =>
      Theme.of(context).extension<HapticTheme>() ?? standard;

  static final HapticTheme standard = HapticTheme(
    select: HapticFeedback.selectionClick,
    commit: HapticFeedback.lightImpact,
    reject: HapticFeedback.lightImpact,
    success: HapticFeedback.mediumImpact,
    milestone: HapticFeedback.heavyImpact,
    enabled: true,
  );

  /// Silences every slot. The map still exists — the design still declares what
  /// *would* happen — which is what makes turning haptics back on a settings
  /// toggle rather than a code change.
  static final HapticTheme muted = HapticTheme(
    select: HapticFeedback.selectionClick,
    commit: HapticFeedback.lightImpact,
    reject: HapticFeedback.lightImpact,
    success: HapticFeedback.mediumImpact,
    milestone: HapticFeedback.heavyImpact,
    enabled: false,
  );

  /// Returns a copy with the central gate flipped, keeping every slot intact.
  HapticTheme withEnabled(bool value) => HapticTheme(
        select: select,
        commit: commit,
        reject: reject,
        success: success,
        milestone: milestone,
        enabled: value,
      );

  @override
  HapticTheme copyWith({
    Future<void> Function()? select,
    Future<void> Function()? commit,
    Future<void> Function()? reject,
    Future<void> Function()? success,
    Future<void> Function()? milestone,
    bool? enabled,
  }) {
    return HapticTheme(
      select: select ?? this.select,
      commit: commit ?? this.commit,
      reject: reject ?? this.reject,
      success: success ?? this.success,
      milestone: milestone ?? this.milestone,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Snaps: functions and a boolean gate are not interpolable, and the app
  /// bans theme animation, so `lerp` never runs.
  @override
  HapticTheme lerp(ThemeExtension<HapticTheme>? other, double t) =>
      t < 0.5 ? this : (other is HapticTheme ? other : this);

  /// Deliberately identity-based. These are top-level tear-offs to static
  /// plugin channels: two separately-constructed maps are behaviourally
  /// identical, and comparing closures structurally would make every theme
  /// rebuild look like a change.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}
