import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _openJobDetailMaxWidth = 900;

/// Job statuses used across the Open profile.
enum JobStatus { draft, inProgress, awaitingPayment, completed, cancelled }

extension JobStatusLabel on JobStatus {
  String label(AppLocalizations l10n) => switch (this) {
        JobStatus.draft => l10n.openJobStatusDraft,
        JobStatus.inProgress => l10n.openJobStatusInProgress,
        JobStatus.awaitingPayment => l10n.openJobStatusAwaitingPayment,
        JobStatus.completed => l10n.openJobStatusCompleted,
        JobStatus.cancelled => l10n.openJobStatusCancelled,
      };

  StatusTone tone(AppColors colors) => switch (this) {
        JobStatus.draft => StatusTone.neutral,
        JobStatus.inProgress => StatusTone.warning,
        JobStatus.awaitingPayment => StatusTone.warning,
        JobStatus.completed => StatusTone.success,
        JobStatus.cancelled => StatusTone.danger,
      };

  IconData get icon => switch (this) {
        JobStatus.draft => Icons.edit_outlined,
        JobStatus.inProgress => Icons.build_outlined,
        JobStatus.awaitingPayment => Icons.schedule_outlined,
        JobStatus.completed => Icons.check_circle_outline,
        JobStatus.cancelled => Icons.cancel_outlined,
      };
}

/// One job's detail: overview, financial breakdown, job activity, actions.
///
/// Completing a job is separate from settlement — a job can be completed
/// without being fully paid. Quoted price, final price, payments, receivables
/// and costs remain separate values.
class OpenJobDetailScreen extends StatefulWidget {
  const OpenJobDetailScreen({super.key, required this.jobId});

  final int jobId;

  @override
  State<OpenJobDetailScreen> createState() => _OpenJobDetailScreenState();
}

