import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import 'cash_control_sheets.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../services/roles.dart';
import '../models/audit_log.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../utils/datetime_format.dart';
import '../utils/money.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  int _rangeDays = 30;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      DatabaseHelper.instance.getExpenseHistory(
          since: DateTime.now().subtract(Duration(days: _rangeDays)));

  void _reload() => setState(() => _future = _load());

  Future<void> _payExpense(Map<String, dynamic> row) async {
    final remaining = (row['remaining_payable_minor'] as num?)?.toInt() ?? 0;
    if (remaining <= 0) return;
    final saved = await showExpensePaymentSheet(
      context,
      expenseId: row['id'] as int,
      remainingMinor: remaining,
    );
    if (saved && mounted) _reload();
  }

  Future<void> _voidExpense(Map<String, dynamic> row) async {
    final appState = context.read<AppState>();
    if (!appState.isOwnerSession) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void expense?'),
        content:
            const Text('This keeps the record but removes it from totals.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Void')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await DatabaseHelper.instance.voidExpense(row['id'] as int);
      await recordActionAudit(
        appState,
        action: AuditAction.expenseVoided,
        entity: AuditEntity.expense,
        entityId: 'id-${row['id']}',
        detail: row['category_name'] as String? ?? 'expense',
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appState = context.watch<AppState>();
    final canView = appState.hasPermission(PermissionKey.recordExpense);
    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.expenseHistoryTitle)),
        body: Center(child: Text(l10n.expenseManagerOnly)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.expenseHistoryTitle)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorStateView(
              message: l10n.shiftLoadFailedTitle,
              detail: l10n.shiftLoadFailedDetail,
              onRetry: _reload,
            );
          }
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return Center(child: Text(l10n.expenseHistoryEmpty));
          }
          final total = rows.fold<int>(
            0,
            (sum, row) => sum + (row['amount_minor'] as num).toInt(),
          );
          final byCategory = <String, int>{};
          for (final row in rows) {
            final category = row['category_name'] as String? ?? 'Other';
            byCategory[category] = (byCategory[category] ?? 0) +
                (row['amount_minor'] as num).toInt();
          }
          final spacing = AppSpacing.of(context);
          final colors = AppColors.of(context);
          final type = AppTypography.of(context);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: EdgeInsets.all(spacing.md),
              children: <Widget>[
                SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment(value: 7, label: Text('7 days')),
                    ButtonSegment(value: 30, label: Text('30 days')),
                    ButtonSegment(value: 365, label: Text('1 year')),
                  ],
                  selected: <int>{_rangeDays},
                  onSelectionChanged: (value) {
                    setState(() {
                      _rangeDays = value.first;
                      _future = _load();
                    });
                  },
                ),
                SizedBox(height: spacing.md),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l10n.expenseHistoryTotal,
                          style: type.labelLarge
                              ?.copyWith(color: colors.onSurfaceMuted)),
                      SizedBox(height: spacing.xs),
                      Text(formatMoney(Money.fromMinor(total)),
                          style: type.headlineMedium),
                      SizedBox(height: spacing.sm),
                      for (final entry in byCategory.entries)
                        Padding(
                          padding: EdgeInsets.only(top: spacing.xs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Text(entry.key),
                                  Text(formatMoney(
                                      Money.fromMinor(entry.value))),
                                ],
                              ),
                              SizedBox(height: spacing.xs),
                              LinearProgressIndicator(
                                  value: total == 0 ? 0 : entry.value / total),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.md),
                for (final row in rows)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(row['category_name'] as String? ?? 'Other'),
                      subtitle: Text(
                        '${formatInstant(row['created_at'] as String)}'
                        '${(row['note'] as String?)?.trim().isNotEmpty == true ? ' • ${row['note']}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(formatMoney(Money.fromMinor(
                              (row['amount_minor'] as num).toInt()))),
                          if (appState.isOwnerSession)
                            IconButton(
                              tooltip: 'Void expense',
                              onPressed: () => _voidExpense(row),
                              icon: const Icon(Icons.block_outlined),
                            ),
                          if (row['paid_from'] == 'payable' &&
                              ((row['remaining_payable_minor'] as num?)
                                          ?.toInt() ??
                                      0) >
                                  0)
                            IconButton(
                              tooltip: 'Pay expense',
                              onPressed: () => _payExpense(row),
                              icon: const Icon(Icons.payment_outlined),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
