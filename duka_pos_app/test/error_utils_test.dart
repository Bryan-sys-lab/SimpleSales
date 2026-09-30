import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/utils/error_utils.dart';

void main() {
  group('Error Utils Tests', () {
    test('Database error messages', () {
      expect(
        ErrorUtils.userMessage(Exception('SQLite unique constraint failed')),
        contains('already exists'),
      );
      expect(
        ErrorUtils.userMessage(
            Exception('Database NOT NULL constraint failed')),
        contains('fill in all required'),
      );
    });

    test('Network error messages', () {
      expect(
        ErrorUtils.userMessage(Exception('SocketException: Connection failed')),
        contains('No internet'),
      );
      expect(
        ErrorUtils.userMessage(Exception('timeout error')),
        contains('timed out'),
      );
    });

    test('Auth error messages', () {
      expect(
        ErrorUtils.userMessage(Exception('401 Unauthorized')),
        contains('Session expired'),
      );
      expect(
        ErrorUtils.userMessage(Exception('403 Forbidden')),
        contains('don\'t have permission'),
      );
    });

    test('Payment error messages', () {
      expect(
        ErrorUtils.userMessage(Exception('PayHero payment failed')),
        contains('Payment failed'),
      );
    });

    test('Generic error fallback', () {
      expect(
        ErrorUtils.userMessage(Exception('Unknown error')),
        contains('Something went wrong'),
      );
    });
  });
}
