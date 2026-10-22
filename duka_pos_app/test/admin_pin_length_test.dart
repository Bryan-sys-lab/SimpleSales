// The owner's PIN is an ADMIN PIN, and an admin PIN is six digits.
//
// ## THE BUG THIS PINS
//
// The app asked for the owner's PIN in two places, and the two disagreed.
//
//   * The SETUP screen made a FOUR-digit PIN.
//   * The sheet that PROVES OWNERSHIP — the one in front of account deletion,
//     the one in front of changing a shop's settings — asked for SIX.
//
// So the owner had a PIN the app would not accept where it mattered most:
// account deletion was impossible, because the one PIN they had was the wrong
// length, and the sheet that asked for it would not take it.
//
// ## THE RULE
//
// One owner PIN, six digits, everywhere it is asked for:
//
//   * the setup screen makes it six;
//   * the sign-in pad asks for six when the owner is the picked identity;
//   * the proof sheet asks for six.
//
// ## WHAT IS NOT CHANGING
//
// A STAFF PIN is still four digits. It is typed forty times a day at a
// counter, and it is a different PIN — the one the till asks for at sign-in
// when a cashier is picked.

import 'dart:io';

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/utils/pin_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('the rule', () {
    test('an admin PIN is six digits, and only digits', () {
      expect(PinRules.adminLength, 6);
      expect(PinRules.isAdminPin('123456'), isTrue);
      expect(PinRules.isAdminPin('12345'), isFalse);
      expect(PinRules.isAdminPin('1234567'), isFalse);
      expect(PinRules.isAdminPin('12345a'), isFalse);
      expect(PinRules.isAdminPin('12 456'), isFalse);
      expect(PinRules.isAdminPin(''), isFalse);
    });

    test('a staff PIN is still four digits', () {
      expect(PinRules.staffLength, 4);
      expect(PinRules.isStaffPin('1234'), isTrue);
      expect(PinRules.isStaffPin('123'), isFalse);
      expect(PinRules.isStaffPin('12345'), isFalse);
      expect(PinRules.isStaffPin('12a4'), isFalse);
    });
  });

  group('the screens that ask for the owner PIN', () {
    // The setup screen and the proof sheet are read as source, because the
    // thing that has to agree is the LENGTH each one asks for — and a length
    // is a number in a form field, not a behaviour a widget test can watch
    // without a real database underneath it.
    //
    // The proof sheet already asked for six. The setup screen asked for four.
    // This pins both, and pins that the setup screen's field is limited to
    // six as well — a field that accepts seven digits and rejects the value
    // afterwards is a field that lies to the person typing in it.

    test('the setup screen asks for six digits', () {
      final String source = _read('lib/screens/owner_setup_screen.dart');

      expect(
        source.contains(r'^\d{4}\$'),
        isFalse,
        reason: 'the owner PIN is an admin PIN, and an admin PIN is six '
            'digits',
      );
      expect(
        source.contains('PinRules.adminPattern'),
        isTrue,
        reason: 'the setup screen must use the shared rule, not a pattern of '
            'its own that can drift from it',
      );
      expect(
        source.contains('maxLength: PinRules.adminLength'),
        isTrue,
        reason: 'the field must accept exactly as many digits as the rule '
            'says, and no more',
      );
    });

    test('the sign-in pad asks for six digits for the owner', () {
      final String source = _read('lib/screens/login_screen.dart');
      expect(
        source.contains('PinRules.adminLength'),
        isTrue,
        reason: 'the sign-in pad must ask the owner for the same six digits '
            'the rest of the app asks for',
      );
      expect(
        source.contains('PinRules.staffLength'),
        isTrue,
        reason: 'and it must still ask a staff member for four',
      );
    });

    test('the proof sheet asks for six digits', () {
      final String source = _read('lib/ui/dialogs/verify_identity_dialog.dart');
      expect(
        source.contains('LengthLimitingTextInputFormatter(6)'),
        isTrue,
        reason: 'the sheet that proves ownership takes six digits',
      );
      expect(
        source.contains('entered.length != 6'),
        isTrue,
        reason: 'and it refuses anything else',
      );
    });

    test('the staff PIN is still asked for as four digits', () {
      final String source = _read('lib/screens/settings_screen.dart');
      expect(
        source.contains(r'^\d{4}$'),
        isTrue,
        reason: 'a cashier still signs in with a four-digit PIN',
      );
    });
  });

  group('the words', () {
    test('the copy says six where the owner PIN is concerned', () async {
      final AppLocalizations l10n = await loadL10n();
      expect(l10n.validationPinNotSixDigits, contains('6'));
      expect(l10n.ownerSetupPinLabel, contains('6'));
      // The staff copy is unchanged.
      expect(l10n.validationPinNotFourDigits, contains('4'));
    });
  });
}

/// The contents of a file in the app, read from the test's working directory.
String _read(String path) => File(path).readAsStringSync();
