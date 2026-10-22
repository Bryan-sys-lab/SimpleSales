import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_brand.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/excel_service.dart';
import '../services/printer/printer_config.dart';
import '../services/printer/receipt_printer.dart';
import '../services/session_refresh_mixin.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../ui/components/status.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../ui/components/screen_title.dart';
import 'reports_shifts.dart';

const int kRecentSalesLimit = 50;

@immutable
class StaffTakings {
  const StaffTakings({
    required this.staffName,
    required this.transactions,
    required this.total,
    required this.profit,
  });

  final String staffName;
  final int transactions;

  final Money total;
  final Money profit;
}

@immutable
class ReportsData {
  const ReportsData({
    required this.sales,
    required this.shifts,
    required this.totalShifts,
    required this.staff,
  });

  static const ReportsData empty = ReportsData(
    sales: <Sale>[],
    shifts: <ShiftReportRow>[],
    totalShifts: 0,
    staff: <StaffTakings>[],
  );

  final List<Sale> sales;
  final List<ShiftReportRow> shifts;
  final int totalShifts;
  final List<StaffTakings> staff;

  bool get isUnrecorded => sales.isEmpty && shifts.isEmpty;

  List<Sale> get recent => sales.take(kRecentSalesLimit).toList();
}

sealed class ReportsView {
  const ReportsView();
}

final class ReportsLoading extends ReportsView {
  const ReportsLoading(this.previous);
  final ReportsData previous;
}

final class ReportsFailure extends ReportsView {
  const ReportsFailure(this.message);
  final String message;
}

final class ReportsReady extends ReportsView {
  const ReportsReady(this.data);
  final ReportsData data;
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SessionRefresh<ReportsScreen> {
  final ExcelService _excel = ExcelService();
  final TextEditingController _search = TextEditingController();

  ReportsView _view = const ReportsLoading(ReportsData.empty);
  ReportsData _shown = ReportsData.empty;
  String _query = '';

  int _unfilteredCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void clearForSession() {
    _view = const ReportsLoading(ReportsData.empty);
    _shown = ReportsData.empty;
    _query = '';
    _unfilteredCount = 0;
    _search.clear();
  }

  @override
  Future<void> reloadFromSession() => _load();

  Future<void> _load() async {
    final AppState state = context.read<AppState>();
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final List<Object> results = await Future.wait(<Future<Object>>[
        db.getSales(
          staffName:
              state.currentRole == 'cashier' ? state.currentStaffName : null,
          // Reports aggregates per sale only; skip hydrating line items.
          withItems: false,
        ),
        db.getShifts(),
      ]);
      final List<Sale> sales = results[0] as List<Sale>;
      final List<Shift> shifts = results[1] as List<Shift>;
      final List<ShiftReportRow> shiftRows =
          await loadShiftReports(shifts, sales);
      if (!mounted) return;
      setState(() {
        _unfilteredCount = sales.length;
        _shown = _filter(
          ReportsData(
            sales: sales,
            shifts: shiftRows,
            totalShifts: shifts.length,
            staff: _takingsByStaff(sales),
          ),
        );
        _view = ReportsReady(_shown);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _view = const ReportsFailure('Couldn’t load sales reports.');
      });
    }
  }

  static List<StaffTakings> _takingsByStaff(List<Sale> sales) {
    final Map<String, Map<String, Object>> byStaff =
        <String, Map<String, Object>>{};
    for (final Sale s in sales) {
      final Map<String, Object> m = byStaff.putIfAbsent(
        s.staffName,
        () =>
            <String, Object>{'n': 0, 'total': Money.zero, 'profit': Money.zero},
      );
      m['n'] = (m['n']! as int) + 1;
      m['total'] = (m['total']! as Money) + s.total;
      m['profit'] = (m['profit']! as Money) + s.profit;
    }
    final List<StaffTakings> rows = <StaffTakings>[
      for (final MapEntry<String, Map<String, Object>> e in byStaff.entries)
        StaffTakings(
          staffName: e.key,
          transactions: e.value['n']! as int,
          total: e.value['total']! as Money,
          profit: e.value['profit']! as Money,
        ),
    ]..sort((StaffTakings a, StaffTakings b) => b.total.compareTo(a.total));
    return rows;
  }

