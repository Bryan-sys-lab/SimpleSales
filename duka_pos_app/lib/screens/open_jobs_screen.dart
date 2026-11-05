import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _openJobsMaxWidth = 1200;

enum JobFilter { all, active, awaitingPayment, completed }

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

JobStatus _statusOf(Map<String, dynamic> job) {
  final raw = (job['status'] as String?) ?? 'draft';
  return switch (raw) {
    'draft' => JobStatus.draft,
    'in_progress' => JobStatus.inProgress,
    'awaiting_payment' => JobStatus.awaitingPayment,
    'completed' => JobStatus.completed,
    'cancelled' => JobStatus.cancelled,
    _ => JobStatus.draft,
  };
}

/// Jobs list for the Open profile.
///
/// Compact clickable rows: title, customer, status, quoted amount, amount
/// paid, outstanding balance, last activity. Filter by All, Active,
/// Awaiting payment, Completed. Tapping a row opens the job detail.
class OpenJobsScreen extends StatefulWidget {
  const OpenJobsScreen({super.key});

  @override
  State<OpenJobsScreen> createState() => _OpenJobsScreenState();
}

class _OpenJobsScreenState extends State<OpenJobsScreen> {
  List<Map<String, dynamic>> _jobs = const [];
  JobFilter _filter = JobFilter.all;
  String _searchQuery = '';
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
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredJobs {
    final query = _searchQuery.trim().toLowerCase();
    return _jobs.where((job) {
      final matchesQuery = query.isEmpty ||
          (job['title'] as String? ?? '').toLowerCase().contains(query) ||
          (job['customer_name'] as String? ?? '').toLowerCase().contains(query);
      final status = _statusOf(job);
      final matchesFilter = switch (_filter) {
        JobFilter.all => true,
        JobFilter.active =>
            status == JobStatus.draft || status == JobStatus.inProgress,
        JobFilter.awaitingPayment => status == JobStatus.awaitingPayment,
        JobFilter.completed => status == JobStatus.completed,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  int _jobQuote(Map<String, dynamic> job) =>
      (job['quote_minor'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final jobs = _filteredJobs;

    return AdaptivePage(
      scrollable: true,
      maxContentWidth: _openJobsMaxWidth,
      padding: PageGutter.of(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          BackupReminderBanner(onBackupNow: () async {}),
          SizedBox(height: spacing.section),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.openJobsTitle,
                      style: AppTypography.of(context).headlineSmall,
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      l10n.openJobsSubtitle,
                      style: AppTypography.of(context)
                          .bodyMedium
                          ?.copyWith(color: colors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => context.push(Routes.openJobNew),
                icon: const Icon(Icons.add_task),
                label: Text(l10n.openJobsNewJob),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: spacing.sm),
            child: TextField(
              decoration: InputDecoration(
                labelText: l10n.openJobsSearch,
                hintText: l10n.openJobsSearchHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                constraints: BoxConstraints(
                  minHeight: AppSpacing.of(context).textFieldHeight,
                ),
              ),
              onChanged: (value) =>
                  setState(() => _searchQuery = value),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: spacing.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  FilterChip(
                    selected: _filter == JobFilter.all,
                    label: Text(l10n.openJobsFilterAll),
                    onSelected: (v) => setState(() => _filter = JobFilter.all),
                  ),
                  SizedBox(width: spacing.sm),
                  FilterChip(
                    selected: _filter == JobFilter.active,
                    label: Text(l10n.openJobsFilterActive),
                    onSelected: (v) => setState(() => _filter = JobFilter.active),
                  ),
                  SizedBox(width: spacing.sm),
                  FilterChip(
                    selected: _filter == JobFilter.awaitingPayment,
                    label: Text(l10n.openJobsFilterAwaitingPayment),
                    onSelected: (v) =>
                        setState(() => _filter = JobFilter.awaitingPayment),
                  ),
                  SizedBox(width: spacing.sm),
                  FilterChip(
                    selected: _filter == JobFilter.completed,
                    label: Text(l10n.openJobsFilterCompleted),
                    onSelected: (v) =>
                        setState(() => _filter = JobFilter.completed),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading || jobs.isEmpty
                ? _OpenJobsEmpty(
                    isEmpty: jobs.isEmpty && !_loading,
                    onNewJob: () => context.push(Routes.openJobNew),
                  )
                : ListView.separated(
                    itemCount: jobs.length,
                    separatorBuilder: (_, i) => Divider(
                      height: 1,
                      indent: spacing.md,
                      color: colors.outline,
                    ),
                    itemBuilder: (_, i) {
                      final job = jobs[i];
                      final status = _statusOf(job);
                      final quote = _jobQuote(job);
                      final paid = 0;
                      final outstanding = quote - paid;

                      return Semantics(
                        label:
                            '${job['title']} · ${job['customer_name'] ?? 'No customer'} · ${status.label(l10n)} · Outstanding ${formatMoney(Money.fromMinor(outstanding))}',
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: status.tone(colors)
                                  .container(colors),
                              borderRadius: AppShapes.of(context)
                                  .controlRadius,
                            ),
                            child: Icon(
                              status.icon,
                              size: 18,
                              color: status.tone(colors).onContainer(colors),
                            ),
                          ),
                          title: Text(
                            job['title'] as String,
                            style: AppTypography.of(context).bodyMedium,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '${job['customer_name'] ?? l10n.openJobsNoCustomer} · ${status.label(l10n)}',
                                style: AppTypography.of(context)
                                    .labelSmall
                                    ?.copyWith(color: colors.onSurfaceMuted),
                              ),
                              SizedBox(height: spacing.xs),
                              Row(
                                children: <Widget>[
                                  Text(
                                    formatMoney(Money.fromMinor(quote)),
                                    style: AppTypography.of(context)
                                        .labelSmall
                                        ?.copyWith(color: colors.onSurfaceMuted),
                                  ),
                                  SizedBox(width: spacing.sm),
                                  Text(
                                    formatMoney(Money.fromMinor(paid)),
                                    style: AppTypography.of(context)
                                        .labelSmall
                                        ?.copyWith(color: colors.onSurfaceMuted),
                                  ),
                                  SizedBox(width: spacing.sm),
                                  Text(
                                    formatMoney(Money.fromMinor(outstanding)),
                                    style: AppTypography.of(context)
                                        .labelSmall
                                        ?.copyWith(
                                          color: outstanding > 0
                                              ? colors.danger
                                              : colors.onSurfaceMuted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: StatusChip(
                            tone: status.tone(colors),
                            text: status.label(l10n),
                            dense: true,
                          ),
                          onTap: () => context.push(
                            '${Routes.openJobDetail}/${job['id']}',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _OpenJobsEmpty extends StatelessWidget {
  const _OpenJobsEmpty({required this.isEmpty, required this.onNewJob});

  final bool isEmpty;
  final VoidCallback onNewJob;

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
                isEmpty ? l10n.openJobsNoJobs : l10n.openJobsLoading,
                style: type.bodyMedium,
              ),
              SizedBox(height: spacing.xs),
              Text(
                isEmpty
                    ? l10n.openJobsNoJobsSubtitle
                    : l10n.openJobsLoadingSubtitle,
                style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        FilledButton.icon(
          onPressed: onNewJob,
          icon: const Icon(Icons.add_task),
          label: Text(l10n.openJobsNewJob),
        ),
      ],
    );
  }
}
