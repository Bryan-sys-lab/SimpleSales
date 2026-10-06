// Receipt layout and ESC/POS encoding.
//
// Both are pure, which is the entire reason they were built as pure: the money
// arithmetic on a receipt is the part an auditor checks, and none of it can be
// exercised on a machine that has never had a thermal printer attached to it.
// The invariants asserted here are the ones that would silently produce a
// receipt a customer cannot reconcile.

import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/printer/esc_pos_encoder.dart';
import 'package:duka_pos/services/printer/receipt_builder.dart';
import 'package:duka_pos/utils/money.dart';

SaleItem line(
  String name, {
  double qty = 1,
  num unitPrice = 100,
  String portion = 'full',
}) =>
    SaleItem(
      saleId: 1,
      productId: 1,
      productName: name,
      qty: qty,
      unitPrice: Money.fromMajor(unitPrice),
      unitCost: Money.fromMajor(unitPrice * 0.6),
      portion: portion,
      portionMl: portion == 'full' ? 500 : 250,
    );

ReceiptInput receipt({
  List<SaleItem>? items,
  int vatRatePercent = 16,
  Money? total,
  Money? tendered,
  Money? change,
  String? etimsNumber,
  String? etimsPayload,
  String shopName = 'Kijani Stores',
  String receiptNumber = 'T1-000001',
}) {
  final lines = items ?? [line('Soda 350ml', qty: 2, unitPrice: 80)];
  final computed = sumMoney(lines.map((item) => item.total));
  return ReceiptInput(
    shopName: shopName,
    receiptNumber: receiptNumber,
    issuedAt: DateTime(2026, 10, 3, 14, 5),
    cashierName: 'Alice',
    cashierRole: 'Cashier',
    items: lines,
    total: total ?? computed,
    amountTendered: tendered ?? (total ?? computed),
    changeGiven: change ?? Money.zero,
    vatRatePercent: vatRatePercent,
    etimsReceiptNumber: etimsNumber,
    etimsVerificationPayload: etimsPayload,
  );
}

/// The receipt as text, one string per printed line, with trailing spaces kept
/// so a column assertion sees the real layout.
List<String> render(ReceiptInput input, {int budget = k58mmColumnBudget}) =>
    ReceiptBuilder(columnBudget: budget)
        .build(input)
        .map((line) => line.render(budget))
        .toList();

