import 'package:flutter/material.dart';

import '../services/excel_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../ui/components/controls.dart';

/// A soft, non-blocking nudge — never a dialog that stops someone mid-sale —
/// reminding the owner to back up if it's been a while. Checked once when the
/// dashboard loads; dismissing it just hides it for this session, it isn't
/// meant to be nagged into oblivion, just to catch the case where a backup
/// has genuinely been forgotten for days.
///
/// Colours come from the warning slots as a matched PAIR: a container to read
/// on and an on-container tone for the ink inside it. Reusing one value for
/// both is how a warning banner ends up at 3:1 in dark mode without anybody
/// measuring it.
class BackupReminderBanner extends StatefulWidget {
  const BackupReminderBanner({
    super.key,
    required this.onBackupNow,
  });

  final Future<void> Function() onBackupNow;

  @override
  State<BackupReminderBanner> createState() => _BackupReminderBannerState();
}

class _BackupReminderBannerState extends State<BackupReminderBanner> {
  bool _dismissed = false;

  /// Null until the check resolves. A "no" is as good as a dismissal here: the
  /// banner is simply not there.
  bool? _overdue;

  @override
  void initState() {
    super.initState();
    ExcelService.isBackupOverdue().then((bool overdue) {
      if (mounted) setState(() => _overdue = overdue);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _overdue != true) return const SizedBox.shrink();

    final AppColors colors = AppColors.of(context);

    // A live region: the banner arrives on its own, after a query, and an
    // eye-only arrival is silence for anyone listening.
    return Semantics(
      container: true,
      liveRegion: true,
      child: MaterialBanner(
        backgroundColor: colors.warningContainer,
        leading: ExcludeSemantics(
          child: Icon(Icons.backup_outlined, color: colors.warning),
        ),
        content: Text(
          "It's been a while since the last backup. Worth doing one now?",
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.onWarningContainer),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => setState(() => _dismissed = true),
            style: TextButton.styleFrom(
                foregroundColor: colors.onWarningContainer),
            child: Text(AppLocalizations.of(context).backupLaterAction),
          ),
          FilledButton(
            onPressed: _backUpNow,
            style: FilledButton.styleFrom(
              backgroundColor: colors.warning,
              foregroundColor: colors.onWarningContainer,
            ),
            child: Text(AppLocalizations.of(context).backupNowAction),
          ),
        ],
      ),
    );
  }

  Future<void> _backUpNow() async {
    try {
      await widget.onBackupNow();
      if (mounted) setState(() => _dismissed = true);
    } catch (_) {
      // A failed export is the one thing here worth interrupting for: the owner
      // asked for a backup and did not get one.
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context).backupFailedMessage,
      );
    }
  }
}