  static ReportsData _filter(ReportsData data) {
    return data;
  }

  void _setQuery(String value) {
    if (value == _query) return;
    setState(() => _query = value);
  }

  bool _matches(String staffName) =>
      _query.trim().isEmpty ||
      staffName.toLowerCase().contains(_query.trim().toLowerCase());

  List<Sale> get _visibleSales =>
      (_view is ReportsReady ? (_view as ReportsReady).data.sales : <Sale>[])
          .where((Sale s) => _matches(s.staffName))
          .toList();

  List<ShiftReportRow> get _visibleShifts => (_view is ReportsReady
          ? (_view as ReportsReady).data.shifts
          : <ShiftReportRow>[])
      .where((ShiftReportRow r) =>
          _matches(r.cashierLabel(AppLocalizations.of(context))))
      .toList();

  List<StaffTakings> get _visibleStaff => (_view is ReportsReady
          ? (_view as ReportsReady).data.staff
          : <StaffTakings>[])
      .where((StaffTakings s) => _matches(s.staffName))
      .toList();

  Future<void> _showShiftSummary() async {
    await context.push(Routes.shift);
    if (!mounted) return;
    await _load();
  }

  Future<void> _exportSales() async {
    final file = await _excel.exportEncryptedSales();
    await _excel.shareFile(file);
  }

  Future<void> _exportShift(Shift shift) async {
    final DateTime? start = DateTime.tryParse(shift.startTime);
    final file = await _excel.exportSales(since: start);
    await _excel.shareFile(file);
  }

  Future<int> _vatRateForSale(int saleId) async {
    final row = await DatabaseHelper.instance.getSaleRowById(saleId);
    if (row == null) return await DatabaseHelper.instance.getVatRatePercent();
    return await DatabaseHelper.instance.vatRateForSale(row);
  }