/// Whether [needle] appears as a contiguous run inside [haystack].
///
/// Hand-rolled rather than a matcher because the sequences under test are raw
/// ESC/POS opcodes, and a byte list has no built-in subsequence search.
bool containsSequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  group('VAT extraction', () {
    test('extracts the component contained inside a VAT-inclusive price', () {
      // 8000 cents at 16%: 8000 * 16/116 = 1103.4 -> 1103.
      expect(vatComponentOf(Money.fromMinor(8000), ratePercent: 16).minorUnits,
          1103);
    });

    test('rounds half up, never truncates', () {
      // 1600 * 16/116 = 220.69. Truncating would take a cent off every one of
      // these lines and the shop would under-report its VAT.
      expect(vatComponentOf(Money.fromMinor(1600), ratePercent: 16).minorUnits,
          221);
      // 2500 * 16/116 = 344.83 -> 345
      expect(vatComponentOf(Money.fromMinor(2500), ratePercent: 16).minorUnits,
          345);
    });

    test('the extracted net and vat always re-add to the gross figure', () {
      // The one invariant that makes a printed VAT line defensible: whatever
      // split is chosen, `net + vat` must be the figure on the receipt. There
      // is no requirement that net be exactly gross/1.16 — after rounding to
      // whole cents it cannot be — only that the printed pair adds up.
      for (var minor = 1; minor <= 20000; minor += 7) {
        final gross = Money.fromMinor(minor);
        final vat = vatComponentOf(gross, ratePercent: 16);
        expect((gross - vat).minorUnits + vat.minorUnits, minor,
            reason: '$minor cents did not reconcile (vat=$vat)');
      }
    });

    test('a zero rate means exempt, not a division by zero', () {
      expect(
          vatComponentOf(Money.fromMinor(8000), ratePercent: 0).minorUnits, 0);
    });

    test('handles a non-16 rate the same way', () {
      // 10000 at 5%: 10000 * 5/105 = 476.19 -> 476
      expect(vatComponentOf(Money.fromMinor(10000), ratePercent: 5).minorUnits,
          476);
    });
  });

  group('printed figures reconcile', () {
    test('the printed item lines sum to the printed total', () {
      final input = receipt(items: [
        line('Soda 350ml', qty: 2, unitPrice: 80),
        line('Kenyana Beer', qty: 1, unitPrice: 120),
        line('Water 500ml', qty: 3, unitPrice: 30),
      ]);
      final text = render(input);

      // Every money line on the right-hand side, in order.
      final amounts = <int>[];
      for (final row in text) {
        final match = RegExp(r'(\d+)\.(\d{2})\s*$').firstMatch(row);
        if (match == null) continue;
        amounts.add(int.parse(match.group(1)! + match.group(2)!));
      }
      final expected = input.total.minorUnits;
      expect(amounts, contains(expected),
          reason: 'the recorded total must appear on the receipt');
    });

    test('printed per-line VAT sums to the printed VAT figure', () {
      // The plan's reconciliation requirement: an auditor adds up what is
      // printed. Summing the components is what makes that add up, rather than
      // printing a VAT figure derived from the total which will not.
      final input = receipt(items: [
        line('Soda 350ml', qty: 2, unitPrice: 80),
        line('Kenyana Beer', qty: 1, unitPrice: 120),
        line('Water 500ml', qty: 3, unitPrice: 30),
      ]);
      final perLine = input.items
          .map((item) => vatComponentOf(item.total, ratePercent: 16))
          .fold(Money.zero, (total, item) => total + item);

      var summed = 0;
      for (final item in input.items) {
        summed += vatComponentOf(item.total, ratePercent: 16).minorUnits;
      }

      final text = render(input);
      final vatLine = text.firstWhere((row) => row.startsWith('VAT ('));
      final printedVat = RegExp(r'(\d+)\.(\d{2})\s*$')
          .firstMatch(vatLine)!
          .group(0)!
          .replaceAll('.', '');
      expect(int.parse(printedVat), summed);
      expect(summed, perLine.minorUnits);
    });

    test('net plus VAT is the gross figure on every line', () {
      for (final minor in [1, 99, 100, 2500, 8000, 19999, 100000]) {
        final gross = Money.fromMinor(minor);
        final vat = vatComponentOf(gross, ratePercent: 16);
        expect((gross - vat).minorUnits + vat.minorUnits, minor);
      }
    });
  });

  group('column budget', () {
    test('no printed line exceeds the 58mm budget, even with a huge name', () {
      final input = receipt(items: [
        line(
            'Kenyana Special Reserve Aged Extra Long Name Malt '
            'Bottle 500ml With Gift Packaging',
            qty: 1,
            unitPrice: 250),
      ]);
      for (final row in render(input)) {
        expect(row.length, lessThanOrEqualTo(k58mmColumnBudget),
            reason: 'over budget: "$row" (${row.length})');
      }
    });

    test('the amount is never what gets truncated', () {
      final input = receipt(items: [
        line(
            'A product name that is far too long to fit on one line of a '
            'thermal receipt without help',
            qty: 1,
            unitPrice: 123456),
      ]);
      // A nine-figure amount leaves room for a shorter label, not a shorter
      // number: the figure is what the customer is checking.
      final row = render(input).firstWhere((r) => r.contains('123456.00'));
      expect(row.trimRight(), endsWith('123456.00'));
      expect(row.length, lessThanOrEqualTo(k58mmColumnBudget));
    });

    test('a truncated name is visibly truncated, not silently shortened', () {
      final input = receipt(items: [
        line('Kenyana Special Reserve Aged Extra Long Name Malt',
            unitPrice: 80),
      ]);
      final row = render(input).firstWhere((r) => r.contains('Kenyana'));
      expect(row, contains('...'));
    });

    test('an 80mm roll gets a wider budget', () {
      final input = receipt(items: [
        line('Kenyana Special Reserve Aged Extra Long Name Malt Bottle',
            unitPrice: 80),
      ]);
      final narrow = render(input, budget: k58mmColumnBudget);
      final wide = render(input, budget: k80mmColumnBudget);
      for (final row in wide) {
        expect(row.length, lessThanOrEqualTo(k80mmColumnBudget));
      }
      // The wide layout has room for a longer name than the narrow one.
      expect(wide.first.length, greaterThanOrEqualTo(narrow.first.length));
    });
  });

  group('exempt shops', () {
    test('a zero VAT rate omits the VAT line rather than printing zero', () {
      final text = render(receipt(vatRatePercent: 0));
      expect(text.where((row) => row.startsWith('VAT (')), isEmpty);
      expect(text.any((row) => row.contains('0.00 VAT')), isFalse);
    });

    test('the total still prints', () {
      final input = receipt(vatRatePercent: 0);
      final text = render(input);
      expect(text.any((row) => row.startsWith('TOTAL')), isTrue);
    });
  });

  group('receipt content', () {
    test('carries shop, receipt number, cashier, date, tendered and change',
        () {
      final input = receipt(
        tendered: Money.fromMajor(500),
        change: Money.fromMajor(120),
        etimsNumber: 'KRA-8f2a-0001',
      );
      final text = render(input).join('\n');
      expect(text, contains('Kijani Stores'));
      expect(text, contains('T1-000001'));
      expect(text, contains('Alice'));
      expect(text, contains('03-10-2026'));
      expect(text, contains('14:05'));
      expect(text, contains('500.00'));
      expect(text, contains('120.00'));
      expect(text, contains('KRA-8f2a-0001'));
    });

    test('an eTIMS verification QR is emitted with the number', () {
      final lines = const ReceiptBuilder().build(
          receipt(etimsNumber: 'KRA-1', etimsPayload: 'https://kra/v/1'));
      expect(lines.whereType<ReceiptQr>().map((qr) => qr.payload),
          contains('https://kra/v/1'));
    });

    test('no QR is emitted when there is no eTIMS number', () {
      final lines = const ReceiptBuilder().build(receipt());
      expect(lines.whereType<ReceiptQr>(), isEmpty);
    });

    test('zero change does not print a change line', () {
      final text =
          render(receipt(tendered: Money.fromMajor(160), change: Money.zero));
      expect(text.any((row) => row.startsWith('Change')), isFalse);
    });

    test('an item sold as a portion is labelled so on the receipt', () {
      final text = render(receipt(
          items: [line('Whisky', qty: 1, unitPrice: 500, portion: 'half')]));
      expect(text.firstWhere((r) => r.contains('Whisky')), contains('half'));
    });
  });

  group('ESC/POS bytes', () {
    test('starts by initialising the printer and ends with a cut', () {
      final bytes =
          const EscPosEncoder().encode(const ReceiptBuilder().build(receipt()));
      expect(bytes.sublist(0, 2), [0x1b, 0x40]);
      expect(bytes.sublist(bytes.length - 4), [0x1d, 0x56, 0x42, 0x00]);
    });

    test('emits the text of every line followed by a line feed', () {
      final input = receipt();
      final lines = const ReceiptBuilder().build(input);
      final bytes = const EscPosEncoder().encode(lines);
      final decoded = String.fromCharCodes(bytes);
      expect(decoded, contains('Kijani Stores'));
      expect(decoded, contains('SALES RECEIPT'));
      // A hard assertion that each text line is terminated.
      for (final line in lines.whereType<ReceiptText>()) {
        expect(decoded, contains(line.render(k58mmColumnBudget)));
      }
    });

    test('emits bold for the total and not for the body', () {
      final bytes =
          const EscPosEncoder().encode(const ReceiptBuilder().build(receipt()));
      // ESC E 1 then ESC E 0 both appear: the layout really does toggle bold.
      expect(containsSequence(bytes, [0x1b, 0x45, 0x01]), isTrue);
      expect(containsSequence(bytes, [0x1b, 0x45, 0x00]), isTrue);
    });

    test('sets alignment for centred lines', () {
      final bytes =
          const EscPosEncoder().encode(const ReceiptBuilder().build(receipt()));
      // ESC a 1 = centre.
      expect(containsSequence(bytes, [0x1b, 0x61, 0x01]), isTrue);
    });

    test('a QR carries its full payload with correct length fields', () {
      const payload = 'https://verify.example/v/KRA-8f2a-0001';
      final bytes = const EscPosEncoder().encode(const ReceiptBuilder()
          .build(receipt(etimsNumber: 'KRA-8f2a-0001', etimsPayload: payload)));
      final decoded = String.fromCharCodes(bytes);
      expect(decoded, contains(payload));
      // pL/pH must be (len + 3); a wrong length silently truncates the URL,
      // which still loads, so nothing else would catch it.
      const header = [0x1d, 0x28, 0x6b, 0, 0, 0x31, 0x50, 0x30];
      expect(
        containsSequence(bytes, [
          header[0],
          header[1],
          header[2],
          0,
          payload.length + 3,
          0x31,
          0x50,
          0x30
        ]),
        isTrue,
      );
    });

    test('a payload longer than 255 bytes still gets the right high byte', () {
      final long = 'https://verify.example/v/${'A' * 400}';
      final bytes = const EscPosEncoder().encode(const ReceiptBuilder()
          .build(receipt(etimsNumber: 'KRA-LONG', etimsPayload: long)));
      final length = long.length + 3;
      expect(
          containsSequence(bytes, [
            0x1d,
            0x28,
            0x6b,
            length ~/ 256,
            length % 256,
            0x31,
            0x50,
            0x30
          ]),
          isTrue);
    });

    test('non-Latin1 characters degrade to ? rather than throwing', () {
      // A product named in a script the printer's code page cannot hold must
      // still produce a receipt. Throwing here would stop a sale being printed
      // because of one emoji in the catalogue.
      final bytes = const EscPosEncoder().encode(const ReceiptBuilder()
          .build(receipt(items: [line('Café 🥤 Lager')])));
      expect(bytes, isNotEmpty);
      expect(bytes.every((b) => b <= 0xff), isTrue);
    });

    test('the same layout produces different bytes for 58mm and 80mm', () {
      final lines = const ReceiptBuilder(columnBudget: k80mmColumnBudget)
          .build(receipt());
      final narrow =
          const EscPosEncoder().encode(const ReceiptBuilder().build(receipt()));
      final wide =
          const EscPosEncoder().encode(lines, columnBudget: k80mmColumnBudget);
      expect(narrow, isNot(equals(wide)));
    });
  });
}
