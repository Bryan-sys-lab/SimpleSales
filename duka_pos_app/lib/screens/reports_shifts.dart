import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/analytics.dart';
import '../services/printer/printer_service.dart';
import '../services/printer/receipt_printer.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../utils/money.dart';

/// How many shifts one load resolves figures for.
///
/// A Z-report table that silently stops at a row count reports a shorter
/// history than the ledger holds, so the card says how many were left out
/// rather than pretending the list ends there. Thirty is a month of shifts for
/// a single till, which is what anyone actually reads.
const int kShiftReportLimit = 30;

/// One shift, with the figures a Z report is made of.
///
/// Resolved once at load time. Nothing here is summed in `build()`: the takings
/// come from the ledger's own aggregate over the shift's window, and the
/// expected balance comes from `expectedTillBalance`, which is the same figure
/// the reconciliation screen compares a physical count against.
@immutable
class ShiftReportRow {
  const ShiftReportRow({
    required this.shift,
    required this.grossSales,
    required this.expectedTill,
    required this.variance,
    required this.reconciliationCount,
    required this.latestSale,
  });

  final Shift shift;

  /// Every tender rung up inside the shift's window, not just cash: this is the
  /// Z report's gross, and it is scoped on `staff_id` rather than the display
  /// name, because a shared till can have someone else's sales in the same
  /// window and attributing them to this cashier would hand them a variance
  /// they did not cause.
  final Money grossSales;

  /// What the drawer should hold: the opening float plus the verified cash.
  final Money expectedTill;

  /// The most recent reconciliation's variance, or null while the shift is open
  /// or was never counted.
  final Money? variance;

  /// How many times the shift was reconciled. More than one means it was
  /// re-counted, which an owner looking at a variance needs to know.
  final int reconciliationCount;

  /// The most recent sale inside the window — the document a reprint prints.
  final Sale? latestSale;

  bool get isOpen => shift.status == 'open';

  int? get id => shift.id;

  /// The catalogue comes in, because this is a value type built in a query loop
  /// with no `Localizations` above it.
  String cashierLabel(AppLocalizations l10n) => shift.staffName.trim().isEmpty
      ? l10n.shiftHistoryUnknownCashier
      : shift.staffName;

  /// "3 Jan, 2:00 pm – 6:30 pm", or the raw stored string when the timestamp
  /// does not parse. A report that shows nothing for an unparseable date is
  /// worse than one that shows the stored value.
  String get windowLabel {
    final DateTime? start = _parse(shift.startTime);
    if (start == null) return shift.startTime;
    final DateTime? end = _parse(shift.endTime);
    if (end == null) return DateFormat('d MMM, h:mm a').format(start);
    return '${DateFormat('d MMM, h:mm a').format(start)} – '
        '${DateFormat('h:mm a').format(end)}';
  }

  /// The day the shift opened, for grouping and for the export label.
  DateTime? get openedOn => _parse(shift.startTime);

