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
import '../theme/app_spacing.dart';
import '../ui/components/surface.dart';

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
    final hasClaimedDiscountVoucher =
        entitlement?.claimedVoucherType == 'discount' ||
            entitlement?.discountVoucherDurationMonths != null;
    final appliedDiscountPercent = checkout != null
        ? checkout.discountPercent
        : hasClaimedDiscountVoucher
            ? entitlement?.claimedVoucherDiscountPercent ??
                entitlement?.discountPercent ??
                0
            : 0;
    final appliedDiscountMinor = checkout?.discountAmountMinor ??
        (priceMinor == null
            ? null
            : (priceMinor * appliedDiscountPercent.clamp(0, 100) / 100)
                .round());
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

    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    return SurfaceCard(
      key: const ValueKey<String>('subscription-price-period'),
      accentEdge: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: colors.accent),
              SizedBox(width: spacing.xs),
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
          SizedBox(height: spacing.sm),
          Text(price, style: theme.textTheme.headlineSmall),
          SizedBox(height: spacing.xxs),
          Text(
            entitlement == null
                ? period
                : l10n.planDetailsBillingPeriod(period),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (checkout != null) ...[
            Divider(height: spacing.lg),
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
            SizedBox(height: spacing.xxs),
            Text(
              l10n.planDetailsBillingPeriod(
                  _paymentPeriodLabel(l10n, checkout.durationMonths)),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (appliedDiscountPercent > 0) ...[
            SizedBox(height: spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    l10n.paywallDiscount(appliedDiscountPercent),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Text(
                  appliedDiscountMinor == null
                      ? '-'
                      : _formatPrice(entitlement!, appliedDiscountMinor),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.success,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ],
          if (hasClaimedDiscountVoucher && appliedDiscountPercent == 0) ...[
            SizedBox(height: spacing.sm),
            Text(
              l10n.paywallDiscountVoucherHelp,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (entitlement?.discountVoucherDurationMonths != null &&
              checkout != null &&
              entitlement!.discountVoucherDurationMonths !=
                  checkout.durationMonths) ...[
            SizedBox(height: spacing.xs),
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
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
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
        SurfaceCard(
          accentEdge: true,
          padding: EdgeInsets.all(spacing.xs),
          child: ClipRRect(
            borderRadius: shapes.cardRadius,
            child: Image.asset(
              'assets/branding/simple_sales_s_mark.png',
              width: spacing.spacious,
              height: spacing.spacious,
              fit: BoxFit.cover,
            ),
          ),
        ),
        SizedBox(height: spacing.xs),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'simple'),
              TextSpan(
                text: 'Sales',
                style: TextStyle(color: colors.accent),
              ),
            ],
          ),
          style: theme.textTheme.titleLarge,
        ),
        SizedBox(height: spacing.lg),
        Text.rich(
          TextSpan(children: headingSpans),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall,
        ),
        SizedBox(height: spacing.sm),
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
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    return SurfaceCard(
      accentEdge: true,
      semanticLabel: l10n.paywallViewPlan,
      onTap: () => context.push(Routes.planDetails),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, color: colors.accent),
          SizedBox(width: spacing.md),
          Expanded(
            child: Text(
              l10n.paywallViewPlan,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ],
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
    final AppSpacing spacing = AppSpacing.of(context);
    return SurfaceCard(
      key: const ValueKey<String>('subscription-payment'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: colors.accent),
              SizedBox(width: spacing.xs),
              Expanded(
                child: Text(
                  l10n.paywallPaymentMethodTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
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
            SizedBox(height: spacing.xs),
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
            SizedBox(height: spacing.xs),
            Text(l10n.settingsSubscriptionNotConfigured,
                style: theme.textTheme.bodyMedium),
          ],
          if (isOwner &&
              checkout != null &&
              method != null &&
              (payment == null || _paymentFailed)) ...[
            SizedBox(height: spacing.md),
            TextField(
              key: const ValueKey<String>('subscription-payment-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.paywallPaymentPhone,
                border: const OutlineInputBorder(),
              ),
            ),
            SizedBox(height: spacing.sm),
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
            Divider(height: spacing.lg),
            Text(
              l10n.paywallPaymentPrompt(
                entitlement?.currency ?? 'KES',
                (payment.amountMinor / 100).toStringAsFixed(2),
                payment.durationMonths,
              ),
              style: theme.textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.xxs),
            Text(l10n.paywallPaymentReference(payment.reference),
                style: theme.textTheme.bodySmall),
            if (_paymentStatus != null) ...[
              SizedBox(height: spacing.xs),
              Text(_paymentStatus!, style: theme.textTheme.bodyMedium),
            ],
            SizedBox(height: spacing.xs),
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
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final entitlement = _entitlement;
    final duration = entitlement?.availableVoucherDurationMonths;
    if (duration == null) return const SizedBox.shrink();
    final String title = entitlement?.availableVoucherType == 'discount'
        ? l10n.paywallAvailableDiscountVoucher(
            entitlement?.availableVoucherDiscountPercent ?? 0,
            duration,
          )
        : l10n.paywallVoucherReady(duration);

    final claimButton = FilledButton(
      onPressed: _loading ? null : _claimAvailableVoucher,
      child: Text(
        l10n.planDetailsClaimVoucher,
      ),
    );

    return SurfaceCard(
      key: const ValueKey<String>('available-voucher-claim'),
      accentEdge: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleWidget = Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          );
          final icon = Icon(
            Icons.bolt_rounded,
            color: colors.success,
            size: 30,
          );
          if (constraints.maxWidth < 300) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    icon,
                    SizedBox(width: spacing.sm),
                    Expanded(child: titleWidget),
                  ],
                ),
                SizedBox(height: spacing.sm),
                SizedBox(width: double.infinity, child: claimButton),
              ],
            );
          }
          return Row(
            children: [
              icon,
              SizedBox(width: spacing.sm),
              Expanded(child: titleWidget),
              SizedBox(width: spacing.xs),
              claimButton,
            ],
          );
        },
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
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    return SurfaceCard(
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: colors.success),
          SizedBox(width: spacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _buildVoucherEntry(AppLocalizations l10n, ThemeData theme) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final voucherField = TextField(
      key: const ValueKey<String>('membership-voucher-code'),
      controller: _voucher,
      textCapitalization: TextCapitalization.characters,
      autofillHints: const [AutofillHints.oneTimeCode],
      decoration: InputDecoration(
        labelText: l10n.paywallVoucherPlaceholder,
        hintText: l10n.paywallVoucherPlaceholder,
      ),
    );
    final applyButton = FilledButton(
      onPressed: _loading ? null : _redeem,
      child: Text(l10n.paywallApplyVoucher),
    );

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.confirmation_number_outlined,
                color: colors.accent,
                size: 28,
              ),
              SizedBox(width: spacing.xs),
              Expanded(
                child: Text(
                  l10n.paywallEnterVoucherTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 320) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    voucherField,
                    SizedBox(height: spacing.xs),
                    applyButton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: voucherField),
                  SizedBox(width: spacing.xs),
                  applyButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrDivider(AppLocalizations l10n, ThemeData theme) {
    final AppSpacing spacing = AppSpacing.of(context);
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.sm),
          child: Text(l10n.paywallOr, style: theme.textTheme.bodyMedium),
        ),
        const Expanded(child: Divider()),
      ],
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
    final AppSpacing spacing = AppSpacing.of(context);

    return PopScope<Object?>(
      canPop: !widget.subscriptionRequired,
      child: Scaffold(
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
                        if (widget.subscriptionRequired)
                          SizedBox(
                            width: spacing.spacious - spacing.md,
                          )
                        else
                          IconButton(
                            tooltip: l10n.planDetailsTitle,
                            onPressed: () {
                              Navigator.of(context).maybePop();
                            },
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        const Spacer(),
                        IconButton(
                          tooltip: l10n.paywallCheckVoucher,
                          onPressed: _loading ? null : _refreshEntitlement,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const LinearProgressIndicator(),
                  Expanded(
                    child: ListView(
                      key: const ValueKey<String>('membership-vouchers'),
                      padding: EdgeInsets.fromLTRB(
                        spacing.mobilePageGutter,
                        spacing.sm,
                        spacing.mobilePageGutter,
                        spacing.xl,
                      ),
                      children: [
                        _buildBrandHero(l10n, theme),
                        SizedBox(height: spacing.lg),
                        _buildPlanLink(l10n, theme),
                        if (_entitlement?.availableVoucherDurationMonths !=
                            null) ...[
                          SizedBox(height: spacing.md),
                          _buildAvailableVoucher(l10n, theme),
                          SizedBox(height: spacing.md),
                          _buildOrDivider(l10n, theme),
                          SizedBox(height: spacing.md),
                        ] else
                          SizedBox(height: spacing.sm),
                        _buildVoucherEntry(l10n, theme),
                        SizedBox(height: spacing.sm),
                        _buildClaimedVoucher(l10n, theme),
                        if (_error != null) ...[
                          SizedBox(height: spacing.sm),
                          SurfaceCard(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: AppColors.of(context).danger,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: spacing.md),
                        _buildPricingCard(l10n, theme),
                        SizedBox(height: spacing.sm),
                        _buildPaymentCard(l10n, theme, isOwner: isOwner),
                        if (widget.subscriptionRequired)
                          Padding(
                            padding: EdgeInsets.only(top: spacing.md),
                            child: Text(
                              l10n.paywallVoucherChooseText,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        if (_entitlement?.allowed == true) ...[
                          SizedBox(height: spacing.md),
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
    );
  }
}
