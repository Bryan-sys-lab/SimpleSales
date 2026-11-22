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

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _voucher = TextEditingController();
  final _phone = TextEditingController();
  final _receipt = TextEditingController();
  SubscriptionEntitlement? _entitlement;
  bool _loading = true;
  String? _error;
  String? _paymentReference;
  bool _quoteRequested = false;

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

  Future<void> _requestQuote() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await BackendService.requestSubscriptionQuote();
      if (!mounted) return;
      setState(() {
        _quoteRequested = true;
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (error.response?.data is Map
                ? error.response!.data['error'] as String?
                : null) ??
            'Could not send the quote request.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not send the quote request.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await BackendService.fetchSubscriptionEntitlement();
      if (result?.allowed == true) {
        // The route may have been opened before the just-verified voucher
        // finished refreshing. Do not present a payment wall to a shop that
        // is already entitled to use the app.
        await _unlockAndReturn();
        return;
      }
      if (mounted) {
        setState(() {
          _entitlement = result;
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

  Future<void> _redeem() async {
    if (_voucher.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await BackendService.redeemAccessVoucher(_voucher.text);
      if (!mounted) return;
      if (result?.allowed == true) {
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

  Future<void> _startPayment() async {
    if (_phone.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reference = await BackendService.startSubscriptionPayment(
          phoneNumber: _phone.text.trim());
      if (mounted) {
        setState(() {
          _paymentReference = reference;
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
    _voucher.dispose();
    _phone.dispose();
    _receipt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final price = _entitlement?.priceMinor;
    final hasStarterVoucher = _entitlement?.firstMonthVoucherAvailable == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Activate your shop')),
      body: SafeArea(
        child: ListView(
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
                        hasStarterVoucher
                            ? 'Your shop is ready for its first month'
                            : 'Activate access for this shop',
                        style: theme.textTheme.headlineSmall?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                        hasStarterVoucher
                            ? 'Enter the one-month voucher sent to your email, or choose a subscription below. The 30 days start when you redeem it.'
                            : 'Choose a subscription or enter a voucher issued for this shop. Access is shared by the shop’s owner and staff.',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: colors.onPrimaryContainer)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
                hasStarterVoucher
                    ? 'Use your one-month voucher'
                    : 'Have a voucher?',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
                hasStarterVoucher
                    ? 'Find the code in the email with your verification code.'
                    : 'Enter a code issued by your shop administrator.',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextField(
                controller: _voucher,
                textCapitalization: TextCapitalization.characters,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(
                    labelText: 'Voucher code',
                    hintText: hasStarterVoucher
                        ? 'Enter code from email'
                        : 'Enter voucher code',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: _loading ? null : _redeem,
                icon: const Icon(Icons.redeem_rounded),
                label: Text(_loading
                    ? 'Checking…'
                    : hasStarterVoucher
                        ? 'Redeem one-month voucher'
                        : 'Redeem voucher')),
            const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 10),
            Text('Choose a subscription', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
                'Your shop’s price and billing terms are set by the SimpleSales team.',
                style: theme.textTheme.bodyMedium),
            if (price != null) ...[
              const SizedBox(height: 18),
              Card(
                  child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Your agreed price'),
                      subtitle: Text(
                          '${_entitlement?.currency ?? 'KES'} ${(price / 100).toStringAsFixed(2)} / ${_entitlement?.billingInterval ?? 'month'}'))),
              const SizedBox(height: 12),
              TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                      labelText: 'M-Pesa phone number',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                  onPressed: _loading ? null : _startPayment,
                  icon: const Icon(Icons.phone_android_rounded),
                  label: const Text('Pay with M-Pesa')),
              if (_paymentReference != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: _loading ? null : _checkPayment,
                    child: const Text('Check payment status')),
                TextField(
                    controller: _receipt,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'M-Pesa receipt code (if needed)',
                        border: OutlineInputBorder())),
                TextButton(
                    onPressed: _loading ? null : _confirmReceipt,
                    child: const Text('Verify receipt code')),
              ],
            ],
            if (price == null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: _loading || _quoteRequested ? null : _requestQuote,
                  icon: const Icon(Icons.request_quote_outlined),
                  label: Text(
                      _quoteRequested ? 'Quote requested' : 'Request a quote')),
            ],
            if (SupportContact.whatsappUri(
              message: AppLocalizations.of(context).paywallWhatsAppMessage,
              fallbackUrl: _entitlement?.whatsappUrl,
            )
                case final Uri whatsappUri) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                  onPressed: () => _openSupport(whatsappUri),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Chat with us on WhatsApp')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: AppColors.of(context).danger),
              )
            ],
          ],
        ),
      ),
    );
  }
}