  Future<void> _reprint(Sale sale) async {
    final int? id = sale.id;
    if (id == null) return;
    // Read identity before the first await: everything past this point is a
    // printer round-trip, and the screen can be popped in between.
    final AppState state = context.read<AppState>();
    final PrinterConfig config = await PrinterConfig.load();
    if (!mounted) return;
    if (!config.isConfigured) {
      showAppSnackBar(
        context,
        message:
            AppLocalizations.of(context).reportsPrinterOffPairFirst,
      );
      return;
    }
    showAppSnackBar(
      context,
      message: AppLocalizations.of(context).reportsSendingToPrinter,
    );
    final PrintResult result = await ReceiptPrinter().printSale(
      saleId: id,
      shopName: state.owner?.shopName ?? SimplePosBrand.appName,
      staffRole: state.isOwnerSession ? 'Owner' : state.currentRole,
      config: config,
      vatRatePercent: await _vatRateForSale(id),
      pricesIncludeVat: (await SharedPreferences.getInstance())
              .getBool('prices_include_vat') ??
          true,
    );
    if (!mounted) return;
    if (result.printed) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context).reportsReceiptReprinted,
      );
      return;
    }
    if (result.outcome == PrintOutcome.disabled) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context).reportsPrinterOff,
      );
      return;
    }
    showAppSnackBar(
      context,
      message:
          AppLocalizations.of(context).reportsPrintFailedWith(
              printerAdviceFor(result)),
    );
  }

  void _reprintShift(int shiftId, Sale sale) {
    HapticTheme.of(context).fire(HapticEvent.commit);
    _reprint(sale);
  }

  Future<void> _exportFromShift(Shift shift) async {
    HapticTheme.of(context).fire(HapticEvent.commit);
    await _exportShift(shift);
  }

  @override
  Widget build(BuildContext context) => _body(context);

  Widget _body(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return switch (_view) {
      ReportsLoading() => AdaptivePage(
          padding: EdgeInsets.zero,
          child: const SkeletonList(itemCount: 6),
        ),
      ReportsFailure(message: final String message) => AdaptivePage(
          child: ErrorStateView(
            message: message,
            retryLabel: 'Try again',
            onRetry: () => _load(),
          ),
        ),
      ReportsReady(data: final ReportsData data) =>
        _readyBody(context, data, colors, spacing),
    };
  }

  Widget _readyBody(
    BuildContext context,
    ReportsData data,
    AppColors colors,
    AppSpacing spacing,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<ShiftReportRow> shifts = _visibleShifts;
    final List<Sale> sales = _visibleSales;
    final List<StaffTakings> staff = _visibleStaff;

    if (data.isUnrecorded) {
      return AdaptivePage(
        child: EmptyStateView(
          kind: EmptyKind.collection,
          title: l10n.reportsNoSalesTitle,
          message: l10n.reportsCashierReportWaiting,
          actionLabel: l10n.reportsOpenTillReport,
          onAction: _showShiftSummary,
        ),
      );
    }

    final bool filtered = _query.trim().isNotEmpty &&
        shifts.isEmpty &&
        sales.isEmpty &&
        staff.isEmpty;

    if (filtered) {
      return AdaptivePage(
        child: EmptyStateView(
          kind: EmptyKind.filtered,
          title: l10n.sellNoMatchQuery(_query.trim()),
          message: l10n.reportsNoSalesByCashier,
          actionLabel: l10n.reportsClearSearch,
          onAction: () {
            _search.clear();
            _setQuery('');
          },
        ),
      );
    }

    return AdaptivePage(
      maxContentWidth: double.infinity,
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.md,
            top: spacing.md,
            bottom: spacing.xxl,
          ),
          children: <Widget>[
            // The screen names itself on the canvas.
            //
            // It used to open with the brand wordmark, which said the app's
            // name twice — once in the shell's bar and once here — and said
            // nothing about which screen this was. The brand mark lives in the
            // shell bar now; the title belongs to the screen.
            ScreenTitle(
              title: AppLocalizations.of(context).navAnalyticsShort,
              // The list already insets its content by `md`; the title's own
              // default inset would push it off the gutter the cards sit on.
              padding: EdgeInsetsDirectional.only(bottom: spacing.md),
            ),
            _ReportsActions(
              onOpenShift: _showShiftSummary,
              onExport: _exportSales,
            ),
            SizedBox(height: spacing.md),
            SearchField(
              controller: _search,
              onChanged: _setQuery,
              hintText: 'Filter by cashier',
            ),
            SizedBox(height: spacing.md),
            ShiftReportsCard(
              rows: shifts,
              totalShifts: data.totalShifts,
              onPrint: _reprintShift,
              onExport: (Shift shift) => _exportFromShift(shift),
            ),
            SizedBox(height: spacing.lg),
            _StaffTakingsCard(rows: staff),
            SizedBox(height: spacing.lg),
            _RecentSalesCard(sales: sales, onReprint: _reprint),
            if (_unfilteredCount > sales.length)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: spacing.md,
                  end: spacing.md,
                  top: spacing.md,
                ),
                child: Text(
                  AppLocalizations.of(context)
                      .reportsShowingSales(sales.length, _unfilteredCount),
                  style: AppTypography.of(context).bodySmall?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportsActions extends StatelessWidget {
  const _ReportsActions({required this.onOpenShift, required this.onExport});

  final Future<void> Function() onOpenShift;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    // Expanded rather than fixed widths, so a label that wraps at 200% text
    // scale grows its button instead of overflowing the row.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: () => onOpenShift(),
            icon: const Icon(Icons.receipt_long),
            label: Text(l10n.reportsShiftAndTillSection),
          ),
        ),
        SizedBox(width: spacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => onExport(),
            icon: const Icon(Icons.ios_share),
            label: Text(l10n.actionSendCopy),
          ),
        ),
      ],
    );
  }
}

class _StaffTakingsCard extends StatelessWidget {
  const _StaffTakingsCard({required this.rows});

