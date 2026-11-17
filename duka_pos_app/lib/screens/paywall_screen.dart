import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/backend_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await BackendService.fetchSubscriptionEntitlement();
      if (mounted) setState(() { _entitlement = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Connect to the internet to check this shop subscription.'; });
    }
  }

  Future<void> _redeem() async {
    if (_voucher.text.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await BackendService.redeemAccessVoucher(_voucher.text);
      if (!mounted) return;
      if (result?.allowed == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voucher accepted. This shop is ready to use.')));
        Navigator.of(context).pop(true);
      } else {
        setState(() { _loading = false; _error = 'This voucher could not unlock the shop.'; });
      }
    } on DioException catch (error) {
      if (mounted) setState(() { _loading = false; _error = (error.response?.data is Map ? (error.response!.data['error'] as String?) : null) ?? 'Voucher could not be redeemed.'; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Voucher could not be redeemed.'; });
    }
  }

  Future<void> _startPayment() async {
    if (_phone.text.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final reference = await BackendService.startSubscriptionPayment(phoneNumber: _phone.text.trim());
      if (mounted) setState(() { _paymentReference = reference; _loading = false; });
    } on DioException catch (error) {
      if (mounted) setState(() { _loading = false; _error = (error.response?.data is Map ? (error.response!.data['error'] as String?) : null) ?? 'Payment could not be started.'; });
    }
  }

  Future<void> _checkPayment() async {
    final reference = _paymentReference;
    if (reference == null) return;
    setState(() => _loading = true);
    try {
      final status = await BackendService.subscriptionPaymentStatus(reference);
      if (!mounted) return;
      if (status == 'SUCCESS') { Navigator.of(context).pop(true); } else { setState(() { _loading = false; _error = status == 'FAILED' ? 'Payment failed. You can try again.' : 'Payment is still pending. Confirm the M-Pesa prompt, then check again.'; }); }
    } catch (_) { if (mounted) setState(() { _loading = false; _error = 'Could not verify payment yet.'; }); }
  }

  Future<void> _confirmReceipt() async {
    final reference = _paymentReference;
    if (reference == null || _receipt.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await BackendService.confirmSubscriptionPaymentCode(reference: reference, mpesaCode: _receipt.text);
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (error) {
      if (mounted) setState(() { _loading = false; _error = (error.response?.data is Map ? (error.response!.data['error'] as String?) : null) ?? 'That receipt could not be verified yet.'; });
    }
  }

  @override
  void dispose() { _voucher.dispose(); _phone.dispose(); _receipt.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = _entitlement?.priceMinor;
    return Scaffold(
      appBar: AppBar(title: const Text('Shop subscription')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          children: [
            Icon(Icons.lock_rounded, size: 46, color: theme.colorScheme.primary),
            const SizedBox(height: 18),
            Text('Keep this shop running', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('This shop uses a negotiated subscription. The system administrator sets the price and billing terms for each shop.', style: theme.textTheme.bodyLarge),
            if (price != null) ...[
              const SizedBox(height: 18),
              Text('${_entitlement?.currency ?? 'KES'} ${(price / 100).toStringAsFixed(2)} / ${_entitlement?.billingInterval ?? 'month'}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 28),
            Text('Have a voucher?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(controller: _voucher, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Voucher code', hintText: 'SS-…', border: OutlineInputBorder())),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _loading ? null : _redeem, icon: const Icon(Icons.redeem_rounded), label: Text(_loading ? 'Checking…' : 'Redeem voucher')),
            const SizedBox(height: 28),
            Text('Pay by M-Pesa', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'M-Pesa phone number', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(onPressed: _loading ? null : _startPayment, icon: const Icon(Icons.phone_android_rounded), label: const Text('Send payment prompt')),
            if (_paymentReference != null) ...[
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _loading ? null : _checkPayment, child: const Text('I have paid — verify payment')),
              const SizedBox(height: 10),
              TextField(controller: _receipt, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'M-Pesa receipt code (if needed)', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextButton(onPressed: _loading ? null : _confirmReceipt, child: const Text('Verify receipt code')),
            ],
            if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: TextStyle(color: Colors.red))],
            const SizedBox(height: 22),
            Text('Ask your system administrator to activate the shop subscription or issue a voucher. No payment is collected by this screen.', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
