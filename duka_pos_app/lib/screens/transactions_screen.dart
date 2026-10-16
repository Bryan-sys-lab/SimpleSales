/// Who sold what.
///
/// The dashboard's transactions count is a DOOR: a manager who sees "23" today
/// is asking "which 23, and by whom". This is that list — each sale with the
/// person who rang it, what they sold and when — and the audit entry recorded
/// against it, because a ring-up is the one act that moves money and it is the
/// one that has to be attributable afterwards.
///
/// Two records of the same act, deliberately. The sale row is the money
/// (totals, items, tender); the audit row is the accountability (who, from
/// which session). A list of only the money cannot answer "was this the
/// cashier or the owner", and a list of only the audit lines cannot answer
/// "what was in the basket".
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../utils/money.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

/// What the ledger is showing, and whether it could be loaded at all.
sealed class _LedgerState {}

class _LedgerLoading extends _LedgerState {}

class _LedgerReady extends _LedgerState {
  _LedgerReady(this.sales, this.audit, this.canSeeSellers);

  final List<Sale> sales;
  final List<AuditLogEntry> audit;

  /// Whether this session may read every seller, or only its own.
  final bool canSeeSellers;
}

class _LedgerFailed extends _LedgerState {
  _LedgerFailed(this.message);
  final String message;
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  _LedgerState _state = _LedgerLoading();

  /// How far back the ledger reads.
  ///
  /// Bounded like every other shop-wide read: "everything ever" on a shop with
  /// two years of trading is a list nobody scrolls, and two rows per
  /// transaction is already twice the work of the count that opens it.
  static const int _days = 14;

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
      final String? staff = state.canManageStock ? null : state.currentStaffName;
      final List<Sale> sales =
          await db.getSales(since: since, staffName: staff, limit: 200);
      final List<AuditLogEntry> audit = await db.auditLog(
        AuditLogQuery(actions: <AuditAction>[AuditAction.saleRecorded], limit: 200),
      );
      if (!mounted) return;
      setState(() => _state = _LedgerReady(sales, audit, staff == null));
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
          :final List<Sale> sales,
          :final List<AuditLogEntry> audit,
          :final bool canSeeSellers,
        ) =>
          sales.isEmpty
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
                    sales: sales,
                    audit: audit,
                    canSeeSellers: canSeeSellers,
                  ),
                ),
      },
    );
  }
}

/// The list itself, as one sliver list so the whole screen scrolls as one.
class _Ledger extends StatelessWidget {
  const _Ledger({
    required this.sales,
    required this.audit,
    required this.canSeeSellers,
  });

  final List<Sale> sales;
  final List<AuditLogEntry> audit;

  /// The who-sold-it column is management-facing: a cashier's own shift is
  /// theirs, a roster-wide ledger of everyone's is not.
  final bool canSeeSellers;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    // Two keys, because there are two ways a sale reaches the log: checkout
    // writes `id-<saleId>` (sell_screen.dart:1056) and the reconciled M-Pesa path
    // writes the provider's reference (sell_screen.dart:388). Requiring the
    // `id-` prefix explicitly matters — `int.tryParse` on a bare numeric
    // reference would otherwise coerce it into a sale id and attribute one
    // sale's audit line to another.
    final Map<int, AuditLogEntry> bySale = <int, AuditLogEntry>{
      for (final AuditLogEntry entry in audit)
        if (entry.entityId case final String id when id.startsWith('id-'))
          if (int.tryParse(id.substring(3)) case final int saleId)
            saleId: entry,
    };

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.md,
              end: spacing.md,
              top: spacing.md,
              bottom: spacing.sm,
            ),
            child: Text(
              l10n.transactionsSubtitle(sales.length),
              style: AppTypography.of(context).bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
            ),
          ),
        ),
        SliverList.separated(
          itemCount: sales.length,
          separatorBuilder: (_, __) => SizedBox(height: spacing.sm),
          itemBuilder: (BuildContext context, int index) => TransactionsRow(
            sale: sales[index],
            audit: bySale[sales[index].id],
            canSeeSellers: canSeeSellers,
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: spacing.xxl)),
      ],
    );
  }
}

/// One sale, with the audit entry recorded against it.
///
/// Public so a test can render a row from constructed values: the pairing this
/// screen exists for is per-row, and a row is the unit worth pinning.
class TransactionsRow extends StatelessWidget {
  const TransactionsRow({
    required this.sale,
    required this.audit,
    required this.canSeeSellers,
    super.key,
  });

  final Sale sale;
  final AuditLogEntry? audit;

  /// See [_Ledger.canSeeSellers].
  final bool canSeeSellers;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
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
                Text(
                  l10n.transactionsAuditBy(audit!.actorName),
                  style: type.labelMedium?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// When, relative on a till: "2h ago" is what a manager scanning today needs,
  /// and the date is what they need for a dispute.
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
