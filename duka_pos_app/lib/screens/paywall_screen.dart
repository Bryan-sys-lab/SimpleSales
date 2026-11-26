import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_keys.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../routing/app_stage_controller.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../ui/components/membership_style.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    this.subscriptionRequired = false,
  });

  final bool subscriptionRequired;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final TextEditingController _voucher = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  SubscriptionEntitlement? _entitlement;
  SubscriptionPaymentQuote? _payment;
  bool _loading = true;
  bool _paymentBusy = false;
  bool _checkingPayment = false;
  bool _paymentFailed = false;
  String? _paymentStatus;
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
      final result = await BackendService.fetchSubscriptionEntitlement();
      if (!mounted) return;
      setState(() {
        _entitlement = result;
        _loading = false;
      });
    } catch (error, stack) {
      debugPrint('Could not load subscription entitlement: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).settingsSubscriptionUnavailable;
      });
    }
  }

  Future<void> _refreshEntitlement() => _load();

  Future<void> _unlockAndReturn() async {
    await context.read<AppStageController>().refreshSubscription();
    if (!mounted) return;
    context.go(Routes.dashboard);
  }

  Future<SubscriptionEntitlement> _reloadVoucherTerms(
      SubscriptionEntitlement claimed) async {
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
      debugPrint('Could not refresh subscription checkout after voucher claim: '
          '$error\n$stack');
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).settingsSubscriptionUnavailable;
        });
      }
      return claimed;
    }
  }

  Future<void> _completeSuccessfulPayment() async {
    try {
      await context.read<AppStageController>().refreshSubscription();
      if (!mounted) return;
      context.go(Routes.dashboard);
    } catch (error, stack) {
      debugPrint(
          'Payment succeeded but entitlement refresh failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _paymentBusy = false;
        _checkingPayment = false;
        _paymentStatus = AppLocalizations.of(context).paywallPaymentReceived;
        _error = AppLocalizations.of(context).settingsSubscriptionUnavailable;
      });
    }
  }

  Future<void> _redeem() async {
    if (_voucher.text.trim().isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await BackendService.redeemVoucher(_voucher.text);
      if (!mounted) return;
      if (result?.claimedVoucherType == 'discount') {
        final updated = await _reloadVoucherTerms(result!);
        if (!mounted) return;
        setState(() {
          _entitlement = updated;
          _loading = false;
          _voucher.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).paywallDiscountVoucherClaimed(
            updated.claimedVoucherDiscountPercent ?? updated.discountPercent,
            updated.claimedVoucherDurationMonths ??
                updated.discountVoucherDurationMonths ??
                1,
          )),
        ));
      } else if (result?.allowed == true) {
        await _unlockAndReturn();
      } else {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context).paywallVoucherRedemptionFailed;
        });
      }
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (error.response?.data is Map
                ? error.response!.data['error'] as String?
                : null) ??
            AppLocalizations.of(context).paywallVoucherRedemptionFailed;
      });
    } catch (error, stack) {
      debugPrint('Could not redeem subscription voucher: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).paywallVoucherRedemptionFailed;
      });
    }
  }

  Future<void> _claimAvailableVoucher() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await BackendService.claimAvailableVoucher();
      if (!mounted) return;
      if (result?.claimedVoucherType == 'discount') {
        final updated = await _reloadVoucherTerms(result!);
        if (!mounted) return;
        setState(() {
          _entitlement = updated;
          _loading = false;
        });
        final duration = updated.claimedVoucherDurationMonths ??
            updated.discountVoucherDurationMonths ??
            1;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).paywallDiscountVoucherClaimed(
            updated.claimedVoucherDiscountPercent ?? updated.discountPercent,
            duration,
          )),
        ));
        if (result.allowed) {
          await context.read<AppStageController>().refreshSubscription();
        }
      } else if (result?.allowed == true) {
        await _unlockAndReturn();
      } else {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context).paywallVoucherClaimFailed;
        });
      }
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (error.response?.data is Map
                ? error.response!.data['error'] as String?
                : null) ??
            AppLocalizations.of(context).paywallVoucherClaimFailed;
      });
    } catch (error, stack) {
      debugPrint('Could not claim issued subscription voucher: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).paywallVoucherClaimFailed;
      });
    }
  }

  Future<void> _startPayment() async {
    final l10n = AppLocalizations.of(context);
    final phone = _phone.text.trim();
    if (!RegExp(r'^\+?\d{9,15}$').hasMatch(phone)) {
      setState(() => _error = l10n.paywallPaymentPhoneInvalid);
      return;
    }
    setState(() {
      _paymentBusy = true;
      _error = null;
      _paymentStatus = null;
      _payment = null;
      _paymentFailed = false;
    });
    try {
      final payment =
          await BackendService.startSubscriptionPayment(phoneNumber: phone);
      if (!mounted) return;
      if (payment.status.toUpperCase() == 'SUCCESS') {
        setState(() {
          _payment = payment;
          _paymentBusy = false;
        });
        await _completeSuccessfulPayment();
        return;
      }
      setState(() {
        _payment = payment;
        _paymentFailed = payment.status.toUpperCase() == 'FAILED';
        _paymentStatus = _paymentFailed
            ? l10n.paywallPaymentFailed
            : l10n.paywallPaymentPending;
        _paymentBusy = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _paymentBusy = false;
        _error = error.response?.statusCode == 503
            ? l10n.paywallPaymentUnavailable
            : (error.response?.data is Map
                    ? error.response!.data['error'] as String?
                    : null) ??
                l10n.paywallPaymentFailed;
      });
    } catch (error, stack) {
      debugPrint('Could not start subscription payment: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _paymentBusy = false;
        _error = l10n.paywallPaymentFailed;
      });
    }
  }

  Future<void> _checkPaymentStatus() async {
    final payment = _payment;
    if (payment == null || _checkingPayment) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _checkingPayment = true;
      _error = null;
    });
    try {
      final status =
          (await BackendService.subscriptionPaymentStatus(payment.reference))
              .toUpperCase();
      if (!mounted) return;
      if (status == 'SUCCESS') {
        await _completeSuccessfulPayment();
        return;
      }
      setState(() {
        _checkingPayment = false;
        _paymentFailed = status == 'FAILED';
        _paymentStatus = status == 'FAILED'
            ? l10n.paywallPaymentFailed
            : l10n.paywallPaymentPending;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingPayment = false;
        _error = (error.response?.data is Map
                ? error.response!.data['error'] as String?
                : null) ??
            l10n.paywallPaymentFailed;
      });
    } catch (error, stack) {
      debugPrint('Could not check subscription payment: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _checkingPayment = false;
        _error = l10n.paywallPaymentFailed;
      });
    }
  }

  String _paymentPeriodLabel(AppLocalizations l10n, int months) {
    if (months == 0) return l10n.planDetailsNoPeriodEnd;
    return switch (months) {
      1 => l10n.billingIntervalMonthly,
      3 => l10n.billingIntervalQuarterly,
      6 => l10n.billingIntervalSemiannual,
      12 => l10n.billingIntervalAnnual,
      _ => l10n.paywallPaymentDuration(months),
    };
  }

  Widget _buildPricingCard(AppLocalizations l10n, ThemeData theme) {
    final entitlement = _entitlement;
    final priceMinor = entitlement?.priceMinor;
    final checkout = entitlement?.checkout;
    final acceptedAgreement = checkout?.agreementId != null;
    final bool configured = priceMinor != null && priceMinor > 0;
    final String price = acceptedAgreement
        ? _formatPrice(entitlement!, checkout!.amountMinor)
        : checkout != null
            ? _formatPrice(entitlement!, checkout.baseAmountMinor)
            : configured
                ? _formatPrice(entitlement!, priceMinor)
                : l10n.settingsSubscriptionNotConfigured;
    final period = checkout == null
        ? entitlement == null
            ? l10n.settingsSubscriptionUnavailable
            : l10n.billingIntervalLabel(entitlement.billingInterval)
        : _paymentPeriodLabel(l10n, checkout.durationMonths);

    final colors = AppColors.of(context);
    return MembershipCard(
      key: const ValueKey<String>('subscription-price-period'),
      highlighted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  acceptedAgreement
                      ? l10n.paywallAgreedPrice
                      : l10n.paywallAdminPriceTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(price, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            entitlement == null
                ? period
                : l10n.planDetailsBillingPeriod(period),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (checkout != null) ...[
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    l10n.paywallAmountDue,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  _formatPrice(entitlement!, checkout.amountMinor),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.planDetailsBillingPeriod(
                  _paymentPeriodLabel(l10n, checkout.durationMonths)),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (entitlement != null && entitlement.discountPercent > 0) ...[
            const SizedBox(height: 12),
            Text(
              l10n.paywallDiscountVoucherHelp,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (entitlement?.discountVoucherDurationMonths != null &&
              checkout != null &&
              entitlement!.discountVoucherDurationMonths !=
                  checkout.durationMonths) ...[
            const SizedBox(height: 8),
            Text(
              l10n.paywallVoucherPeriodMismatch(
                  entitlement.discountVoucherDurationMonths!),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBrandHero(AppLocalizations l10n, ThemeData theme) {
    final colors = AppColors.of(context);
    final heading = l10n.paywallAccessTitle;
    final brandIndex = heading.indexOf('SimpleSales');
    final headingSpans = brandIndex < 0
        ? <InlineSpan>[TextSpan(text: heading)]
        : <InlineSpan>[
            TextSpan(text: heading.substring(0, brandIndex)),
            TextSpan(
              text: 'SimpleSales',
              style: TextStyle(color: colors.accent),
            ),
            TextSpan(
                text: heading.substring(brandIndex + 'SimpleSales'.length)),
          ];
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.accent, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.26),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Image.asset(
              'assets/branding/simple_sales_s_mark.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'simple'),
              TextSpan(
                text: 'Sales',
                style: TextStyle(color: colors.accent),
              ),
            ],
          ),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        Text.rich(
          TextSpan(children: headingSpans),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.paywallAccessMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPlanLink(AppLocalizations l10n, ThemeData theme) {
    final colors = AppColors.of(context);
    final shapes = AppShapes.of(context);
    return MembershipCard(
      highlighted: true,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: shapes.cardRadius,
          onTap: () => context.push(Routes.planDetails),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  color: colors.accent,
                  size: 30,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.paywallViewPlan,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.accent, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCard(
    AppLocalizations l10n,
    ThemeData theme, {
    required bool isOwner,
  }) {
    final entitlement = _entitlement;
    final method = _payment?.paymentMethod ?? entitlement?.paymentMethod;
    final checkout = entitlement?.checkout;
    final payment = _payment;
    final colors = AppColors.of(context);
    return MembershipCard(
      key: const ValueKey<String>('subscription-payment'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.paywallPaymentMethodTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (method == null) ...[
            Text(l10n.paywallPaymentUnavailable,
                style: theme.textTheme.bodyMedium),
          ] else ...[
            Text(
              method.method == 'mpesa_stk'
                  ? l10n.paywallPaymentMethodMpesa
                  : method.method,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(l10n.paywallPaymentDestinationTitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceMuted,
                )),
            Text(
              switch (method.channelType) {
                'till' => l10n.paywallPaymentTillDestination(method.shortCode),
                'paybill' =>
                  l10n.paywallPaymentPaybillDestination(method.shortCode),
                'bank' => l10n.paywallPaymentBankDestination(
                    method.shortCode,
                    method.accountNumber ?? '',
                  ),
                _ => method.shortCode,
              },
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (isOwner && checkout == null) ...[
            const SizedBox(height: 8),
            Text(l10n.settingsSubscriptionNotConfigured,
                style: theme.textTheme.bodyMedium),
          ],
          if (isOwner &&
              checkout != null &&
              method != null &&
              (payment == null || _paymentFailed)) ...[
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey<String>('subscription-payment-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.paywallPaymentPhone,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('subscription-payment-start'),
              onPressed: _loading || _paymentBusy ? null : _startPayment,
              icon: const Icon(Icons.payment_rounded),
              label: Text(_paymentBusy
                  ? l10n.paywallCheckingPayment
                  : l10n.paywallPayMpesa),
            ),
          ],
          if (payment != null) ...[
            const Divider(height: 24),
            Text(
              l10n.paywallPaymentPrompt(
                entitlement?.currency ?? 'KES',
                (payment.amountMinor / 100).toStringAsFixed(2),
                payment.durationMonths,
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.paywallPaymentReference(payment.reference),
                style: theme.textTheme.bodySmall),
            if (_paymentStatus != null) ...[
              const SizedBox(height: 8),
              Text(_paymentStatus!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey<String>('subscription-payment-check'),
              onPressed: _checkingPayment ? null : _checkPaymentStatus,
              child: Text(_checkingPayment
                  ? l10n.paywallCheckingPayment
                  : l10n.paywallCheckPaymentStatus),
            ),
          ],
        ],
      ),
    );
  }

  String _formatPrice(SubscriptionEntitlement entitlement, int priceMinor) =>
      '${entitlement.currency} ${(priceMinor / 100).toStringAsFixed(2)}';

  Widget _buildAvailableVoucher(AppLocalizations l10n, ThemeData theme) {
    final entitlement = _entitlement;
    final duration = entitlement?.availableVoucherDurationMonths;
    if (duration == null) return const SizedBox.shrink();
    final String title = entitlement?.availableVoucherType == 'discount'
        ? l10n.paywallAvailableDiscountVoucher(
            entitlement?.availableVoucherDiscountPercent ?? 0,
            duration,
          )
        : l10n.paywallVoucherReady(duration);

    return MembershipCard(
      highlighted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _loading ? null : _claimAvailableVoucher,
            icon: const Icon(Icons.bolt_rounded),
            label: Text(l10n.paywallClaimVoucher),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimedVoucher(AppLocalizations l10n, ThemeData theme) {
    final entitlement = _entitlement;
    final duration = entitlement?.claimedVoucherDurationMonths ??
        entitlement?.discountVoucherDurationMonths;
    if (duration == null) return const SizedBox.shrink();
    final text = entitlement?.claimedVoucherType == 'discount' ||
            entitlement?.discountVoucherDurationMonths != null
        ? l10n.paywallDiscountVoucherClaimed(
            entitlement?.claimedVoucherDiscountPercent ??
                entitlement?.discountPercent ??
                0,
            duration,
          )
        : l10n.paywallVoucherReady(duration);
    return MembershipCard(
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _buildVoucherEntry(AppLocalizations l10n, ThemeData theme) {
    final colors = AppColors.of(context);
    final shapes = AppShapes.of(context);
    final voucherField = TextField(
      key: const ValueKey<String>('membership-voucher-code'),
      controller: _voucher,
      textCapitalization: TextCapitalization.characters,
      autofillHints: const [AutofillHints.oneTimeCode],
      decoration: InputDecoration(
        labelText: l10n.paywallVoucherPlaceholder,
        hintText: l10n.paywallVoucherPlaceholder,
        border: OutlineInputBorder(borderRadius: shapes.controlRadius),
      ),
    );
    final applyButton = FilledButton(
      onPressed: _loading ? null : _redeem,
      style: FilledButton.styleFrom(
        backgroundColor: colors.warning,
        foregroundColor: Theme.of(context).brightness == Brightness.dark
            ? colors.onAccent
            : colors.onPrimaryButton,
        shape: RoundedRectangleBorder(borderRadius: shapes.controlRadius),
      ),
      child: Text(l10n.paywallApplyVoucher),
    );

    return MembershipCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.confirmation_number_outlined, color: colors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.paywallEnterVoucherTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.paywallVoucherManualHelp,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    voucherField,
                    const SizedBox(height: 8),
                    applyButton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: voucherField),
                  const SizedBox(width: 8),
                  applyButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrDivider(AppLocalizations l10n, ThemeData theme) => Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(l10n.paywallOr, style: theme.textTheme.bodyMedium),
          ),
          const Expanded(child: Divider()),
        ],
      );

  @override
  void dispose() {
    _voucher.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isOwner = context.watch<AppState>().isOwnerSession;

    return PopScope<Object?>(
      canPop: !widget.subscriptionRequired,
      child: Scaffold(
        body: MembershipBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Row(
                    children: [
                      if (widget.subscriptionRequired)
                        const SizedBox(width: 48)
                      else
                        IconButton(
                          tooltip: l10n.planDetailsTitle,
                          onPressed: () {
                            Navigator.of(context).maybePop();
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                      const Spacer(),
                      IconButton(
                        tooltip: l10n.paywallCheckVoucher,
                        onPressed: _loading ? null : _refreshEntitlement,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: ListView(
                    key: const ValueKey<String>('membership-vouchers'),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      _buildBrandHero(l10n, theme),
                      const SizedBox(height: 24),
                      _buildPlanLink(l10n, theme),
                      const SizedBox(height: 12),
                      _buildPricingCard(l10n, theme),
                      const SizedBox(height: 12),
                      _buildPaymentCard(l10n, theme, isOwner: isOwner),
                      const SizedBox(height: 12),
                      if (_error != null) ...[
                        MembershipCard(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: AppColors.of(context).danger,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildVoucherEntry(l10n, theme),
                      if (_entitlement?.availableVoucherDurationMonths !=
                          null) ...[
                        const SizedBox(height: 16),
                        _buildOrDivider(l10n, theme),
                        const SizedBox(height: 16),
                        _buildAvailableVoucher(l10n, theme),
                      ],
                      _buildClaimedVoucher(l10n, theme),
                      if (widget.subscriptionRequired)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            l10n.paywallVoucherChooseText,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      if (_entitlement?.allowed == true) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _unlockAndReturn,
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(l10n.paywallContinue),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
