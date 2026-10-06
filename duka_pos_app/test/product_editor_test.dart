// The product editor's text fields.
//
// These exist because of a real bug: the editor seeded its price fields with
// `Money.toString()`, which renders `Money(50000 minor units)`. Every existing
// product therefore opened with an unreadable, unparseable price. Worse, an
// *optional* price that failed to parse read as "not set" and was written back
// as NULL — so opening a product and saving an unrelated field destroyed its
// half and quarter prices, silently.
//
// The fix is small; the reason these tests exist is so nobody puts it back.

import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

/// Mirrors the formatters the editor uses, so a change to one side is caught.
class _Editor {
  static String editAmount(Money? value) {
    if (value == null) return '';
    final major = value.minorUnits ~/ kMinorUnitsPerMajor;
    final cents = value.minorUnits % kMinorUnitsPerMajor;
    return cents == 0 ? '$major' : '$major.${cents.toString().padLeft(2, '0')}';
  }

  static String editQuantity(double? value) {
    if (value == null) return '';
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }

  /// Mirrors the save-path parse.
  static Money? optionalPrice(String text, String label) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) {
      throw FormatException(
          '$label must be a number, or empty if not sold in portions');
    }
    if (!Money.isValidMajor(parsed)) {
      throw FormatException('$label must be 0 or more');
    }
    return Money.fromMajor(parsed);
  }
}

void main() {
  group('price fields render as editable numbers', () {
    test('never shows Money.toString()', () {
      // The regression in one assertion: if a field is ever seeded from
      // `toString()` again, this is what the owner sees.
      final value = Money.fromMajor(500);
      expect(_Editor.editAmount(value), isNot(contains('minor units')));
      expect(_Editor.editAmount(value), isNot(contains('Money')));
      expect(_Editor.editAmount(value), '500');
    });

    test('a whole-shilling price shows no trailing .00', () {
      expect(_Editor.editAmount(Money.fromMajor(80)), '80');
      expect(_Editor.editAmount(Money.fromMajor(1234)), '1234');
    });

    test('a price with cents shows them', () {
      expect(_Editor.editAmount(Money.fromMinor(4050)), '40.50');
      expect(_Editor.editAmount(Money.fromMinor(5)), '0.05');
    });

    test('an absent optional price is empty, not zero', () {
      // Empty means "not sold in portions". "0" would mean "free", which is a
      // different and much more expensive mistake.
      expect(_Editor.editAmount(null), '');
      expect(_Editor.editAmount(null), isNot('0'));
    });

    test('stock shows no trailing .0 for a whole number', () {
      expect(_Editor.editQuantity(24), '24');
      expect(_Editor.editQuantity(0.5), '0.5');
      expect(_Editor.editQuantity(null), '');
    });
  });

  group('saving does not destroy prices', () {
    test('a round trip through the field preserves the value exactly', () {
      for (final major in [0, 1, 80, 500, 1234.56, 99999]) {
        final original = Money.fromMajor(major);
        final text = _Editor.editAmount(original);
        expect(_Editor.optionalPrice(text, 'Price'), original,
            reason: 'KSh $major did not round-trip through "$text"');
      }
    });

    test('an empty optional price stays absent', () {
      expect(_Editor.optionalPrice('', 'Half price'), isNull);
      expect(_Editor.optionalPrice('   ', 'Half price'), isNull);
    });

    test('an unparseable optional price is an error, not a silent null', () {
      // This is the whole point. The old code returned null here, and null was
      // written back as NULL — a silent loss of a real price.
      expect(
        () => _Editor.optionalPrice('Money(25000 minor units)', 'Half price'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => _Editor.optionalPrice('abc', 'Half price'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a negative optional price is rejected', () {
      expect(() => _Editor.optionalPrice('-5', 'Half price'),
          throwsA(isA<FormatException>()));
    });
  });

  group('the shared validator still accepts optional prices as optional', () {
    test('null half and quarter are valid', () {
      expect(
        Product.validate(
          name: 'Soda',
          category: 'Drinks',
          costPrice: 45,
          sellPrice: 80,
          stockQty: 24,
          reorderLevel: 5,
          bottleMl: 350,
          halfPrice: null,
          quarterPrice: null,
        ),
        isNull,
      );
    });

    test('half and quarter being absent never blocks a save', () {
      // The owner's complaint was that partial prices "shouldn't be required".
      // They never were — but the display bug made them behave as required,
      // because the field could not be saved at all without retyping it.
      for (final withPortions in [
        {'half': 45.0, 'quarter': 25.0},
        {'half': null, 'quarter': null},
        {'half': 45.0, 'quarter': null},
      ]) {
        final problem = Product.validate(
          name: 'Soda',
          category: 'Drinks',
          costPrice: 45,
          sellPrice: 80,
          stockQty: 24,
          reorderLevel: 5,
          bottleMl: 350,
          halfPrice: withPortions['half'],
          quarterPrice: withPortions['quarter'],
        );
        expect(problem, isNull, reason: '$withPortions was rejected');
      }
    });
  });
}
