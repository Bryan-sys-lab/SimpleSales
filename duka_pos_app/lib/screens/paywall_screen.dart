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

    return Card(
      key: const ValueKey<String>('subscription-price-period'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                acceptedAgreement
                    ? l10n.paywallAgreedPrice
                    : l10n.paywallAdminPriceTitle,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(price, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              entitlement == null
                  ? period
                  : l10n.planDetailsBillingPeriod(period),
              style: theme.textTheme.bodyMedium,
            ),
            if (checkout != null) ...[
              const Divider(height: 24),
              Text(l10n.paywallAmountDue, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                _formatPrice(entitlement!, checkout.amountMinor),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.planDetailsBillingPeriod(
                    _paymentPeriodLabel(l10n, checkout.durationMonths)),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (entitlement != null && entitlement.discountPercent > 0) ...[
              const Divider(height: 24),
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
    return Card(
      key: const ValueKey<String>('subscription-payment'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.paywallPaymentMethodTitle,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (method == null) ...[
              Text(l10n.paywallPaymentUnavailable,
                  style: theme.textTheme.bodyMedium),
            ] else ...[
              Text(
                method.method == 'mpesa_stk'
                    ? l10n.paywallPaymentMethodMpesa
                    : method.method,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(l10n.paywallPaymentDestinationTitle,
                  style: theme.textTheme.titleSmall),
              Text(
                switch (method.channelType) {
                  'till' =>
                    l10n.paywallPaymentTillDestination(method.shortCode),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _loading ? null : _claimAvailableVoucher,
              icon: const Icon(Icons.redeem_rounded),
              label: Text(l10n.paywallClaimVoucher),
            ),
          ],
        ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: theme.textTheme.bodyMedium),
      ),
    );
  }

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

    if (_loading && _entitlement == null) {
      return PopScope<Object?>(
        canPop: !widget.subscriptionRequired,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.membershipVouchers)),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return PopScope<Object?>(
      canPop: !widget.subscriptionRequired,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.membershipVouchers),
          actions: [
            IconButton(
              tooltip: l10n.paywallCheckVoucher,
              onPressed: _loading ? null : _refreshEntitlement,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    _error!,
                    style: TextStyle(color: AppColors.of(context).danger),
                  ),
                ),
              Expanded(
                child: ListView(
                  key: const ValueKey<String>('membership-vouchers'),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    _buildPricingCard(l10n, theme),
                    const SizedBox(height: 12),
                    _buildPaymentCard(l10n, theme, isOwner: isOwner),
                    const SizedBox(height: 12),
                    _buildAvailableVoucher(l10n, theme),
                    _buildClaimedVoucher(l10n, theme),
                    const SizedBox(height: 12),
                    Text(l10n.paywallVoucherSectionTitle,
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(l10n.paywallVoucherManualHelp,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey<String>('membership-voucher-code'),
                      controller: _voucher,
                      textCapitalization: TextCapitalization.characters,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      decoration: InputDecoration(
                        labelText: l10n.paywallVoucherPlaceholder,
                        hintText: l10n.paywallVoucherPlaceholder,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _redeem,
                      icon: const Icon(Icons.redeem_rounded),
                      label: Text(_loading
                          ? l10n.paywallCheckingVoucher
                          : l10n.paywallRedeemVoucher),
                    ),
                    if (widget.subscriptionRequired)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          l10n.paywallVoucherChooseText,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