  static DateTime? _parse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

/// Resolves the Z-report figures for [shifts].
///
/// Three ledger reads per shift — the window's takings, the expected drawer
/// balance, and the reconciliation history — each of which is a small indexed
/// query. That is deliberately per-shift rather than one sweep in Dart: the
/// scoping rules (`staff_id`, the verified-cash filter, the window boundaries)
/// already exist in `DatabaseHelper`, and re-implementing them here to save a
/// query is how a report and a reconciliation end up disagreeing.
///
/// [sales] is the sale list the screen has already loaded for the recent-sales
/// section; the reprint action resolves its target from it instead of issuing a
/// fourth query per row.
Future<List<ShiftReportRow>> loadShiftReports(
  List<Shift> shifts,
  List<Sale> sales,
) async {
  final DatabaseHelper db = DatabaseHelper.instance;
  final List<Shift> window = shifts.take(kShiftReportLimit).toList();

  final List<ShiftReportRow> rows = await Future.wait(
    window.map((Shift shift) async {
      final DateTime? start = ShiftReportRow._parse(shift.startTime);
      final DateTime? end = ShiftReportRow._parse(shift.endTime);
      final int? shiftId = shift.id;

      final List<Object> results = await Future.wait(<Future<Object>>[
        // Gross takings. `until` is exclusive, and an open shift has none, so
        // the window simply runs to now — which is exactly what an open shift
        // means.
        db.salesTotalsFor(since: start, until: end, staffId: shift.staffId),
        db.expectedTillBalance(shift),
        if (shiftId == null)
          Future<Object>.value(const <Reconciliation>[])
        else
          db.getReconciliationsForShift(shiftId),
      ]);

      final DailyTotals gross = results[0] as DailyTotals;
      final List<Reconciliation> reconciliations =
          results[2] as List<Reconciliation>;

      return ShiftReportRow(
        shift: shift,
        grossSales: gross.total,
        expectedTill: results[1] as Money,
        variance:
            reconciliations.isEmpty ? null : reconciliations.first.variance,
        reconciliationCount: reconciliations.length,
        latestSale: _latestSaleIn(sales, shift),
      );
    }),
  );

  return rows;
}

/// The newest sale that falls inside [shift]'s window and was rung by the same
/// cashier, or null when the shift took nothing.
Sale? _latestSaleIn(List<Sale> sales, Shift shift) {
  final DateTime? start = ShiftReportRow._parse(shift.startTime);
  final DateTime? end = ShiftReportRow._parse(shift.endTime);
  if (start == null) return null;
  for (final Sale sale in sales) {
    final DateTime? at = ShiftReportRow._parse(sale.createdAt);
    if (at == null || at.isBefore(start)) continue;
    if (end != null && !at.isBefore(end)) continue;
    if (sale.staffName != shift.staffName) continue;
    return sale;
  }
  return null;
}

/// The shift ledger: one row per shift, newest first.
class ShiftReportsCard extends StatelessWidget {
  const ShiftReportsCard({
    required this.rows,
    required this.totalShifts,
    required this.onPrint,
    required this.onExport,
    super.key,
  });

  final List<ShiftReportRow> rows;

  /// Every shift on record, including any left out of [rows].
  final int totalShifts;

  /// Resolved from a shift id, never from a captured figure.
  final void Function(int shiftId, Sale sale) onPrint;
  final void Function(Shift shift) onExport;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final int hidden = totalShifts - rows.length;

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(
            label: 'Shift and Z reports',
            trailing: CountBadge(
              count: totalShifts,
              noun: totalShifts == 1 ? 'shift' : 'shifts',
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                spacing.sm,
                spacing.md,
                spacing.md,
              ),
              child: Text(
                'No shifts have been opened on this till yet.',
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            )
          else
            for (int i = 0; i < rows.length; i++)
              _ShiftReportLine(
                row: rows[i],
                showDivider: i != rows.length - 1,
                onPrint: onPrint,
                onExport: onExport,
              ),
          if (hidden > 0)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.md,
                end: spacing.md,
                top: spacing.sm,
                bottom: spacing.md,
              ),
              child: Text(
                'and $hidden earlier '
                '${hidden == 1 ? 'shift' : 'shifts'} not shown',
                style: AppTypography.of(context).bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// One shift: when and who on the first line, the figures on the second.
///
/// The two-line shape is what keeps five figures legible at a till's width. A
/// single row of When / Cashier / Gross / Expected / Variance is unreadable
/// below about 560 logical pixels, and a report whose columns cannot be read is
/// a report nobody trusts.
class _ShiftReportLine extends StatelessWidget {
  const _ShiftReportLine({
    required this.row,
    required this.showDivider,
    required this.onPrint,
    required this.onExport,
  });

  final ShiftReportRow row;
  final bool showDivider;
  final void Function(int shiftId, Sale sale) onPrint;
  final void Function(Shift shift) onExport;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final int? shiftId = row.id;
    final Sale? sale = row.latestSale;

    final Widget line = Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: spacing.md,
        bottom: spacing.md,
      ),
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
                      row.windowLabel,
                      style: AppTypography.of(context).titleSmall,
                    ),
                    Text(
                      row.cashierLabel(AppLocalizations.of(context)),
                      style: AppTypography.of(context).bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              MoneyText(amount: formatMoney(row.grossSales), size: 15),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _ExpectedCaption(row: row)),
              _ShiftActions(
                row: row,
                onPrint: shiftId != null && sale != null
                    ? () => onPrint(shiftId, sale)
                    : null,
                onExport: () => onExport(row.shift),
              ),
            ],
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: '${row.windowLabel}, ${row.cashierLabel}, '
          '${formatMoney(row.grossSales)} taken, '
          '${formatMoney(row.expectedTill)} expected in the till, '
          '${_varianceSpoken(row)}',
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: showDivider
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  line,
                  Divider(height: 1, color: colors.outline),
                ],
              )
            : line,
      ),
    );
  }

  static String _varianceSpoken(ShiftReportRow row) {
    final Money? variance = row.variance;
    if (variance == null) return row.isOpen ? 'still open' : 'not reconciled';
    if (variance.isZero) return 'balanced';
    return variance.isNegative ? 'short' : 'over';
  }
}

