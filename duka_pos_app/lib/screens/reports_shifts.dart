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

const int kShiftReportLimit = 30;

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

  final Money grossSales;

  final Money expectedTill;

  final Money? variance;

  final int reconciliationCount;

  final Sale? latestSale;

  bool get isOpen => shift.status == 'open';

  int? get id => shift.id;

  String cashierLabel(AppLocalizations l10n) => shift.staffName.trim().isEmpty
      ? l10n.shiftHistoryUnknownCashier
      : shift.staffName;

  String get windowLabel {
    final DateTime? start = _parse(shift.startTime);
    if (start == null) return shift.startTime;
    final DateTime? end = _parse(shift.endTime);
    if (end == null) return DateFormat('d MMM, h:mm a').format(start);
    return '${DateFormat('d MMM, h:mm a').format(start)} – '
        '${DateFormat('h:mm a').format(end)}';
  }

  DateTime? get openedOn => _parse(shift.startTime);

  static DateTime? _parse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

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

class ShiftReportsCard extends StatelessWidget {
  const ShiftReportsCard({
    required this.rows,
    required this.totalShifts,
    required this.onPrint,
    required this.onExport,
    super.key,
  });

  final List<ShiftReportRow> rows;

  final int totalShifts;

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
        Semantics(
          button: true,
          label: printable
              ? 'Reprint the last receipt in this shift'
              : 'No receipt to reprint in this shift',
          child: IconButton(
            tooltip: printable
                ? 'Reprint the last receipt in this shift'
                : 'No receipt to reprint in this shift',
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined),
          ),
        ),
        SizedBox(width: spacing.xs),
        Semantics(
          button: true,
          label: 'Export sales from this shift',
          child: IconButton(
            tooltip: 'Export sales from this shift',
            onPressed: onExport,
            icon: const Icon(Icons.ios_share),
          ),
        ),
      ],
    );
  }
}

String printerAdviceFor(PrintResult result) => switch (result.failure) {
      PrinterFailure.notPaired =>
        'Pair the printer from this phone\'s Bluetooth settings.',
      PrinterFailure.permissionDenied ||
      PrinterFailure.permissionPermanentlyDenied =>
        'Allow Bluetooth for the app in the phone\'s app settings.',
      _ => 'Check the printer is switched on and in range, then try again.',
    };
