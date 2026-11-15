import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMoneyInput', () {
    test('reads plain numbers', () {
      expect(parseMoneyInput('1500'), 1500);
      expect(parseMoneyInput('  250.75 '), 250.75);
      expect(parseMoneyInput('.5'), 0.5);
    });

    test('reads what people actually type', () {
      expect(parseMoneyInput('1,500'), 1500);
      expect(parseMoneyInput('1,250,000'), 1250000);
      expect(parseMoneyInput('1 500'), 1500);
      expect(parseMoneyInput('1\u00A0500'), 1500);
      expect(parseMoneyInput("1'500"), 1500);
      expect(parseMoneyInput('KES 1500'), 1500);
      expect(parseMoneyInput('Ksh. 2,000.50'), 2000.5);
      expect(parseMoneyInput('kshs3000'), 3000);
    });

    test('a lone trailing comma with one or two digits is a decimal comma', () {
      expect(parseMoneyInput('12,5'), 12.5);
      expect(parseMoneyInput('12,50'), 12.5);
      // Three digits after the comma is a thousands separator.
      expect(parseMoneyInput('12,500'), 12500);
    });

    test('rejects anything that is not a plain non-negative number', () {
      expect(parseMoneyInput(null), isNull);
      expect(parseMoneyInput(''), isNull);
      expect(parseMoneyInput('   '), isNull);
      expect(parseMoneyInput('abc'), isNull);
      expect(parseMoneyInput('-5'), isNull);
      expect(parseMoneyInput('1.2.3'), isNull);
      expect(parseMoneyInput('12abc'), isNull);
      expect(parseMoneyInput('NaN'), isNull);
      expect(parseMoneyInput('Infinity'), isNull);
    });

    test('feeds Money.fromMajor without a hidden remainder', () {
      expect(Money.fromMajor(parseMoneyInput('1,500.10')!).minorUnits, 150010);
    });
  });
}
