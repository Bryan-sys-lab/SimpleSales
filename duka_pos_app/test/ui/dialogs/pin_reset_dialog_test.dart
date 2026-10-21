// The Forgot-PIN dialog: the parts a locked-out owner has to get past.
//
// The bugs this covers are all the same shape: the dialog left the owner
// STUCK.
//
//  * An error that was not a typed [PinResetException] — a raw socket error, a
//    storage exception, a bug — left the button reading "Sending…" or
//    "Saving…" for the rest of the session. The owner was told the app was
//    working, and it was not.
//  * There was no resend. The owner who did not get the email had exactly one
//    way out: close the dialog, which drops the challenge, and start again —
//    losing the code they had already typed.
//  * The code field did not offer itself to the platform's autofill, so a code
//    that arrived by SMS had to be read off one phone and typed into another.
//
// The network calls are INJECTED, because a widget whose only path to its
// behaviour is a live backend is a widget nobody can test.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/services/pin_reset_service.dart';
import 'package:duka_pos/ui/dialogs/pin_reset_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  Widget dialog({
    Future<PinResetOutcome> Function()? requestCode,
    Future<bool> Function(String code, String newPin)? confirm,
  }) =>
      Scaffold(
        body: Center(
          child: PinResetDialog(
            ownerEmail: 'amina@duka.co.ke',
            requestCode: requestCode,
            confirm: confirm,
          ),
        ),
      );

  group('an error that is not a typed failure still ends the button', () {
    testWidgets('a request that throws something else comes back',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: dialog(
          requestCode: () async => throw StateError('the socket exploded'),
        ),
      );

      await tester.tap(find.text(l10n.pinResetSendCode));
      await tester.pumpAndSettle();

      // The button is back to asking, not stuck on "Sending…".
      expect(find.text(l10n.pinResetSendCode), findsOneWidget);
      expect(find.text(l10n.pinResetSending), findsNothing);

      // And the owner is told, in words they can act on.
      expect(find.text(l10n.errorUnknown), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a save that throws something else comes back',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: dialog(
          requestCode: () async =>
              const PinResetOutcome(maskedEmail: 'a***@duka.co.ke'),
          confirm: (String code, String newPin) async =>
              throw StateError('the database went away'),
        ),
      );

      await tester.tap(find.text(l10n.pinResetSendCode));
      await tester.pumpAndSettle();

      // Into the second step.
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.enterText(find.byType(TextField).at(2), '123456');
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.actionSave));
      await tester.pumpAndSettle();

      // The button is not stuck on "Saving…".
      expect(find.text(l10n.pinResetSaving), findsNothing);
      expect(find.text(l10n.actionSave), findsOneWidget);
      expect(find.text(l10n.errorUnknown), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the owner can ask for another code', () {
    testWidgets('a resend appears once a code has been asked for',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      int asked = 0;
      await tester.pumpApp(
        home: dialog(
          requestCode: () async {
            asked++;
            return const PinResetOutcome(maskedEmail: 'a***@duka.co.ke');
          },
        ),
      );

      await tester.tap(find.text(l10n.pinResetSendCode));
      await tester.pumpAndSettle();
      expect(asked, 1);

      // The resend is there, in the step that needs it.
      expect(find.text(l10n.pinResetResend), findsOneWidget);

      // And it asks again — without closing the dialog, which is what used to
      // throw the challenge away.
      await tester.tap(find.text(l10n.pinResetResend));
      await tester.pumpAndSettle();
      expect(asked, 2);
      expect(find.text(l10n.pinResetResend), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a resend clears the code that was typed',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: dialog(
          requestCode: () async =>
              const PinResetOutcome(maskedEmail: 'a***@duka.co.ke'),
        ),
      );

      await tester.tap(find.text(l10n.pinResetSendCode));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '111111');
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.pinResetResend));
      await tester.pumpAndSettle();

      // The code that was mailed is spent; leaving it in the field invites the
      // owner to redeem a code the server has already thrown away.
      final TextField codeField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(codeField.controller?.text, isEmpty);
    });
  });

  group('the code field offers itself to the platform', () {
    testWidgets('it asks for a one-time code', (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: dialog(
          requestCode: () async =>
              const PinResetOutcome(maskedEmail: 'a***@duka.co.ke'),
        ),
      );

      await tester.tap(find.text(l10n.pinResetSendCode));
      await tester.pumpAndSettle();

      // So a code that arrived by SMS can be offered to the field, instead of
      // the owner reading six digits off a phone in one hand and typing them
      // with the other.
      final TextField codeField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(codeField.autofillHints, contains(AutofillHints.oneTimeCode));
    });
  });
}
