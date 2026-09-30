import 'package:flutter/material.dart';
import '../services/excel_service.dart';
import '../theme/app_theme.dart';

/// A soft, non-blocking nudge — never a dialog that stops someone mid-sale —
/// reminding the owner to back up if it's been a while. Checked once when the
/// dashboard loads; dismissing it just hides it for this session, it isn't
/// meant to be nagged into oblivion, just to catch the case where a backup
/// has genuinely been forgotten for days.
class BackupReminderBanner extends StatefulWidget {
  final Future<void> Function() onBackupNow;
  const BackupReminderBanner({super.key, required this.onBackupNow});

  @override
  State<BackupReminderBanner> createState() => _BackupReminderBannerState();
}

class _BackupReminderBannerState extends State<BackupReminderBanner> {
  bool _dismissed = false;
  bool? _overdue;

  @override
  void initState() {
    super.initState();
    ExcelService.isBackupOverdue().then((v) {
      if (mounted) setState(() => _overdue = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _overdue != true) return const SizedBox.shrink();
    return MaterialBanner(
      backgroundColor: DukaColors.surfaceWarm,
      leading: const Icon(Icons.backup_outlined, color: DukaColors.warning),
      content: const Text(
          "It's been a while since the last backup. Worth doing one now?"),
      actions: [
        TextButton(
            onPressed: () => setState(() => _dismissed = true),
            child: const Text('Later')),
        FilledButton(
          onPressed: () async {
            try {
              await widget.onBackupNow();
              if (mounted) setState(() => _dismissed = true);
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Backup could not be completed. Check storage and try again.')),
              );
            }
          },
          child: const Text('Back up now'),
        ),
      ],
    );
  }
}
