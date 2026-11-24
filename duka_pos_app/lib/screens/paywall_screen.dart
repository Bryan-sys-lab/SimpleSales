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
  const PaywallScreen({
    super.key,
    this.subscriptionRequired = false,
  });

  final bool subscriptionRequired;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _voucher = TextEditingController();
  final _phone = TextEditingController();
  final _receipt = TextEditingController();
  final _requirements = TextEditingController();
  final _message = TextEditingController();
  final Set<String> _selectedFeatures = <String>{};
  List<MembershipRequest> _membershipRequests = const [];
  List<MembershipPayment> _membershipPayments = const [];
  List<MembershipVoucher> _membershipVouchers = const [];
  String? _selectedMembershipRequestId;
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

  MembershipRequest? get _currentMembershipRequest {
    for (final request in _membershipRequests) {
      if (request.id == _selectedMembershipRequestId) return request;
    }
    return _membershipRequests.isEmpty ? null : _membershipRequests.first;
  }

  Future<void> _refreshMembershipData() async {
    final requests = await BackendService.membershipRequests();
    final payments = await BackendService.membershipPayments();
    final vouchers = await BackendService.membershipVouchers();
    if (!mounted) return;
    setState(() {
      _membershipRequests = requests;
      _membershipPayments = payments;
      _membershipVouchers = vouchers;
      if (!requests
          .any((request) => request.id == _selectedMembershipRequestId)) {
        _selectedMembershipRequestId =
            requests.isEmpty ? null : requests.first.id;
      }
    });
  }

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
      final request = await BackendService.requestSubscriptionQuote(
        features: selectedFeatures,
        requirements: requirements,
      );
      if (!mounted) return;
      setState(() {
        _membershipRequests = [
          request,
          ..._membershipRequests.where((item) => item.id != request.id),
        ];
        _selectedMembershipRequestId = request.id;
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
      List<MembershipRequest> requests = const [];
      List<MembershipPayment> payments = const [];
      List<MembershipVoucher> vouchers = const [];
      try {
        requests = await BackendService.membershipRequests();
        payments = await BackendService.membershipPayments();
        vouchers = await BackendService.membershipVouchers();
      } catch (error, stack) {
        debugPrint('Could not load membership account details: $error\n$stack');
      }
      if (mounted) {
        setState(() {
          _entitlement = result;
          _membershipRequests = requests;
          _membershipPayments = payments;
          _membershipVouchers = vouchers;
          _selectedMembershipRequestId =
              requests.isEmpty ? null : requests.first.id;
          _quoteRequested = requests.isNotEmpty;
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

  Future<void> _startPayment({String? agreementId}) async {
    if (_phone.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quote = await BackendService.startSubscriptionPayment(
        phoneNumber: _phone.text.trim(),
        durationMonths: _durationMonths,
        agreementId: agreementId,
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

  Future<void> _sendMembershipMessage() async {
    final request = _currentMembershipRequest;
    final body = _message.text.trim();
    if (request == null || body.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sent = await BackendService.sendMembershipMessage(
          requestId: request.id, body: body);
      if (!mounted) return;
      setState(() {
        _membershipRequests = _membershipRequests
            .map((item) => item.id == request.id
                ? MembershipRequest(
                    id: item.id,
                    status: item.status == 'offer_ready'
                        ? 'negotiating'
                        : item.status,
                    features: item.features,
                    requirements: item.requirements,
                    offers: item.offers,
                    messages: [...item.messages, sent],
                    agreement: item.agreement,
                  )
                : item)
            .toList();
        _message.clear();
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (error.response?.data is Map
                ? error.response!.data['error'] as String?
                : null) ??
            'Your message could not be sent.';
      });
    } catch (error, stack) {
      debugPrint('Could not send membership message: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Your message could not be sent.';
      });
    }
  }

  Future<void> _reviewAndAcceptOffer(
    MembershipRequest request,
    MembershipOffer offer,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await BackendService.previewMembershipOffer(
        requestId: request.id,
        offerId: offer.id,
      );
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Review offer ${offer.revision}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your price: ${offer.currency} ${(preview.amountMinor / 100).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (preview.discountPercent > 0)
                  Text(
                    'Voucher discount: ${preview.discountPercent}% '
                    '(-${offer.currency} ${(preview.discountAmountMinor / 100).toStringAsFixed(2)})',
                  ),
                if (preview.voucherNotApplicable)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'Your claimed voucher does not apply to this offer.'),
                  ),
                const SizedBox(height: 12),
                Text('Payment: ${offer.paymentArrangement}'),
                Text('Renewal: ${offer.renewalTerms}'),
                if (offer.termMonths != null)
                  Text('Term: ${offer.termMonths} months'),
                if (offer.includedFeatures.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Included features'),
                  ...offer.includedFeatures.map(
                    (feature) => Text('- $feature'),
                  ),
                ],
                if (offer.additionalConditions?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(offer.additionalConditions!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Accept offer'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final acceptedAgreement = await BackendService.acceptMembershipOffer(
        requestId: request.id,
        offerId: offer.id,
        preview: preview,
      );
      if (!mounted) return;
      setState(() {
        _membershipRequests = _membershipRequests
            .map((item) => item.id == request.id
                ? MembershipRequest(
                    id: item.id,
                    status: 'accepted',
                    features: item.features,
                    requirements: item.requirements,
                    offers: item.offers,
                    messages: item.messages,
                    agreement: acceptedAgreement,
                  )
                : item)
            .toList();
        _loading = false;
      });
      try {
        await _refreshMembershipData();
      } catch (error, stack) {
        debugPrint(
            'Agreement accepted but account refresh failed: $error\n$stack');
      }
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (error.response?.data is Map
                ? error.response!.data['error'] as String?
                : null) ??
            'This offer could not be accepted.';
      });
    } catch (error, stack) {
      debugPrint('Could not review membership offer: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This offer could not be accepted.';
      });
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
    _message.dispose();
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _buildMembershipRequestSummary(theme),
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
        const SizedBox(height: 16),
        _featureGroup(
          l10n,
          theme,
          title: l10n.membershipAdditionalFeatures,
          description: l10n.membershipAdditionalDescription,
          features: _additionalFeatures(l10n),
        ),
        const SizedBox(height: 16),
        _featureGroup(
          l10n,
          theme,
          title: l10n.membershipExtraSupport,
          description: l10n.membershipSupportDescription,
          features: _supportFeatures(l10n),
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _requestQuote,
          icon: const Icon(Icons.arrow_forward),
          label: Text(l10n.membershipRequestOffer),
        ),
      ],
    );
  }

  Widget _buildPlansContent(AppLocalizations l10n, ThemeData theme) {
    if (_buildingPlan) return _buildPlanBuilder(l10n, theme);
    final colors = theme.colorScheme;
    final Widget? configuredPricing = _buildConfiguredPricing(l10n, theme);
    return ListView(
      key: const ValueKey<String>('membership-explore'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _buildMembershipRequestSummary(theme),
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
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => setState(() => _buildingPlan = true),
                  child: Text(l10n.membershipGetStarted),
                ),
              ],
            ),
          ),
        ),
        if (configuredPricing != null) ...[
          const SizedBox(height: 16),
          configuredPricing,
        ],
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
        const SizedBox(height: 16),
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
      ],
    );
  }

  Widget? _buildConfiguredPricing(AppLocalizations l10n, ThemeData theme) {
    final entitlement = _entitlement;
    final int? monthlyPriceMinor = entitlement?.priceMinor;
    if (entitlement == null ||
        monthlyPriceMinor == null ||
        monthlyPriceMinor <= 0 ||
        entitlement.discountVoucherDurationMonths != null ||
        entitlement.claimedVoucherType == 'discount') {
      return null;
    }

    final int durationMonths = _durationMonths > 0 ? _durationMonths : 1;
    final int discountPercent =
        entitlement.discountPercent.clamp(0, 100).toInt();
    final int baseAmountMinor = monthlyPriceMinor * durationMonths;
    final int amountDueMinor =
        (baseAmountMinor * (100 - discountPercent) / 100).round();
    final int discountAmountMinor = baseAmountMinor - amountDueMinor;
    final String currency = entitlement.currency;
    final TextTheme textTheme = theme.textTheme;

    String amount(int minor) => '$currency ${(minor / 100).toStringAsFixed(2)}';

    String durationLabel() => switch (durationMonths) {
          1 => l10n.paywallOneMonth,
          3 => l10n.paywallThreeMonths,
          6 => l10n.paywallSixMonths,
          12 => l10n.paywallTwelveMonths,
          _ => '$durationMonths months',
        };

    return Card(
      key: const ValueKey<String>('admin-subscription-pricing'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.paywallAdminPriceTitle,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.paywallAssignedPrice(
                currency,
                (monthlyPriceMinor / 100).toStringAsFixed(2),
                entitlement.billingInterval,
              ),
              style: textTheme.bodyMedium,
            ),
            const Divider(height: 24),
            _PricingRow(
              label: l10n.paywallDuration,
              value: durationLabel(),
            ),
            const SizedBox(height: 8),
            _PricingRow(
              label: l10n.paywallQuoteBase,
              value: amount(baseAmountMinor),
            ),
            if (discountPercent > 0) ...<Widget>[
              const SizedBox(height: 8),
              _PricingRow(
                label: l10n.paywallDiscount(discountPercent),
                value: '-${amount(discountAmountMinor)}',
              ),
            ],
            const Divider(height: 24),
            _PricingRow(
              label: l10n.paywallAmountDue,
              value: amount(amountDueMinor),
              emphasize: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembershipRequestSummary(ThemeData theme) {
    final request = _currentMembershipRequest;
    if (request == null) return const SizedBox.shrink();
    final accepted = request.status == 'accepted';
    final quoteReady = request.status == 'offer_ready';
    final canStartAnother = accepted || request.status == 'closed';
    final colorScheme = theme.colorScheme;

    return Card(
      color: accepted
          ? colorScheme.secondaryContainer
          : colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  accepted
                      ? Icons.check_circle_outline
                      : quoteReady
                          ? Icons.markunread_mailbox_outlined
                          : Icons.hourglass_top_rounded,
                  color: accepted
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    accepted
                        ? 'Quote accepted'
                        : quoteReady
                            ? 'Your quote is ready'
                            : 'Request · ${request.status.replaceAll('_', ' ')}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: accepted
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh request',
                  onPressed: _loading
                      ? null
                      : () async {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          try {
                            await _refreshMembershipData();
                          } catch (error, stack) {
                            debugPrint(
                                'Could not refresh membership: $error\n$stack');
                            if (mounted) {
                              setState(() =>
                                  _error = 'Could not refresh your request.');
                            }
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              accepted
                  ? 'Your agreement is active. You can request a new plan whenever you need a change.'
                  : quoteReady
                      ? 'Review the proposed terms in your request.'
                      : 'Your request is saved. Check here for status updates and replies.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: accepted
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onTertiaryContainer,
              ),
            ),
            if (request.features.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                request.features.take(3).join(', '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accepted
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onTertiaryContainer,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _section = _MembershipSection.quote;
                    _buildingPlan = false;
                  }),
                  child: const Text('View request'),
                ),
                if (canStartAnother)
                  TextButton(
                    onPressed: () => setState(() {
                      _section = _MembershipSection.plans;
                      _buildingPlan = true;
                      _selectedFeatures.clear();
                      _requirements.clear();
                    }),
                    child: const Text('Request a new plan'),
                  ),
              ],
            ),
          ],
        ),
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.check_circle_outline,
                  color: theme.colorScheme.primary),
              title: Text(l10n.membershipMySubscription),
              subtitle: Text(subtitle),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _buildingPlan = true;
                  _section = _MembershipSection.plans;
                }),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Request a change'),
              ),
            ),
          ],
        ),
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
        if (_membershipVouchers.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Your vouchers', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          ..._membershipVouchers.map((voucher) {
            final expiry = DateTime.tryParse(voucher.expiresAt ?? '');
            return Card(
              child: ListTile(
                leading: const Icon(Icons.redeem_outlined),
                title: Text(
                  voucher.voucherType == 'discount'
                      ? '${voucher.discountPercent}% off · ${voucher.durationMonths} months'
                      : 'Access · ${voucher.durationMonths} months',
                ),
                subtitle: Text(
                  'Code prefix ${voucher.codePrefix}'
                  '${voucher.redeemedAt == null ? ' · Not claimed' : ' · Claimed'}',
                ),
                trailing: expiry == null
                    ? null
                    : Text(
                        'Expires ${MaterialLocalizations.of(context).formatShortDate(expiry.toLocal())}',
                        style: theme.textTheme.bodySmall,
                      ),
              ),
            );
          }),
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
    final request = _currentMembershipRequest;
    final agreement = request?.agreement;
    final Widget? configuredPricing =
        agreement == null ? _buildConfiguredPricing(l10n, theme) : null;
    final snapshot = agreement?.snapshot ?? const <String, dynamic>{};
    final agreedAmount = (snapshot['amountMinor'] as num?)?.toInt();
    final agreementCurrency = snapshot['currency'] as String? ?? 'KES';
    final requestPayments = agreement == null
        ? const <MembershipPayment>[]
        : _membershipPayments
            .where((payment) => payment.agreementId == agreement.id)
            .toList();
    return ListView(
      key: const ValueKey<String>('membership-quote'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(l10n.membershipQuote, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(l10n.membershipQuoteDescription, style: theme.textTheme.bodyLarge),
        if (configuredPricing != null) ...[
          const SizedBox(height: 16),
          configuredPricing,
        ],
        if (_membershipRequests.length > 1) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: request?.id,
            decoration: const InputDecoration(
              labelText: 'Your requests',
              border: OutlineInputBorder(),
            ),
            items: _membershipRequests
                .map((item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(
                        '${item.status.replaceAll('_', ' ')} · ${item.features.take(2).join(', ')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: _loading
                ? null
                : (id) => setState(() => _selectedMembershipRequestId = id),
          ),
        ],
        if (request == null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.request_quote_outlined, size: 30),
                  const SizedBox(height: 12),
                  Text(l10n.membershipQuoteEmptyTitle,
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(l10n.membershipQuoteEmptyDescription),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      _section = _MembershipSection.plans;
                      _buildingPlan = true;
                    }),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.membershipGetStarted),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.request_quote_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Request · ${request.status.replaceAll('_', ' ')}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh request',
                        onPressed: _loading
                            ? null
                            : () async {
                                try {
                                  await _refreshMembershipData();
                                } catch (error, stack) {
                                  debugPrint(
                                      'Could not refresh membership: $error\n$stack');
                                  if (mounted) {
                                    setState(() => _error =
                                        'Could not refresh your request.');
                                  }
                                }
                              },
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (request.features.isNotEmpty)
                    Text('Requested: ${request.features.join(', ')}'),
                  if (request.requirements.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(request.requirements),
                    ),
                ],
              ),
            ),
          ),
          if (agreement != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your agreement', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Reference: ${agreement.reference}'),
                    if (agreedAmount != null)
                      Text(
                        'Agreed price: $agreementCurrency '
                        '${(agreedAmount / 100).toStringAsFixed(2)}',
                      ),
                    Text(
                      'Payment: ${snapshot['paymentArrangement'] ?? 'As agreed'}',
                    ),
                    Text(
                      'Renewal: ${snapshot['renewalTerms'] ?? 'As agreed'}',
                    ),
                    if (snapshot['termMonths'] is num)
                      Text('Term: ${snapshot['termMonths']} months'),
                    if (snapshot['includedFeatures'] is List) ...[
                      const SizedBox(height: 8),
                      const Text('Included features'),
                      ...((snapshot['includedFeatures'] as List)
                          .whereType<String>()
                          .map((feature) => Text('- $feature'))),
                    ],
                    if (snapshot['additionalConditions'] is String &&
                        (snapshot['additionalConditions'] as String)
                            .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(snapshot['additionalConditions'] as String),
                    ],
                    if (_entitlement?.allowed != true) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'M-Pesa phone number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _startPayment(agreementId: agreement.id),
                        icon: const Icon(Icons.phone_android_rounded),
                        label: const Text('Complete payment'),
                      ),
                    ],
                    if (_paymentReference != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Payment request: $_paymentReference',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (_paymentQuote != null)
                        Text(
                          'Confirm $agreementCurrency '
                          '${(_paymentQuote!.amountMinor / 100).toStringAsFixed(2)} '
                          'on your phone.',
                        ),
                      OutlinedButton(
                        onPressed: _loading ? null : _checkPayment,
                        child: const Text('Check payment'),
                      ),
                      TextField(
                        controller: _receipt,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'M-Pesa receipt code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      TextButton(
                        onPressed: _loading ? null : _confirmReceipt,
                        child: const Text('Verify receipt'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (requestPayments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Payment history', style: theme.textTheme.titleMedium),
              ...requestPayments.map((payment) => Card(
                    child: ListTile(
                      title: Text(
                        '${payment.status} · $agreementCurrency '
                        '${(payment.amountMinor / 100).toStringAsFixed(2)}',
                      ),
                      subtitle: Text(payment.reference),
                      trailing: payment.status == 'PENDING'
                          ? TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => setState(() {
                                        _paymentReference = payment.reference;
                                        _paymentQuote =
                                            SubscriptionPaymentQuote(
                                          reference: payment.reference,
                                          amountMinor: payment.amountMinor,
                                          baseAmountMinor: payment.amountMinor,
                                          discountAmountMinor: 0,
                                          discountPercent: 0,
                                          durationMonths:
                                              payment.durationMonths,
                                        );
                                      }),
                              child: const Text('Check'),
                            )
                          : null,
                    ),
                  )),
            ],
          ],
          ...request.offers
              .where((offer) => offer.status == 'offered')
              .map((offer) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Offer ${offer.revision}',
                              style: theme.textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text('Your quoted price is reviewed below.'),
                          Text('Payment: ${offer.paymentArrangement}'),
                          Text('Renewal: ${offer.renewalTerms}'),
                          if (offer.termMonths != null)
                            Text('Term: ${offer.termMonths} months'),
                          if (offer.includedFeatures.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text('Included features'),
                            ...offer.includedFeatures
                                .map((feature) => Text('- $feature')),
                          ],
                          if (offer.additionalConditions?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(offer.additionalConditions!),
                            ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _loading
                                ? null
                                : () => _reviewAndAcceptOffer(request, offer),
                            child: const Text('Review offer'),
                          ),
                        ],
                      ),
                    ),
                  )),
          if (request.messages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Conversation', style: theme.textTheme.titleLarge),
            ...request.messages.map((message) => Card(
                  child: ListTile(
                    title: Text(
                        message.senderType == 'sales' ? 'Sales team' : 'You'),
                    subtitle: Text(message.body),
                  ),
                )),
          ],
          if (request.status != 'accepted' && request.status != 'closed') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Write a message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _loading ? null : _sendMembershipMessage,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send message'),
            ),
          ],
          if (_quoteRequested)
            OutlinedButton.icon(
              onPressed: _salesWhatsappUri(l10n) == null
                  ? null
                  : () => _openSupport(_salesWhatsappUri(l10n)!),
              icon: const Icon(Icons.chat_outlined),
              label: Text(l10n.membershipDiscussOnWhatsApp),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (_loading && _entitlement == null) {
      return PopScope<Object?>(
        canPop: !widget.subscriptionRequired,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.membershipTitle)),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final sectionIndex = _section.index;

    return PopScope<Object?>(
      canPop: !widget.subscriptionRequired,
      child: Scaffold(
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
              if (_loading && _entitlement != null)
                const LinearProgressIndicator(),
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
                    _buildPlansContent(l10n, theme),
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
      ),
    );
  }
}

class _PricingRow extends StatelessWidget {
  const _PricingRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = emphasize
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            )
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(value, style: style),
      ],
    );
  }
}