/// "Expected in till KSh 26,600" and the variance, as glyph + word + figure.
class _ExpectedCaption extends StatelessWidget {
  const _ExpectedCaption({required this.row});

  final ShiftReportRow row;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final Money? variance = row.variance;

    final StatusTone tone;
    final String word;
    if (row.isOpen) {
      tone = StatusTone.pending;
      word = 'Still open';
    } else if (variance == null) {
      tone = StatusTone.neutral;
      word = 'Not reconciled';
    } else if (variance.isZero) {
      tone = StatusTone.success;
      word = 'Balanced';
    } else if (variance.isNegative) {
      tone = StatusTone.danger;
      word = 'Short';
    } else {
      tone = StatusTone.warning;
      word = 'Over';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                AppLocalizations.of(context)
                    .reportsExpectedTill(formatMoney(row.expectedTill)),
                style: AppTypography.of(context).bodySmall,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.xs),
        Row(
          children: <Widget>[
            StatusChip(tone: tone, text: word, dense: true),
            if (variance != null && !variance.isZero) ...<Widget>[
              SizedBox(width: spacing.sm),
              MoneyText(
                amount: formatMoney(variance.abs),
                size: 13,
                color: AppColors.of(context).onSurfaceVariant,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The row's two real side effects: reprint, and export.
class _ShiftActions extends StatelessWidget {
  const _ShiftActions({
    required this.row,
    required this.onPrint,
    required this.onExport,
  });

  final ShiftReportRow row;
  final VoidCallback? onPrint;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final bool printable = onPrint != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: printable
              ? 'Reprint the last receipt in this shift'
              : 'No receipt to reprint in this shift',
          onPressed: onPrint,
          icon: const Icon(Icons.print_outlined),
        ),
        SizedBox(width: spacing.xs),
        IconButton(
          tooltip: 'Export sales from this shift',
          onPressed: onExport,
          icon: const Icon(Icons.ios_share),
        ),
      ],
    );
  }
}

/// Advice for a failed print, in terms the owner can act on.
String printerAdviceFor(PrintResult result) => switch (result.failure) {
      PrinterFailure.notPaired =>
        'Pair the printer from this phone\'s Bluetooth settings.',
      PrinterFailure.permissionDenied ||
      PrinterFailure.permissionPermanentlyDenied =>
        'Allow Bluetooth for the app in the phone\'s app settings.',
      _ => 'Check the printer is switched on and in range, then try again.',
    };
