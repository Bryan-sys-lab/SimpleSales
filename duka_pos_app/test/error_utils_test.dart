import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/utils/error_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The catalogue the failure sentences are read from. See `loadL10n`.
late AppLocalizations l10n;

/// The error-to-sentence boundary.
///
/// These assertions are on COPY, not on structure, so they changed when the copy
/// changed — the redesign replaced the terse hyphenated messages with sentences
/// that name the next action ("Ask the owner for access" rather than "You don't
/// have permission to do this"). The MEANING of each case is preserved, and the
/// typed-failure cases below are the ones that should stop drifting: every new
/// failure should arrive with a [PosFailureCode], not as another string to match.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await loadL10n();
  });

  group('a typed failure maps to one sentence, exhaustively', () {
    for (final PosFailureCode code in PosFailureCode.values) {
      test('$code', () {
        final String message = ErrorUtils.messageFor(l10n, code);
        expect(message, isNotEmpty);
        // A sentence, not a code: an untranslated identifier in the UI is the
        // failure mode this whole layer exists to prevent.
        expect(message, isNot(contains('_')));
        expect(message.endsWith('.'), isTrue);
      });
    }

    test('an unknown failure still says something actionable', () {
      final String message =
          ErrorUtils.messageFor(l10n, PosFailureCode.unknown);
      expect(message, contains('Try again'));
    });

    test('an offline failure says how to fix it, not just what broke', () {
      expect(ErrorUtils.messageFor(l10n, PosFailureCode.offline),
          contains('network'));
    });

    test('a permission failure names who can help', () {
      expect(
        ErrorUtils.messageFor(l10n, PosFailureCode.notPermitted),
        contains('owner'),
      );
    });
  });

  group('a typed failure does not need its string inspected', () {
    test('PosFailure is recognised directly', () {
      expect(
        ErrorUtils.userMessage(
            l10n, const PosFailure(PosFailureCode.duplicateName)),
        ErrorUtils.messageFor(l10n, PosFailureCode.duplicateName),
      );
    });

    test('the cause is carried for the log but never leaks into the message',
        () {
      const PosFailure failure = PosFailure(
        PosFailureCode.writeFailed,
        detail: '/data/user/0/com.dukapos/databases/shop.db: no such table',
      );
      final String message = ErrorUtils.userMessage(l10n, failure);
      expect(message, isNot(contains('no such table')));
      expect(message, isNot(contains('.db')));
      expect(message, isNot(contains('/data/')));
      // But it is still available to a crash reporter.
      expect(failure.detail, contains('shop.db'));
    });

    test('a typed failure beats a misleading string in the detail', () {
      // The point of typing the failure: a database path that happens to contain
      // "stock" must not be reported to a shopkeeper as "not enough stock".
      final String message = ErrorUtils.userMessage(
        l10n,
        const PosFailure(
          PosFailureCode.writeFailed,
          detail: 'Exception: no such column: stock_adjustments',
        ),
      );
      expect(message, isNot(contains('Not enough stock')));
      expect(message, contains('Could not save'));
    });
  });

  group('raw exceptions from the legacy service layer still map', () {
    // The string-matching fallback is the reason this boundary exists at all:
    // `DatabaseHelper` and the services still throw raw exceptions, so something
    // has to absorb them. Replacing a raw throw with a typed PosFailure upstream
    // should REMOVE a case here, never add one.
    test('Database error messages', () {
      expect(
        ErrorUtils.userMessage(
            l10n, Exception('SQLite unique constraint failed')),
        contains('already taken'),
      );
      expect(
        ErrorUtils.userMessage(
            l10n, Exception('Database NOT NULL constraint failed')),
        contains('Fill in every required field'),
      );
    });

    test('Network error messages', () {
      expect(
        ErrorUtils.userMessage(
            l10n, Exception('SocketException: Connection failed')),
        contains('No internet'),
      );
      expect(
        ErrorUtils.userMessage(l10n, Exception('timeout error')),
        contains('timed out'),
      );
    });

    test('Auth error messages', () {
      expect(
        ErrorUtils.userMessage(l10n, Exception('401 Unauthorized')),
        contains('Session expired'),
      );
      expect(
        ErrorUtils.userMessage(l10n, Exception('403 Forbidden')),
        contains('owner'),
      );
    });

    test('Payment error messages', () {
      expect(
        ErrorUtils.userMessage(l10n, Exception('PayHero payment failed')),
        contains('Payment failed'),
      );
    });

    test('Stock error messages', () {
      expect(
        ErrorUtils.userMessage(l10n, Exception('not enough inventory')),
        contains('Not enough stock'),
      );
    });

    test('Generic error fallback', () {
      expect(
        ErrorUtils.userMessage(l10n, Exception('Unknown error')),
        contains('Something went wrong'),
      );
    });

    test('no message ever leaks a path or an exception type', () {
      for (final Object error in <Object>[
        Exception('SQLite exception'),
        Exception('SocketException'),
        Exception('FormatException: invalid json'),
        const PosFailure(PosFailureCode.unknown, detail: 'stack trace here'),
      ]) {
        final String message = ErrorUtils.userMessage(l10n, error);
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('/')));
      }
    });
  });
}
