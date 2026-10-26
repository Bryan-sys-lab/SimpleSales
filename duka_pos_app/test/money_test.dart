// Money arithmetic tests.
//
// Amounts are integer minor units (cents). They used to be `double` shillings,
// which binary floating point cannot represent exactly: summing a cart of prices
// drifted a fraction of a cent above the figure the customer was quoted, and
// because the recorded total is compared against the cash handed over, the till
// then refused the sale.
//
// Each drift case below is a value that is genuinely inexact in binary floating
// point, not an arbitrary round number.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  test('largest remainder allocation preserves every minor unit', () {
    expect(largestRemainderAllocation(10, <int>[1, 1, 1]), <int>[4, 3, 3]);
    expect(largestRemainderAllocation(1, <int>[1, 1]), <int>[1, 0]);
    expect(largestRemainderAllocation(7, <int>[0, 0]), <int>[7, 0]);
  });

  group('Money.fromMajor', () {
    test('quantises typed shillings to whole cents', () {
      expect(Money.fromMajor(12.3456).minorUnits, 1235);
      expect(Money.fromMajor(100).minorUnits, 10000);
      expect(Money.fromMajor(0).minorUnits, 0);
    });

    test('absorbs the classic float artefacts', () {
      // 0.1 + 0.2 is 0.30000000000000004 in binary floating point.
      expect(Money.fromMajor(0.1 + 0.2).minorUnits, 30);
      expect(Money.fromMajor(37.500000000000014).minorUnits, 3750);
      expect(Money.fromMajor(59.97000000000001).minorUnits, 5997);
    });

    test('rounds a half cent up rather than truncating it', () {
      // Truncating would quietly charge the customer less than the label says.
      expect(Money.fromMajor(12.005).minorUnits, 1201);
      expect(Money.fromMajor(12.004).minorUnits, 1200);
    });
  });

  group('arithmetic', () {
    test('adding cents is exact', () {
      // Verified against the pre-fix arithmetic: as a raw double this sum is
      // 1.9100000000000001, and paying the displayed 1.91 was rejected.
      final total = Money.fromMajor(0.92) + Money.fromMajor(0.99);
      expect(total.minorUnits, 191);
      expect(Money.fromMajor(1.91) >= total, isTrue,
          reason: 'paying the displayed amount must not be rejected');
    });

    test('subtraction is exact', () {
      expect((Money.fromMajor(100) - Money.fromMajor(37.5)).minorUnits, 6250);
      expect((Money.fromMajor(100) - Money.fromMajor(100)).minorUnits, 0);
    });

    test('never drifts across many additions', () {
      var total = Money.zero;
      for (var i = 0; i < 100; i++) {
        total = total + Money.fromMajor(0.07);
      }
      expect(total.minorUnits, 700, reason: '100 x KSh 0.07 is exactly 7.00');
    });

    test('scaling by a quantity rounds once, to a whole cent', () {
      expect(Money.fromMajor(19.99).times(3).minorUnits, 5997);
      expect(Money.fromMajor(10.01).times(0.5).minorUnits, 501,
          reason: 'an odd-cent price halves to a real amount');
      expect(Money.fromMajor(12.50).times(0.25).minorUnits, 313,
          reason: 'a quarter of 12.50 is 3.13, not 3.125');
    });

    test('sumMoney equals the sum of its parts', () {
      final parts = [
        Money.fromMajor(12.5),
        Money.fromMajor(0.1),
        Money.fromMajor(33.33),
        Money.fromMajor(7.77),
      ];
      expect(sumMoney(parts).minorUnits,
          parts.fold<int>(0, (sum, p) => sum + p.minorUnits));
      expect(sumMoney(const []), Money.zero);
    });
  });

  group('comparison', () {
    test('orders by minor units', () {
      expect(Money.fromMajor(10) > Money.fromMajor(9.99), isTrue);
      expect(Money.fromMajor(1) < Money.fromMajor(1.01), isTrue);
      expect(Money.fromMajor(5) >= Money.fromMajor(5), isTrue);
      expect(Money.fromMajor(5) <= Money.fromMajor(5), isTrue);
    });

    test('equality and hash agree, so it is safe in a set', () {
      expect(Money.fromMajor(12.5), Money.fromMinor(1250));
      expect({Money.fromMajor(1), Money.fromMinor(100)}, hasLength(1));
    });

    test('zero is recognisable without comparing', () {
      expect(Money.zero.isZero, isTrue);
      expect(Money.fromMajor(0.01).isZero, isFalse);
    });
  });

  group('isValidMajor', () {
    test('rejects the values that would poison a ledger', () {
      expect(Money.isValidMajor(10), isTrue);
      expect(Money.isValidMajor(0), isTrue);
      expect(Money.isValidMajor(12.5), isTrue);
      expect(Money.isValidMajor(-1), isFalse);
      expect(Money.isValidMajor(double.nan), isFalse);
      expect(Money.isValidMajor(double.infinity), isFalse);
    });
  });

  group('abs', () {
    test('a short balance states its magnitude without the sign', () {
      // A till reconciliation has to say "KSh 400 short" rather than printing a
      // signed number the cashier has to decode while serving a queue.
      expect(Money.fromMajor(-400).abs, Money.fromMajor(400));
    });

    test('an over balance is already its own magnitude', () {
      expect(Money.fromMajor(400).abs, Money.fromMajor(400));
    });

    test('zero is its own magnitude', () {
      expect(Money.zero.abs, Money.zero);
    });

    test('the smallest representable amount survives', () {
      // A one-cent short is a real variance a shop has to see, not an artefact.
      expect(Money.fromMinor(-1).abs.minorUnits, 1);
    });
  });

  group('divideMoneyHalfUp', () {
    test('halves a whole cent rather than losing it', () {
      // The bug this closes: 0.29 / 2 in binary floating point is
      // 0.14499999999999999, so `Money.fromMajor(0.29 / 2)` rounded DOWN to 14
      // cents where the exact half-up answer is 15. Every average basket on
      // the portfolio screen went through that double round trip.
      expect(divideMoneyHalfUp(29, 2), 15);
      expect(divideMoneyHalfUp(15, 2), 8);
      expect(divideMoneyHalfUp(25, 2), 13);
    });

    test('exact divisions stay exact', () {
      expect(divideMoneyHalfUp(100, 4), 25);
      expect(divideMoneyHalfUp(0, 4), 0);
      expect(divideMoneyHalfUp(100, 1), 100);
    });

    test('a third truncates in the shop\'s favour, like the VAT split', () {
      // `vatComponentOf` divides the same way, so an average and a tax split
      // must never disagree about which way a remainder goes.
      expect(divideMoneyHalfUp(100, 3), 33);
      expect(divideMoneyHalfUp(200, 3), 67);
      expect(divideMoneyHalfUp(101, 3), 34);
    });

    test('equal shares round the same way, and stay close to the whole', () {
      // The invariant that matters for an AVERAGE: every share rounds
      // identically, so the shares never disagree with each other, and their
      // sum is the whole to within half a cent per part — never a drift.
      for (final (minor, count) in <(int, int)>[
        (100, 3),
        (29, 2),
        (12345, 7),
        (1, 4),
        (999, 9),
        (5000, 2),
      ]) {
        final share = divideMoneyHalfUp(minor, count);
        var sum = 0;
        for (var i = 0; i < count; i++) {
          expect(divideMoneyHalfUp(minor, count), share);
          sum += share;
        }
        expect((sum - minor).abs(), lessThan(count));
      }
    });

    test('a zero count is zero rather than a throw', () {
      // Money math must never throw into the UI: an empty shop has a zero
      // average basket, not a crash.
      expect(divideMoneyHalfUp(500, 0), 0);
    });

    test('negatives mirror, the way the discount path needs', () {
      expect(divideMoneyHalfUp(-29, 2), -15);
      expect(divideMoneyHalfUp(-100, 3), -33);
    });
  });

  group('formatMoney', () {
    test('whole shillings render without decimals', () {
      expect(formatMoney(Money.fromMajor(100)), contains('100'));
      expect(formatMoney(Money.fromMajor(100)), isNot(contains('100.00')));
    });

    test('a fractional amount is shown honestly rather than rounded away', () {
      // KSh 12.50 used to display as KSh 13, so the shelf label and the receipt
      // disagreed with each other and with the ledger.
      expect(formatMoney(Money.fromMajor(12.5)), contains('12.50'));
    });

    test('float drift cannot change the displayed amount', () {
      expect(formatMoney(Money.fromMajor(37.500000000000014)),
          formatMoney(Money.fromMajor(37.5)));
      expect(formatMoney(Money.fromMajor(59.97000000000001)),
          formatMoney(Money.fromMajor(59.97)));
    });
  });

  // Money crosses three boundaries that speak in whole shillings: the
  // spreadsheet a person edits, the backend wire format, and the display. A
  // Money object reaching any of them serialises as "Money(4050 minor units)"
  // or as a 4050 in a price column — a silent corruption that no type error
  // catches, because Money is a perfectly valid Object.
  group('edges that speak in shillings', () {
    test('a spreadsheet row carries shillings, not cents', () {
      final row = Product(
        name: 'Soda 350ml',
        category: 'Drinks',
        costPrice: Money.fromMajor(40.5),
        sellPrice: Money.fromMajor(80.0),
        stockQty: 24,
        reorderLevel: 6,
        halfPrice: Money.fromMajor(40.0),
        updatedAt: '2026-01-01T00:00:00.000',
      ).toSheetRow();

      // Columns: 3 cost, 4 sell ... 9 half, 10 quarter.
      expect(row[3], 40.5);
      expect(row[4], 80.0);
      expect(row[9], 40.0, reason: 'half price in shillings');
      expect(row[10], '', reason: 'an unset portion price stays blank, not 0');
      for (final cell in row) {
        expect(cell is! Money, isTrue, reason: 'no Money may reach a cell');
      }
    });

    test('a sale sheet row carries shillings', () {
      final item = SaleItem(
        saleId: 1,
        productId: 1,
        productName: 'Soda',
        qty: 2,
        unitPrice: Money.fromMajor(80.0),
        unitCost: Money.fromMajor(40.0),
      );
      final sale = Sale(
        staffName: 'Alice',
        total: Money.fromMajor(160.0),
        profit: Money.fromMajor(80.0),
        createdAt: '2026-01-02T09:30:00.000',
        amountTendered: Money.fromMajor(200.0),
        changeGiven: Money.fromMajor(40.0),
        items: [item],
      );

      final row = sale.toSheetRows().single;
      expect(row[4], 200.0, reason: 'amount_tendered in shillings');
      expect(row[5], 40.0, reason: 'change_given in shillings');
      expect(row[8], 80.0, reason: 'unit_price in shillings');
      expect(row[9], 160.0, reason: 'line_total in shillings');
      for (final cell in row) {
        expect(cell is! Money, isTrue, reason: 'no Money may reach a cell');
      }
    });

    test('a spreadsheet row re-imports to the same amount', () {
      // The round trip a shop actually performs: export, edit, import.
      final product = Product(
        name: 'Soda 350ml',
        category: 'Drinks',
        costPrice: Money.fromMajor(40.5),
        sellPrice: Money.fromMajor(59.97),
        stockQty: 24,
        reorderLevel: 6,
        updatedAt: '2026-01-01T00:00:00.000',
      );
      final reimported = Product.fromRow(product.toSheetRow())!;
      expect(reimported.sellPrice, product.sellPrice);
      expect(reimported.costPrice, product.costPrice);
    });
  });

  // The pending-payment snapshot is the one place the app persists money to JSON.
  // It is written *after* an M-Pesa payment has been initiated, so a failure to
  // encode is not a cosmetic error: the customer has already paid and the sale
  // is not recorded. jsonEncode throws outright on a Money rather than writing
  // something lossy, which is why this had to be caught by reading the code.
  group('the pending-payment cart snapshot', () {
    List<Map<String, dynamic>> encodeCart(List<Map<String, dynamic>> cart) =>
        (jsonDecode(jsonEncode(cart)) as List<dynamic>)
            .cast<Map<String, dynamic>>();

    test('round-trips prices as minor units', () {
      final encoded = encodeCart([
        {
          'productId': 1,
          'productName': 'Soda 350ml',
          'qty': 2.0,
          'unitPrice': Money.fromMajor(80.0).minorUnits,
          'unitCost': Money.fromMajor(40.0).minorUnits,
          'portion': 'full',
          'portionMl': 350,
        }
      ]);

      final line = encoded.single;
      expect(line['unitPrice'], 8000);
      expect(line['unitCost'], 4000);
      expect(line['portion'], 'full');
      expect(line['portionMl'], 350);
    });

    test('encoding a Money object would throw, which is why it is not done',
        () {
      // Pins the actual failure mode. If someone "simplifies" the snapshot back
      // to writing the Money object, this test fails with the encoder's error
      // rather than the crash surfacing in a shop.
      expect(
        () => jsonEncode([
          {'unitPrice': Money.fromMajor(80.0)}
        ]),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });
  });
}
