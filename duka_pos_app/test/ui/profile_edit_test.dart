// Editing the owner's own details.
//
// The profile used to be read-only, on the grounds that the address is what
// the emailed codes go to. That is true of the EMAIL and false of the rest: a
// shop owner whose name changed, or whose shop was renamed, had no way to
// correct it.
//
// What this pins:
//   * the sheet hands back what was typed, and hands back NOTHING when it is
//     dismissed — a cancelled edit must not change anything;
//   * the save button is disabled until the form is valid, and the reason is
//     on the field rather than in a dialog;
//   * the email is editable, and the sheet says what changing it means.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/widgets/profile_edit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  /// Opens the sheet and exposes what it handed back.
  Future<ValueNotifier<ProfileEdit?>> openSheet(
    WidgetTester tester, {
    String name = 'Amina Duka',
    String shopName = 'Amina Duka',
    String email = 'amina@duka.co.ke',
  }) async {
    final ValueNotifier<ProfileEdit?> result = ValueNotifier<ProfileEdit?>(null);
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              result.value = await showModalBottomSheet<ProfileEdit>(
                context: context,
                isScrollControlled: true,
                builder: (BuildContext sheetContext) => ProfileEditSheet(
                  name: name,
                  shopName: shopName,
                  email: email,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('it hands back what the owner typed', (tester) async {
    tester.useDevice(Device.small);
    final ValueNotifier<ProfileEdit?> result = await openSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextField, l10n.profileEditNameLabel),
      'Amina Wanjiru',
    );
    await tester.enterText(
      find.widgetWithText(TextField, l10n.profileEditShopNameLabel),
      'Mwirigi Store',
    );
    await tester.pumpAndSettle();

    // The email is editable too, and the consequence of changing it is
    // stated ON the sheet, before the owner presses Save.
    expect(find.text(l10n.profileEditEmailWarning), findsOneWidget);

    await tester.tap(find.text(l10n.profileEditSave));
    await tester.pumpAndSettle();

    expect(result.value?.name, 'Amina Wanjiru');
    expect(result.value?.shopName, 'Mwirigi Store');
    expect(result.value?.email, 'amina@duka.co.ke');
  });

  testWidgets('the save button is disabled until the form is valid',
      (tester) async {
    tester.useDevice(Device.small);
    await openSheet(tester);

    FilledButton button() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l10n.profileEditSave),
        );

    // The name starts filled, so it is enabled.
    expect(button().onPressed, isNotNull);

    // Empty the name: a till that says nothing about who it belongs to is a
    // till nobody can claim.
    await tester.enterText(
      find.widgetWithText(TextField, l10n.profileEditNameLabel),
      '',
    );
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
  });

  testWidgets('a dismissed sheet changes nothing', (tester) async {
    tester.useDevice(Device.small);
    final ValueNotifier<ProfileEdit?> result = await openSheet(tester);

    // Dismissed by tapping the barrier.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(result.value, isNull);
  });

  testWidgets('it fits a 320dp phone at 200% text', (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const Scaffold(
        body: ProfileEditSheet(
          name: 'Amina Duka',
          shopName: 'Amina Duka',
          email: 'amina@duka.co.ke',
        ),
      ),
      textScaler: TextScaler.linear(2.0),
    );
    await tester.pumpAndSettle();

    tester.expectNoOverflow('profile edit sheet at 2x text');
  });
}
