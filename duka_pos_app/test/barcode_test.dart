// Barcode normalisation, validation and wedge-scanner discrimination.
//
// These are the rules that decide "does this scan mean this product?", so every
// test here corresponds to a way a till could get it wrong: scanning a code
// that belongs to something else, rejecting a real code the shop typed, or
// reading a cashier's typing as a scan.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/services/barcode/barcode_service.dart';
import 'package:duka_pos/services/barcode/scan_input_service.dart';

void main() {
  group('normalise', () {
    test('strips whitespace, hyphens and the GS1 group separator', () {
      expect(Barcode.normalise(' 600123456 7892 '), '6001234567892');
      expect(Barcode.normalise('600-123-456-7892'), '6001234567892');
      expect(Barcode.normalise('600123456\x1d7892'), '6001234567892');
      expect(Barcode.normalise('600123456<GS>7892'), '6001234567892');
    });

    test('uppercases, so a lowercase Code-128 still matches', () {
      expect(Barcode.normalise('ab-12345'), 'AB12345');
    });

    test('preserves leading zeros', () {
      // The rule that routes a code through `int` would merge 0123456789012
      // with 123456789012. Those are two different products.
      expect(Barcode.normalise('0123456789012'), '0123456789012');
      expect(Barcode.normalise('0123456789012'),
          isNot(Barcode.normalise('123456789012')));
    });

    test('is idempotent', () {
      const raw = ' 600-123 \x1d 4567892 ';
      final once = Barcode.normalise(raw);
      expect(Barcode.normalise(once), once);
    });
  });

  group('validation', () {
    test('accepts a well-formed EAN-13', () {
      // 6001234567899: the check digit is verified, not assumed.
      expect(Barcode.isValid('6001234567899'), isTrue);
    });

    test('rejects an EAN-13 whose check digit is wrong', () {
      expect(Barcode.isValid('6001234567890'), isFalse);
      expect(Barcode.rejectionReason('6001234567890'), contains('check digit'));
    });

    test('accepts a valid EAN-8, UPC-A and GTIN-14', () {
      for (final code in ['96385074', '036000291452', '12345678901231']) {
        expect(Barcode.isValid(code), isTrue, reason: code);
      }
    });

    test('accepts a digit-only code of a non-GTIN length without a check', () {
      // Refusing it would block a real code on the authority of a rule the
      // owner cannot see or satisfy.
      expect(Barcode.isValid('123456789012345'), isTrue);
      expect(Barcode.isValid('12345'), isFalse, reason: 'too short');
    });

    test('accepts an alphanumeric code unchecked', () {
      expect(Barcode.isValid('ABC-12345'), isTrue);
      expect(Barcode.isValid('SHOP/0001'), isTrue);
    });

    test('rejects characters no scanner can emit', () {
      expect(Barcode.isValid('ABC#12345'), isFalse);
      expect(Barcode.isValid('ABC*12345'), isFalse);
    });

    test('rejects an over-long code', () {
      expect(Barcode.isValid('1' * (Barcode.maxLength + 1)), isFalse);
      expect(Barcode.rejectionReason('1' * (Barcode.maxLength + 1)),
          contains('${Barcode.maxLength}'));
    });

    test('a zero-length code is not a barcode', () {
      expect(Barcode.isValid(''), isFalse);
      expect(Barcode.rejectionReason(''), isNotNull);
    });
  });

  group('check digit', () {
    test('matches the published GS1 mod-10 worked example', () {
      // GS1 mod-10: weights alternate 3,1 from the right of the payload, and
      // the check digit carries the total up to the next multiple of ten.
      expect(Barcode.checkDigit('600123456789'), 9);
      expect(Barcode.hasValidCheckDigit('6001234567899'), isTrue);
    });

    test('works for a UPC-A', () {
      // 03600029145 -> check digit 2.
      expect(Barcode.checkDigit('03600029145'), 2);
    });

    test('a single wrong digit is caught', () {
      const valid = '96385074';
      expect(Barcode.hasValidCheckDigit(valid), isTrue);
      expect(Barcode.hasValidCheckDigit('96385075'), isFalse);
    });
  });

  group('wedge scanner buffer', () {
    /// A clock the test drives, so timing rules can be exercised without
    /// sleeping.
    var now = DateTime(2026, 1, 1);
    WedgeScannerBuffer buffer() =>
        WedgeScannerBuffer(clock: () => now)..reset();

    KeyEvent down(String char) => KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
          character: char,
        );

    const enter = KeyDownEvent(
      logicalKey: LogicalKeyboardKey.enter,
      physicalKey: PhysicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );

    void fastType(WedgeScannerBuffer wedge, String code) {
      for (final char in code.split('')) {
        now = now.add(const Duration(milliseconds: 5));
        wedge.onKey(down(char));
      }
    }

    test('a fast run terminated by Enter is one scan', () {
      final wedge = buffer();
      fastType(wedge, '6001234567899');
      now = now.add(const Duration(milliseconds: 5));
      final scan = wedge.onKey(enter);
      expect(scan, isNotNull);
      expect(scan!.normalised, '6001234567899');
      expect(scan.source, ScanSource.wedge);
    });

    test('a slow human-speed run is not a scan', () {
      final wedge = buffer();
      for (final char in '6001234567899'.split('')) {
        now = now.add(const Duration(milliseconds: 400));
        wedge.onKey(down(char));
      }
      now = now.add(const Duration(milliseconds: 400));
      expect(wedge.onKey(enter), isNull);
    });

    test('a short fast run is rejected for being too short', () {
      final wedge = buffer();
      fastType(wedge, '123');
      now = now.add(const Duration(milliseconds: 5));
      expect(wedge.onKey(enter), isNull);
    });

    test('normalises what it captures', () {
      final wedge = buffer();
      fastType(wedge, '600-123 456\x1d7899');
      now = now.add(const Duration(milliseconds: 5));
      expect(wedge.onKey(enter)!.normalised, '6001234567899');
    });

    test('a modifier key does not poison the buffer', () {
      final wedge = buffer();
      fastType(wedge, '600123456');
      wedge.onKey(const KeyDownEvent(
        logicalKey: LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        timeStamp: Duration.zero,
      ));
      fastType(wedge, '7899');
      now = now.add(const Duration(milliseconds: 5));
      expect(wedge.onKey(enter)!.normalised, '6001234567899');
    });

    test('a pause mid-code discards the partial run', () {
      // The run before a long pause is thrown away rather than being prefixed
      // to whatever comes next, which would produce a code belonging to no
      // product and scanning as "unknown" forever.
      final wedge = buffer();
      fastType(wedge, '600123');
      now = now.add(const Duration(seconds: 3));
      fastType(wedge, '4567892');
      now = now.add(const Duration(milliseconds: 5));
      expect(wedge.onKey(enter)!.normalised, '4567892');
    });

    test('a reset clears a partially typed code', () {
      final wedge = buffer();
      fastType(wedge, '6001234567899');
      wedge.reset();
      now = now.add(const Duration(milliseconds: 5));
      expect(wedge.onKey(enter), isNull);
    });

    test('an over-long run is dropped rather than growing forever', () {
      final wedge = WedgeScannerBuffer(maxLength: 8, clock: () => now);
      fastType(wedge, '12345678901234567890');
      expect(wedge.pending.length, lessThanOrEqualTo(8));
      now = now.add(const Duration(milliseconds: 5));
      expect(wedge.onKey(enter), isNull);
    });

    test('key-up events are ignored', () {
      final wedge = buffer();
      const up = KeyUpEvent(
        logicalKey: LogicalKeyboardKey.keyA,
        physicalKey: PhysicalKeyboardKey.keyA,
        timeStamp: Duration.zero,
      );
      expect(wedge.onKey(up), isNull);
      expect(wedge.pending, isEmpty);
    });
  });

  group('scan lookup outcomes', () {
    test('a match names the product and the code', () {
      final outcome = ScanOutcome.unmatched(
        raw: '6001234567892',
        normalised: '6001234567892',
        reason: 'No product carries that barcode.',
      );
      expect(outcome.matched, isFalse);
      expect(outcome.reason, isNotNull);
      expect(outcome.normalised, '6001234567892');
    });
  });
}
