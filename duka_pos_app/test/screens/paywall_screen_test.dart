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
  bool offerReady = false;
  bool agreementAccepted = false;
  bool paymentStarted = false;

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
    final Map<String, Object?> payload;
    if (options.path.endsWith('/tenant/membership/requests') &&
        options.method == 'POST') {
      payload = <String, Object?>{
        'request': <String, Object?>{
          'id': 'membership-request-1',
          'status': 'pending',
          'features': requestBodies.last['features'],
          'requirements': requestBodies.last['requirements'],
          'offers': <Object>[],
          'messages': <Object>[],
          'agreement': null,
        },
      };
    } else if (options.path.endsWith('/tenant/membership/requests')) {
      payload = <String, Object?>{
        'requests': <Object>[
          <String, Object?>{
            'id': 'membership-request-1',
            'status': agreementAccepted
                ? 'accepted'
                : offerReady
                    ? 'offer_ready'
                    : 'pending',
            'features': <String>['Inventory'],
            'requirements': 'Train two staff members.',
            'offers': offerReady ? <Object>[_membershipOffer] : <Object>[],
            'messages': <Object>[],
            'agreement': agreementAccepted ? _membershipAgreement : null,
          },
        ],
      };
    } else if (options.path.endsWith('/tenant/membership/payments')) {
      payload = <String, Object?>{
        'payments': paymentStarted
            ? <Object>[
                <String, Object?>{
                  'reference': 'SUBS-test',
                  'amountMinor': 7500,
                  'durationMonths': 3,
                  'status': 'PENDING',
                  'agreementId': 'agreement-1',
                  'createdAt': DateTime.now().toIso8601String(),
                },
              ]
            : <Object>[],
      };
    } else if (options.path.endsWith('/tenant/membership/vouchers')) {
      payload = <String, Object?>{'vouchers': <Object>[]};
    } else if (options.path.endsWith('/offers/offer-1/preview')) {
      payload = <String, Object?>{
        'offer': _membershipOffer,
        'pricing': <String, Object?>{
          'currency': 'KES',
          'baseAmountMinor': 10000,
          'discountPercent': 25,
          'discountAmountMinor': 2500,
          'amountMinor': 7500,
          'voucherApplied': true,
          'voucherNotApplicable': false,
        },
      };
    } else if (options.path.endsWith('/offers/offer-1/accept')) {
      agreementAccepted = true;
      payload = <String, Object?>{'agreement': _membershipAgreement};
    } else if (options.path.endsWith('/tenant/subscription/payment') &&
        options.method == 'POST') {
      paymentStarted = true;
      payload = <String, Object?>{
        'reference': 'SUBS-test',
        'amountMinor': 7500,
        'baseAmountMinor': 10000,
        'discountAmountMinor': 2500,
        'discountPercent': 25,
        'durationMonths': 3,
        'agreementId': 'agreement-1',
        'status': 'PENDING',
      };
    } else {
      payload = <String, Object?>{
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
      };
    }
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  static const Map<String, Object?> _membershipOffer = <String, Object?>{
    'id': 'offer-1',
    'revision': 1,
    'status': 'offered',
    'amountMinor': 10000,
    'currency': 'KES',
    'termMonths': 3,
    'paymentArrangement': 'Pay by M-Pesa',
    'renewalTerms': 'Renewal as agreed',
    'includedFeatures': <String>['Inventory', 'Reports'],
    'additionalConditions': null,
    'expiresAt': null,
  };

  static const Map<String, Object?> _membershipAgreement = <String, Object?>{
    'id': 'agreement-1',
    'reference': 'AGR-test',
    'acceptedAt': '2026-11-23T12:00:00.000Z',
    'snapshot': <String, Object?>{
      'amountMinor': 7500,
      'baseAmountMinor': 10000,
      'discountPercent': 25,
      'discountAmountMinor': 2500,
      'currency': 'KES',
      'termMonths': 3,
      'paymentArrangement': 'Pay by M-Pesa',
      'renewalTerms': 'Renewal as agreed',
      'includedFeatures': <String>['Inventory', 'Reports'],
      'additionalConditions': null,
      'voucherId': 'voucher-1',
    },
  };
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
    'claims a discount voucher without showing a fixed subscription price',
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
      expect(find.text(l10n.membershipExistingOffer), findsNothing);
      expect(find.textContaining('KES 2250.00'), findsNothing);
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
    'sends selected membership needs through the dedicated quote request path',
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

      expect(find.text('Request · pending'), findsOneWidget);
      expect(
        adapter.requestedPaths,
        contains(endsWith('/tenant/membership/requests')),
      );
      final Map<String, dynamic> body = adapter.requestBodies.last;
      expect(body['features'], contains(l10n.membershipFeatureInventory));
      expect(body['requirements'],
          'Please include training for two staff members.');
    },
  );

  testWidgets(
    'reviews, accepts, and pays for the accepted membership offer',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await WorkspaceService.register(
        workspaceKey: 'accepted-membership-test',
        tenantId: 'tenant-accepted-membership',
        shopName: 'Accepted membership test',
      );
      await WorkspaceService.setActiveWorkspace('accepted-membership-test');
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
        find.text(l10n.membershipRequestOffer),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(l10n.membershipRequestOffer));
      await tester.pumpAndSettle();

      adapter.offerReady = true;
      await tester.tap(find.byTooltip('Refresh request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review offer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('KES 75.00'), findsOneWidget);
      await tester.tap(find.text('Accept offer'));
      await tester.pumpAndSettle();
      expect(find.text('Reference: AGR-test'), findsOneWidget);
      final acceptBody = adapter.requestBodies
          .firstWhere((body) => body.containsKey('expectedAmountMinor'));
      expect(acceptBody, <String, dynamic>{
        'expectedAmountMinor': 7500,
        'expectedDiscountPercent': 25,
        'expectedVoucherApplied': true,
      });

      await tester.scrollUntilVisible(
        find.text('Complete payment'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byWidgetPredicate((widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'M-Pesa phone number'),
        '254700000000',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Complete payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete payment'));
      await tester.pumpAndSettle();

      expect(adapter.paymentStarted, isTrue);
      expect(adapter.requestBodies.last['agreementId'], 'agreement-1');
      expect(adapter.requestBodies.last['phoneNumber'], '254700000000');
      expect(adapter.requestedPaths,
          contains(endsWith('/tenant/subscription/payment')));
      tester.expectNoOverflow('accepted membership agreement and payment');
    },
  );
}
