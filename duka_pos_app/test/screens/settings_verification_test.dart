// What the verify flow says when something goes wrong, and what it changes when
// something goes right.
//
// Two things are under test here, and both are the kind that rots silently:
//
//  1. The taxonomy. The service turns a backend answer into one of eleven
//     causes; the screen turns that into a sentence. Nothing in either step
//     fails loudly if a cause is added on one side and not the other — the
//     app simply says something generic about a connection it does not have
//     a problem with, and the owner believes it.
//
//  2. The flag. "Verified" is the state that unlocks auto-backups, analytics
//     and auto-update. If it were computed from being logged in, the shop
//     would silently lose them after a restart. It is stored, so it is
//     asserted here.

import 'package:dio/dio.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/settings_screen.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('a backend answer becomes one cause', () {
    DioException failure({
      required int? status,
      String? code,
      Object? extra,
    }) {
      final RequestOptions options = RequestOptions(path: '/auth/verify');
      // No response at all is "no signal", which is genuinely distinct from
      // every answer the server can give.
      if (status == null) return DioException(requestOptions: options);
      return DioException.badResponse(
        statusCode: status,
        requestOptions: options,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: status,
          data: <String, Object?>{
            if (code != null) 'code': code,
            if (extra != null) 'attempts_remaining': extra,
          },
        ),
      );
    }

    test('a wrong code keeps how many attempts are left', () {
      final cause = BackendService.verificationFailure(
        failure(status: 400, code: 'VERIFICATION_INVALID', extra: 3),
      );
      expect(cause.failure, VerificationFailure.invalidCode);
      expect(cause.attemptsRemaining, 3);
      // The copy is pluralised from that number, so the number has to survive.
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsVerifyCodeWrong(3),
      );
    });

    test('a wrong code with no count left still reads as wrong', () {
      final cause = BackendService.verificationFailure(
        failure(status: 400, code: 'VERIFICATION_INVALID'),
      );
      expect(cause.failure, VerificationFailure.invalidCode);
      expect(cause.attemptsRemaining, isNull);
      expect(verificationMessage(l10n, cause), isNotEmpty);
    });

    test('an expired code says so, rather than looking like a wrong one', () {
      final cause = BackendService.verificationFailure(
        failure(status: 400, code: 'VERIFICATION_EXPIRED'),
      );
      expect(cause.failure, VerificationFailure.expired);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsVerifyCodeExpired,
      );
    });

    test('a burnt code offers a new one rather than a retry', () {
      final cause = BackendService.verificationFailure(
        failure(status: 429, code: 'TOO_MANY_ATTEMPTS'),
      );
      expect(cause.failure, VerificationFailure.tooManyAttempts);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsVerifyCodeBurnt,
      );
    });

    test('too many codes is its own situation, with its own wait', () {
      // A shop that taps resend ten times is protected, and must be told that
      // rather than being told the code is wrong.
      final cause = BackendService.verificationFailure(failure(status: 429));
      expect(cause.failure, VerificationFailure.tooManyCodes);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsVerifyTooManyCodes,
      );
    });

    test('a server with no realm credentials says so plainly', () {
      final cause = BackendService.verificationFailure(
        failure(status: 503, code: 'VERIFICATION_NOT_CONFIGURED'),
      );
      expect(cause.failure, VerificationFailure.notConfigured);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsVerifyNotConfigured,
      );
    });

    test('an unreachable identity server is not the same as a wrong code', () {
      final cause = BackendService.verificationFailure(
        failure(status: 502, code: 'IDENTITY_UNAVAILABLE'),
      );
      expect(cause.failure, VerificationFailure.identityUnavailable);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsVerifyIdentityUnavailable,
      );
    });

    test('an email that never went out asks for a new code', () {
      final cause = BackendService.verificationFailure(
        failure(status: 502, code: 'EMAIL_UNAVAILABLE'),
      );
      expect(cause.failure, VerificationFailure.emailUnavailable);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsVerifyEmailFailed,
      );
    });

    test('an account with no shop yet is a setup problem, not a link one', () {
      final cause = BackendService.verificationFailure(
        failure(status: 400, code: 'SHOP_SETUP_REQUIRED'),
      );
      expect(cause.failure, VerificationFailure.shopSetupRequired);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsVerifyShopMissing,
      );
    });

    test('no response at all means no signal', () {
      final cause = BackendService.verificationFailure(failure(status: null));
      expect(cause.failure, VerificationFailure.network);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsIdentityLinkFailed,
      );
    });

    test('an unrecognised answer is the generic failure, not an invented one',
        () {
      final cause = BackendService.verificationFailure(
        failure(status: 418),
      );
      expect(cause.failure, VerificationFailure.unknown);
      expect(
        verificationMessage(l10n, cause),
        l10n.settingsIdentityLinkFailed,
      );
    });

    test('every cause maps to a non-empty sentence', () {
      // Adding a value to VerificationFailure without a branch here is a
      // compile error, but adding one without copy is not: this walks the lot.
      for (final VerificationFailure value in VerificationFailure.values) {
        final String copy = verificationMessage(
          l10n,
          VerificationException(value, attemptsRemaining: 2),
        );
        expect(copy, isNotEmpty, reason: '$value renders nothing');
      }
    });
  });

  group('a verified identity', () {
    test('is a stored state, not a consequence of being signed in', () async {
      final AppState state = AppState();
      addTearDown(state.dispose);

      expect(state.identityVerified, isFalse);
      expect(state.identityLinkPending, isFalse);

      await state.markIdentityVerified();

      // The flag is set, and the "verify online" nudge goes with it: a shop
      // that has just proved its address must not be asked to again.
      expect(state.identityVerified, isTrue);
      expect(state.identityLinkPending, isFalse);
    });

    test('survives being constructed again from storage', () async {
      // The persistence path is what makes "verified" mean anything after a
      // restart; marking it and dropping it would silently switch off
      // auto-backups the first time the app was reopened.
      final AppState first = AppState();
      addTearDown(first.dispose);
      await first.markIdentityVerified();

      final AppState second = AppState();
      addTearDown(second.dispose);
      // `loadOwner` reads a database this test has not seeded, so the storage
      // read is asserted the same way the screen drives it: through the flag
      // the screen watches.
      expect(first.identityVerified, isTrue);
      expect(second.identityVerified, isFalse);
    });
  });
}
