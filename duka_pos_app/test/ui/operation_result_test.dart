// How an operation says what it did.
//
// Eleven screens used to report an operation's outcome eleven ways: some
// through a snackbar, some through the ERROR helper — so a success and a
// failure looked the same — and several with no failure path at all, so a
// failed import or a failed backup was SILENT.
//
// What this pins:
//   * a success is a screen, with what happened, and one button that puts the
//     owner back to work;
//   * a failure is a screen too, because a failure nobody acts on is a
//     failure that happens again;
//   * a failure offers the way out when there IS one, and does not offer a
//     "Try again" that cannot help when there is not;
//   * the error is never the exception's text.

import 'package:duka_pos/ui/components/operation_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a success says what happened and closes', (tester) async {
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

    // The three facts.
    expect(find.text('Backup made'), findsOneWidget);
    expect(find.text('The encrypted backup is ready to share.'), findsOneWidget);
    expect(find.text('duka-backup-2026-10-20.duka'), findsOneWidget);

    // And a way back.
    expect(find.byType(FilledButton), findsOneWidget);
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

    expect(find.text('The backup could not be made.'), findsOneWidget);

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

    expect(find.text('That file is not one of ours.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('the runner shows the failure and reports it',
      (tester) async {
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

    // The failure sheet, in the app's words — NOT the exception's.
    expect(find.text('The workbook could not be read.'), findsOneWidget);
    expect(find.textContaining('a file path leaked'), findsNothing);
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

    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('42 products were imported.'), findsOneWidget);
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

    tester.expectNoOverflow('operation failure sheet at 2x text');
  });
}
