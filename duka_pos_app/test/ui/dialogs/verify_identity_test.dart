// The two steps of Verify, as a person types through them.
//
// What matters here is not that the widgets render — it is what happens when
// something is wrong. A verification dialog that closes on a bad code, or that
// shows its error only once before going silent, sends the owner back to the
// top of a three-step flow every time. Both dialogs therefore have to keep
// their field, keep their error, and report only two outcomes.
//
// These dialogs are driven by callbacks rather than by the network, which is
// what makes the failure paths testable at all: the service layer is where the
// HTTP lives, and the copy is where the translation lives.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/ui/dialogs/verify_identity_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

late AppLocalizations l10n;

void main() {
  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('the PIN step', () {
    testWidgets('refuses a short PIN without calling the backend',
        (tester) async {
      var submissions = 0;
      await tester.pumpApp(
        home: VerifyIdentityPinSheet(
          email: 'owner@example.com',
          onSubmit: (pin) async {
            submissions += 1;
            return null;
          },
        ),
      );

      // Nothing to check the PIN against on the device yet: submitting an
      // empty field must not reach the network, because the network is where
      // a wrong PIN would be rate-limited five times before anyone noticed.
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionContinue));
      await tester.pump();
      expect(submissions, 0);

      await tester.enterText(find.byType(TextFormField), '12');
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionContinue));
      await tester.pump();
      expect(submissions, 0);
      tester.expectNoOverflow('pin dialog with a short pin');
    });

    testWidgets('keeps the field and shows why when the PIN is wrong',
        (tester) async {
      await tester.pumpApp(
        home: VerifyIdentityPinSheet(
          email: 'owner@example.com',
          onSubmit: (pin) async => l10n.settingsVerifyPinWrong,
        ),
      );

      await tester.enterText(find.byType(TextFormField), '999999');
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionContinue));
      await tester.pumpAndSettle();

      // The dialog is still open, so the owner retypes rather than starting
      // the whole flow again.
      expect(find.byType(VerifyIdentityPinSheet), findsOneWidget);
      expect(find.text(l10n.settingsVerifyPinWrong), findsOneWidget);
      // The digits are still there. Clearing them is what makes a retry feel
      // like a punishment on a phone keypad.
      expect(find.text('999999'), findsOneWidget);
    });

    testWidgets('hands the PIN back and closes when it is accepted',
        (tester) async {
      String? handedBack;
      await tester.pumpApp(
        home: Builder(builder: (context) {
          return VerifyIdentityPinSheet(
            email: 'owner@example.com',
            onSubmit: (pin) async {
              handedBack = pin;
              return null;
            },
          );
        }),
      );

      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionContinue));
      await tester.pumpAndSettle();

      expect(handedBack, '123456');
      expect(find.byType(VerifyIdentityPinSheet), findsNothing);
    });

    testWidgets('cancels without touching the network', (tester) async {
      var submissions = 0;
      await tester.pumpApp(
        home: VerifyIdentityPinSheet(
          email: 'owner@example.com',
          onSubmit: (pin) async {
            submissions += 1;
            return null;
          },
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, l10n.actionCancel));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyIdentityPinSheet), findsNothing);
      expect(submissions, 0);
    });

    testWidgets('takes digits only', (tester) async {
      await tester.pumpApp(
        home: VerifyIdentityPinSheet(
          email: 'owner@example.com',
          onSubmit: (pin) async => null,
        ),
      );

      await tester.enterText(find.byType(TextFormField), '12ab34cd5678');
      await tester.pump();
      // Digits, and only six of them: a PIN field that accepts letters is a
      // PIN the backend cannot use.
      expect(find.text('123456'), findsOneWidget);
    });
  });

  group('the code step', () {
    testWidgets('shows where the code went and how long it lasts',
        (tester) async {
      await tester.pumpApp(
        home: VerifyIdentityCodeSheet(
          maskedEmail: 'ow***@example.com',
          onSubmit: (code) async => null,
          onResend: () async => null,
        ),
      );

      expect(find.text(l10n.settingsVerifyCodeTitle), findsOneWidget);
      expect(
        find.text(l10n.settingsVerifyCodeMessage('ow***@example.com', 10)),
        findsOneWidget,
      );
      tester.expectNoOverflow('code dialog');
    });

    testWidgets('stays open with the attempts left when the code is wrong',
        (tester) async {
      await tester.pumpApp(
        home: VerifyIdentityCodeSheet(
          maskedEmail: 'ow***@example.com',
          onSubmit: (code) async => l10n.settingsVerifyCodeWrong(3),
          onResend: () async => null,
        ),
      );

      await tester.enterText(find.byType(TextField), '111111');
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionContinue));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyIdentityCodeSheet), findsOneWidget);
      expect(find.text(l10n.settingsVerifyCodeWrong(3)), findsOneWidget);
    });

    testWidgets('accepts six digits and closes', (tester) async {
      String? handedBack;
      await tester.pumpApp(
        home: VerifyIdentityCodeSheet(
          maskedEmail: 'ow***@example.com',
          onSubmit: (code) async {
            handedBack = code;
            return null;
          },
          onResend: () async => null,
        ),
      );

      await tester.enterText(find.byType(TextField), '481503');
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionContinue));
      await tester.pumpAndSettle();

      expect(handedBack, '481503');
      expect(find.byType(VerifyIdentityCodeSheet), findsNothing);
    });

    testWidgets('refuses five digits without a round trip', (tester) async {
      var submissions = 0;
      await tester.pumpApp(
        home: VerifyIdentityCodeSheet(
          maskedEmail: 'ow***@example.com',
          onSubmit: (code) async {
            submissions += 1;
            return null;
          },
          onResend: () async => null,
        ),
      );

      await tester.enterText(find.byType(TextField), '48150');
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionContinue));
      await tester.pump();

      expect(submissions, 0);
      // The error says what to DO, not what the field is called.
      //
      // It used to show the field's own label — "6-digit code" — as the
      // error, which is the one piece of information the person filling it in
      // already had, and says nothing they can act on.
      expect(find.text(l10n.settingsVerifyCodeInvalid), findsOneWidget);
    });

    testWidgets('offers a new code without restarting the flow',
        (tester) async {
      var resends = 0;
      await tester.pumpApp(
        home: VerifyIdentityCodeSheet(
          maskedEmail: 'ow***@example.com',
          onSubmit: (code) async => null,
          onResend: () async {
            resends += 1;
            return l10n.settingsVerifyCodeSent('ow***@example.com');
          },
        ),
      );

      // The resend is a text button beside the error line, not an action in the
      // dialog's bar: the owner who did not get the email should not have to
      // cancel to ask again.
      await tester.tap(find.text(l10n.settingsVerifyResendAction));
      await tester.pumpAndSettle();

      expect(resends, 1);
      expect(find.byType(VerifyIdentityCodeSheet), findsOneWidget);
      // A successful resend confirms where the new code went, in the same line
      // that used to carry the error.
      expect(
        find.text(l10n.settingsVerifyCodeSent('ow***@example.com')),
        findsOneWidget,
      );
    });

    testWidgets('reports a failed resend and stays put', (tester) async {
      await tester.pumpApp(
        home: VerifyIdentityCodeSheet(
          maskedEmail: 'ow***@example.com',
          onSubmit: (code) async => null,
          onResend: () async => l10n.settingsVerifyEmailFailed,
        ),
      );

      await tester.tap(find.text(l10n.settingsVerifyResendAction));
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsVerifyEmailFailed), findsOneWidget);
      expect(find.byType(VerifyIdentityCodeSheet), findsOneWidget);
    });
  });

  group('the code step at the extremes of the matrix', () {
    for (final Device device in Device.all) {
      testWidgets('fits on ${device.name} at 2.0x text', (tester) async {
        tester.useDevice(device);
        await tester.pumpApp(
          home: VerifyIdentityCodeSheet(
            maskedEmail: 'owner@example.com',
            onSubmit: (code) async => l10n.settingsVerifyCodeWrong(3),
            onResend: () async => l10n.settingsVerifyTooManyCodes,
          ),
          textScaler: TextScaler.linear(2.0),
        );

        // With both failure lines on screen at the largest text scale the app
        // supports: the owner reading them is doing so on the phone they own,
        // at the size they chose.
        await tester.enterText(find.byType(TextField), '111111');
        await tester
            .tap(find.widgetWithText(FilledButton, l10n.actionContinue));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.settingsVerifyResendAction));
        await tester.pumpAndSettle();

        tester.expectNoOverflow('code dialog at 2.0x on ${device.name}');
      });
    }
  });
}
