library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../models/financial_event.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../utils/money.dart';
import '../widgets/sale_details_sheet.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

sealed class _LedgerState {}

class _LedgerLoading extends _LedgerState {}

class _LedgerReady extends _LedgerState {
  _LedgerReady(
    this.items,
    this.sales,
    this.expenses,
    this.audit,
    this.canSeeSellers,
    this.returnedFractions,
  );

  final List<_LedgerItem> items;
  final List<Sale> sales;
  final List<Map<String, dynamic>> expenses;
  final List<AuditLogEntry> audit;

  final bool canSeeSellers;

  /// How much of each sale has come back, by sale id.
  final Map<int, double> returnedFractions;
}

/// One normalized row in the shop-scoped money timeline. Sales retain their
/// typed model for the existing detail/return flow; expenses retain their
/// posted ledger row and use the same chronological list.
class _LedgerItem {
  const _LedgerItem.sale(this.sale)
      : expense = null,
        event = null,
        at = null,
        kindOrder = 0;

  const _LedgerItem.expense(this.expense)
      : sale = null,
        event = null,
        at = null,
        kindOrder = 1;

  const _LedgerItem.event(this.event)
      : sale = null,
        expense = null,
        at = null,
        kindOrder = 2;

  final Sale? sale;
  final Map<String, dynamic>? expense;
  final FinancialEvent? event;
  final DateTime? at;
  final int kindOrder;

  DateTime get timestamp {
    final String value = sale?.createdAt ??
        expense?['created_at'] as String? ??
        event?.occurredAtUtc ??
        '';
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  int get recordId => sale?.id ?? (expense?['id'] as int? ?? event?.id ?? 0);

  static int amountMinor(_LedgerItem item) {
    if (item.sale != null) return item.sale!.total.minorUnits;
    if (item.expense != null) {
      return -((item.expense!['amount_minor'] as num?)?.toInt() ?? 0);
    }
    return FinancialEventTimelineRow.primaryAmountMinor(item.event!);
  }

  static String? category(_LedgerItem item) {
    if (item.sale != null) return 'Sale';
    if (item.expense != null) {
      return item.expense!['category_name'] as String? ?? 'Other';
    }
    return item.event?.eventType;
  }

  static String? paymentMethod(_LedgerItem item) {
    if (item.sale != null) return item.sale!.paymentMethod;
    if (item.expense != null) return item.expense!['paid_from'] as String?;
    final String metadata = item.event?.metadataJson ?? '{}';
    try {
      final decoded = jsonDecode(metadata);
      if (decoded is Map<String, dynamic>) {
        return decoded['payment_method'] as String? ??
            decoded['method'] as String?;
      }
    } catch (_) {
      // A malformed optional label must not hide a financial event.
    }
    return null;
  }
}

class _LedgerFailed extends _LedgerState {
  _LedgerFailed(this.message);
  final String message;
}

enum _LedgerRange { today, week, month, custom }

enum _LedgerDirection { all, moneyIn, moneyOut }

class _TransactionsScreenState extends State<TransactionsScreen> {
  _LedgerState _state = _LedgerLoading();

