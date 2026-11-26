import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/paywall_screen.dart';
import 'package:duka_pos/screens/plan_details_screen.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:flutter/widgets.dart' show Scrollable, ValueKey;
import 'package:material_ui/material_ui.dart'
    show
        Builder,
        MaterialPageRoute,
        NavigationBar,
        Navigator,
        Scaffold,
        Text,
        TextButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/harness.dart';

class _VoucherAdapter implements HttpClientAdapter {
  final List<String> requestedPaths = <String>[];
  bool existingAccess = false;
  bool configuredPayment = false;
  bool acceptedAgreement = false;
  bool voucherClaimed = false;
  String paymentStatus = 'PENDING';
  Map<String, Object?>? paymentRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    if (options.path.endsWith('/tenant/subscription/payment') &&
        options.method == 'POST') {
      paymentRequest = Map<String, Object?>.from(options.data as Map);
      return ResponseBody.fromString(
        jsonEncode(<String, Object?>{
          'reference': 'SUBS-test-reference',
          'amountMinor': 27000,
          'baseAmountMinor': 30000,
          'discountAmountMinor': 3000,
          'discountPercent': 10,
          'durationMonths': 3,
          'agreementId': acceptedAgreement ? 'agreement-1' : null,
          'paymentMethod': <String, Object?>{
            'method': 'mpesa_stk',
            'channelType': 'paybill',
            'shortCode': '123456',
            'accountNumber': null,
          },
          'status': 'PENDING',
        }),
        201,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    if (options.path.contains('/tenant/subscription/payment/')) {
      return ResponseBody.fromString(
        jsonEncode(<String, Object?>{'status': paymentStatus}),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    final bool claiming = options.path.endsWith('/auth/voucher/claim') ||
        options.path.endsWith('/auth/voucher/redeem');
    if (claiming) voucherClaimed = true;
    final int durationMonths = configuredPayment ? 3 : 1;
    final String billingInterval = configuredPayment ? 'quarterly' : 'monthly';
    final int discountPercent =
        acceptedAgreement || (voucherClaimed && configuredPayment) ? 25 : 10;
    final int baseAmountMinor = 30000;
    final int amountMinor = baseAmountMinor * (100 - discountPercent) ~/ 100;
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
              'priceMinor': configuredPayment ? 10000 : 100000,
              'discountPercent': discountPercent,
              'discountVoucherDurationMonths': 3,
              'currency': 'KES',
              'billingInterval': billingInterval,
              'currentPeriodEnd': null,
            },
          }
        : <String, Object?>{
            'entitlement': <String, Object?>{
              'allowed': existingAccess,
              'status': existingAccess ? 'active' : 'pending',
              'reason': existingAccess ? 'active' : 'subscription_required',
              'priceMinor': configuredPayment ? 10000 : 100000,
              'discountPercent': discountPercent,
              if (voucherClaimed) 'discountVoucherDurationMonths': 3,
              'currency': 'KES',
              'billingInterval': billingInterval,
              'currentPeriodEnd': null,
            },
            'support': <String, Object?>{
              if (configuredPayment)
                'paymentMethod': <String, Object?>{
                  'method': 'mpesa_stk',
                  'channelType': 'paybill',
                  'shortCode': '123456',
                  'accountNumber': null,
                },
              if (configuredPayment)
                'checkout': <String, Object?>{
                  'amountMinor': amountMinor,
                  'baseAmountMinor': baseAmountMinor,
                  'discountAmountMinor': baseAmountMinor - amountMinor,
                  'discountPercent': discountPercent,
                  'durationMonths': durationMonths,
                  'agreementId': acceptedAgreement ? 'agreement-1' : null,
                },
              if (!voucherClaimed)
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

  testWidgets('keeps only vouchers and displays configured price and period',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    final adapter = _VoucherAdapter();
    BackendService.setHttpClientAdapterForTesting(adapter);
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

    await tester.pumpApp(home: const PaywallScreen());
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text(l10n.membershipPlans), findsNothing);
    expect(find.text(l10n.membershipQuote), findsNothing);
    expect(find.text(l10n.membershipHelp), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('subscription-price-period')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey<String>('subscription-price-period')),
        findsOneWidget);
    expect(find.text('KES 1000.00'), findsOneWidget);
    expect(
        find.text(l10n.planDetailsBillingPeriod(l10n.billingIntervalMonthly)),
        findsOneWidget);
    tester.expectNoOverflow('voucher-only subscription screen');
  });

  testWidgets('claims an available voucher and displays the saved discount',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    final adapter = _VoucherAdapter()..configuredPayment = true;
    BackendService.setHttpClientAdapterForTesting(adapter);
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

    await tester.pumpApp(home: const PaywallScreen());
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
    await tester.scrollUntilVisible(
      find.text(l10n.paywallAvailableDiscountVoucher(25, 3)),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
        find.text(l10n.paywallAvailableDiscountVoucher(25, 3)), findsOneWidget);
    await tester.tap(find.text(l10n.planDetailsClaimVoucher));
    await tester.pumpAndSettle();

    expect(adapter.requestedPaths, contains(endsWith('/auth/voucher/claim')));
    await tester.scrollUntilVisible(
      find.text('KES 225.00'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('KES 225.00'), findsOneWidget);
    expect(find.text('KES 300.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(l10n.paywallDiscountVoucherClaimed(25, 3)).first,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.paywallDiscountVoucherClaimed(25, 3)), findsWidgets);
    expect(
        find.text(l10n.paywallAvailableDiscountVoucher(25, 3)), findsNothing);
    expect(find.text(l10n.paywallVoucherPeriodMismatch(3)), findsNothing);
    tester.expectNoOverflow('claimed discount voucher');
  });

  testWidgets('accepted agreement displays its actual agreed amount',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    final adapter = _VoucherAdapter()
      ..configuredPayment = true
      ..acceptedAgreement = true;
    BackendService.setHttpClientAdapterForTesting(adapter);
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));
    final appState = AppState()..isOwnerSession = true;

    await tester.pumpApp(
      home: const PaywallScreen(),
      appState: appState,
    );
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('subscription-price-period')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.paywallAgreedPrice), findsOneWidget);
    expect(find.text('KES 225.00'), findsNWidgets(2));
    expect(find.text('KES 300.00'), findsNothing);
    expect(
      find.text(l10n.planDetailsBillingPeriod(l10n.billingIntervalQuarterly)),
      findsNWidgets(2),
    );
    await tester.scrollUntilVisible(
      find.text(l10n.paywallDiscount(25)),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.paywallDiscount(25)), findsOneWidget);
    expect(find.text('KES 75.00'), findsOneWidget);
  });

  testWidgets('plan details shows status, price, payment, and voucher access',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    final adapter = _VoucherAdapter()..configuredPayment = true;
    BackendService.setHttpClientAdapterForTesting(adapter);
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

    await tester.pumpApp(home: const PlanDetailsScreen());
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(PlanDetailsScreen)));
    expect(find.text(l10n.planDetailsDashboardTitle), findsOneWidget);
    expect(find.text(l10n.planDetailsStatusActive), findsNothing);
    expect(find.text(l10n.planDetailsStatusPending), findsOneWidget);
    expect(find.text('KES 300.00'), findsOneWidget);
    expect(find.text('KES 270.00'), findsOneWidget);
    expect(find.text(l10n.billingIntervalQuarterly), findsOneWidget);
    expect(
      find.text(l10n.paywallPaymentPaybillDestination('123456')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text(l10n.planDetailsClaimVoucher),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.planDetailsClaimVoucher), findsOneWidget);
    await tester.tap(find.text(l10n.planDetailsClaimVoucher));
    await tester.pumpAndSettle();
    expect(adapter.requestedPaths, contains(endsWith('/auth/voucher/claim')));
    expect(find.byType(PaywallScreen), findsNothing);
    expect(
      find.text(l10n.paywallDiscountVoucherClaimed(25, 3)),
      findsWidgets,
    );
    tester.expectNoOverflow('plan details screen');
  });

  testWidgets('plan details uses the full configured billing-period quote',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    final adapter = _VoucherAdapter()..configuredPayment = true;
    BackendService.setHttpClientAdapterForTesting(adapter);
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

    await tester.pumpApp(home: const PlanDetailsScreen());
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(PlanDetailsScreen)));
    expect(find.text('KES 300.00'), findsOneWidget);
    expect(find.text('KES 270.00'), findsOneWidget);
    expect(find.text(l10n.billingIntervalQuarterly), findsOneWidget);
  });

  testWidgets('shows admin payment terms and starts the server-priced checkout',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    final adapter = _VoucherAdapter()..configuredPayment = true;
    BackendService.setHttpClientAdapterForTesting(adapter);
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));
    final appState = AppState()..isOwnerSession = true;

    await tester.pumpApp(
      home: const PaywallScreen(),
      appState: appState,
    );
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
    await tester.scrollUntilVisible(
      find.text(l10n.paywallAmountDue),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.paywallAmountDue), findsOneWidget);
    expect(find.text('KES 270.00'), findsOneWidget);
    expect(
      find.text(l10n.planDetailsBillingPeriod(l10n.billingIntervalQuarterly)),
      findsNWidgets(2),
    );
    await tester.scrollUntilVisible(
      find.text(l10n.paywallPaymentPaybillDestination('123456')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.paywallPaymentPaybillDestination('123456')),
        findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('subscription-payment-phone')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('subscription-payment-phone')),
      '254700000000',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('subscription-payment-start')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester
        .tap(find.byKey(const ValueKey<String>('subscription-payment-start')));
    await tester.pumpAndSettle();

    expect(adapter.paymentRequest, <String, Object?>{
      'phoneNumber': '254700000000',
    });
    expect(
      find.text(l10n.paywallPaymentReference('SUBS-test-reference')),
      findsOneWidget,
    );
    expect(find.text(l10n.paywallPaymentPending), findsOneWidget);

    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('subscription-payment-check')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('subscription-payment-check')),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey<String>('subscription-payment-check')));
    await tester.pumpAndSettle();
    expect(adapter.requestedPaths,
        contains(endsWith('/tenant/subscription/payment/SUBS-test-reference')));
    expect(find.text(l10n.paywallPaymentPending), findsOneWidget);
    tester.expectNoOverflow('admin-configured subscription checkout');
  });

  testWidgets('redeems a manually entered voucher',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await WorkspaceService.register(
      workspaceKey: 'paywall-test',
      tenantId: 'tenant-test',
      shopName: 'Paywall test',
    );
    await WorkspaceService.setActiveWorkspace('paywall-test');
    final adapter = _VoucherAdapter();
    BackendService.setHttpClientAdapterForTesting(adapter);
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

    await tester.pumpApp(home: const PaywallScreen());
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('membership-voucher-code')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('membership-voucher-code')),
      'SS-DISCOUNT-MANUAL',
    );
    await tester.scrollUntilVisible(
      find.text(l10n.paywallApplyVoucher),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(l10n.paywallApplyVoucher));
    await tester.pumpAndSettle();

    expect(adapter.requestedPaths, contains(endsWith('/auth/voucher/redeem')));
    expect(find.text(l10n.paywallDiscountVoucherClaimed(25, 3)), findsWidgets);
    tester.expectNoOverflow('manual voucher redemption');
  });

  testWidgets('a required subscription cannot be backed out into Settings',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    BackendService.setHttpClientAdapterForTesting(_VoucherAdapter());
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

    await tester.pumpApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey<String>('open-required-subscription'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const PaywallScreen(subscriptionRequired: true),
              ),
            ),
            child: const Text('Settings'),
          ),
        ),
      ),
    );
    await tester
        .tap(find.byKey(const ValueKey<String>('open-required-subscription')));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('an optional voucher screen can return to Settings',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    BackendService.setHttpClientAdapterForTesting(_VoucherAdapter());
    addTearDown(() => BackendService.setHttpClientAdapterForTesting(null));

    await tester.pumpApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey<String>('open-optional-subscription'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const PaywallScreen(),
              ),
            ),
            child: const Text('Settings'),
          ),
        ),
      ),
    );
    await tester
        .tap(find.byKey(const ValueKey<String>('open-optional-subscription')));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(PaywallScreen)));
    await tester.tap(find.byTooltip(l10n.planDetailsTitle));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });
}
