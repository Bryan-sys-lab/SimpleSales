import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/utils/validation_utils.dart';

void main() {
  group('Validation Tests', () {
    test('Product name validation', () {
      expect(ValidationUtils.validateProductName(''), isNotNull);
      expect(ValidationUtils.validateProductName('A'), isNotNull);
      expect(ValidationUtils.validateProductName('Valid Name'), isNull);
    });

    test('Price validation', () {
      expect(ValidationUtils.validatePrice('', 'Cost'), isNotNull);
      expect(ValidationUtils.validatePrice('-100', 'Cost'), isNotNull);
      expect(ValidationUtils.validatePrice('abc', 'Cost'), isNotNull);
      expect(ValidationUtils.validatePrice('1000', 'Cost'), isNull);
      expect(ValidationUtils.validatePrice('1,500', 'Cost'), isNull);
    });

    test('Stock validation', () {
      expect(ValidationUtils.validateStock(''), isNotNull);
      expect(ValidationUtils.validateStock('-5'), isNotNull);
      expect(ValidationUtils.validateStock('10.5'), isNotNull);
      expect(ValidationUtils.validateStock('10'), isNull);
    });

    test('PIN validation', () {
      expect(ValidationUtils.validatePIN(''), isNotNull);
      expect(ValidationUtils.validatePIN('123'), isNotNull);
      expect(ValidationUtils.validatePIN('12345'), isNotNull);
      expect(ValidationUtils.validatePIN('abcd'), isNotNull);
      expect(ValidationUtils.validatePIN('1234'), isNull);
    });

    test('Email validation', () {
      expect(ValidationUtils.validateEmail(''), isNotNull);
      expect(ValidationUtils.validateEmail('invalid'), isNotNull);
      expect(ValidationUtils.validateEmail('test@'), isNotNull);
      expect(ValidationUtils.validateEmail('test@example.com'), isNull);
    });

    test('Password validation', () {
      expect(ValidationUtils.validatePassword(''), isNotNull);
      expect(ValidationUtils.validatePassword('12345'), isNotNull);
      expect(ValidationUtils.validatePassword('123456'), isNull);
    });

    test('Phone validation', () {
      expect(ValidationUtils.validatePhone(''), isNotNull);
      expect(ValidationUtils.validatePhone('123'), isNotNull);
      expect(ValidationUtils.validatePhone('0712345678'), isNull);
      expect(ValidationUtils.validatePhone('+254712345678'), isNull);
    });
  });
}
