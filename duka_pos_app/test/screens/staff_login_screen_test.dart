import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/staff_login_screen.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextFormField;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/harness.dart';

class _StaffAuthAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(<String, String>{'error': 'Invalid staff credentials'}),
      401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final Map<String, String> secureStorage = <String, String>{};

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return key == null ? null : secureStorage[key];
          case 'write':
            final value = args['value'] as String?;
            if (key != null && value != null) secureStorage[key] = value;
            return null;
          case 'delete':
            if (key != null) secureStorage.remove(key);
            return null;
          default:
            return null;
        }
      },
    );
  });

  setUp(() async {
    secureStorage.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await WorkspaceService.register(
      workspaceKey: 'linked-shop',
      tenantId: 'main-shop-1234',
      shopName: 'Main shop',
    );
    await WorkspaceService.setActiveWorkspace('linked-shop');
  });

  testWidgets(
    'tries remote authentication for a synced staff row without a local PIN',
    (WidgetTester tester) async {
      tester.useDevice(Device.small);
      final adapter = _StaffAuthAdapter();
      BackendService.setHttpClientAdapterForTesting(adapter);
      addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

      await tester.pumpApp(
        home: StaffLoginScreen(
          staffLoader: () async => <Staff>[
            Staff(
              id: 7,
              remoteId: 'remote-staff-7',
              name: 'Amina',
              username: 'amina',
              pinHash: '',
              role: 'cashier',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), '  amina  ');
      await tester.enterText(find.byType(TextFormField).at(2), ' 1234 ');
      final AppLocalizations l10n =
          AppLocalizations.of(tester.element(find.byType(StaffLoginScreen)));
      final signInButton = find.text(l10n.loginSignInAction);
      await tester.ensureVisible(signInButton);
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      final staffRequests = adapter.requests
          .where(
              (request) => request.path.endsWith('/tenant/staff/authenticate'))
          .toList();
      expect(staffRequests, hasLength(1));
      expect(
        staffRequests.single.path,
        endsWith('/tenant/staff/authenticate'),
      );
      expect(
        staffRequests.single.headers['x-tenant-id'],
        'main-shop-1234',
      );
      final staffRequestData = Map<String, dynamic>.from(
        staffRequests.single.data as Map,
      );
      expect(staffRequestData, containsPair('username', 'amina'));
      expect(staffRequestData, containsPair('pin', '1234'));
      expect(staffRequestData['device_id'], isA<String>());
      expect((staffRequestData['device_id'] as String).trim(), isNotEmpty);
      expect(find.text(l10n.loginWrongCredentials), findsOneWidget);
    },
  );
}