  // Keep a bounded local history so the custom-period filter does not turn the
  // phone into an unbounded report query. The visible filters narrow this
  // window without creating a second transaction source.
  static const int _days = 365;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _state = _LedgerLoading());
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final AppState state = context.read<AppState>();
      final DateTime since =
          DateTime.now().toUtc().subtract(const Duration(days: _days));
      // The money and the accountability, read together: neither answers "who
      // sold what" without the other.
      //
      // SCOPED TO THE SESSION unless it may read the whole shop. A cashier's
      // business is this counter, not the roster's — the same reading the
      // dashboard and the reports guard use, and the reason the screen exists
      // for the person who can act on it and not for everyone who can sign in.
      // `canSeeSellers` below hides NAMES; this hides the ROWS.
      final String? staff =
          state.canManageStock ? null : state.currentStaffName;
      final List<Sale> sales =
          await db.getSales(since: since, staffName: staff, limit: 200);
      final List<Map<String, dynamic>> expenses = state.canManageStock
          ? await db.getExpenseHistory(since: since, limit: 200)
          : const <Map<String, dynamic>>[];
      final List<_LedgerItem> items;
      if (state.canManageStock) {
        final events = await db.getFinancialEvents(
          sinceUtc: since,
          limit: 200,
        );
        final eventSaleIds = events
            .where((event) => event.sourceType == 'sale')
            .map((event) => event.sourceId)
            .whereType<int>()
            .toSet();
        final eventExpenseIds = events
            .where((event) => event.sourceType == 'expense')
            .map((event) => event.sourceId)
            .whereType<int>()
            .toSet();
        items = <_LedgerItem>[
          ...events.map(_LedgerItem.event),
          ...sales
              .where((sale) => !eventSaleIds.contains(sale.id))
              .map(_LedgerItem.sale),
          ...expenses
              .where((expense) => !eventExpenseIds.contains(expense['id']))
              .map(_LedgerItem.expense),
        ];
      } else {
        items = <_LedgerItem>[
          ...sales.map(_LedgerItem.sale),
          ...expenses.map(_LedgerItem.expense),
        ];
      }
      items.sort((a, b) {
        final int byTime = b.timestamp.compareTo(a.timestamp);
        if (byTime != 0) return byTime;
        final int byKind = a.kindOrder.compareTo(b.kindOrder);
        if (byKind != 0) return byKind;
        return b.recordId.compareTo(a.recordId);
      });
      final List<AuditLogEntry> audit = await db.auditLog(
        AuditLogQuery(
            actions: <AuditAction>[AuditAction.saleRecorded], limit: 200),
      );
      // How much of each sale has come back, in ONE query for the whole list.
      // The row says so — "Returned", "Partly returned" — because a sale that
      // has been given back is not a sale like the others, and a list that
      // does not say so reads as if the money was taken twice.
      final Map<int, double> returnedFractions =
          await db.getReturnedFractionsForSales(
        sales.map((Sale s) => s.id).whereType<int>().toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _state = _LedgerReady(
            items,
            sales,
            expenses,
            audit,
            staff == null,
            returnedFractions,
          ));
    } catch (_) {
      if (!mounted) return;
      // The typed failure, never `toString()`: an owner reading "Garbage state
      // detected in SplayTreeMap" learns nothing they can act on.
      setState(() => _state = _LedgerFailed(
            AppLocalizations.of(context).transactionsLoadFailed,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.transactionsTitle),
        actions: <Widget>[
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.actionRetry,
          ),
        ],
      ),
      body: switch (_state) {
        _LedgerLoading() => const SkeletonList(),
        _LedgerFailed(:final String message) => ErrorStateView(
            message: message,
            onRetry: _load,
            retryLabel: l10n.actionRetry,
          ),
        _LedgerReady(
          :final List<_LedgerItem> items,
          :final List<Sale> sales,
          :final List<Map<String, dynamic>> expenses,
          :final List<AuditLogEntry> audit,
          :final bool canSeeSellers,
          :final Map<int, double> returnedFractions,
        ) =>
          items.isEmpty
              ? EmptyStateView(
                  title: canSeeSellers
                      ? l10n.transactionsEmptyTitle
                      : l10n.transactionsEmptyOwnTitle,
                  message: canSeeSellers
                      ? l10n.transactionsEmptyMessage
                      : l10n.transactionsEmptyOwnMessage,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _Ledger(
                    items: items,
                    sales: sales,
                    expenses: expenses,
                    audit: audit,
                    canSeeSellers: canSeeSellers,
                    returnedFractions: returnedFractions,
                  ),
                ),
      },
    );
  }
}

class _Ledger extends StatefulWidget {
  const _Ledger({
    required this.items,
    required this.sales,
    required this.expenses,
    required this.audit,
    required this.canSeeSellers,
    required this.returnedFractions,
  });

  final List<_LedgerItem> items;
  final List<Sale> sales;
  final List<Map<String, dynamic>> expenses;
  final List<AuditLogEntry> audit;

  final bool canSeeSellers;

