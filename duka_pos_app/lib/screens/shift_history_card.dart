// What the last shifts did, and how each one reconciled.
//
// Two lists, because they answer two different questions and an owner looking at
// a shortage needs both: "which shifts do I have on record" is answered by the
// shift ledger, and "which counts disagreed with the ledger" is answered by the
// reconciliations. Merging them into one timeline would make the second question
// require reading past the rows that are fine.
//
// Neither list is unbounded: both cap, and both SAY how many were left out.
// A shift report that silently stops at twenty rows reports a shorter history
// than the ledger holds, which is worse than no report — it is a report that
// looks complete.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../utils/datetime_format.dart';
import '../utils/money.dart';
import 'shift_variance.dart';

/// How many shifts and reconciliations this screen shows.
///
/// Thirty is a month of shifts for a single till, which is what anyone actually
/// reads. Anything deeper is a question for Analytics, which has a date range.
const int kShiftHistoryLimit = 30;

/// The shift ledger: one row per shift, newest first.
class ShiftHistoryCard extends StatelessWidget {
  const ShiftHistoryCard({
    required this.shifts,
    required this.totalShifts,
    super.key,
  });

  /// The newest [kShiftHistoryLimit] closed shifts.
  final List<Shift> shifts;

  /// Every closed shift on record, so the card can say what it left out.
  final int totalShifts;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int hidden = totalShifts - shifts.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          label: 'Past shifts',
          trailing: CountBadge(
            count: totalShifts,
            noun: AppLocalizations.of(context)
                .shiftHistoryShiftCount(totalShifts),
          ),
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < shifts.length; i++)
                _ShiftLine(
                  shift: shifts[i],
                  showDivider: i != shifts.length - 1 || hidden > 0,
                ),
              if (hidden > 0)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: spacing.md,
                    end: spacing.md,
                    top: spacing.md,
                    bottom: spacing.md,
                  ),
                  child: Text(
                    hidden == 1
                        ? l10n.shiftHistoryHiddenOne
                        : l10n.shiftHistoryHiddenMany(hidden),
                    style: AppTypography.of(context).bodySmall?.copyWith(
                          color: AppColors.of(context).onSurfaceMuted,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One closed shift: the window and who ran it, then the float it ended with and
/// how it reconciled.
///
/// Two lines rather than five columns, because a single row of When / Cashier /
/// Float / Expected / Variance is unreadable below about 560 logical pixels and
/// a report whose columns cannot be read is a report nobody trusts.
class _ShiftLine extends StatelessWidget {
  const _ShiftLine({required this.shift, required this.showDivider});

  final Shift shift;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String window = formatWindow(
      startIso: shift.startTime,
      endIso: shift.endTime,
    );
    final String cashier = shift.staffName.trim().isEmpty
        ? l10n.shiftHistoryUnknownCashier
        : shift.staffName;

    final Widget line = Padding(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      window,
                      style: AppTypography.of(context).titleSmall,
                    ),
                    Text(
                      cashier,
                      style: AppTypography.of(context).bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              Flexible(
                child: MoneyText(
                  amount: formatMoney(shift.endFloat),
                  size: 15,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(
            l10n.shiftHistoryOpener(formatMoney(shift.startFloat)),
            style: AppTypography.of(context)
                .bodySmall
                ?.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );

    final Widget ruled = showDivider
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              line,
              Divider(height: 1, color: colors.outline),
            ],
          )
        : line;

    return Semantics(
      container: true,
      label: '$window, $cashier, opened with '
          '${formatMoney(shift.startFloat)}, closed with '
          '${formatMoney(shift.endFloat)}',
      child: ruled,
    );
  }
}

/// The reconciliation ledger: every counted figure and how it disagreed with the
/// ledger.
///
/// Newest first, so the variance an owner is looking for is at the top rather
/// than at the bottom of a list they have to scroll to find.
class ReconciliationHistoryCard extends StatelessWidget {
  const ReconciliationHistoryCard({
    required this.reconciliations,
    super.key,
  });

  final List<Reconciliation> reconciliations;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int outOfBalance =
        reconciliations.where((Reconciliation r) => !r.variance.isZero).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          label: 'Reconciliations',
          trailing: CountBadge(
            count: reconciliations.length,
            noun: l10n.shiftReconciliationsCount(reconciliations.length),
          ),
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // The one figure a manager opens this screen for, stated before the
              // rows: how many counts did not balance.
              Padding(
                padding: EdgeInsets.all(spacing.md),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        outOfBalance == 0
                            ? l10n.shiftReconciliationsAllBalanced
                            : l10n.shiftReconciliationsDidNotBalance,
                        style: AppTypography.of(context).titleSmall,
                      ),
                    ),
                    StatusChip(
                      tone: outOfBalance == 0
                          ? StatusTone.success
                          : StatusTone.warning,
                      text: outOfBalance == 0
                          ? l10n.shiftReconciliationsAllBalancedChip
                          : l10n.shiftReconciliationsOutOfCount(
                              outOfBalance,
                              reconciliations.length,
                            ),
                    ),
                  ],
                ),
              ),
              for (int i = 0; i < reconciliations.length; i++)
                _ReconciliationLine(
                  reconciliation: reconciliations[i],
                  showDivider: i != reconciliations.length - 1,
                ),
              if (reconciliations.isEmpty)
                Padding(
                  padding: EdgeInsets.all(spacing.md),
                  child: Text(
                    l10n.shiftReconciliationsNoneYet,
                    style: AppTypography.of(context).bodyMedium?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One reconciliation: what was expected, what was counted, and the difference.
class _ReconciliationLine extends StatelessWidget {
  const _ReconciliationLine({
    required this.reconciliation,
    required this.showDivider,
  });

  final Reconciliation reconciliation;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ShiftVariance variance = ShiftVariance.between(
        l10n, reconciliation.countedCash, reconciliation.expectedCash);

    final Widget line = Padding(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      formatInstant(reconciliation.recordedAt),
                      style: AppTypography.of(context).titleSmall,
                    ),
                    Text(
                      l10n.shiftReconciliationsCountedOf(
                        formatMoney(reconciliation.countedCash),
                        formatMoney(reconciliation.expectedCash),
                      ),
                      style: AppTypography.of(context).bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              // The glyph is decorative beside the word; the word is the state.
              Icon(
                variance.tone.icon,
                size: 18,
                color: variance.tone.color(colors),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: <Widget>[
              StatusChip(tone: variance.tone, text: variance.word, dense: true),
              if (!variance.isZero) ...<Widget>[
                SizedBox(width: spacing.sm),
                MoneyText(
                  amount: formatMoney(variance.magnitude),
                  size: 13,
                  color: AppColors.of(context).onSurfaceVariant,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (!showDivider) return line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        line,
        Divider(height: 1, color: colors.outline),
      ],
    );
  }
}