  final List<StaffTakings> rows;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SectionHeader(label: 'Takings by staff'),
          if (rows.isEmpty)
            _CardNote('No takings for that cashier.')
          else
            for (int i = 0; i < rows.length; i++)
              _StaffTakingsRow(
                row: rows[i],
                showDivider: i != rows.length - 1,
              ),
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.md,
              end: spacing.md,
              top: spacing.sm,
              bottom: spacing.md,
            ),
            child: Text(
              'Profit is what the shop kept after the cost of the goods sold.',
              style: AppTypography.of(context).bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffTakingsRow extends StatelessWidget {
  const _StaffTakingsRow({required this.row, required this.showDivider});

  final StaffTakings row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    final Widget line = Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: spacing.md,
        bottom: spacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A round tonal badge on the leading edge, the way every other row in
          // the app is marked: a marker, not a status — the row's own name
          // carries the meaning, so the badge carries none.
          const IconBadge(icon: Icons.person_outline),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(row.staffName),
                SizedBox(height: spacing.xs),
                Text(
                  // An ICU plural, not a ternary: `1 transaction` / `2 transactions`
                  // is a two-way fork this app can only express in English.
                  AppLocalizations.of(context)
                      .reportsTransactionCaption(row.transactions),
                  style: _smallFigure(context),
                ),
              ],
            ),
          ),
          SizedBox(width: spacing.sm),
          MoneyText(amount: formatMoney(row.total), size: 15),
        ],
      ),
    );

    return Semantics(
      container: true,
      // gen-l10n orders the parameters ALPHABETICALLY by placeholder name —
      // count, name, profit, total — not in the order the sentence reads them.
      // The profit and the total were swapped, so a screen reader announced
      // "…, <total>, <profit> profit" with the two figures reversed.
      label: AppLocalizations.of(context).reportsStaffRowSpoken(
        row.transactions,
        row.staffName,
        formatMoney(row.profit),
        formatMoney(row.total),
      ),
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
}

class _RecentSalesCard extends StatelessWidget {
  const _RecentSalesCard({required this.sales, required this.onReprint});

  final List<Sale> sales;
  final Future<void> Function(Sale sale) onReprint;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(
            label: 'Recent sales',
            trailing: CountBadge(
              count: sales.length,
              noun: sales.length == 1 ? 'sale' : 'sales',
            ),
          ),
          if (sales.isEmpty)
            const _CardNote('No sales for that cashier.')
          else
            for (int i = 0; i < sales.length; i++)
              _RecentSaleRow(
                sale: sales[i],
                showDivider: i != sales.length - 1,
                onReprint: onReprint,
              ),
        ],
      ),
    );
  }
}

class _RecentSaleRow extends StatelessWidget {
  const _RecentSaleRow({
    required this.sale,
    required this.showDivider,
    required this.onReprint,
  });

  final Sale sale;
  final bool showDivider;
  final Future<void> Function(Sale sale) onReprint;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final DateTime? at = DateTime.tryParse(sale.createdAt);

    final String detail = <String>[
      if (at != null) DateFormat('MMM d, h:mm a').format(at),
      sale.paymentMethod,
      if (!sale.changeGiven.isNegative && !sale.changeGiven.isZero)
        AppLocalizations.of(context)
            .reportsChange(formatMoney(sale.changeGiven)),
    ].join(' · ');

    final Widget line = Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.sm,
        top: spacing.sm,
        bottom: spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(sale.staffName),
                SizedBox(height: spacing.xs),
                Text(detail, style: _smallFigure(context)),
              ],
            ),
          ),
          SizedBox(width: spacing.sm),
          Padding(
            padding: EdgeInsetsDirectional.only(top: spacing.sm),
            child: MoneyText(amount: formatMoney(sale.total), size: 15),
          ),
          Semantics(
            button: true,
            label: sale.id == null
                ? 'No receipt to reprint for this sale'
                : 'Reprint receipt for ${sale.staffName}',
            child: IconButton(
              tooltip: 'Reprint receipt',
              onPressed: sale.id == null ? null : () => onReprint(sale),
              icon: const Icon(Icons.print_outlined),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      // gen-l10n sorts the parameters ALPHABETICALLY — amount, detail,
      // staffName — so the money leads even though the name reads first.
      label: AppLocalizations.of(context)
          .reportsStaffName(formatMoney(sale.total), detail, sale.staffName),
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
}

class _CardNote extends StatelessWidget {
  const _CardNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.md,
      ),
      child: Text(
        message,
        style: AppTypography.of(context).bodyMedium?.copyWith(
              color: AppColors.of(context).onSurfaceMuted,
            ),
      ),
    );
  }
}

TextStyle _smallFigure(BuildContext context) =>
    (AppTypography.of(context).bodySmall ?? const TextStyle()).copyWith(
      fontFeatures: AppTypography.tabular,
      color: AppColors.of(context).onSurfaceVariant,
    );
