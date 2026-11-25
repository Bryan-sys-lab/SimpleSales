import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_keys.dart';
import '../services/backend_service.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';

class PlanDetailsScreen extends StatefulWidget {
  const PlanDetailsScreen({super.key});

  @override
  State<PlanDetailsScreen> createState() => _PlanDetailsScreenState();
}

class _PlanDetailsScreenState extends State<PlanDetailsScreen> {
  SubscriptionEntitlement? _entitlement;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entitlement = await BackendService.fetchSubscriptionEntitlement();
      if (!mounted) return;
      setState(() {
        _entitlement = entitlement;
        _loading = false;
      });
    } catch (error, stack) {
      debugPrint('Could not load plan details: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).settingsSubscriptionUnavailable;
      });
    }
  }

  String _formatAmount(int minor, String currency) =>
      '$currency ${(minor / 100).toStringAsFixed(2)}';

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return MaterialLocalizations.of(context).formatMediumDate(parsed.toLocal());
  }

  String _billingPeriodLabel(
    AppLocalizations l10n,
    SubscriptionEntitlement entitlement,
  ) {
    final checkout = entitlement.checkout;
    if (checkout == null) {
      return l10n.billingIntervalLabel(entitlement.billingInterval);
    }
    return switch (checkout.durationMonths) {
      1 => l10n.billingIntervalMonthly,
      3 => l10n.billingIntervalQuarterly,
      6 => l10n.billingIntervalSemiannual,
      12 => l10n.billingIntervalAnnual,
      _ => l10n.paywallPaymentDuration(checkout.durationMonths),
    };
  }

  String _statusLabel(AppLocalizations l10n, SubscriptionEntitlement? e) {
    if (e == null) return l10n.settingsSubscriptionNotConfigured;
    final status = e.status.toLowerCase();
    if (status == 'active') return l10n.planDetailsStatusActive;
    if (status == 'grace') return l10n.planDetailsStatusGrace;
    if (status == 'expired') return l10n.planDetailsStatusExpired;
    if (status == 'pending') return l10n.planDetailsStatusPending;
    if (e.allowed) return l10n.planDetailsStatusActive;
    return e.status;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final e = _entitlement;
    final checkout = e?.checkout;
    final discountPercent =
        checkout?.discountPercent ?? e?.discountPercent ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.planDetailsTitle),
        actions: [
          IconButton(
            tooltip: l10n.paywallCheckVoucher,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child:
                        Text(_error!, style: TextStyle(color: colors.danger)),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.planDetailsCurrentPlan,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _DetailRow(
                          label: l10n.planDetailsStatusLabel,
                          value: _statusLabel(l10n, e),
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: l10n.planDetailsPriceLabel,
                          value: checkout != null
                              ? _formatAmount(
                                  checkout.baseAmountMinor, e!.currency)
                              : e?.priceMinor != null && e!.priceMinor! > 0
                                  ? _formatAmount(e.priceMinor!, e.currency)
                                  : l10n.settingsSubscriptionNotConfigured,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: l10n.planDetailsBillingPeriodLabel,
                          value: e == null
                              ? l10n.settingsSubscriptionUnavailable
                              : _billingPeriodLabel(l10n, e),
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: l10n.planDetailsPeriodEndLabel,
                          value: e?.currentPeriodEnd == null
                              ? l10n.planDetailsNoPeriodEnd
                              : _formatDate(e!.currentPeriodEnd),
                        ),
                        if (e != null && discountPercent > 0) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: l10n.paywallDiscount(discountPercent),
                            value: checkout != null
                                ? _formatAmount(
                                    checkout.amountMinor, e.currency)
                                : e.priceMinor != null && e.priceMinor! > 0
                                    ? _formatAmount(
                                        (e.priceMinor! *
                                                (100 -
                                                    discountPercent.clamp(
                                                        0, 100)) /
                                                100)
                                            .round(),
                                        e.currency,
                                      )
                                    : '-',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (e?.claimedVoucherDurationMonths != null ||
                    e?.discountVoucherDurationMonths != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.membershipVouchers,
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            e?.claimedVoucherType == 'discount' ||
                                    e?.discountVoucherDurationMonths != null
                                ? l10n.paywallDiscountVoucherClaimed(
                                    e?.claimedVoucherDiscountPercent ??
                                        e?.discountPercent ??
                                        0,
                                    e?.claimedVoucherDurationMonths ??
                                        e?.discountVoucherDurationMonths ??
                                        0,
                                  )
                                : l10n.paywallVoucherReady(
                                    e?.claimedVoucherDurationMonths ??
                                        e?.discountVoucherDurationMonths ??
                                        0,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.push(Routes.paywall),
                  icon: const Icon(Icons.redeem_outlined),
                  label: Text(l10n.planDetailsManageVoucher),
                ),
              ],
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: style?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
