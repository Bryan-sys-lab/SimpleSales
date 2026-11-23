import 'dart:async';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/backend_service.dart';
import '../services/support_contact.dart';
import '../routing/app_stage_controller.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';

enum _MembershipSection { plans, quote, vouchers, help }

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _voucher = TextEditingController();
  final _phone = TextEditingController();
  final _receipt = TextEditingController();
  final _requirements = TextEditingController();
  final Set<String> _selectedFeatures = <String>{};
  SubscriptionEntitlement? _entitlement;
  _MembershipSection _section = _MembershipSection.plans;
  bool _loading = true;
  String? _error;
  String? _paymentReference;
  SubscriptionPaymentQuote? _paymentQuote;
  bool _quoteRequested = false;
  bool _buildingPlan = false;
  bool _refreshing = false;
  int _durationMonths = 1;
  Timer? _voucherRefreshTimer;

  Future<void> _unlockAndReturn() async {
    await context.read<AppStageController>().refreshSubscription();
    if (!mounted) return;
    context.go(Routes.dashboard);
  }

  Future<void> _openSupport(Uri uri) async {
    try {
      final bool opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) _showSupportError();
    } catch (error, stack) {
      debugPrint('Could not open subscription support contact: $error\n$stack');
      if (mounted) _showSupportError();
    }
  }

  void _showSupportError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).supportContactOpenFailed),
      ),
    );
  }

  List<(String, String)> _coreFeatures(AppLocalizations l10n) =>
      <(String, String)>[
        ('sales_checkout', l10n.membershipFeatureSales),
        ('inventory', l10n.membershipFeatureInventory),
        ('reports', l10n.membershipFeatureReports),
      ];

  List<(String, String)> _additionalFeatures(AppLocalizations l10n) =>
      <(String, String)>[
        ('staff_accounts', l10n.membershipFeatureStaff),
        ('product_tools', l10n.membershipFeatureProductTools),
        ('customer_records', l10n.membershipFeatureCustomers),
      ];

  List<(String, String)> _supportFeatures(AppLocalizations l10n) =>
      <(String, String)>[
        ('setup_help', l10n.membershipFeatureSetupHelp),
        ('team_training', l10n.membershipFeatureTraining),
        ('priority_support', l10n.membershipFeaturePrioritySupport),
      ];

  Future<void> _requestQuote() async {
    final l10n = AppLocalizations.of(context);
    final features = <(String, String)>[
      ..._coreFeatures(l10n),
      ..._additionalFeatures(l10n),
      ..._supportFeatures(l10n),
    ];
    final selectedFeatures = features
        .where((feature) => _selectedFeatures.contains(feature.$1))
        .map((feature) => feature.$2)
        .toList();
    final requirements = _requirements.text.trim();
    if (selectedFeatures.isEmpty && requirements.isEmpty) {
      setState(() => _error = l10n.membershipChooseSomething);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await BackendService.requestSubscriptionQuote(
        features: selectedFeatures,
        requirements: requirements,
      );
      if (!mounted) return;
      setState(() {
        _quoteRequested = true;
        _buildingPlan = false;
        _section = _MembershipSection.quote;
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (error.response?.data is Map
                ? error.response!.data['error'] as String?
                : null) ??
            l10n.membershipRequestFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = l10n.membershipRequestFailed;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _voucherRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshEntitlement(),
    );
  }

  Future<void> _load() async {
    try {
      final result = await BackendService.fetchSubscriptionEntitlement();
      if (mounted) {
        setState(() {
          _entitlement = result;
          _durationMonths =
              result?.discountVoucherDurationMonths ?? _durationMonths;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connect to the internet to check this shop subscription.';
        });
      }
    }
  }

  Future<void> _refreshEntitlement() async {
    if (_loading || _refreshing) return;
    _refreshing = true;
    try {
      final result = await BackendService.fetchSubscriptionEntitlement();
      if (mounted) {
        setState(() {
          _entitlement = result;
          _durationMonths =
              result?.discountVoucherDurationMonths ?? _durationMonths;
          _error = null;
        });
      }
    } catch (error, stack) {
      debugPrint(
          'Could not refresh subscription voucher status: $error\n$stack');
      if (mounted) {
        setState(() {
          _error =
              'Could not refresh your voucher status. Check your connection.';
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _redeem() async {
    if (_voucher.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await BackendService.redeemVoucher(_voucher.text);
      if (!mounted) return;
      if (result?.claimedVoucherType == 'discount') {
        setState(() {
          _entitlement = result;
          _durationMonths = result?.discountVoucherDurationMonths ??
              result?.claimedVoucherDurationMonths ??
              _durationMonths;
          _loading = false;
          _voucher.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).paywallDiscountVoucherClaimed(
            result?.claimedVoucherDiscountPercent ?? result!.discountPercent,
            _durationMonths,
          )),
        ));
      } else if (result?.allowed == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Voucher accepted. This shop is ready to use.')));
        await _unlockAndReturn();
      } else {
        setState(() {
          _loading = false;
          _error = 'This voucher could not unlock the shop.';
        });
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = (error.response?.data is Map
                  ? (error.response!.data['error'] as String?)
                  : null) ??
              'Voucher could not be redeemed.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Voucher could not be redeemed.';
        });
      }
    }
  }

  Future<void> _claimAvailableVoucher() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await BackendService.claimAvailableVoucher();
      if (!mounted) return;
      if (result?.claimedVoucherType == 'discount') {
        setState(() {
          _entitlement = result;
          _durationMonths = result?.discountVoucherDurationMonths ??
              result?.claimedVoucherDurationMonths ??
              _durationMonths;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).paywallDiscountVoucherClaimed(
            result?.claimedVoucherDiscountPercent ?? result!.discountPercent,
            _durationMonths,
          )),
        ));
        if (result?.allowed == true) {
          await context.read<AppStageController>().refreshSubscription();
        }
      } else if (result?.allowed == true) {
        await _unlockAndReturn();
      } else {
        setState(() {
          _loading = false;
          _error =
              'The issued voucher could not be claimed. Refresh and try again.';
        });
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = (error.response?.data is Map
                  ? error.response!.data['error'] as String?
                  : null) ??
              'The issued voucher could not be claimed.';
        });
      }
    } catch (error, stack) {
      debugPrint('Could not claim issued subscription voucher: $error\n$stack');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'The issued voucher could not be claimed.';
        });
      }
    }
  }

  Future<void> _startPayment() async {
    if (_phone.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quote = await BackendService.startSubscriptionPayment(
        phoneNumber: _phone.text.trim(),
        durationMonths: _durationMonths,
      );
      if (mounted) {
        setState(() {
          _paymentQuote = quote;
          _paymentReference = quote.reference;
          _loading = false;
        });
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = (error.response?.data is Map
                  ? (error.response!.data['error'] as String?)
                  : null) ??
              'Payment could not be started.';
        });
      }
    }
  }

  Future<void> _checkPayment() async {
    final reference = _paymentReference;
    if (reference == null) return;
    setState(() => _loading = true);
    try {
      final status = await BackendService.subscriptionPaymentStatus(reference);
      if (!mounted) return;
      if (status == 'SUCCESS') {
        await _unlockAndReturn();
      } else {
        setState(() {
          _loading = false;
          _error = status == 'FAILED'
              ? 'Payment failed. You can try again.'
              : 'Payment is still pending. Confirm the M-Pesa prompt, then check again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not verify payment yet.';
        });
      }
    }
  }

  Future<void> _confirmReceipt() async {
    final reference = _paymentReference;
    if (reference == null || _receipt.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await BackendService.confirmSubscriptionPaymentCode(
          reference: reference, mpesaCode: _receipt.text);
      await _unlockAndReturn();
    } on DioException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = (error.response?.data is Map
                  ? (error.response!.data['error'] as String?)
                  : null) ??
              'That receipt could not be verified yet.';
        });
      }
    }
  }

  @override
  void dispose() {
    _voucherRefreshTimer?.cancel();
    _voucher.dispose();
    _phone.dispose();
    _receipt.dispose();
    _requirements.dispose();
    super.dispose();
  }

  Widget _featureGroup(
    AppLocalizations l10n,
    ThemeData theme, {
    required String title,
    required String description,
    required List<(String, String)> features,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            ...features.map((feature) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(feature.$2),
                  value: _selectedFeatures.contains(feature.$1),
                  onChanged: _loading
                      ? null
                      : (selected) => setState(() {
                            if (selected == true) {
                              _selectedFeatures.add(feature.$1);
                            } else {
                              _selectedFeatures.remove(feature.$1);
                            }
                          }),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanBuilder(AppLocalizations l10n, ThemeData theme) {
    return ListView(
      key: const ValueKey<String>('membership-plan-builder'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _buildingPlan = false),
            icon: const Icon(Icons.arrow_back),
            label: Text(l10n.membershipBackToExplore),
          ),
        ),
        Text(
          l10n.membershipStepLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.membershipWhatDoYouNeed,
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(l10n.membershipChooseFeatures, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 18),
        _featureGroup(
          l10n,
          theme,
          title: l10n.membershipCoreFeatures,
          description: l10n.membershipCoreDescription,
          features: _coreFeatures(l10n),
        ),
        const SizedBox(height: 8),
        _featureGroup(
          l10n,
          theme,
          title: l10n.membershipAdditionalFeatures,
          description: l10n.membershipAdditionalDescription,
          features: _additionalFeatures(l10n),
        ),
        const SizedBox(height: 8),
        _featureGroup(
          l10n,
          theme,
          title: l10n.membershipExtraSupport,
          description: l10n.membershipSupportDescription,
          features: _supportFeatures(l10n),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.membershipCustomRequirements,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey<String>('membership-custom-requirements'),
                  controller: _requirements,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: l10n.membershipCustomRequirementsHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _requestQuote,
          icon: const Icon(Icons.arrow_forward),
          label: Text(l10n.membershipRequestOffer),
        ),
      ],
    );
  }

  Widget _buildPlansContent(
    AppLocalizations l10n,
    ThemeData theme, {
    required int? price,
    required List<(int, String)> availableDurations,
    required int baseAmountMinor,
    required int discountedAmountMinor,
    required int discountPercent,
  }) {
    if (_buildingPlan) return _buildPlanBuilder(l10n, theme);
    final colors = theme.colorScheme;
    return ListView(
      key: const ValueKey<String>('membership-explore'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Card(
          color: colors.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.storefront_outlined,
                    color: colors.onPrimaryContainer, size: 30),
                const SizedBox(height: 14),
                Text(
                  l10n.membershipHeroTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.membershipHeroDescription,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => _buildingPlan = true),
                  child: Text(l10n.membershipGetStarted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: Text(l10n.membershipAvailableFeatures),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l10n.membershipAvailableFeaturesDescription),
            ),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => setState(() => _buildingPlan = true),
          ),
        ),
        Card(
          child: ListTile(
            title: Text(l10n.membershipMemberRewards),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l10n.membershipMemberRewardsDescription),
            ),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => setState(() => _section = _MembershipSection.vouchers),
          ),
        ),
        if (_entitlement?.allowed == true) ...[
          const SizedBox(height: 12),
          _buildSubscriptionSummary(l10n, theme),
        ],
        if (price != null && _entitlement?.allowed != true) ...[
          const SizedBox(height: 12),
          _buildExistingOffer(
            l10n,
            theme,
            price: price,
            availableDurations: availableDurations,
            baseAmountMinor: baseAmountMinor,
            discountedAmountMinor: discountedAmountMinor,
            discountPercent: discountPercent,
          ),
        ],
      ],
    );
  }

  Widget _buildSubscriptionSummary(AppLocalizations l10n, ThemeData theme) {
    final periodEnd = _entitlement?.currentPeriodEnd;
    final parsedPeriodEnd =
        periodEnd == null ? null : DateTime.tryParse(periodEnd);
    final subtitle = parsedPeriodEnd == null
        ? l10n.membershipActiveDescription
        : l10n.membershipRenewalDate(
            MaterialLocalizations.of(context)
                .formatMediumDate(parsedPeriodEnd.toLocal()),
          );
    return Card(
      child: ListTile(
        leading:
            Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
        title: Text(l10n.membershipMySubscription),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _buildExistingOffer(
    AppLocalizations l10n,
    ThemeData theme, {
    required int price,
    required List<(int, String)> availableDurations,
    required int baseAmountMinor,
    required int discountedAmountMinor,
    required int discountPercent,
  }) {
    final currency = _entitlement?.currency ?? 'KES';
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(l10n.membershipExistingOffer),
        subtitle: Text(l10n.membershipExistingOfferDescription),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.membershipConfiguredPrice),
            subtitle: Text(
              '$currency ${(price / 100).toStringAsFixed(2)} / '
              '${_entitlement?.billingInterval ?? 'month'}',
            ),
          ),
          DropdownButtonFormField<int>(
            initialValue: _durationMonths,
            decoration: InputDecoration(
              labelText: l10n.paywallDuration,
              border: const OutlineInputBorder(),
            ),
            items: availableDurations
                .map((duration) => DropdownMenuItem<int>(
                      value: duration.$1,
                      child: Text(duration.$2),
                    ))
                .toList(),
            onChanged: _loading
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _durationMonths = value;
                        _paymentQuote = null;
                        _paymentReference = null;
                      });
                    }
                  },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${l10n.paywallQuoteBase}: $currency '
              '${(baseAmountMinor / 100).toStringAsFixed(2)}',
            ),
          ),
          if (discountPercent > 0) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${l10n.paywallDiscount(discountPercent)}: -$currency '
                '${((baseAmountMinor - discountedAmountMinor) / 100).toStringAsFixed(2)}',
              ),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${l10n.paywallAmountDue}: $currency '
              '${(discountedAmountMinor / 100).toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(
              labelText: l10n.membershipMpesaPhone,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _loading ? null : _startPayment,
            icon: const Icon(Icons.phone_android_rounded),
            label: Text(l10n.paywallPayMpesa),
          ),
          if (_paymentQuote != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.paywallPaymentPrompt(
                currency,
                (_paymentQuote!.amountMinor / 100).toStringAsFixed(2),
                _paymentQuote!.durationMonths,
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (_paymentReference != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _loading ? null : _checkPayment,
              child: Text(l10n.membershipCheckPayment),
            ),
            TextField(
              controller: _receipt,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.membershipMpesaReceipt,
                border: const OutlineInputBorder(),
              ),
            ),
            TextButton(
              onPressed: _loading ? null : _confirmReceipt,
              child: Text(l10n.membershipVerifyReceipt),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoucherContent(AppLocalizations l10n, ThemeData theme) {
    final int? duration = _entitlement?.availableVoucherDurationMonths;
    final String? voucherType = _entitlement?.availableVoucherType;
    final availableTitle = duration == null
        ? null
        : voucherType == 'discount'
            ? l10n.paywallAvailableDiscountVoucher(
                _entitlement?.availableVoucherDiscountPercent ?? 0,
                duration,
              )
            : l10n.paywallVoucherReady(duration);
    final claimedDuration = _entitlement?.discountVoucherDurationMonths;
    return ListView(
      key: const ValueKey<String>('membership-vouchers'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(l10n.membershipVouchers, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(l10n.membershipVoucherDescription,
            style: theme.textTheme.bodyLarge),
        if (duration != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(availableTitle!, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _loading ? null : _claimAvailableVoucher,
                    icon: const Icon(Icons.redeem_rounded),
                    label: Text(l10n.paywallClaimVoucher),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (claimedDuration != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.paywallDiscountVoucherClaimed(
                  _entitlement?.discountPercent ?? 0,
                  claimedDuration,
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(l10n.paywallVoucherSectionTitle,
            style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(l10n.paywallVoucherManualHelp, style: theme.textTheme.bodyMedium),
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
        TextButton.icon(
          onPressed: _loading ? null : _refreshEntitlement,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.paywallCheckVoucher),
        ),
      ],
    );
  }

  Uri? _salesWhatsappUri(AppLocalizations l10n) => SupportContact.whatsappUri(
        message: l10n.paywallSalesMessage,
        phoneNumber: SupportContact.secondaryNumber,
      );

  Uri? _supportWhatsappUri(AppLocalizations l10n) => SupportContact.whatsappUri(
        message: l10n.paywallWhatsAppMessage,
        fallbackUrl: _entitlement?.whatsappUrl,
      );

  Widget _contactCard({
    required String title,
    required String description,
    required String actionLabel,
    required IconData icon,
    required Uri? uri,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(title),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(description),
              ),
            ),
            if (uri == null)
              Text(AppLocalizations.of(context).membershipContactUnavailable)
            else
              OutlinedButton.icon(
                onPressed: () => _openSupport(uri),
                icon: const Icon(Icons.open_in_new),
                label: Text(actionLabel),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpContent(AppLocalizations l10n, ThemeData theme) {
    return ListView(
      key: const ValueKey<String>('membership-help'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(l10n.membershipHelp, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(l10n.membershipHelpDescription, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        _contactCard(
          title: l10n.membershipSales,
          description: l10n.membershipSalesDescription,
          actionLabel: l10n.membershipContactSales,
          icon: Icons.forum_outlined,
          uri: _salesWhatsappUri(l10n),
        ),
        _contactCard(
          title: l10n.membershipSupport,
          description: l10n.membershipSupportContactDescription,
          actionLabel: l10n.membershipContactSupport,
          icon: Icons.support_agent_outlined,
          uri: _supportWhatsappUri(l10n),
        ),
      ],
    );
  }

  Widget _buildQuoteContent(AppLocalizations l10n, ThemeData theme) {
    return ListView(
      key: const ValueKey<String>('membership-quote'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(l10n.membershipQuote, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(l10n.membershipQuoteDescription, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _quoteRequested
                      ? Icons.mark_email_read_outlined
                      : Icons.request_quote_outlined,
                  color: theme.colorScheme.primary,
                  size: 30,
                ),
                const SizedBox(height: 12),
                Text(
                  _quoteRequested
                      ? l10n.membershipRequestSentTitle
                      : l10n.membershipQuoteEmptyTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _quoteRequested
                      ? l10n.membershipRequestSentDescription
                      : l10n.membershipQuoteEmptyDescription,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_quoteRequested)
          OutlinedButton.icon(
            onPressed: _salesWhatsappUri(l10n) == null
                ? null
                : () => _openSupport(_salesWhatsappUri(l10n)!),
            icon: const Icon(Icons.chat_outlined),
            label: Text(l10n.membershipDiscussOnWhatsApp),
          )
        else
          FilledButton.icon(
            onPressed: () => setState(() {
              _section = _MembershipSection.plans;
              _buildingPlan = true;
            }),
            icon: const Icon(Icons.arrow_forward),
            label: Text(l10n.membershipGetStarted),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (_loading && _entitlement == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.membershipTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final price = _entitlement?.priceMinor;
    final discountPercent = _entitlement?.discountPercent ?? 0;
    final discountDuration = _entitlement?.discountVoucherDurationMonths;
    final baseAmountMinor = (price ?? 0) * _durationMonths;
    final discountedAmountMinor =
        (baseAmountMinor * (100 - discountPercent) / 100).round();
    final durations = <(int, String)>[
      (1, l10n.paywallOneMonth),
      (3, l10n.paywallThreeMonths),
      (6, l10n.paywallSixMonths),
      (12, l10n.paywallTwelveMonths),
    ];
    final availableDurations = discountDuration == null
        ? durations
        : durations
            .where((duration) => duration.$1 == discountDuration)
            .toList();
    final sectionIndex = _section.index;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.membershipTitle),
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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  _error!,
                  style: TextStyle(color: AppColors.of(context).danger),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: sectionIndex,
                children: [
                  _buildPlansContent(
                    l10n,
                    theme,
                    price: price,
                    availableDurations: availableDurations,
                    baseAmountMinor: baseAmountMinor,
                    discountedAmountMinor: discountedAmountMinor,
                    discountPercent: discountPercent,
                  ),
                  _buildQuoteContent(l10n, theme),
                  _buildVoucherContent(l10n, theme),
                  _buildHelpContent(l10n, theme),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: sectionIndex,
        onDestinationSelected: (index) => setState(
          () => _section = _MembershipSection.values[index],
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: l10n.membershipPlans,
          ),
          NavigationDestination(
            icon: const Icon(Icons.request_quote_outlined),
            selectedIcon: const Icon(Icons.request_quote),
            label: l10n.membershipQuote,
          ),
          NavigationDestination(
            icon: const Icon(Icons.redeem_outlined),
            selectedIcon: const Icon(Icons.redeem),
            label: l10n.membershipVouchers,
          ),
          NavigationDestination(
            icon: const Icon(Icons.help_outline),
            selectedIcon: const Icon(Icons.help),
            label: l10n.membershipHelp,
          ),
        ],
      ),
    );
  }
}
