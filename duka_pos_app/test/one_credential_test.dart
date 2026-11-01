// ONE credential (custom JWT).
//
// The app holds a single access token issued by the backend, with a single
// refresh token. There is no separate OIDC token or second session.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the app holds one credential', () {
    test('the live channel carries the identity token', () {
      final String live =
          File('lib/services/live_channel_service.dart').readAsStringSync();
      expect(
        live.contains('IdentityService.accessToken'),
        isTrue,
        reason: 'the live channel must send the backend access token',
      );
    });

    test('backend service uses the identity service', () {
      final String service =
          File('lib/services/backend_service.dart').readAsStringSync();
      expect(
        service.contains('IdentityService.accessToken'),
        isTrue,
      );
    });
  });
}
