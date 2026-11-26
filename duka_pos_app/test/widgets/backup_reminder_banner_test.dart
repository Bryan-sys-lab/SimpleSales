import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/theme/app_colors.dart';
import 'package:duka_pos/widgets/backup_reminder_banner.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('backup reminder uses neutral copy and runs its backup action',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var backupRequested = false;

    await tester.pumpApp(
      home: BackupReminderBanner(
        onBackupNow: () async {
          backupRequested = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext context =
        tester.element(find.byType(BackupReminderBanner));
    final AppColors colors = AppColors.of(context);
    final MaterialBanner banner =
        tester.widget<MaterialBanner>(find.byType(MaterialBanner));
    expect(banner.backgroundColor, colors.surface);
    expect(
      tester
          .widget<Text>(
            find.text(
                "It's been a while since the last backup. Worth doing one now?"),
          )
          .style
          ?.color,
      colors.onSurfaceVariant,
    );

    final AppLocalizations l10n = AppLocalizations.of(context);
    await tester.tap(find.text(l10n.backupNowAction));
    await tester.pumpAndSettle();

    expect(backupRequested, isTrue);
    expect(find.byType(MaterialBanner), findsNothing);
  });
}
