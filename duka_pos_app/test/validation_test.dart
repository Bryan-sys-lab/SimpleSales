import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/utils/validation_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The catalogue every assertion below reads.
///
/// Loaded once, through the real delegate, rather than stubbed: these messages
/// are ARB entries now, and a test that constructs them by hand would pass even
/// if the key had been renamed out from under the app.
late AppLocalizations l10n;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await loadL10n();
  });

  group('Validation Tests', () {
    test('Product name validation', () {
      expect(ValidationUtils.validateProductName(l10n, ''), isNotNull);
      expect(ValidationUtils.validateProductName(l10n, 'A'), isNotNull);
      expect(ValidationUtils.validateProductName(l10n, 'Valid Name'), isNull);
    });

    test('Price validation', () {
      expect(ValidationUtils.validatePrice(l10n, '', 'Cost'), isNotNull);
      expect(ValidationUtils.validatePrice(l10n, '-100', 'Cost'), isNotNull);
      expect(ValidationUtils.validatePrice(l10n, 'abc', 'Cost'), isNotNull);
      expect(ValidationUtils.validatePrice(l10n, '1000', 'Cost'), isNull);
      expect(ValidationUtils.validatePrice(l10n, '1,500', 'Cost'), isNull);
    });

    test('Stock validation', () {
      expect(ValidationUtils.validateStock(l10n, ''), isNotNull);
      expect(ValidationUtils.validateStock(l10n, '-5'), isNotNull);
      expect(ValidationUtils.validateStock(l10n, '10.5'), isNotNull);
      expect(ValidationUtils.validateStock(l10n, '10'), isNull);
    });

    test('PIN validation', () {
      expect(ValidationUtils.validatePIN(l10n, ''), isNotNull);
      expect(ValidationUtils.validatePIN(l10n, '123'), isNotNull);
      expect(ValidationUtils.validatePIN(l10n, '12345'), isNotNull);
      expect(ValidationUtils.validatePIN(l10n, 'abcd'), isNotNull);
      expect(ValidationUtils.validatePIN(l10n, '1234'), isNull);
    });

    test('Email validation', () {
      expect(ValidationUtils.validateEmail(l10n, ''), isNotNull);
      expect(ValidationUtils.validateEmail(l10n, 'invalid'), isNotNull);
      expect(ValidationUtils.validateEmail(l10n, 'test@'), isNotNull);
      expect(ValidationUtils.validateEmail(l10n, 'test@example.com'), isNull);
    });

    test('Password validation', () {
      expect(ValidationUtils.validatePassword(l10n, ''), isNotNull);
      expect(ValidationUtils.validatePassword(l10n, '12345'), isNotNull);
      expect(ValidationUtils.validatePassword(l10n, '123456'), isNull);
    });

    test('Phone validation', () {
      expect(ValidationUtils.validatePhone(l10n, ''), isNotNull);
      expect(ValidationUtils.validatePhone(l10n, '123'), isNotNull);
      expect(ValidationUtils.validatePhone(l10n, '0712345678'), isNull);
      expect(ValidationUtils.validatePhone(l10n, '+254712345678'), isNull);
    });
  });
}
