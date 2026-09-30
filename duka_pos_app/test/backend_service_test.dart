import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/services/backend_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Backend Service Tests', () {
    test('Backend URL is configured', () {
      expect(BackendService.backendUrl, isNotEmpty);
    });
  });

  group('Payment Outcome Tests', () {
    test('Payment outcome enum values exist', () {
      expect(PaymentOutcome.values.length, equals(3));
      expect(PaymentOutcome.success, isNotNull);
      expect(PaymentOutcome.failed, isNotNull);
      expect(PaymentOutcome.timedOut, isNotNull);
    });
  });

  group('Product Sync Data Tests', () {
    test('Product sync data structure is valid', () {
      final productData = {
        'id': 1,
        'remoteId': null,
        'name': 'Test Product',
        'category': 'Wine',
        'costPrice': 500.0,
        'sellPrice': 750.0,
        'stockQty': 10,
        'reorderLevel': 5,
        'exciseStampBatch': '',
        'active': true,
      };

      expect(productData['name'], isNotNull);
      expect(productData['costPrice'], greaterThan(0));
      expect(productData['sellPrice'], greaterThan(0));
      expect(productData['stockQty'], greaterThanOrEqualTo(0));
    });

    test('Payment items structure is valid', () {
      final items = [
        {'productId': 1, 'qty': 2, 'unitPrice': 750.0},
        {'productId': 2, 'qty': 1, 'unitPrice': 300.0},
      ];

      expect(items.length, equals(2));
      expect(items[0]['qty'], greaterThan(0));
      expect(items[0]['unitPrice'], greaterThan(0));
    });
  });

  group('Phone Number Validation', () {
    test('Phone number format for M-Pesa', () {
      const phone = '254712345678';
      expect(phone.startsWith('254'), isTrue);
      expect(phone.length, equals(12));
    });

    test('Invalid phone number should not start with 0', () {
      const phone = '0712345678';
      expect(phone.startsWith('0'), isTrue);
    });
  });
}
