import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/signup_paywall_screen.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('requires the issued voucher before completing registration',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const SignupPaywallScreen(
        registration: PendingRegistration(
          email: 'owner@example.com',
          pin: '123456',
          code: '654321',
          shopName: 'Shop',
          ownerName: 'Owner',
        ),
      ),
    );

    final AppLocalizations l10n =
        AppLocalizations.of(tester.element(find.byType(SignupPaywallScreen)));
    expect(find.text(l10n.signupPaywallHeadline), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    tester.expectNoOverflow('signup voucher screen');

    await tester.tap(find.text(l10n.signupPaywallRedeem));
    await tester.pump();

    expect(find.text(l10n.signupPaywallVoucherRequired), findsOneWidget);
    tester.expectNoOverflow('signup voucher validation');
  });
}
