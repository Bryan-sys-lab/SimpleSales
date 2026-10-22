// The three screens a till shows when something is not the happy path.
//
//   * The STATUS BAR — the strip that says the till is offline, or that the
//     backup is late, or that the account deletion has not reached the
//     server. It is a strip, not a dialog: a till's state changes without
//     anybody asking it to, and none of those changes is worth stopping a
//     sale for.
//   * The SUCCESS VIEW — the moment a sale is done, with the amount and the
//     change, because a snackbar cannot be read while a cashier is counting
//     coins out of a drawer.
//   * The ERROR VIEW — what a screen shows when it could not load. It is
//     already used in ten places; what is worth proving is that it always
//     offers the way out.
//
// What the three share: none of them is silent, and none of them is a dead
// end.

import 'package:duka_pos/ui/components/states.dart';
import 'package:duka_pos/ui/components/success_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  group('the success view', () {
    testWidgets('shows the amount, the method and the change', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(
          body: SuccessView(
            title: 'Sale recorded',
            message: 'Paid in cash',
            amountLabel: 'KSh 1,240.00',
            facts: <SuccessFact>[
              SuccessFact(label: 'Paid', value: 'KSh 1,500.00'),
              SuccessFact(label: 'Change', value: 'KSh 260.00'),
            ],
          ),
        ),
      );

      // The three facts the screen exists for: what was handed over, how it
      // was paid, and what to give back. A cashier counts coins out of a
      // drawer while reading them, so each is its own line — a sentence like
      // "Paid in cash, change due KSh 260" makes the eye hunt for the number
      // it is about to speak.
      expect(find.text('Sale recorded'), findsOneWidget);
      expect(find.text('Paid in cash'), findsOneWidget);
      expect(find.text('KSh 1,240.00'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('KSh 1,500.00'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('KSh 260.00'), findsOneWidget);
    });

    testWidgets('an exact cash sale still answers "do I owe them change?"', (
      tester,
    ) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(
          body: SuccessView(
            title: 'Sale recorded',
            message: 'Paid in cash',
            amountLabel: 'KSh 1,240.00',
            facts: <SuccessFact>[
              SuccessFact(label: 'Paid', value: 'KSh 1,240.00'),
              SuccessFact(label: 'Change', value: 'KSh 0.00'),
            ],
          ),
        ),
      );

      expect(find.text('KSh 0.00'), findsOneWidget);
    });

    testWidgets('the next button moves on', (tester) async {
      tester.useDevice(Device.small);
      bool next = false;
      await tester.pumpApp(
        home: Scaffold(
          body: SuccessView(
            title: 'Sale recorded',
            message: 'Paid in cash',
            amountLabel: 'KSh 1,240.00',
            onNext: () => next = true,
            nextLabel: 'Next sale',
          ),
        ),
      );

      expect(find.text('Next sale'), findsOneWidget);
      await tester.tap(find.text('Next sale'));
      await tester.pumpAndSettle();
      expect(next, isTrue);
    });

    testWidgets('it fits a 320dp phone at 200% text', (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: const Scaffold(
          body: SuccessView(
            title: 'Sale recorded',
            message: 'Paid by M-Pesa',
            amountLabel: 'KSh 1,240.00',
            facts: <SuccessFact>[
              SuccessFact(label: 'Paid', value: 'KSh 1,500.00'),
              SuccessFact(label: 'Change', value: 'KSh 260.00'),
            ],
            detail: 'The receipt is still printing.',
          ),
        ),
        textScaler: TextScaler.linear(2.0),
      );
      await tester.pumpAndSettle();

      tester.expectNoOverflow('success view at 2x text');
    });
  });

  group('the error view', () {
    testWidgets('always offers the way out', (tester) async {
      tester.useDevice(Device.small);
      bool retried = false;
      await tester.pumpApp(
        home: Scaffold(
          body: ErrorStateView(
            message: 'The product catalogue could not be read.',
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('The product catalogue could not be read.'),
          findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(retried, isTrue);
    });

    testWidgets('it fits a 320dp phone at 200% text', (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: const Scaffold(
          body: ErrorStateView(
            message: 'The product catalogue could not be read.',
            detail: 'Selling needs the catalogue. Nothing has been charged.',
            onRetry: null,
          ),
        ),
        textScaler: TextScaler.linear(2.0),
      );
      await tester.pumpAndSettle();

      tester.expectNoOverflow('error view at 2x text');
    });
  });
}