class _OpenJobDetailScreenState extends State<OpenJobDetailScreen> {
  Map<String, dynamic>? _job;
  List<Map<String, dynamic>> _jobCosts = const [];
  List<Map<String, dynamic>> _jobPayments = const [];
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
      final jobs = await _db.getOpenJobs();
      final job = jobs.firstWhere(
        (j) => (j['id'] as num).toInt() == widget.jobId,
        orElse: () => <String, dynamic>{},
      );
      final costs = await _db.getJobCosts(widget.jobId);
      final payments = await _db.getJobPayments(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = job;
        _jobCosts = costs;
        _jobPayments = payments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int _quoteMinor() => (_job?['quote_minor'] as num?)?.toInt() ?? 0;
  int _finalPriceMinor() => (_job?['final_price_minor'] as num?)?.toInt() ?? 0;
  int _totalCostsMinor() => _jobCosts.fold<int>(
        0,
        (sum, c) => sum + ((c['amount_minor'] as num?)?.toInt() ?? 0),
      );
  int _totalPaymentsMinor() => _jobPayments.fold<int>(
        0,
        (sum, p) => sum + ((p['amount_minor'] as num?)?.toInt() ?? 0),
      );

  Future<void> _recordPayment() async {
    final l10n = AppLocalizations.of(context);
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    String method = 'cash';
    bool paymentVerified = false;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.openJobDetailReceivePayment),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (KES)'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(labelText: l10n.openJobDetailPaymentMethod),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'cash', child: Text(l10n.openJobDetailPaymentCash)),
                  DropdownMenuItem(value: 'mpesa', child: Text(l10n.openJobDetailPaymentMpesa)),
                  DropdownMenuItem(value: 'bank_transfer', child: Text(l10n.openJobDetailPaymentBank)),
                ],
                onChanged: (v) => setState(() => method = v ?? 'cash'),
              ),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(labelText: 'Reference (optional)'),
              ),
              if (method != 'cash') ...<Widget>[
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: Text('I have verified this payment was received'),
                  subtitle: const Text(
                    'Do not record unless you have confirmation (e.g. M-Pesa SMS, bank notification)',
                  ),
                  value: paymentVerified,
                  onChanged: (v) => setState(() => paymentVerified = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.actionCancel)),
            FilledButton(
              onPressed: method != 'cash' && !paymentVerified ? null : () => Navigator.pop(ctx, <String, String>{
                'amount': amountController.text.trim(),
                'method': method,
                'reference': referenceController.text.trim(),
              }),
              child: Text(l10n.openJobDetailReceivePayment),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    referenceController.dispose();
    if (result == null || !mounted) return;
    final amount = double.tryParse(result['amount'] ?? '');
    if (amount == null || amount <= 0) return;
    try {
      await _db.recordJobPayment(
        uuid: 'jobpay-${DateTime.now().microsecondsSinceEpoch}',
        jobId: widget.jobId,
        amount: Money.fromMajor(amount),
        paymentMethod: result['method'] ?? 'cash',
        reference: (result['reference'] ?? '').isEmpty ? null : result['reference'],
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.openJobDetailCouldNotRecordPayment(e))),
        );
      }
    }
  }

  bool get _isCompleted => _job?['status'] == 'closed';

  JobStatus _statusOf(Map<String, dynamic> job) {
    final raw = (job['status'] as String?) ?? 'draft';
    return switch (raw) {
      'draft' => JobStatus.draft,
      'open' => JobStatus.inProgress,
      'in_progress' => JobStatus.inProgress,
      'awaiting_payment' => JobStatus.awaitingPayment,
      'completed' => JobStatus.completed,
      'closed' => JobStatus.completed,
      'cancelled' => JobStatus.cancelled,
      _ => JobStatus.draft,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final appState = context.watch<AppState>();

    final bool canManageJobs = appState.canManageStock;
    final bool canReceivePayments =
        appState.hasPermission(PermissionKey.receiveStock);
    final bool canRecordSales =
        appState.isOwnerSession || appState.role == ShopRole.manager;

    if (_loading) {
      return AdaptivePage(
        maxContentWidth: _openJobDetailMaxWidth,
        padding: PageGutter.of(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_job == null || _job!.isEmpty) {
      return AdaptivePage(
        maxContentWidth: _openJobDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            Text(
              l10n.openJobDetailNotFound,
              style: AppTypography.of(context).headlineSmall,
            ),
          ],
        ),
      );
    }

    final quote = Money.fromMinor(_quoteMinor());
    final finalPrice = Money.fromMinor(_finalPriceMinor());
    final totalCosts = Money.fromMinor(_totalCostsMinor());
    final totalPayments = Money.fromMinor(_totalPaymentsMinor());
    final outstanding = Money.fromMinor(_finalPriceMinor() - _totalPaymentsMinor());
    final estimatedProfit = Money.fromMinor(
      _finalPriceMinor() - _totalCostsMinor(),
    );

    final status = _statusOf(_job!);

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _openJobDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            // Job header: title, customer, status chip
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _job!['title'] as String,
                        style: AppTypography.of(context).headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        '${_job!['customer_name'] ?? l10n.openJobDetailNoCustomer}',
                        style: AppTypography.of(context)
                            .bodyMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  tone: status.tone(colors),
                  text: status.label(l10n),
                ),
              ],
            ),
            SizedBox(height: spacing.xl),
            // Job overview section
            _DetailSection(
              title: l10n.openJobDetailOverview,
              children: <Widget>[
                _DetailRow(
                  label: l10n.openJobDetailQuote,
                  value: formatMoney(quote),
                ),
                _DetailRow(
                  label: l10n.openJobDetailFinalPrice,
                  value: formatMoney(finalPrice),
                ),
                _DetailRow(
                  label: l10n.openJobDetailStatus,
                  value: status.label(l10n),
                ),
                _DetailRow(
                  label: l10n.openJobDetailCreated,
                  value: _job!['created_at'] as String? ?? '',
                ),
              ],
            ),
            SizedBox(height: spacing.lg),
            // Financial breakdown section
            _DetailSection(
              title: l10n.openJobDetailFinancials,
              children: <Widget>[
                _DetailRow(
                  label: l10n.openJobDetailQuotedAmount,
                  value: formatMoney(quote),
                ),
                _DetailRow(
                  label: l10n.openJobDetailDirectCosts,
                  value: formatMoney(totalCosts),
                ),
                _DetailRow(
                  label: l10n.openJobDetailPaymentsReceived,
                  value: formatMoney(totalPayments),
                ),
                _DetailRow(
                  label: l10n.openJobDetailOutstanding,
                  value: formatMoney(outstanding),
                  tone: outstanding.minorUnits > 0
                      ? StatusTone.warning
                      : StatusTone.success,
                ),
                _DetailRow(
                  label: l10n.openJobDetailEstimatedProfit,
                  value: formatMoney(estimatedProfit),
                ),
              ],
            ),
            SizedBox(height: spacing.lg),
            // Job activity section
            _DetailSection(
              title: l10n.openJobDetailActivity,
              children: <Widget>[
                if (_jobCosts.isEmpty && _jobPayments.isEmpty)
                  Text(
                    l10n.openJobDetailNoActivity,
                    style: AppTypography.of(context)
                        .labelSmall
                        ?.copyWith(color: colors.onSurfaceMuted),
                  )
                else ...<Widget>[
                  for (final cost in _jobCosts)
                    _ActivityRow(
                      label: l10n.openJobDetailCostAdded,
                      amount: Money.fromMinor(
                        (cost['amount_minor'] as num?)?.toInt() ?? 0,
                      ),
                      when: cost['created_at'] as String? ?? '',
                    ),
                  for (final payment in _jobPayments)
                    _ActivityRow(
                      label: l10n.openJobDetailPaymentReceived,
                      amount: Money.fromMinor(
                        (payment['amount_minor'] as num?)?.toInt() ?? 0,
                      ),
                      when: payment['created_at'] as String? ?? '',
                    ),
                ],
              ],
            ),
            SizedBox(height: spacing.xl),
            // Actions section
            _DetailSection(
              title: l10n.openJobDetailActions,
              children: <Widget>[
                if (canManageJobs)
                  _ActionButton(
                    label: l10n.openJobDetailEditJob,
                    icon: Icons.edit_outlined,
                    onPressed: () => context.push(Routes.openJobEdit(widget.jobId)),
                  ),
                if (canManageJobs)
                  _ActionButton(
                    label: l10n.openJobDetailAddCost,
                    icon: Icons.add_circle_outlined,
                    onPressed: () => context.push(
                      Routes.openJobAddCost(widget.jobId),
                    ),
                  ),
                if (canReceivePayments)
                  _ActionButton(
                    label: l10n.openJobDetailReceivePayment,
                    icon: Icons.payment_outlined,
                    onPressed: _recordPayment,
                  ),
                if (canRecordSales)
                  _ActionButton(
                    label: l10n.openJobDetailRecordSale,
                    icon: Icons.point_of_sale_outlined,
                    onPressed: () => context.push(Routes.sell, extra: widget.jobId),
                  ),
                if (canManageJobs && !_isCompleted)
                  _ActionButton(
                    label: l10n.openJobDetailCompleteJob,
                    icon: Icons.check_circle_outlined,
                    onPressed: () => _completeJob(context),
                  ),
              ],
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }

  void _completeJob(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final initialMajor = ((_finalPriceMinor() > 0 ? _finalPriceMinor() : _quoteMinor()) / 100.0)
        .toStringAsFixed(2);
    controller.text = initialMajor;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.openJobDetailCompleteJob),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(l10n.openJobDetailCompleteJobConfirm),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Final price'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.openJobDetailCancel),
          ),
          FilledButton(
            onPressed: () async {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || parsed <= 0) return;
              final finalPrice = Money.fromMajor(parsed);
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(dialogContext);
              try {
                await _db.completeJob(jobId: widget.jobId, finalPrice: finalPrice);
                if (mounted) await _load();
              } catch (_) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.openJobDetailCouldNotCompleteJob)),
                  );
                }
              }
            },
            child: Text(l10n.openJobDetailCompleteAndSettle),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: spacing.sm),
        ...children,
        SizedBox(height: spacing.lg),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.tone,
  });

  final String label;
  final String value;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Text(
                  value,
                  style: type.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tone != null
                        ? (tone == StatusTone.danger
                            ? colors.danger
                            : colors.warning)
                        : colors.onSurface,
                  ),
                ),
                if (tone != null) ...<Widget>[
                  SizedBox(width: spacing.sm),
                  StatusChip(
                    tone: tone!,
                    text: tone!.label,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.label,
    required this.amount,
    required this.when,
  });

  final String label;
  final Money amount;
  final String when;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: type.bodyMedium,
                ),
                SizedBox(height: spacing.xs),
                Text(
                  when,
                  style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(amount),
            style: type.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: spacing.sm),
        ),
      ),
    );
  }
}
