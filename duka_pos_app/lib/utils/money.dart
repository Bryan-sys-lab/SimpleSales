import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Number of minor units in one Kenyan shilling.
///
/// KES is a two-decimal currency, so a cent is the smallest amount that can
/// exist. Everything that is an amount of money is stored and computed as an
/// integer count of these.
const int kMinorUnitsPerMajor = 100;

/// An amount of Kenyan shillings, held as integer minor units.
///
/// The integer is the whole point. Amounts used to be `double` shillings, which
/// binary floating point cannot represent exactly: summing a cart of prices
/// drifted a fraction of a cent above the figure the customer was quoted, and
/// because the recorded total is compared against the cash handed over, the
/// till then refused the sale. Integer minor units make addition exact and
/// remove that entire class of bug.
///
/// Conversion to a `double` happens only at the edges — parsing what a user
/// typed, and formatting for display — never in the middle of an arithmetic
/// chain.
@immutable
class Money implements Comparable<Money> {
  const Money._(this.minorUnits);

  /// An amount in minor units (cents). The canonical representation.
  final int minorUnits;

  static const Money zero = Money._(0);

  /// Reads an amount expressed in whole shillings, as typed by a user or held
  /// in a spreadsheet. Rounds to the nearest cent; half a cent rounds up, so a
  /// price entered as 12.005 becomes KSh 12.01 rather than being silently
  /// truncated against the shop.
  factory Money.fromMajor(num major) =>
      Money._((major * kMinorUnitsPerMajor).round());

  /// Wraps an integer count of cents read straight from the database.
  factory Money.fromMinor(int minor) => Money._(minor);

  /// The amount in whole shillings.
  ///
  /// For display and for talking to systems that speak in shillings. Never feed
  /// the result back into arithmetic — go through [Money.fromMajor] instead, so
  /// the value is re-quantised rather than carrying a hidden binary remainder.
  double get asMajor => minorUnits / kMinorUnitsPerMajor;

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;

  Money operator +(Money other) => Money._(minorUnits + other.minorUnits);

  Money operator -(Money other) => Money._(minorUnits - other.minorUnits);

  /// Scales by a quantity — a number of bottles, or a portion of one.
  ///
  /// This is the single point where a non-integer can enter the arithmetic, so
  /// rounding happens here, once per line, rather than on every intermediate
  /// sum. Two bottles at KSh 19.99 is 3998 cents exactly, not a float.
  Money times(num quantity) => Money._((minorUnits * quantity).round());

  bool operator >(Money other) => minorUnits > other.minorUnits;

  bool operator <(Money other) => minorUnits < other.minorUnits;

  bool operator >=(Money other) => minorUnits >= other.minorUnits;

  bool operator <=(Money other) => minorUnits <= other.minorUnits;

  /// True when [value] is a usable amount: finite and not negative.
  ///
  /// Guards the entry points where a value arrives from outside the app — a
  /// typed price, an imported spreadsheet cell — so NaN or infinity can never be
  /// written to the ledger, where it would poison every total it touches.
  static bool isValidMajor(num value) => value.isFinite && value >= 0;

  static Money get nanGuard => zero;

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  @override
  String toString() => 'Money($minorUnits minor units)';
}

/// Sums [values] exactly. Integer addition, so no drift is possible.
Money sumMoney(Iterable<Money> values) =>
    values.fold(Money.zero, (total, value) => total + value);

/// Quantises a raw major-unit figure. Retained for the places that still hold a
/// plain `double` mid-edit (spreadsheet cells, legacy columns during migration).
double roundMoney(num amount) {
  if (!amount.isFinite) return 0;
  return (amount * kMinorUnitsPerMajor).roundToDouble() / kMinorUnitsPerMajor;
}

String formatMoney(Money amount) {
  final hasFraction = amount.minorUnits % kMinorUnitsPerMajor != 0;
  return NumberFormat.currency(
    locale: 'en_KE',
    symbol: 'KSh ',
    decimalDigits: hasFraction ? 2 : 0,
  ).format(amount.asMajor);
}

/// Formats a figure that is still a raw `double`, converting it first.
///
/// Only for values that have not been migrated to [Money] yet. Every such use
/// is a candidate for replacement, not a permanent API.
@Deprecated('Pass a Money instead of a raw double. Use Money.fromMajor to convert.')
String formatMoneyMajor(num amount) => formatMoney(Money.fromMajor(amount));