  /// How much of each sale has come back, by sale id.
  final Map<int, double> returnedFractions;

  @override
  State<_Ledger> createState() => _LedgerStateWidget();
}

class _LedgerStateWidget extends State<_Ledger> {
  _LedgerRange _range = _LedgerRange.month;
  _LedgerDirection _direction = _LedgerDirection.all;
  String? _category;
  String? _paymentMethod;
  DateTimeRange? _customRange;

  List<_LedgerItem> get _filteredItems {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime start = switch (_range) {
      _LedgerRange.today => today,
      _LedgerRange.week => today.subtract(const Duration(days: 6)),
      _LedgerRange.month => today.subtract(const Duration(days: 29)),
      _LedgerRange.custom => _customRange?.start ?? today,
    };
    final DateTime end = switch (_range) {
      _LedgerRange.custom =>
        (_customRange?.end ?? today).add(const Duration(days: 1)),
      _ => now.add(const Duration(seconds: 1)),
    };
    return widget.items.where((item) {
      final DateTime at = item.timestamp.toLocal();
      if (at.isBefore(start) || !at.isBefore(end)) return false;
      if (_direction != _LedgerDirection.all) {
        final int amount = _LedgerItem.amountMinor(item);
        if (_direction == _LedgerDirection.moneyIn && amount <= 0) {
          return false;
        }
        if (_direction == _LedgerDirection.moneyOut && amount >= 0) {
          return false;
        }
      }
      if (_category != null && _LedgerItem.category(item) != _category) {
        return false;
      }
      if (_paymentMethod != null &&
          _LedgerItem.paymentMethod(item) != _paymentMethod) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<String> _options(String? Function(_LedgerItem) read) {
    final Set<String> values = <String>{
      for (final _LedgerItem item in widget.items)
        if (read(item) case final String value when value.isNotEmpty) value,
    };
    return values.toList()..sort();
  }

  Future<void> _pickCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customRange,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _range = _LedgerRange.custom;
      _customRange = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final List<_LedgerItem> items = _filteredItems;

    // Two keys, because there are two ways a sale reaches the log: checkout
    // writes `id-<saleId>` (sell_screen.dart:1056) and the reconciled M-Pesa path
    // writes the provider's reference (sell_screen.dart:388). Requiring the
    // `id-` prefix explicitly matters — `int.tryParse` on a bare numeric
    // reference would otherwise coerce it into a sale id and attribute one
    // sale's audit line to another.
    final Map<int, AuditLogEntry> bySale = <int, AuditLogEntry>{
      for (final AuditLogEntry entry in widget.audit)
        if (entry.entityId case final String id when id.startsWith('id-'))
          if (int.tryParse(id.substring(3)) case final int saleId)
            saleId: entry,
    };

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: _LedgerFilters(
            range: _range,
            direction: _direction,
            category: _category,
            paymentMethod: _paymentMethod,
            categories: _options(_LedgerItem.category),
            paymentMethods: _options(_LedgerItem.paymentMethod),
            customRange: _customRange,
            onRangeChanged: (value) => setState(() => _range = value),
            onDirectionChanged: (value) => setState(() => _direction = value),
            onCategoryChanged: (value) => setState(() => _category = value),
            onPaymentMethodChanged: (value) =>
                setState(() => _paymentMethod = value),
            onCustomRange: _pickCustomRange,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.md,
              end: spacing.md,
              top: spacing.md,
              bottom: spacing.sm,
            ),
            child: Text(
              AppLocalizations.of(context).transactionsSubtitle(items.length),
              style: AppTypography.of(context).bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
            ),
          ),
        ),
        SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => SizedBox(height: spacing.sm),
          itemBuilder: (BuildContext context, int index) {
            final _LedgerItem item = items[index];
            final Sale? sale = item.sale;
            final FinancialEvent? event = item.event;
            if (event != null) {
              if (event.sourceType == 'sale') {
                final Sale? eventSale = widget.sales
                    .where((candidate) => candidate.id == event.sourceId)
                    .firstOrNull;
                if (eventSale != null) {
                  return TransactionsRow(
                    sale: eventSale,
                    audit: bySale[eventSale.id],
                    canSeeSellers: widget.canSeeSellers,
                    returnedFraction:
                        widget.returnedFractions[eventSale.id] ?? 0,
                  );
                }
              }
              if (event.sourceType == 'expense') {
                final Map<String, dynamic>? eventExpense = widget.expenses
                    .where((candidate) => candidate['id'] == event.sourceId)
                    .firstOrNull;
                if (eventExpense != null) {
                  return ExpenseTimelineRow(expense: eventExpense);
                }
              }
              return FinancialEventTimelineRow(event: event);
            }
            return sale != null
                ? TransactionsRow(
                    sale: sale,
                    audit: bySale[sale.id],
                    canSeeSellers: widget.canSeeSellers,
                    returnedFraction: widget.returnedFractions[sale.id] ?? 0,
                  )
                : ExpenseTimelineRow(expense: item.expense!);
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: spacing.xxl)),
      ],
    );
  }
}

