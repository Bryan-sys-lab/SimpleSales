import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_keys.dart';
import '../routing/app_stage_controller.dart';
import '../services/backend_service.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../ui/components/surface.dart';

class PlanDetailsScreen extends StatefulWidget {
  const PlanDetailsScreen({super.key});

  @override
  State<PlanDetailsScreen> createState() => _PlanDetailsScreenState();
}

class _PlanDetailsScreenState extends State<PlanDetailsScreen> {
  SubscriptionEntitlement? _entitlement;
  bool _loading = true;
  bool _claimingVoucher = false;
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

  Future<SubscriptionEntitlement> _reloadClaimedVoucherTerms(
    SubscriptionEntitlement claimed,
  ) async {
    try {
      final refreshed = await BackendService.fetchSubscriptionEntitlement();
      if (refreshed == null) {
        throw StateError('Subscription response did not include entitlement');
      }
      return refreshed.copyWith(
        claimedVoucherType: claimed.claimedVoucherType,
        claimedVoucherDurationMonths: claimed.claimedVoucherDurationMonths,
        claimedVoucherDiscountPercent: claimed.claimedVoucherDiscountPercent,
      );
    } catch (error, stack) {
      debugPrint(
        'Could not refresh plan details after voucher claim: $error\n$stack',
      );
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).settingsSubscriptionUnavailable;
        });
      }
      return claimed;
    }
  }

  Future<void> _claimAvailableVoucher() async {
    if (_loading || _claimingVoucher) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _claimingVoucher = true;
      _error = null;
    });
    try {
      final claimed = await BackendService.claimAvailableVoucher();
      if (claimed == null) {
        throw StateError('Voucher claim response did not include entitlement');
      }
      if (!mounted) return;

      if (claimed.claimedVoucherType == 'discount') {
        final updated = await _reloadClaimedVoucherTerms(claimed);
        if (!mounted) return;
        setState(() => _entitlement = updated);
        final duration = updated.claimedVoucherDurationMonths ??
            updated.discountVoucherDurationMonths ??
            1;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.paywallDiscountVoucherClaimed(
                updated.claimedVoucherDiscountPercent ??
                    updated.discountPercent,
                duration,
              ),
            ),
          ),
        );
        if (claimed.allowed) {
          await context.read<AppStageController>().refreshSubscription();
        }
        return;
      }

      if (claimed.allowed) {
        await context.read<AppStageController>().refreshSubscription();
        if (!mounted) return;
        context.go(Routes.dashboard);
        return;
      }

      setState(() {
        _error = l10n.paywallVoucherClaimFailed;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = (error.response?.data is Map
                ? error.response!.data['error'] as String?
                : null) ??
            l10n.paywallVoucherClaimFailed;
      });
    } catch (error, stack) {
      debugPrint('Could not claim issued plan voucher: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _error = l10n.paywallVoucherClaimFailed;
      });
    } finally {
      if (mounted) {
        setState(() => _claimingVoucher = false);
      }
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
    if (status == 'active') return l10n.planDetailsStatusAccessActive;
    if (status == 'grace') return l10n.planDetailsStatusGrace;
    if (status == 'expired') return l10n.planDetailsStatusExpired;
    if (status == 'pending') return l10n.planDetailsStatusPending;
    if (e.allowed) return l10n.planDetailsStatusActive;
    return e.status;
  }

  String _paymentMethodLabel(
    AppLocalizations l10n,
    SubscriptionPaymentMethod method,
  ) {
    if (method.method == 'mpesa_stk') return l10n.paywallPaymentMethodMpesa;
    return method.method;
  }

  String _paymentDestinationLabel(
    AppLocalizations l10n,
    SubscriptionPaymentMethod method,
  ) =>
      switch (method.channelType) {
        'till' => l10n.paywallPaymentTillDestination(method.shortCode),
        'paybill' => l10n.paywallPaymentPaybillDestination(method.shortCode),
        'bank' => l10n.paywallPaymentBankDestination(
            method.shortCode,
            method.accountNumber ?? '',
          ),
        _ => method.shortCode,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final e = _entitlement;
    final checkout = e?.checkout;
    final hasClaimedDiscountVoucher = e?.claimedVoucherType == 'discount' ||
        e?.discountVoucherDurationMonths != null;
    final discountPercent = checkout != null
        ? checkout.discountPercent
        : hasClaimedDiscountVoucher
            ? e?.claimedVoucherDiscountPercent ?? e?.discountPercent ?? 0
            : 0;
    final paymentMethod = e?.paymentMethod;
    final accessColor = e?.allowed == true ? colors.success : colors.warning;
    final availableVoucherDuration = e?.availableVoucherDurationMonths;
    final availableVoucherLabel = e?.availableVoucherType == 'discount'
        ? l10n.paywallAvailableDiscountVoucher(
            e?.availableVoucherDiscountPercent ?? 0,
            availableVoucherDuration ?? 0,
          )
        : availableVoucherDuration == null
            ? null
            : l10n.paywallVoucherReady(availableVoucherDuration);

    return Scaffold(
      body: SafeArea(
        child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    spacing.md,
                    spacing.xxs,
                    spacing.md,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: l10n.paywallViewPlan,
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: Text(
                          l10n.planDetailsDashboardTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.paywallCheckVoucher,
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const LinearProgressIndicator(),
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        spacing.lg,
                        spacing.md,
                        spacing.lg,
                        spacing.xl,
                      ),
                      children: [
                        if (_error != null)
                          SurfaceCard(
                            child: Text(
                              _error!,
                              style: TextStyle(color: colors.danger),
                            ),
                          ),
                        SurfaceCard(
                          accentEdge: true,
                          child: Row(
                            children: [
                              Container(
                                width: spacing.spacious + spacing.sm,
                                height: spacing.spacious + spacing.sm,
                                decoration: BoxDecoration(
                                  color: colors.surfaceSunken,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: accessColor,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.workspace_premium_rounded,
                                  color: accessColor,
                                  size: 46,
                                ),
                              ),
                              SizedBox(width: spacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.circle,
                                            size: 12, color: accessColor),
                                        SizedBox(width: spacing.xs),
                                        Flexible(
                                          child: Text(
                                            _statusLabel(l10n, e),
                                            style: theme.textTheme.titleMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: spacing.xs),
                                    Text(
                                      e?.currentPeriodEnd == null
                                          ? l10n.planDetailsNoExpiryDate
                                          : l10n.planDetailsUntilDate(
                                              _formatDate(e!.currentPeriodEnd),
                                            ),
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: spacing.md),
                        SurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.planDetailsCurrentPlan,
                                  style: theme.textTheme.titleMedium),
                              SizedBox(height: spacing.sm),
                              if (e?.claimedVoucherType != null ||
                                  e?.discountVoucherDurationMonths != null) ...[
                                _DetailRow(
                                  icon: Icons.sell_outlined,
                                  label: l10n.planDetailsAccessTypeLabel,
                                  value: l10n.planDetailsVoucherAccessType,
                                ),
                                Divider(height: spacing.lg),
                              ],
                              _DetailRow(
                                icon: Icons.calendar_month_outlined,
                                label: l10n.planDetailsExpiryDateLabel,
                                value: e?.currentPeriodEnd == null
                                    ? l10n.planDetailsNoExpiryDate
                                    : _formatDate(e!.currentPeriodEnd),
                              ),
                            ],
                          ),
                        ),
                        if (checkout != null ||
                            paymentMethod != null ||
                            (e?.priceMinor ?? 0) > 0) ...[
                          SizedBox(height: spacing.md),
                          SurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_outlined,
                                      color: colors.accent,
                                    ),
                                    SizedBox(width: spacing.xs),
                                    Text(
                                      l10n.planDetailsPaymentDetailsTitle,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                                Divider(height: spacing.lg),
                                if (e != null) ...[
                                  _DetailRow(
                                    icon: Icons.sell_outlined,
                                    label: l10n.planDetailsPriceLabel,
                                    value: checkout != null
                                        ? _formatAmount(
                                            checkout.baseAmountMinor,
                                            e.currency,
                                          )
                                        : e.priceMinor != null &&
                                                e.priceMinor! > 0
                                            ? _formatAmount(
                                                e.priceMinor!,
                                                e.currency,
                                              )
                                            : l10n
                                                .settingsSubscriptionNotConfigured,
                                  ),
                                  SizedBox(height: spacing.xs),
                                  _DetailRow(
                                    icon: Icons.calendar_month_outlined,
                                    label: l10n.planDetailsBillingPeriodLabel,
                                    value: _billingPeriodLabel(l10n, e),
                                  ),
                                ],
                                if (checkout != null && e != null) ...[
                                  SizedBox(height: spacing.xs),
                                  _DetailRow(
                                    icon: Icons.payments_outlined,
                                    label: l10n.paywallAmountDue,
                                    value: _formatAmount(
                                      checkout.amountMinor,
                                      e.currency,
                                    ),
                                  ),
                                ],
                                if (e != null && discountPercent > 0) ...[
                                  SizedBox(height: spacing.xs),
                                  _DetailRow(
                                    icon: Icons.percent_rounded,
                                    label:
                                        l10n.paywallDiscount(discountPercent),
                                    value: checkout != null
                                        ? _formatAmount(
                                            checkout.discountAmountMinor,
                                            e.currency,
                                          )
                                        : e.priceMinor != null &&
                                                e.priceMinor! > 0
                                            ? _formatAmount(
                                                (e.priceMinor! *
                                                        discountPercent.clamp(
                                                            0, 100) /
                                                        100)
                                                    .round(),
                                                e.currency,
                                              )
                                            : '-',
                                  ),
                                ],
                                if (paymentMethod != null) ...[
                                  Divider(height: spacing.lg),
                                  _DetailRow(
                                    icon: Icons.phone_android_rounded,
                                    label: l10n.paywallPaymentMethodTitle,
                                    value: _paymentMethodLabel(
                                        l10n, paymentMethod),
                                  ),
                                  SizedBox(height: spacing.xs),
                                  _DetailRow(
                                    icon: Icons.place_outlined,
                                    label: l10n.paywallPaymentDestinationTitle,
                                    value: _paymentDestinationLabel(
                                      l10n,
                                      paymentMethod,
                                    ),
                                  ),
                                ] else if (checkout != null) ...[
                                  Divider(height: spacing.lg),
                                  Text(l10n.paywallPaymentUnavailable),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (e?.allowed == true) ...[
                          SizedBox(height: spacing.md),
                          SurfaceCard(
                            accentEdge: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.planDetailsIncludedTitle,
                                  style: theme.textTheme.titleMedium,
                                ),
                                SizedBox(height: spacing.sm),
                                Row(
                                  children: [
                                    Icon(Icons.check_circle,
                                        color: colors.success, size: 22),
                                    SizedBox(width: spacing.sm),
                                    Text(
                                      l10n.planDetailsFullAccess,
                                      style: theme.textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (e?.claimedVoucherDurationMonths != null ||
                            e?.discountVoucherDurationMonths != null) ...[
                          SizedBox(height: spacing.md),
                          SurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.membershipVouchers,
                                    style: theme.textTheme.titleMedium),
                                SizedBox(height: spacing.xs),
                                Text(
                                  e?.claimedVoucherType == 'discount' ||
                                          e?.discountVoucherDurationMonths !=
                                              null
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
                        ],
                        SizedBox(height: spacing.md),
                        SurfaceCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: colors.info,
                                size: 26,
                              ),
                              SizedBox(width: spacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.planDetailsNeedAnotherVoucher,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (availableVoucherLabel != null) ...[
                                      SizedBox(height: spacing.xxs),
                                      Text(
                                        availableVoucherLabel,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                key: const ValueKey<String>(
                                  'plan-claim-available-voucher',
                                ),
                                onPressed: _loading || _claimingVoucher
                                    ? null
                                    : availableVoucherDuration != null
                                        ? _claimAvailableVoucher
                                        : () => context.push(Routes.paywall),
                                child: _claimingVoucher
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colors.accent,
                                        ),
                                      )
                                    : Text(l10n.planDetailsClaimVoucher),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.icon,
  });

  final IconData? icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            color: AppColors.of(context).accent,
            size: 22,
          ),
          SizedBox(width: AppSpacing.of(context).sm),
        ],
        Expanded(child: Text(label, style: style)),
        SizedBox(width: AppSpacing.of(context).sm),
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
