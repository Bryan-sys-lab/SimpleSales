// The strip that says what state the till is in.
//
// ## WHY IT IS A STRIP AND NOT A DIALOG
//
// A till's state changes without anybody asking it to: the network drops, the
// backup falls overdue, the shop's account deletion could not reach the
// server. None of those is worth stopping a sale for, and all of them are
// worth KNOWING about.
//
// So they are a strip: one line, under the app bar, on every screen, that
// says the thing that is wrong and nothing when nothing is. It never blocks,
// and it never asks.
//
// ## WHY IT IS ONE LINE
//
// A strip that can grow is a strip that pushes the content down, and a screen
// whose content moves when a notification arrives is a screen that jumps
// under a thumb. So the strip takes the MOST IMPORTANT thing that is wrong,
// and only that.
//
// ## WHY IT IS NOT THE DASHBOARD'S JOB
//
// The dashboard already has a live status line and a backup reminder. But a
// dashboard is one screen of five, and the till does not stay on it: a
// cashier is on the SELL screen, and a till that cannot reach the server is
// exactly where the owner needs to know.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/account_deletion_service.dart';
import '../../services/excel_service.dart';
import '../../services/live_channel_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';

/// The one thing the till most needs to say, right now.
enum TillStatus {
  /// The shop's online account could not be deleted and the server has not
  /// confirmed it. This is the one that matters most: an account the owner
  /// believes is gone may still exist.
  deletionPending,

  /// The backup is overdue.
  backupOverdue,

  /// The live channel is not connected.
  offline,

  /// The live channel is trying to connect.
  connecting,
}

/// The strip. Renders nothing when there is nothing to say.
class TillStatusBar extends StatefulWidget {
  const TillStatusBar({super.key});

  @override
  State<TillStatusBar> createState() => _TillStatusBarState();
}

class _TillStatusBarState extends State<TillStatusBar> {
  /// Whether the backup is overdue. Null until the check answers.
  bool? _backupOverdue;

  /// Whether a remote account deletion is still pending.
  bool _deletionPending = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  /// Reads the two facts that are not already in the widget tree.
  ///
  /// Held here rather than handed to a `FutureBuilder`: a builder is given a
  /// new future on every build and starts over, so the check would repeat on
  /// every rebuild of the strip.
  Future<void> _check() async {
    final bool overdue = await ExcelService.isBackupOverdue();
    final String? pending = await AccountDeletionService.pendingDeletionEmail();
    if (!mounted) return;
    setState(() {
      _backupOverdue = overdue;
      _deletionPending = pending != null && pending.trim().isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    // The live channel, which the service already publishes.
    final LiveConnectionState connection =
        context.watch<LiveChannelService>().state;

    // THE MOST IMPORTANT THING THAT IS WRONG.
    //
    // One line, one fact: the order is the order of how much it matters, and
    // an account the owner believes is gone outranks a backup that is late.
    final TillStatus? status = _deletionPending
        ? TillStatus.deletionPending
        : _backupOverdue == true
            ? TillStatus.backupOverdue
            : switch (connection) {
                LiveConnectionState.off ||
                LiveConnectionState.paused =>
                  TillStatus.offline,
                LiveConnectionState.connecting => TillStatus.connecting,
                LiveConnectionState.connected => null,
              };

    // Nothing to say: the strip is not there, and the content does not move.
    if (status == null) return const SizedBox.shrink();

    final (String message, IconData icon, Color ink) = switch (status) {
      TillStatus.deletionPending => (
          l10n.statusDeletionPending,
          Icons.cloud_off_outlined,
          colors.danger,
        ),
      TillStatus.backupOverdue => (
          l10n.statusBackupOverdue,
          Icons.backup_outlined,
          colors.warning,
        ),
      TillStatus.offline => (
          l10n.statusOffline,
          Icons.cloud_off_outlined,
          colors.onSurfaceMuted,
        ),
      TillStatus.connecting => (
          l10n.statusConnecting,
          Icons.cloud_sync_outlined,
          colors.onSurfaceMuted,
        ),
    };

    return Semantics(
      container: true,
      // A live region: the strip can APPEAR on its own, after a check, and an
      // eye-only arrival is silence for anyone listening.
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: colors.surfaceSunken,
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: spacing.lg,
          vertical: spacing.xs,
        ),
        child: Row(
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(icon, size: 14, color: ink),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                message,
                style: type.labelMedium?.copyWith(color: ink),
                // No `maxLines` and no ellipsis: a message the owner cannot
                // finish reading is a message that was not said. These are
                // short, controlled sentences, so the strip is one line in
                // practice — and if a translation is longer it WRAPS rather
                // than being cut.
              ),
            ),
          ],
        ),
      ),
    );
  }
}
