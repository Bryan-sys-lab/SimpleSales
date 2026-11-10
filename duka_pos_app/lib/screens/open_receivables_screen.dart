import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database_helper.dart';
import '../models/credit.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../routing/routes.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _openReceivablesMaxWidth = 1200;

/// Receivables / customer payment history for the Open profile.
///
/// Total outstanding, amount overdue, payments received today, customers
/// with outstanding balances. Each customer row: name, outstanding amount,
/// oldest unpaid record. Opening a customer reveals jobs, sales, payments,
/// balances, references, full history.
class OpenReceivablesScreen extends StatefulWidget {
  const OpenReceivablesScreen({super.key});

  @override
  State<OpenReceivablesScreen> createState() => _OpenReceivablesScreenState();
}

class _OpenReceivablesScreenState extends State<OpenReceivablesScreen> {
  int _totalOwedMinor = 0;
  int _customerCount = 0;
  List<Customer> _customers = const [];
  List<Map<String, dynamic>> _jobReceivables = const [];
  bool _loading = true;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final summary = await _db.creditSummary();
      final customers = await _db.getCustomers(owesOnly: true);

      // Add job receivables: completed/closed jobs with outstanding balances.
      final allJobs = await _db.getOpenJobs();
      final jobRecs = <Map<String, dynamic>>[];
      int jobReceivableTotal = 0;
      for (final job in allJobs) {
        final status = (job['status'] as String?) ?? '';
        if (status != 'completed' && status != 'closed') continue;
        final finalPrice = (job['final_price_minor'] as num?)?.toInt() ?? 0;
        if (finalPrice <= 0) continue;
        final jobId = (job['id'] as num).toInt();
        final payments = await _db.getJobPayments(jobId);
        final paid =
            payments.fold<int>(0, (s, p) => s + ((p['amount_minor'] as num?)?.toInt() ?? 0));
        final outstanding = finalPrice - paid;
        if (outstanding > 0) {
          jobRecs.add({
            'id': jobId,
            'title': job['title'] as String? ?? 'Untitled job',
            'customerName': job['customer_name'] as String? ?? 'Unknown customer',
            'outstanding': outstanding,
          });
          jobReceivableTotal += outstanding;
        }
      }

      if (!mounted) return;
      setState(() {
        _totalOwedMinor = summary.totalOwedMinor + jobReceivableTotal;
        _customerCount = summary.customerCount;
        _customers = customers;
        _jobReceivables = jobRecs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final type = AppTypography.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _openReceivablesMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.openReceivablesTitle,
                        style: AppTypography.of(context).headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        l10n.openReceivablesSubtitle,
                        style: AppTypography.of(context)
                            .bodyMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            // Top figures: total outstanding, customer count
            SurfaceCard(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: _ReceivableTile(
                          label: l10n.openReceivablesTotalOutstanding,
                          value: formatMoney(Money.fromMinor(_totalOwedMinor)),
                          tone: _totalOwedMinor > 0
                              ? StatusTone.warning
                              : StatusTone.success,
                          icon: Icons.schedule_outlined,
                        ),
                      ),
                      SizedBox(width: spacing.lg),
                      Expanded(
                        child: _ReceivableTile(
                          label: l10n.openReceivablesCustomersOwed,
                          value: '$_customerCount',
                          tone: StatusTone.neutral,
                          icon: Icons.people_outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xl),
            // Customer list
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.openReceivablesCustomers,
                  style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: spacing.sm),
                _loading || (_customers.isEmpty && _jobReceivables.isEmpty)
                    ? _OpenReceivablesEmpty(
                        isEmpty:
                            _customers.isEmpty && _jobReceivables.isEmpty && !_loading,
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _customers.length + _jobReceivables.length,
                        itemBuilder: (_, i) {
                          if (i < _customers.length) {
                            final c = _customers[i];
                            return Padding(
                              padding: EdgeInsets.only(bottom: spacing.sm),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceSunken,
                                    borderRadius: AppShapes.of(context)
                                        .controlRadius,
                                  ),
                                  child: Icon(
                                    Icons.person_outline,
                                    size: 18,
                                    color: colors.onSurfaceMuted,
                                  ),
                                ),
                                title: Text(
                                  c.name,
                                  style: AppTypography.of(context).bodyMedium,
                                ),
                                subtitle: Text(
                                  '${l10n.openReceivablesOutstanding} ${formatMoney(Money.fromMinor(c.balanceMinor))}',
                                  style: AppTypography.of(context)
                                      .labelSmall
                                      ?.copyWith(color: colors.onSurfaceMuted),
                                ),
                                trailing: Text(
                                  formatMoney(Money.fromMinor(c.balanceMinor)),
                                  style: AppTypography.of(context)
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                // No customer detail route exists yet; do not
                                // expose a tappable row that would lose context.
                              ),
                            );
                          }
                          final j = _jobReceivables[i - _customers.length];
                          return Padding(
                            padding: EdgeInsets.only(bottom: spacing.sm),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colors.surfaceSunken,
                                  borderRadius: AppShapes.of(context)
                                      .controlRadius,
                                ),
                                child: Icon(
                                  Icons.work_outline,
                                  size: 18,
                                  color: colors.onSurfaceMuted,
                                ),
                              ),
                              title: Text(
                                j['title'] as String,
                                style: AppTypography.of(context).bodyMedium,
                              ),
                              subtitle: Text(
                                '${l10n.openReceivablesOutstanding} ${formatMoney(Money.fromMinor(j['outstanding'] as int))}',
                                style: AppTypography.of(context)
                                    .labelSmall
                                    ?.copyWith(color: colors.onSurfaceMuted),
                              ),
                              trailing: Text(
                                formatMoney(Money.fromMinor(j['outstanding'] as int)),
                                style: AppTypography.of(context)
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              onTap: () => context.push(
                                Routes.openJobDetail(j['id'] as int),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }
}

class _ReceivableTile extends StatelessWidget {
  const _ReceivableTile({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String value;
  final StatusTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: EdgeInsets.all(spacing.xs),
          decoration: BoxDecoration(
            color: tone.container(colors),
            borderRadius: AppShapes.of(context).controlRadius,
          ),
          child: Icon(
            icon,
            size: 18,
            color: tone.onContainer(colors),
          ),
        ),
        SizedBox(height: spacing.lg),
        Text(
          value,
          style: AppTypography.money(
            context,
            size: 20,
            weight: FontWeight.w800,
          ),
        ),
        SizedBox(height: spacing.xs),
        Text(
          label,
          style: type.labelMedium?.copyWith(color: colors.onSurfaceMuted),
        ),
      ],
    );
  }
}

class _OpenReceivablesEmpty extends StatelessWidget {
  const _OpenReceivablesEmpty({required this.isEmpty});

  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: spacing.lg),
        Container(
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: AppShapes.of(context).controlRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isEmpty ? l10n.openReceivablesNoOutstanding : l10n.openReceivablesLoading,
                style: type.bodyMedium,
              ),
              SizedBox(height: spacing.xs),
              Text(
                isEmpty
                    ? l10n.openReceivablesNoOutstandingSubtitle
                    : l10n.openReceivablesLoadingSubtitle,
                style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
