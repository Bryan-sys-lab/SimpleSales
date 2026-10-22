// ONE credential.
//
// ## WHAT THIS PINS
//
// There were two ways to be signed in to the backend: a Keycloak access
// token, and a session the backend minted itself — signed with a secret that
// lived in the server process, stored on the phone beside the Keycloak tokens,
// and refreshed by the app's own `/auth/refresh` call.
//
// Two credentials means two things to revoke, two expiry clocks, and a class
// of token the identity server has never heard of. The point of running
// Keycloak is that ONE authority decides who a person is.
//
// So: the app session is gone. The app holds a Keycloak token and nothing
// else; the server accepts a Keycloak token and nothing else; and the verify
// flow proves the address and creates the account WITHOUT handing out a
// credential of its own — the till signs in to Keycloak for that.
//
// ## WHY THIS IS A SOURCE TEST
//
// The rule is about what the app does NOT do, and the things it does not do
// are absences: no second token, no second refresh, no session to clear. A
// test that walks the source is the only one that can see an absence.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the app holds one credential', () {
    test('there is no app session to keep, refresh or clear', () {
      final String service =
          File('lib/services/backend_service.dart').readAsStringSync();
      final String oidc =
          File('lib/services/oidc_service.dart').readAsStringSync();
      final String live =
          File('lib/services/live_channel_service.dart').readAsStringSync();

      for (final String source in <String>[service, oidc, live]) {
        expect(
          source.contains('appSessionAccessToken'),
          isFalse,
          reason: 'the app session is gone: the credential is Keycloak\'s',
        );
        expect(
          source.contains('appSessionRefreshToken'),
          isFalse,
          reason: 'there is no second refresh token to keep',
        );
        expect(
          source.contains('storeAppSession'),
          isFalse,
          reason: 'nothing stores a server-minted session any more',
        );
        expect(
          source.contains("'app_session_access_token'"),
          isFalse,
          reason: 'and nothing writes one to the keystore',
        );
      }
    });

    test('the refresh endpoint is not called', () {
      final String service =
          File('lib/services/backend_service.dart').readAsStringSync();
      expect(
        service.contains('auth/refresh'),
        isFalse,
        reason: 'Keycloak refreshes its own tokens; a refresh endpoint here '
            'would be a second session with a second lifetime',
      );
    });

    test('the live channel carries the Keycloak token', () {
      final String live =
          File('lib/services/live_channel_service.dart').readAsStringSync();
      expect(
        live.contains('OidcService.accessToken'),
        isTrue,
        reason: 'the server verifies the live channel\'s bearer against the '
            'identity server\'s own signing keys, so the app must send the '
            'Keycloak token',
      );
    });

    test('the verify flow signs in to Keycloak for the credential', () {
      final String service =
          File('lib/services/backend_service.dart').readAsStringSync();
      expect(
        service.contains('OidcService.login()'),
        isTrue,
        reason: 'the server creates the account and proves the address; the '
            'TOKEN is the identity server\'s to issue, and the till is the '
            'party that will present it',
      );
    });
  });
}
