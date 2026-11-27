import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Backend Service Tests', () {
    test('Backend URL is configured', () {
      expect(BackendService.backendUrl, isNotEmpty);
    });

    test('external presigned storage origins are not treated as API calls', () {
      final backend = Uri.parse(BackendService.backendUrl);
      expect(
        BackendService.isBackendOriginForTesting(backend),
        isTrue,
      );
      expect(
        BackendService.isBackendOriginForTesting(
          Uri.parse('https://r2.example.test/signed-upload'),
        ),
        isFalse,
      );
    });

    test(
        'staff auth rejection is authoritative while missing response is offline fallback',
        () {
      expect(
        BackendService.isAuthoritativeStaffAuthenticationRejection(
          <String, dynamic>{'_rejected': true},
        ),
        isTrue,
      );
      expect(
        BackendService.isAuthoritativeStaffAuthenticationRejection(null),
        isFalse,
      );
      expect(
        BackendService.isAuthoritativeStaffAuthenticationRejection(
          <String, dynamic>{'session_token': 'token'},
        ),
        isFalse,
      );
    });

    test('staff sync defers authorization and transient failures', () {
      final requestOptions = RequestOptions(path: '/api/tenant/staff/sync');
      final unauthorized = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 401,
        ),
      );
      final connectionFailure = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionError,
      );

      expect(
        BackendService.isDeferrableStaffSyncError(unauthorized),
        isTrue,
      );
      expect(
        BackendService.isDeferrableStaffSyncError(connectionFailure),
        isTrue,
      );
    });

    test('staff sync does not defer server-side conflicts', () {
      final requestOptions = RequestOptions(path: '/api/tenant/staff/sync');
      final conflict = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 409,
        ),
      );

      expect(
        BackendService.isDeferrableStaffSyncError(conflict),
        isFalse,
      );
    });
  });

  group('Payment Outcome Tests', () {
    test('provider review and terminal statuses remain distinct', () {
      expect(
        BackendService.paymentOutcomeFromProviderStatus('SUCCESS'),
        PaymentOutcome.success,
      );
      expect(
        BackendService.paymentOutcomeFromProviderStatus('FAILED'),
        PaymentOutcome.failed,
      );
      expect(
        BackendService.paymentOutcomeFromProviderStatus('REQUIRES_REVIEW'),
        PaymentOutcome.reviewRequired,
      );
      expect(
        BackendService.paymentOutcomeFromProviderStatus('PENDING'),
        isNull,
      );
    });

    test('authentication failures are not treated as payment failures', () {
      expect(
        BackendService.paymentOutcomeFromHttpStatus(401),
        PaymentOutcome.sessionExpired,
      );
      expect(
        BackendService.paymentOutcomeFromHttpStatus(403),
        PaymentOutcome.accessDenied,
      );
      expect(BackendService.paymentOutcomeFromHttpStatus(503), isNull);
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

  group('Serving sync contract', () {
    test('does not send servings until their product has a remote id', () {
      final now = DateTime.now().toIso8601String();
      final cups = <ShotCup>[
        ShotCup(
          id: 1,
          productId: 10,
          productName: 'Unpublished drink',
          capacity: 30,
          unit: 'ml',
          price: Money.fromMajor(50),
          updatedAt: now,
        ),
        ShotCup(
          id: 2,
          productId: 11,
          productName: 'Published drink',
          capacity: 30,
          unit: 'ml',
          price: Money.fromMajor(60),
          updatedAt: now,
        ),
      ];

      final ready = BackendService.shotCupsReadyForSync(
        cups,
        <int, String>{11: 'product_cuid'},
      );

      expect(ready.map((cup) => cup.id), <int?>[2]);
    });

    test('does not send variants until their parent product has a remote id',
        () {
      final variants = <ProductVariant>[
        ProductVariant(
          id: 1,
          productId: 10,
          name: 'Small',
          sellPrice: Money.fromMajor(50),
        ),
        ProductVariant(
          id: 2,
          productId: 11,
          name: 'Large',
          sellPrice: Money.fromMajor(80),
        ),
      ];

      final ready = BackendService.variantsReadyForSync(
        variants,
        <int, String>{11: 'product_cuid'},
      );

      expect(ready.map((variant) => variant.id), <int?>[2]);
    });

    test('does not send purchase or return rows with unresolved products', () {
      expect(
        BackendService.productReferencesReadyForSync(
          <int>[10, 11],
          <int, String>{10: 'product_a'},
        ),
        isFalse,
      );
      expect(
        BackendService.productReferencesReadyForSync(
          <int>[10, 11],
          <int, String>{10: 'product_a', 11: 'product_b'},
        ),
        isTrue,
      );
    });

    test('does not send reorder records with unresolved products', () {
      expect(
        BackendService.reorderRecordReadyForSync(
          <String, dynamic>{
            'kind': 'product_supplier',
            'payload': <String, dynamic>{'product_id': 10},
          },
          <int, String>{},
        ),
        isFalse,
      );
      expect(
        BackendService.reorderRecordReadyForSync(
          <String, dynamic>{
            'kind': 'purchase_order',
            'payload': <String, dynamic>{
              'lines': <Map<String, dynamic>>[
                <String, dynamic>{'product_id': 10},
              ],
            },
          },
          <int, String>{10: 'product_a'},
        ),
        isTrue,
      );
    });

    test('keeps Open cost-pool types aligned with the backend contract', () {
      expect(BackendService.costPoolTypeForSync('lot'), 'lot');
      expect(BackendService.costPoolTypeForSync('bale'), 'bale');
      expect(
          BackendService.costPoolTypeForSync('rolling_stock'), 'rolling_stock');
      expect(BackendService.costPoolTypeForSync('unknown'), 'lot');
    });

    test('does not send lay-bys with unresolved customer or product ids', () {
      final row = <String, dynamic>{
        'customer_id': 1,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'product_id': 2},
        ],
      };
      expect(
        BackendService.laybyReadyForSync(
            row, <int, String>{1: 'customer'}, <int, String>{}),
        isFalse,
      );
      expect(
        BackendService.laybyReadyForSync(
            row, <int, String>{1: 'customer'}, <int, String>{2: 'product'}),
        isTrue,
      );
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
