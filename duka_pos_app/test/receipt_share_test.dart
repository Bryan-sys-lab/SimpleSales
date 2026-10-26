import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/services/receipt_share_service.dart';

void main() {
  test('receipt share storage masks phone numbers to their last four digits',
      () {
    expect(maskReceiptRecipient('+254 712 345 678'), '••••5678');
  });

  test('receipt share storage masks email local parts', () {
    expect(maskReceiptRecipient('amina@example.com'), 'a••••@example.com');
  });

  test('receipt share storage keeps no empty recipient', () {
    expect(maskReceiptRecipient('   '), isNull);
  });
}