class _LedgerFilters extends StatelessWidget {
  const _LedgerFilters({
    required this.range,
    required this.direction,
    required this.category,
    required this.paymentMethod,
    required this.categories,
    required this.paymentMethods,
    required this.customRange,
    required this.onRangeChanged,
    required this.onDirectionChanged,
    required this.onCategoryChanged,
    required this.onPaymentMethodChanged,
    required this.onCustomRange,
  });

  final _LedgerRange range;
  final _LedgerDirection direction;
  final String? category;
  final String? paymentMethod;
  final List<String> categories;
  final List<String> paymentMethods;
  final DateTimeRange? customRange;
  final ValueChanged<_LedgerRange> onRangeChanged;
  final ValueChanged<_LedgerDirection> onDirectionChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onPaymentMethodChanged;
  final VoidCallback onCustomRange;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(top: spacing.md, bottom: spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Period', style: AppTypography.of(context).labelLarge),
          SizedBox(height: spacing.xs),
          Wrap(
            spacing: spacing.xs,
            children: <Widget>[
              for (final (_LedgerRange, String) option
                  in <(_LedgerRange, String)>[
                (_LedgerRange.today, 'Today'),
                (_LedgerRange.week, 'This week'),
                (_LedgerRange.month, 'This month'),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: range == option.$1,
                  onSelected: (_) => onRangeChanged(option.$1),
                ),
              ChoiceChip(
                label: Text(customRange == null ? 'Custom' : 'Custom dates'),
                selected: range == _LedgerRange.custom,
                onSelected: (_) => onCustomRange(),
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Wrap(
            spacing: spacing.xs,
            children: <Widget>[
              for (final (_LedgerDirection, String) option
                  in <(_LedgerDirection, String)>[
                (_LedgerDirection.all, 'All money'),
                (_LedgerDirection.moneyIn, 'Money in'),
                (_LedgerDirection.moneyOut, 'Money out'),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: direction == option.$1,
                  onSelected: (_) => onDirectionChanged(option.$1),
                ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.xs,
            children: <Widget>[
              _LedgerDropdown(
                label: 'Category',
                value: category,
                options: categories,
                onChanged: onCategoryChanged,
              ),
              _LedgerDropdown(
                label: 'Payment method',
                value: paymentMethod,
                options: paymentMethods,
                onChanged: onPaymentMethodChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerDropdown extends StatelessWidget {
  const _LedgerDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: value,
      hint: Text(label),
      items: <DropdownMenuItem<String?>>[
        DropdownMenuItem<String?>(value: null, child: Text('All $label')),
        for (final String option in options)
          DropdownMenuItem<String?>(value: option, child: Text(option)),
      ],
      onChanged: onChanged,
    );
  }
}

class FinancialEventTimelineRow extends StatelessWidget {
  const FinancialEventTimelineRow({required this.event, super.key});

  final FinancialEvent event;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final DateTime? timestamp =
        DateTime.tryParse(event.occurredAtUtc)?.toLocal();
    final int amount = primaryAmountMinor(event);
    final String sign = amount < 0 ? '-' : '+';
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Row(
        children: <Widget>[
          Icon(Icons.account_balance_wallet_outlined,
              size: 20, color: colors.onSurfaceMuted),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_eventTitle(event.eventType), style: type.titleMedium),
                SizedBox(height: spacing.xs),
                Text(
                  timestamp == null ? '' : _formatTimestamp(timestamp),
                  style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          MoneyText(
            amount: '$sign${formatMoney(Money.fromMinor(amount.abs()))}',
            size: 16,
          ),
        ],
      ),
    );
  }

  static int primaryAmountMinor(FinancialEvent event) {
    if (event.cashInMinor != 0 || event.cashOutMinor != 0) {
      return event.cashInMinor - event.cashOutMinor;
    }
    if (event.revenueMinor != 0) return event.revenueMinor;
    if (event.operatingExpenseMinor != 0) return -event.operatingExpenseMinor;
    if (event.cogsMinor != 0) return -event.cogsMinor;
    if (event.receivableDeltaMinor != 0) return event.receivableDeltaMinor;
    if (event.payableDeltaMinor != 0) return -event.payableDeltaMinor;
    return event.customerDepositDeltaMinor;
  }

  static String _eventTitle(String eventType) => switch (eventType) {
        'refund' => 'Refund',
        'purchase' => 'Stock purchase',
        'purchase_void' => 'Stock purchase voided',
        'credit_repayment' => 'Credit repayment',
        'credit_adjustment' => 'Credit adjustment',
        'credit_writeoff' => 'Credit write-off',
        'bad_debt_expense' => 'Bad-debt expense',
        'stock_adjustment' => 'Stock correction',
        'stock_count' => 'Stock count correction',
        'cost_pool_entry' => 'Pool cost',
        'cost_pool_allocation' => 'Pool allocation',
        'job_cost' => 'Job cost',
        'job_completion' => 'Job completed',
        'job_payment' => 'Job payment',
        'owner_transaction' => 'Owner money movement',
        'till_movement' => 'Till movement',
        'expense_payment' => 'Expense payment',
        _ => eventType,
      };

  static String _formatTimestamp(DateTime at) =>
      '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

class ExpenseTimelineRow extends StatelessWidget {
  const ExpenseTimelineRow({required this.expense, super.key});

  final Map<String, dynamic> expense;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final int amount = (expense['amount_minor'] as num?)?.toInt() ?? 0;
    final String category = expense['category_name'] as String? ?? 'Other';
    final String source = expense['paid_from'] == 'till_cash'
        ? l10n.transactionsExpenseSourceTill
        : l10n.transactionsExpenseSourceOther;
    final DateTime? at = DateTime.tryParse(
      expense['created_at'] as String? ?? '',
    )?.toLocal();
    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.receipt_long_outlined,
              size: 20, color: colors.onSurfaceMuted),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.transactionsExpenseTitle(category),
                  style: type.titleMedium,
                ),
                SizedBox(height: spacing.xs),
                Text(
                  '${at == null ? '' : _formatTimestamp(at)} · $source',
                  style: type.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                if ((expense['note'] as String? ?? '').trim().isNotEmpty)
                  Text(
                    (expense['note'] as String).trim(),
                    style: type.bodySmall,
                  ),
              ],
            ),
          ),
          SizedBox(width: spacing.sm),
          MoneyText(
            amount: '-${formatMoney(Money.fromMinor(amount))}',
            size: 16,
          ),
        ],
      ),
    );
  }

  static String _formatTimestamp(DateTime at) =>
      '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

class TransactionsRow extends StatelessWidget {
  const TransactionsRow({
    required this.sale,
    required this.audit,
    required this.canSeeSellers,
    this.returnedFraction = 0,
    super.key,
  });

  final Sale sale;
  final AuditLogEntry? audit;

  final bool canSeeSellers;

  /// How much of this sale has come back, from 0 to 1.
  ///
  /// Zero is a sale that has not been touched; one is a sale that has been
  /// given back in full; anything between is PARTLY returned — which is the
  /// case a badge has to distinguish, because a part-returned sale is still
  /// money the shop took.
  final double returnedFraction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      // The row OPENS.
      //
      // A ledger row is a summary — an amount, a relative time, a method — and
      // a summary cannot answer "what happened at 14:32". The exact time,
      // which till, what actually moved and who rang it are all real facts
      // about the sale that the row does not have room for, so a tap opens
      // the record. A row that is not tappable is a dead end: the person
      // standing in front of the till has to write the answer down instead.
      onTap: () => showSaleDetails(
        context,
        sale: sale,
        audit: audit,
        canSeeSellers: canSeeSellers,
        canProcessReturn:
            context.read<AppState>().hasPermission(PermissionKey.processReturn),
        // The shop the sale was rung in: the session's own, which is the only
        // place this till can ring a sale.
        shopName: context.read<AppState>().owner?.shopName ?? '',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_when(context, sale.createdAt),
                        style: type.titleMedium),
                    if (canSeeSellers) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        l10n.transactionsSoldBy(sale.staffName),
                        // A staff name is typed by a human and it can be long.
                        // It WRAPS: a truncated name is a name the owner cannot
                        // read, and a row that grows to fit it is a ledger that
                        // can still be scanned down.
                        style: type.bodySmall?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  MoneyText(amount: formatMoney(sale.total), size: 16),
                  SizedBox(height: spacing.xs),
                  Text(
                    l10n.transactionsMethod(sale.paymentMethod),
                    style: type.labelMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  // The badge, when the money went back.
                  //
                  // "Returned" and "Partly returned" are DIFFERENT facts and
                  // the row has to say which: a sale given back in full is not
                  // money the shop took, and a part-returned sale is money the
                  // shop took for most of it. A list that does not say so
                  // reads as if the money was taken twice.
                  if (returnedFraction > 0) ...<Widget>[
                    SizedBox(height: spacing.xs),
                    StatusChip(
                      tone: returnedFraction >= 1
                          ? StatusTone.danger
                          : StatusTone.warning,
                      text: returnedFraction >= 1
                          ? l10n.transactionsReturnedBadge
                          : l10n.transactionsPartlyReturnedBadge,
                    ),
                  ],
                ],
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Divider(height: 1, color: colors.outline),
          SizedBox(height: spacing.sm),
          Row(
            children: <Widget>[
              Icon(Icons.receipt_long_outlined,
                  size: 16, color: colors.onSurfaceMuted),
              SizedBox(width: spacing.xs),
              Expanded(
                child: Text(
                  l10n.transactionsItemsCount(sale.items.length),
                  style: type.bodySmall,
                ),
              ),
              // The audit half of the row: the same act, read as
              // accountability. Absent when the log has been pruned or the row
              // predates the audit writer, and the sale still says everything
              // about the money.
              //
              // Gated by the same [canSeeSellers] as the seller column, which a
              // test in `transactions_row_test.dart` pins: the audit actor is a
              // staff name, and a role that may not read the ledger must not get
              // it through the half of the row that was not being watched.
              if (canSeeSellers && audit != null) ...<Widget>[
                Icon(Icons.how_to_reg_outlined,
                    size: 16, color: colors.onSurfaceMuted),
                SizedBox(width: spacing.xs),
                // Flexible, because a Row hands its non-flexible children an
                // UNBOUNDED width: a long staff name here did not wrap, it
                // overflowed the row and pushed the layout into an error the
                // owner saw as the ledger breaking. It WRAPS now, rather than
                // being cut off at the end of the line.
                Flexible(
                  child: Text(
                    l10n.transactionsAuditBy(audit!.actorName),
                    style: type.labelMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _when(BuildContext context, String iso) {
    final DateTime? at = DateTime.tryParse(iso);
    if (at == null) return '';
    final DateTime local = at.toLocal();
    final Duration age = DateTime.now().difference(local);
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (age.inMinutes < 60) {
      return l10n.transactionsMinutesAgo(age.inMinutes);
    }
    if (age.inHours < 24) {
      return l10n.transactionsHoursAgo(age.inHours);
    }
    return l10n.transactionsOn(local.day, local.month);
  }
}
