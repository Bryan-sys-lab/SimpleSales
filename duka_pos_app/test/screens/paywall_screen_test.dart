import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/paywall_screen.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:flutter/widgets.dart' show Scrollable, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/harness.dart';

class _PaywallAdapter implements HttpClientAdapter {
  final List<String> requestedPaths = <String>[];
  final List<Map<String, dynamic>> requestBodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    if (options.data is Map) {
      requestBodies.add(Map<String, dynamic>.from(options.data as Map));
    }
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

class _DiscountVoucherAdapter implements HttpClientAdapter {
  _DiscountVoucherAdapter({this.existingAccess = false});

  final bool existingAccess;
  final List<String> requestedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    final bool claiming = options.path.endsWith('/auth/voucher/claim') ||
        options.path.endsWith('/auth/voucher/redeem');
    final Map<String, Object?> response = claiming
        ? <String, Object?>{
            'status': 'discount_voucher_applied',
            'voucher': <String, Object?>{
              'voucherType': 'discount',
              'durationMonths': 3,
              'discountPercent': 25,
            },
            'entitlement': <String, Object?>{
              'allowed': existingAccess,
              'status': existingAccess ? 'active' : 'pending',
              'reason': existingAccess ? 'active' : 'subscription_required',
              'priceMinor': 100000,
              'discountPercent': 25,
              'discountVoucherDurationMonths': 3,
              'currency': 'KES',
              'billingInterval': 'monthly',
              'currentPeriodEnd': existingAccess
                  ? DateTime.now()
                      .add(const Duration(days: 30))
                      .toIso8601String()
                  : null,
            },
          }
        : <String, Object?>{
            'entitlement': <String, Object?>{
              'allowed': existingAccess,
              'status': existingAccess ? 'active' : 'pending',
              'reason': existingAccess ? 'active' : 'subscription_required',
              'priceMinor': 100000,
              'discountPercent': 10,
              'currency': 'KES',
              'billingInterval': 'monthly',
              'currentPeriodEnd': existingAccess
                  ? DateTime.now()
                      .add(const Duration(days: 30))
                      .toIso8601String()
                  : null,
            },
            'support': <String, Object?>{
              'availableVoucher': <String, Object?>{
                'voucherType': 'discount',
                'durationMonths': 3,
                'discountPercent': 25,
              },
              'whatsappUrl': null,
            },
          };
    return ResponseBody.fromString(
      jsonEncode(response),
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
      await tester.tap(find.text(l10n.membershipVouchers));
      await tester.pumpAndSettle();
      expect(find.text(l10n.paywallClaimVoucher), findsOneWidget);
      expect(find.text(l10n.paywallVoucherReady(6)), findsWidgets);
      expect(
        adapter.requestedPaths,
        contains(endsWith('/tenant/subscription')),
      );
      tester.expectNoOverflow('admin voucher paywall');
    },
  );

  testWidgets(
    'claims a discount voucher without unlocking access and limits checkout to its term',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      final _DiscountVoucherAdapter adapter = _DiscountVoucherAdapter();
      BackendService.setHttpClientAdapterForTesting(adapter);
      addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

      await tester.pumpApp(home: const PaywallScreen());
      await tester.pumpAndSettle();

      final AppLocalizations l10n =
          AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
      await tester.tap(find.text(l10n.membershipVouchers));
      await tester.pumpAndSettle();
      expect(
          find.text(l10n.paywallAvailableDiscountVoucher(25, 3)), findsWidgets);
      await tester.tap(find.text(l10n.paywallClaimVoucher));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.paywallDiscountVoucherClaimed(25, 3)),
        findsWidgets,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text(l10n.membershipPlans));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(l10n.membershipExistingOffer),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(l10n.membershipExistingOffer));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('KES 2250.00'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('KES 2250.00'), findsOneWidget);
      expect(
        adapter.requestedPaths,
        contains(endsWith('/auth/voucher/claim')),
      );
      tester.expectNoOverflow('discount voucher paywall');
    },
  );

  testWidgets(
    'keeps the paywall available to an entitled shop claiming a discount',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      final _DiscountVoucherAdapter adapter =
          _DiscountVoucherAdapter(existingAccess: true);
      BackendService.setHttpClientAdapterForTesting(adapter);
      addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

      await tester.pumpApp(home: const PaywallScreen());
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);

      final AppLocalizations l10n =
          AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
      await tester.tap(find.text(l10n.membershipVouchers));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.paywallClaimVoucher));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(
        find.text(l10n.paywallDiscountVoucherClaimed(25, 3)),
        findsWidgets,
      );
      tester.expectNoOverflow('active-shop discount voucher paywall');
    },
  );

  testWidgets(
    'manual voucher entry also applies a discount without granting access',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await WorkspaceService.register(
        workspaceKey: 'paywall-test',
        tenantId: 'tenant-test',
        shopName: 'Paywall test',
      );
      await WorkspaceService.setActiveWorkspace('paywall-test');
      final _DiscountVoucherAdapter adapter = _DiscountVoucherAdapter();
      BackendService.setHttpClientAdapterForTesting(adapter);
      addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

      await tester.pumpApp(home: const PaywallScreen());
      await tester.pumpAndSettle();
      final AppLocalizations l10n =
          AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
      await tester.tap(find.text(l10n.membershipVouchers));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('membership-voucher-code')),
        'SS-DISCOUNT-MANUAL',
      );
      expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey<String>('membership-voucher-code')))
            .controller
            ?.text,
        'SS-DISCOUNT-MANUAL',
      );
      await tester.scrollUntilVisible(
        find.text(l10n.paywallRedeemVoucher),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(l10n.paywallRedeemVoucher));
      await tester.pumpAndSettle();

      expect(
        adapter.requestedPaths,
        contains(endsWith('/auth/voucher/redeem')),
      );
      expect(
        find.text(l10n.paywallDiscountVoucherClaimed(25, 3)),
        findsWidgets,
      );
      tester.expectNoOverflow('manual discount voucher paywall');
    },
  );

  testWidgets(
    'sends selected membership needs through the existing quote request path',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await WorkspaceService.register(
        workspaceKey: 'membership-test',
        tenantId: 'tenant-membership',
        shopName: 'Membership test',
      );
      await WorkspaceService.setActiveWorkspace('membership-test');
      final _PaywallAdapter adapter = _PaywallAdapter();
      BackendService.setHttpClientAdapterForTesting(adapter);
      addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

      await tester.pumpApp(home: const PaywallScreen());
      await tester.pumpAndSettle();
      final AppLocalizations l10n =
          AppLocalizations.of(tester.element(find.byType(PaywallScreen)));

      await tester.tap(find.text(l10n.membershipGetStarted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.membershipFeatureInventory));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('membership-custom-requirements')),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('membership-custom-requirements')),
        'Please include training for two staff members.',
      );
      await tester.scrollUntilVisible(
        find.text(l10n.membershipRequestOffer),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(l10n.membershipRequestOffer));
      await tester.pumpAndSettle();

      expect(find.text(l10n.membershipRequestSentTitle), findsOneWidget);
      expect(
        adapter.requestedPaths,
        contains(endsWith('/telemetry/support')),
      );
      final Map<String, dynamic> body = adapter.requestBodies.last;
      final items = body['items'] as List;
      final request = items.single as Map;
      expect(request['title'], 'Personal membership quote request');
      expect(request['description'], contains(l10n.membershipFeatureInventory));
      expect(request['description'],
          contains('Please include training for two staff members.'));
    },
  );
}
