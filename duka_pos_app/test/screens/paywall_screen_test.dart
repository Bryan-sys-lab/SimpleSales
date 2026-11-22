import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/paywall_screen.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

class _PaywallAdapter implements HttpClientAdapter {
  final List<String> requestedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'entitlement': <String, Object?>{
          'allowed': false,
          'status': 'pending',
          'reason': 'subscription_required',
          'priceMinor': 100000,
          'discountPercent': 10,
          'currency': 'KES',
          'billingInterval': 'monthly',
          'currentPeriodEnd': null,
        },
        'support': <String, Object?>{
          'availableVoucher': <String, Object>{'durationMonths': 6},
          'whatsappUrl': null,
        },
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'shows the one-tap admin voucher claim when one is available',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      final _PaywallAdapter adapter = _PaywallAdapter();
      BackendService.setHttpClientAdapterForTesting(adapter);
      addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

      await tester.pumpApp(home: const PaywallScreen());
      await tester.pumpAndSettle();

      final AppLocalizations l10n =
          AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
      expect(find.text(l10n.paywallClaimVoucher), findsOneWidget);
      expect(find.text(l10n.paywallVoucherReady(6)), findsWidgets);
      expect(
        adapter.requestedPaths,
        contains(endsWith('/tenant/subscription')),
      );
      tester.expectNoOverflow('admin voucher paywall');
    },
  );
}
