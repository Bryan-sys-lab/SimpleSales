// The manager approval sheet: who approved this, and how we know.
//
// ## WHAT IS PINNED
//
// The sheet answers one question — WHO a manager is, by their own PIN — and
// every way that question can resolve wrongly is a hole in the audit trail:
//
//   * a WRONG PIN must never approve, and must be said out loud;
//   * the CORRECT PIN closes the sheet with that manager, so the caller can
//     record the approver's id;
//   * Cancel (or dismissal) is DECLINE: null comes back, never an approval;
//   * a shop with nobody who could approve says so plainly.
//
// The route is opened for real (showModalBottomSheet) so the pop plumbing —
// what the CALLER receives — is exercised too. The button callbacks are then
// invoked directly rather than through pointer taps: the harness's test view
// has no safe-area insets, so a modal sheet at the bottom edge reports hit
// targets numerically outside the root render box and a synthetic tap would
// miss them for layout reasons that have nothing to do with this sheet.
//
// ## WHY EVERY WAIT IS A RETRY BRIDGE
//
// The staff read and the PIN check are real database and PBKDF2-isolate
// replies, which land only inside `tester.runAsync` — there they land at an
// unpredictable moment. The helpers bridge repeatedly until the awaited state
// is on screen, bounded, so the test stays deterministic.

import 'dart:convert' show base64Url;

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/auth_service.dart';
import 'package:duka_pos/ui/dialogs/manager_approval_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/harness.dart';

void main() {
  late final AppLocalizations l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadAppFonts();
    l10n = await loadL10n();
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DatabaseHelper.openInMemoryForTests();
  });

  /// Bridges real time in bounded windows until [finder] matches, or fails
  /// after the budget. Each frame advances the fake clock, so the sheet's
  /// enter/exit animations run. Never pumpAndSettle: the focused PIN field's
  /// caret blinks forever.
  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int windows = 30,
    Duration window = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < windows; i++) {
      await tester.pump(window);
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(() => Future<void>.delayed(window));
    }
    await tester.pump(window * 4);
    if (finder.evaluate().isEmpty) {
      fail('the awaited state never appeared');
    }
  }

  /// Bridges real time in bounded windows until the sheet has left the route
  /// stack, running the exit animation's frames as it goes.
  Future<void> pumpUntilClosed(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (find.byType(ManagerApprovalSheet).evaluate().isEmpty) return;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
    }
    await tester.pump(const Duration(milliseconds: 300));
    if (find.byType(ManagerApprovalSheet).evaluate().isNotEmpty) {
      fail('the approval sheet never closed');
    }
  }

  /// Seeds one active manager whose PIN is 654321, with the modern
  /// self-describing PBKDF2 format the sheet's verifier accepts. The
  /// derivation lands only in real time, like every other isolate answer.
  Future<void> seedManager(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final salt = List<int>.generate(16, (int i) => (i * 13) & 0xFF);
      final derived = await derivePbkdf2Key(
          Pbkdf2Request('654321', salt, AuthService.defaultIterations, 256));
      final hash =
          'pbkdf2\$${AuthService.defaultIterations}\$${base64Url.encode(salt)}\$${base64Url.encode(derived)}';
      await DatabaseHelper.instance
          .addStaff(Staff(name: name, pinHash: hash, role: 'manager'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
  }

  /// Opens the sheet through a real modal route whose result is captured
  /// verbatim — null means the caller was DECLINED, and the assertions hold
  /// the sheet to that promise.
  Future<ManagerApprovalCapture> openSheet(WidgetTester tester) async {
    final capture = ManagerApprovalCapture();
    tester.useDevice(Device.medium);
    await tester.pumpApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                capture.result = await showManagerApprovalSheet(
                  context,
                  purpose: 'Approve the stock adjustment',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The enter animation must run out before the content settles.
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilFound(tester, find.byType(ManagerApprovalSheet));
    return capture;
  }

  /// Picks an approver through the row's own callback (a loaded list is one
  /// of the sheet's promises: pick yourself, type only your PIN).
  Future<void> pick(WidgetTester tester, String name) async {
    final ListTile row = tester.widget<ListTile>(
      find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
    );
    row.onTap!();
    await tester.pump(const Duration(milliseconds: 60));
  }

  /// Types a full 6-digit PIN; the check starts itself at the last digit and
  /// ends with the sheet closed or a failure banner on it.
  Future<void> typePin(WidgetTester tester, String pin) async {
    await tester.enterText(find.byType(TextField), pin);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      final bool closed =
          find.byType(ManagerApprovalSheet).evaluate().isEmpty;
      final bool failed =
          find.text(l10n.approvalWrongPin).evaluate().isNotEmpty;
      if (closed || failed) return;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Presses a named action button through its own callback.
  Future<void> press(
    WidgetTester tester,
    Finder finder,
    Type buttonType,
  ) async {
    final Widget button = tester.widget(
      find.ancestor(of: finder, matching: find.byType(buttonType)).first,
    );
    final VoidCallback? action = switch (button) {
      (OutlinedButton b) => b.onPressed,
      (FilledButton b) => b.onPressed,
      _ => null,
    };
    action!();
    await pumpUntilClosed(tester);
  }

  testWidgets('a wrong PIN never approves and says so', (tester) async {
    await seedManager(tester, 'Wanjiku');
    final ManagerApprovalCapture capture = await openSheet(tester);
    await pumpUntilFound(tester, find.byType(TextField));

    await pick(tester, 'Wanjiku');
    await typePin(tester, '111111');

    // The sheet is still open and the failure is on it, in words the
    // approver can act on; nothing was approved.
    expect(find.byType(ManagerApprovalSheet), findsOneWidget);
    expect(find.text(l10n.approvalWrongPin), findsOneWidget);
    expect(capture.result, isNull);

    // A correct attempt right after a wrong one succeeds: no sign-in-style
    // lockout stands between an approver and their own correction.
    await typePin(tester, '654321');
    expect(find.byType(ManagerApprovalSheet), findsNothing);
  });

  testWidgets('the correct PIN closes with that manager', (tester) async {
    await seedManager(tester, 'Wanjiku');
    final ManagerApprovalCapture capture = await openSheet(tester);
    await pumpUntilFound(tester, find.byType(TextField));

    await pick(tester, 'Wanjiku');
    await typePin(tester, '654321');

    expect(capture.result, isNotNull);
    expect(capture.result!.name, 'Wanjiku');
    expect(capture.result!.role, 'manager');
  });

  testWidgets('Cancel is a decline: the caller gets null', (tester) async {
    await seedManager(tester, 'Wanjiku');
    final ManagerApprovalCapture capture = await openSheet(tester);
    await pumpUntilFound(tester, find.byType(TextField));

    await press(
        tester, find.text(l10n.actionCancel), OutlinedButton);

    expect(capture.result, isNull);
    expect(find.byType(ManagerApprovalSheet), findsNothing);
  });

  testWidgets('a shop with no approvers says so plainly', (tester) async {
    await tester.runAsync(() async {
      await DatabaseHelper.instance
          .addStaff(Staff(name: 'Amina', pinHash: '', role: 'cashier'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await openSheet(tester);
    await pumpUntilFound(tester, find.byType(ManagerApprovalSheet));
    await pumpUntilFound(tester, find.text(l10n.approvalNoManagers));
    // No PIN field is offered: there is nobody to approve the action.
    expect(find.byType(TextField), findsNothing);
  });
}

/// Captures what the caller got back from the sheet, verbatim.
class ManagerApprovalCapture {
  Staff? result;
}
