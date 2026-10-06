// What a difference between two amounts MEANS, resolved once.
//
// This exists because a variance is shown in three places on this screen — the
// live figure while a shift is open, the figure being committed when it closes,
// and the figure in the history afterwards — and each of those three previously
// re-derived the word, the tone and the sign from the money. That is three
// places to keep in agreement about the one thing an owner is reading the screen
// for, and a difference that renders green in one and amber in the other is how a
// real shortage gets argued about.
//
// Resolving it once also puts the accessibility channels in one place. A
// variance is a stateful meaning, so it gets the full treatment from
// [StatusTone]: a per-state GLYPH, a per-state WORD, and a monotonic weight, with
// colour derived from the value as the last step. Desaturate any screenshot of
// this screen and the shortage still says "Short".
//
// The catalogue is passed IN rather than read from a context: this is a value
// type with no widget above it, it is built inside `build()` methods that
// already hold one, and taking it as a parameter is what lets the whole thing be
// unit-tested in plain Dart.

import 'package:flutter/foundation.dart';

import '../l10n/generated/app_localizations.dart';
import '../ui/components/status.dart';
import '../utils/money.dart';

/// A difference between what should be in the drawer and what is, said three
/// ways at once.
@immutable
class ShiftVariance {
  const ShiftVariance({
    required this.difference,
    required this.tone,
    required this.word,
    required this.spoken,
  });

  /// The signed difference. Negative is short of the expected figure.
  final Money difference;

  /// The magnitude, sign dropped — what the cashier is told they are out by.
  Money get magnitude => difference.abs;

  /// Derived last, from the sign. Never read from a literal.
  final StatusTone tone;

  /// The chip's word. Two or three characters, because it sits next to a figure
  /// rather than replacing one.
  final String word;

  /// The whole sentence, for a screen reader. One node, so the state and the
  /// amount are heard together instead of as two stops.
  final String spoken;

  bool get isZero => difference.isZero;

  bool get isShort => difference.isNegative;

  /// Short is the alarming one and over is merely worth a note, because a drawer
  /// holding LESS than the ledger says is the only direction that can mean money
  /// left it. Someone paid with the wrong note and took change from the float is
  /// the same number as someone who walked out with a bottle.
  static ShiftVariance between(
    AppLocalizations l10n,
    Money counted,
    Money expected,
  ) {
    final Money difference = counted - expected;

    if (difference.isZero) {
      return ShiftVariance(
        difference: difference,
        tone: StatusTone.success,
        word: l10n.varianceBalanced,
        spoken: l10n.varianceBalancedSpoken,
      );
    }

    final String amount = formatMoney(difference.abs);

    return difference.isNegative
        ? ShiftVariance(
            difference: difference,
            tone: StatusTone.danger,
            word: l10n.varianceShort,
            spoken: l10n.varianceShortSpoken(amount),
          )
        : ShiftVariance(
            difference: difference,
            tone: StatusTone.warning,
            word: l10n.varianceOver,
            spoken: l10n.varianceOverSpoken(amount),
          );
  }

  /// A shift that has not been counted yet.
  ///
  /// A distinct state rather than a zero difference: "KSh 0 over" for a drawer
  /// nobody counted would be the worst possible reading of this screen, and it is
  /// what a naive `counted - expected` produces.
  static ShiftVariance notCounted(AppLocalizations l10n) => ShiftVariance(
        difference: Money.zero,
        tone: StatusTone.neutral,
        word: l10n.varianceNotCounted,
        spoken: l10n.varianceNotCountedSpoken,
      );
}
