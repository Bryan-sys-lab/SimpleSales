// How an operation says what it did.
//
// Eleven screens used to report an operation's outcome eleven ways: some
// through a snackbar, some through the ERROR helper — so a success and a
// failure looked the same — and several with no failure path at all, so a
// failed import or a failed backup was SILENT.
//
// What this pins:
//   * a success is a POPUP over the work, not a screen the owner has to
//     dismiss before they can carry on selling;
//   * a failure is a popup too, and it stays longer than a success, because a
//     failure nobody acts on is a failure that happens again;
//   * a failure offers the way out when there IS one, and does not offer a
//     "Try again" that cannot help when there is not;
//   * the error is never the exception's text.
//
// The popup is a SnackBar, so these tests read the SnackBar's own content
// rather than a sheet's — a sheet would be found by the same `find.text`, and
// a test that cannot tell the two apart is not testing the thing that
// changed.

import 'package:duka_pos/ui/components/operation_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// The text of the popup currently on screen, or null when there is none.
String? popupText(WidgetTester tester) {
  final Finder snack = find.byType(SnackBar);
  if (snack.evaluate().isEmpty) return null;
  final Iterable<Text> texts = tester.widgetList<Text>(find.descendant(
    of: snack,
    matching: find.byType(Text),
  ));
  return texts.map((Text t) => t.data ?? '').join(' | ');
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a success says what happened, over the work', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showOperationSuccess(
              context,
              title: 'Backup made',
              message: 'The encrypted backup is ready to share.',
              detail: 'duka-backup-2026-10-20.duka',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // The three facts, in one popup.
    final String? text = popupText(tester);
    expect(text, isNotNull);
    expect(text, contains('Backup made'));
    expect(text, contains('The encrypted backup is ready to share.'));
    expect(text, contains('duka-backup-2026-10-20.duka'));

    // And NO screen: the owner is not made to dismiss anything to keep
    // selling. A sheet would be a route on the navigator.
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a failure says what failed and offers the way out',
      (tester) async {
    tester.useDevice(Device.small);
    bool retried = false;
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showOperationFailure(
              context,
              title: 'The backup failed',
              message: 'The backup could not be made.',
              onRetry: () => retried = true,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(popupText(tester), contains('The backup could not be made.'));

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
  });

  testWidgets('a failure with nothing to retry offers no button',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showOperationFailure(
              context,
              title: 'The backup was not restored',
              message: 'That file is not one of ours.',
              // A malformed file will be malformed again: a "Try again" that
              // cannot help is worse than none.
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(popupText(tester), contains('That file is not one of ours.'));
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a failure stays up longer than a success', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showOperationFailure(
              context,
              title: 'The import failed',
              message: 'The workbook could not be read.',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(popupText(tester), isNotNull);

    // Still there after a success would have gone. The success is a fact
    // about the past; the failure is a fact about what happens next.
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(popupText(tester), isNotNull);
  });

  testWidgets('the runner shows the failure and reports it', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => runOperation(
              context,
              operation: () async => throw StateError('a file path leaked'),
              successTitle: 'Import complete',
              failureTitle: 'The import failed',
              failureMessage: 'The workbook could not be read.',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // The failure popup, in the app's words — NOT the exception's.
    final String? text = popupText(tester);
    expect(text, contains('The workbook could not be read.'));
    expect(text, isNot(contains('a file path leaked')));
  });

  testWidgets('the runner shows the success', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => runOperation(
              context,
              operation: () async {},
              successTitle: 'Import complete',
              successMessage: '42 products were imported.',
              failureTitle: 'The import failed',
              failureMessage: 'The workbook could not be read.',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final String? text = popupText(tester);
    expect(text, contains('Import complete'));
    expect(text, contains('42 products were imported.'));
  });

  testWidgets('it fits a 320dp phone at 200% text', (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showOperationFailure(
              context,
              title: 'The import failed',
              message: 'The workbook could not be read. It may not be one of '
                  'ours, or it may have been changed since it was made.',
              onRetry: () {},
            ),
            child: const Text('go'),
          ),
        ),
      ),
      textScaler: TextScaler.linear(2.0),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    tester.expectNoOverflow('operation failure popup at 2x text');
  });

  group('the popup never takes the app with it', () {
    // The report this pins: an owner edited their account profile in
    // Settings, the success screen came up, they cancelled it, and the app
    // went BLANK — the phone showed nothing, and the only way back was
    // killing the app.
    //
    // The cause was the shape, not the copy. The outcome used to be a modal
    // SHEET: a route on a navigator. Cancelling it popped that route, and the
    // pop reached the wrong navigator — the shell's, above the branch that
    // was actually on screen — and the shell had nothing left to show.
    //
    // So the invariant is not "the copy is friendly". It is: THE OUTCOME IS
    // NOT A ROUTE. Nothing is pushed, so nothing can be popped, so no cancel
    // can take a screen with it.

    testWidgets('a success pushes no route', (tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showOperationSuccess(
                context,
                title: 'Profile saved',
                message: 'Amina Duka',
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );

      // The app's own navigator, read after the app is up: a MaterialApp
      // with a `home` has exactly one route on it, and `canPop` is false.
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      expect(
        navigator.canPop(),
        isFalse,
        reason: 'the app starts with nothing to go back to',
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(
        navigator.canPop(),
        isFalse,
        reason:
            'the outcome must not be a route: a route is something that can '
            'be popped, and a pop that reaches the wrong navigator is what '
            'blanked the app',
      );
    });

    testWidgets('cancelling the outcome leaves the screen alive',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Column(
              children: <Widget>[
                const Text('the settings screen'),
                TextButton(
                  onPressed: () => showOperationSuccess(
                    context,
                    title: 'Profile saved',
                    message: 'Amina Duka',
                  ),
                  child: const Text('go'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(popupText(tester), contains('Profile saved'));

      // Dragged away, the way a person dismisses a popup with a thumb.
      await tester.drag(find.byType(SnackBar), const Offset(0, 400));
      await tester.pumpAndSettle();

      // The screen underneath is still there, and still says what it is.
      expect(
        find.text('the settings screen'),
        findsOneWidget,
        reason: 'dismissing the outcome must leave the app exactly as it was',
      );
      expect(popupText(tester), isNull);
    });
  });
}
