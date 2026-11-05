import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _openCostGroupDetailMaxWidth = 900;

/// One cost group's detail: info, investment, allocations, remaining balance,
/// movement history.
class OpenCostGroupDetailScreen extends StatefulWidget {
  const OpenCostGroupDetailScreen({super.key, required this.poolId});

  final int poolId;

  @override
  State<OpenCostGroupDetailScreen> createState() =>
      _OpenCostGroupDetailScreenState();
}

class _OpenCostGroupDetailScreenState
    extends State<OpenCostGroupDetailScreen> {
  Map<String, dynamic>? _pool;
  List<Map<String, dynamic>> _entries = const [];
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
      final pools = await _db.getCostPools();
      final pool = pools.firstWhere(
        (p) => (p['id'] as num).toInt() == widget.poolId,
        orElse: () => <String, dynamic>{},
      );
      final entries = await _db.getCostPoolEntries(widget.poolId);
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int _investedMinor() => (_pool?['invested_minor'] as num?)?.toInt() ?? 0;
  int _recoveredMinor() => (_pool?['recovered_minor'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return AdaptivePage(
        maxContentWidth: _openCostGroupDetailMaxWidth,
        padding: PageGutter.of(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_pool == null || _pool!.isEmpty) {
      return AdaptivePage(
        maxContentWidth: _openCostGroupDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () async {}),
            SizedBox(height: spacing.section),
            Text(
              l10n.openCostGroupDetailNotFound,
              style: AppTypography.of(context).headlineSmall,
            ),
          ],
        ),
      );
    }

    final invested = Money.fromMinor(_investedMinor());
    final recovered = Money.fromMinor(_recoveredMinor());
    final remaining = Money.fromMinor(
      invested.minorUnits - recovered.minorUnits,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _openCostGroupDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () async {}),
            SizedBox(height: spacing.section),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _pool!['name'] as String,
                        style: AppTypography.of(context).headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        _pool!['note'] as String? ?? l10n.openCostGroupDetailNoNote,
                        style: AppTypography.of(context)
                            .bodyMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  tone: remaining.minorUnits > 0
                      ? StatusTone.warning
                      : StatusTone.success,
                  text: remaining.minorUnits > 0
                      ? l10n.openCostGroupDetailHasRemaining
                      : l10n.openCostGroupDetailFullyAllocated,
                ),
              ],
            ),
            SizedBox(height: spacing.xl),
            _DetailSection(
              title: l10n.openCostGroupDetailInvestment,
              children: <Widget>[
                _DetailRow(
                  label: l10n.openCostGroupDetailInitialInvestment,
                  value: formatMoney(invested),
                ),
                _DetailRow(
                  label: l10n.openCostGroupDetailAllocated,
                  value: formatMoney(recovered),
                ),
                _DetailRow(
                  label: l10n.openCostGroupDetailRemaining,
                  value: formatMoney(remaining),
                  tone: remaining.minorUnits > 0
                      ? StatusTone.warning
                      : StatusTone.success,
                ),
              ],
            ),
            SizedBox(height: spacing.lg),
            _DetailSection(
              title: l10n.openCostGroupDetailMovementHistory,
              children: <Widget>[
                if (_entries.isEmpty)
                  Text(
                    l10n.openCostGroupDetailNoMovements,
                    style: AppTypography.of(context)
                        .labelSmall
                        ?.copyWith(color: colors.onSurfaceMuted),
                  )
                else
                  for (final entry in _entries)
                    _MovementRow(
                      label:
                          entry['description'] as String? ?? l10n.openCostGroupDetailEntry,
                      amount: Money.fromMinor(
                        (entry['amount_minor'] as num?)?.toInt() ?? 0,
                      ),
                      when: entry['created_at'] as String? ?? '',
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

class _MovementRow extends StatelessWidget {
  const _MovementRow({
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
