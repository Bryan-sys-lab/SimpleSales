import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../models/audit_log.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../utils/money.dart';
import 'shift_float_sheet.dart';

/// Prompts the user to start a shift when they try to do something that
/// requires one. Shows what they need a shift for, then offers to open one.
///
/// Returns `true` when a shift was successfully opened, `false` otherwise.
Future<bool> promptToStartShift({
  required BuildContext context,
  required AppState appState,
  required String purpose,
  String? staffName,
}) async {
  final l10n = AppLocalizations.of(context);
  final colors = Theme.of(context).extension<AppColors>()!;

  final bool? proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.shiftStartTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.shiftStartSubtitle,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.shiftStartPurpose(purpose),
            style: TextStyle(color: colors.onSurfaceMuted),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.shiftStartNeedDrawer,
            style: TextStyle(color: colors.onSurfaceMuted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.shiftStartStartShift),
        ),
      ],
    ),
  );

  if (proceed != true || !context.mounted) return false;

  // Ask for opening float.
  final Money? openingFloat = await showFloatSheet(
    context,
    title: l10n.shiftStartOpenShift,
    confirmLabel: l10n.shiftNoShiftAction,
    initialText: '',
  );
  if (openingFloat == null || !context.mounted) return false;

  // Resolve staff id / name.
  final int? staffId = appState.currentStaffId;
  final String name = staffName ?? appState.currentStaffName ?? 'Owner';
  if (staffId == null) {
    // No staff row yet — the user needs to be on the roster first.
    if (!context.mounted) return false;
    showAppSnackBar(
      context,
      message: l10n.shiftNeedsStaffEntry,
    );
    return false;
  }

  try {
    await DatabaseHelper.instance.openShift(
      staffId: staffId,
      staffName: name,
      startFloat: openingFloat,
    );
    await recordActionAudit(
      appState,
      action: AuditAction.shiftOpened,
      entity: AuditEntity.shift,
      entityId: 'id-$staffId',
      detail: 'float ${formatMoney(openingFloat)}',
    );
    if (!context.mounted) return false;
    HapticTheme.of(context).fire(HapticEvent.commit);
    return true;
  } on StateError catch (error) {
    if (!context.mounted) return false;
    showAppSnackBar(
      context,
      message: error.message,
    );
    return false;
  }
}

void showAppSnackBar(BuildContext context, {required String message}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
