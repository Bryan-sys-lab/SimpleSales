import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../models/models.dart';
import '../db/database_helper.dart';
import '../utils/money.dart';

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final List<CartItem> _cart = [];
  final _searchController = TextEditingController();
  List<Product> _products = [];
  String _searchQuery = '';
  bool _loading = true;
  bool _processingPayment = false;
  String? _statusMessage;

  void _announceStatus(String message) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
    unawaited(SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    ));
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final products = await DatabaseHelper.instance.getProducts();
    if (mounted) {
      setState(() {
        _products = products.where((p) => p.active).toList();
        _loading = false;
      });
    }
  }

  /// Bottle units already reserved in the cart for this product, across all
  /// portions. Portion availability must subtract this, otherwise a cashier can
  /// fill the cart with more product than exists and the sale only fails at
  /// `recordSale` — after the customer has already paid.
  double _cartUnitsFor(Product product) {
    var total = 0.0;
    for (final line in _cart) {
      if (line.product.id == product.id) total += line.qty * line.fraction;
    }
    return total;
  }

  /// Offers a safe way out of an outstanding M-Pesa push.
  ///
  /// The guard must not be a dead end: a till that cannot reconcile is a till
  /// that cannot take cash-equivalent payments. Re-querying the provider is the
  /// only safe action — it never re-pushes, so it cannot double-charge. A
  /// definitive FAILED clears the row; SUCCESS books the saved basket from the
  /// durable `cart_json` snapshot; anything else keeps the block in place.
  Future<void> _reconcileOutstandingPayment(
      Map<String, dynamic> pending) async {
    final reference = pending['reference'] as String? ?? '';
    if (reference.isEmpty) {
      await DatabaseHelper.instance.resolvePendingPayment(reference);
      return;
    }

    final amount = pending['amount'];
    _announceStatus('Checking payment $reference…');
    // A reconcile is a status check, not a fresh purchase, so it gets a short
    // budget and visible progress rather than the 90s the sale flow uses. The
    // operator is told to try again if it is still unconfirmed.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator()),
            const SizedBox(width: 16),
            Expanded(
                child:
                    Text('Checking status of $reference with the provider…')),
          ],
        ),
      ),
    );
    final outcome = await BackendService.pollPaymentStatus(
        reference,
        timeout: const Duration(seconds: 20));
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (outcome == PaymentOutcome.failed) {
      // Definitively declined: the basket was never charged, so dropping the
      // row is safe and unblocks the till.
      await DatabaseHelper.instance.resolvePendingPayment(reference);
      if (!mounted) return;
      _announceStatus('Payment $reference was declined. You can retry.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Reference $reference was declined. Safe to retry.'),
      ));
      return;
    }

    if (outcome == PaymentOutcome.success) {
      final recorded = await _recordReconciledSale(pending);
      if (!mounted) return;
      if (recorded) {
        setState(() => _cart.clear());
        _loadProducts();
      }
      return;
    }

    _announceStatus('Payment $reference is still unconfirmed. Do not charge again.');
    final checkAgain = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment still unconfirmed'),
        content: Text(
            'Reference $reference${amount is num ? ' for ${formatMoney(Money.fromMajor(amount))}' : ''} has not been confirmed by the provider. '
            'Do not charge the customer again. Check again now, or record the sale later from Reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Check again'),
          ),
        ],
      ),
    );
    if (checkAgain == true && mounted) {
      await _reconcileOutstandingPayment(pending);
    }
  }

  /// Books the basket saved on an outstanding payment row.
  ///
  /// Uses the persisted `cart_json` rather than the live cart, because the
  /// customer's basket belongs to the original push and must not be mutated by
  /// whatever the cashier has typed since.
  Future<bool> _recordReconciledSale(Map<String, dynamic> pending) async {
    final reference = pending['reference'] as String? ?? '';
    // The row is the only record that this payment still needs booking. If it
    // has already gone — a concurrent reconcile, or the stale sweep — booking
    // it here would write the same sale to the ledger a second time.
    if (!await DatabaseHelper.instance.hasPendingPayment(reference)) {
      _announceStatus('Reference $reference was already reconciled.');
      return false;
    }
    try {
      final decoded = jsonDecode(pending['cart_json'] as String? ?? '[]');
      if (decoded is! List) return false;
      final items = <SaleItem>[];
      for (final line in decoded) {
        if (line is! Map) continue;
        items.add(SaleItem(
          saleId: 0,
          productId: (line['productId'] as num?)?.toInt() ?? 0,
          productName: line['productName'] as String? ?? '',
          qty: (line['qty'] as num?)?.toDouble() ?? 0,
          unitPrice: Money.fromMinor((line['unitPrice'] as num?)?.toInt() ?? 0),
          unitCost: Money.fromMinor((line['unitCost'] as num?)?.toInt() ?? 0),
          portion: line['portion'] as String? ?? 'full',
          portionMl: (line['portionMl'] as num?)?.toInt() ?? 0,
        ));
      }
      if (items.isEmpty) return false;
      await DatabaseHelper.instance.recordSale(
        staffName: pending['staff_name'] as String? ?? 'Unknown',
        staffId: (pending['staff_id'] as num?)?.toInt(),
        items: items,
        // The provider confirmed the money, so authoritative stock already
        // moved server-side. Keep the local ledger consistent regardless of
        // any cached drift.
        enforceStock: false,
        paymentMethod: 'mpesa',
        paymentReference: reference,
      );
      await DatabaseHelper.instance.resolvePendingPayment(reference);
      _announceStatus('Reconciled payment $reference and recorded the sale.');
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('Payment $reference was received. The sale is now recorded.'),
      ));
      return true;
    } catch (_) {
      // The row must survive: the money is confirmed but the local ledger is
      // not, and dropping the row would lose the only copy of the basket.
      _announceStatus('Payment $reference was received but needs manual repair.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Payment $reference was received but could not be recorded locally. Keep this reference and contact support.'),
        ));
      }
      return false;
    }
  }

  Future<void> _addToCart(Product product) async {
    final portion = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Choose serving · ${product.name}',
                style: Theme.of(context).textTheme.titleMedium)),
        _portionOption(
            sheetContext, product, 'full', 'Full', product.sellPrice),
        _portionOption(
            sheetContext, product, 'half', 'Half', product.priceFor('half')),
        _portionOption(sheetContext, product, 'quarter', 'Quarter',
            product.priceFor('quarter')),
      ])),
    );
    if (portion == null || !mounted) return;
    // Re-check after the sheet closes: the picker is async, so the cart or the
    // loaded product list may have changed underneath it.
    final current = _products.where((p) => p.id == product.id).firstOrNull;
    if (current == null) return;
    final needed = current.fractionFor(portion);
    if (current.stockQty - _cartUnitsFor(current) < needed) {
      _announceStatus(
          'Not enough ${current.name} stock left for that serving.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Not enough ${current.name} left. Adjust the cart before adding more.'),
      ));
      return;
    }
    final existing =
        _cart.where((c) => c.product.id == product.id && c.portion == portion);
    if (existing.isNotEmpty) {
      setState(() {
        existing.first.qty++;
      });
    } else {
      setState(() {
        _cart.add(CartItem(product: product, portion: portion, qty: 1));
      });
    }
  }

  Widget _portionOption(BuildContext context, Product product, String portion,
      String label, Money price) {
    final needed = product.fractionFor(portion);
    final available = product.stockQty - _cartUnitsFor(product);
    final canAdd = available >= needed;
    return ListTile(
      leading: const Icon(Icons.local_bar_outlined),
      title: Text('$label · ${product.mlFor(portion)} ml'),
      trailing: Text(formatMoney(price)),
      enabled: canAdd,
      subtitle: !canAdd
          ? Text(available <= 0
              ? 'All stock for this product is already in the cart'
              : 'Only $available of a bottle left')
          : null,
      onTap: canAdd ? () => Navigator.pop(context, portion) : null,
    );
  }

  void _updateQty(int index, double delta) {
    setState(() {
      _cart[index].qty = (_cart[index].qty + delta).clamp(0, 999).toDouble();
      if (_cart[index].qty == 0) _cart.removeAt(index);
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  /// Summing integer cents, the same way [DatabaseHelper.recordSale] does, so the
/// figure on screen is exactly the figure written to the ledger.
Money get _total => sumMoney(_cart.map((item) => item.total));

  static const _offlinePaymentLabels = <String, String>{
    'cash': 'Cash',
    'card': 'Card',
    'bank_transfer': 'Bank transfer',
    'mobile_money_manual': 'Mobile money (manual)',
  };

  Future<void> _checkoutOffline() async {
    if (_cart.isEmpty || _processingPayment) return;
    final amountController =
        TextEditingController(text: _total.asMajor.toStringAsFixed(2));
    final referenceController = TextEditingController();
    var method = 'cash';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Record offline payment'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Sale total: ${formatMoney(_total)}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: _offlinePaymentLabels.entries
                  .map((entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setDialogState(() => method = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              decoration: InputDecoration(
                labelText:
                    method == 'cash' ? 'Amount received' : 'Amount confirmed',
                prefixText: 'KSh ',
                helperText: method == 'cash'
                    ? 'Extra amount is recorded as change.'
                    : 'Must match the sale total.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: referenceController,
              decoration:
                  const InputDecoration(labelText: 'Reference (optional)'),
              textInputAction: TextInputAction.done,
            ),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final typed = double.tryParse(amountController.text.trim());
                final amount = typed == null ? null : Money.fromMajor(typed);
                if (amount == null ||
                    amount < _total ||
                    (method != 'cash' && (amount - _total).minorUnits.abs() > 1)) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                    content: Text(method == 'cash'
                        ? 'Amount received must be at least ${formatMoney(_total)}.'
                        : 'Amount confirmed must equal ${formatMoney(_total)}.'),
                  ));
                  return;
                }
                Navigator.pop(dialogContext, {
                  'method': method,
                  'amount': amount.minorUnits.toString(),
                  'reference': referenceController.text.trim(),
                });
              },
              child: const Text('Record sale'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    referenceController.dispose();
    if (result == null || !mounted) return;
    await _checkout(
      result['method']!,
      amountTendered: Money.fromMinor(int.parse(result['amount']!)),
      paymentReference:
          result['reference']!.isEmpty ? null : result['reference'],
    );
  }

  Future<void> _checkout(
    String paymentMethod, {
    required Money amountTendered,
    String? paymentReference,
  }) async {
    if (_cart.isEmpty || _processingPayment) return;

    final state = context.read<AppState>();

    // Resolve the signed-in cashier once so the sale carries a stable
    // `staff_id`. Ledger attribution is keyed on that id, not the display
    // name, so cash sales must record it too or cashier deletion silently
    // leaves the real name on the ledger.
    int? staffId;
    if (!state.isOwnerSession) {
      final staff = await DatabaseHelper.instance.getStaff();
      final match = staff.where((s) => s.name == state.currentStaffName);
      staffId = match.isEmpty ? null : match.first.id;
    }

    // Prevent double-submit
    setState(() => _processingPayment = true);

    try {
      final items = _cart
          .map((c) => SaleItem(
                saleId: 0,
                productId: c.product.id!,
                productName: c.product.name,
                qty: c.qty,
                unitPrice: c.unitPrice,
                unitCost: c.unitCost,
                portion: c.portion,
                portionMl: c.product.mlFor(c.portion),
              ))
          .toList();

      await DatabaseHelper.instance.recordSale(
        staffName: state.currentStaffName ?? 'Unknown',
        items: items,
        paymentMethod: paymentMethod,
        paymentReference: paymentReference,
        amountTendered: amountTendered,
        staffId: staffId,
      );

      if (mounted) {
        _announceStatus('Sale recorded: ${formatMoney(_total)}');
        final change = amountTendered - _total;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!change.isNegative
              ? 'Sale recorded: ${formatMoney(_total)} · Change ${formatMoney(change)}'
              : 'Sale recorded: ${formatMoney(_total)}'),
        ));
        setState(() {
          _cart.clear();
          _loadProducts(); // Refresh stock
        });
      }
    } catch (e) {
      if (mounted) {
        _announceStatus(
            'Sale could not be completed. Check stock and try again.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Couldn’t complete the sale. Check stock and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingPayment = false);
    }
  }

  Future<void> _checkoutMpesa() async {
    if (_cart.isEmpty || _processingPayment) return;

    final phoneController = TextEditingController();
    final customerNameController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('M-Pesa Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total: ${formatMoney(_total)}'),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: '0712345678',
              ),
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: customerNameController,
              decoration: const InputDecoration(
                labelText: 'Customer Name (optional)',
              ),
              autofillHints: const [AutofillHints.name],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final phone = phoneController.text.trim();
              if (phone.length < 10) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter a valid phone number')),
                );
                return;
              }
              Navigator.pop(ctx, {
                'phone': phone,
                'customer': customerNameController.text.trim(),
              });
            },
            child: const Text('Pay'),
          ),
        ],
      ),
    );
    phoneController.dispose();
    customerNameController.dispose();

    if (result == null) return;
    if (!mounted) return;

    setState(() => _processingPayment = true);

    try {
      // Check if all products have remote IDs (synced)
      final unsynced = _cart.where((c) => c.product.remoteId == null).toList();
      if (unsynced.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sync products first in Settings')),
          );
        }
        return;
      }

      final state = context.read<AppState>();
      await BackendService.syncStaffToBackend();
      final staff = await DatabaseHelper.instance.getStaff();
      final matchingStaff =
          staff.where((s) => s.name == state.currentStaffName).toList();
      final cashierProfile = matchingStaff.isEmpty ? null : matchingStaff.first;
      if (!state.isOwnerSession && cashierProfile?.remoteId == null) {
        throw StateError(
            'Cashier profile is not linked yet. Sync staff and try again.');
      }

      // A previous push for this basket may still be awaiting confirmation.
      // Never issue a second STK push for an outstanding reference: that is the
      // double-charge path. Sweep rows the provider will never confirm, then
      // let the operator reconcile anything still outstanding.
      await DatabaseHelper.instance.deleteStalePendingPayments();
      final outstanding =
          await DatabaseHelper.instance.getBlockingPendingPayments();
      if (outstanding.isNotEmpty) {
        if (!mounted) return;
        await _reconcileOutstandingPayment(outstanding.first);
        return;
      }

      final reference = await BackendService.initiatePayment(
        items: _cart
            .map((c) => {
                  'product_id': c.product.remoteId,
                  'product_name': c.product.name,
                  'qty': c.qty,
                  'portion': c.portion,
                })
            .toList(),
        phoneNumber: result['phone']!,
        staffName: state.currentStaffName ?? 'Unknown',
        staffProfileId: state.isOwnerSession ? null : cashierProfile!.remoteId,
        customerName: result['customer'],
      );

      // Durable record written BEFORE polling. If the poll times out the cart
      // survives, and this row prevents the same basket being pushed again.
      final cartJson = jsonEncode(_cart
          .map((c) => {
                'productId': c.product.id,
                'productName': c.product.name,
                'qty': c.qty,
                // Minor units, not the Money object. jsonEncode throws on
                // anything it cannot encode, so writing `c.unitPrice` here
                // failed outright — and it failed *after* the payment had been
                // initiated, which is the worst possible moment to lose the
                // record of a sale whose money already moved.
                'unitPrice': c.unitPrice.minorUnits,
                'unitCost': c.unitCost.minorUnits,
                'portion': c.portion,
                'portionMl': c.product.mlFor(c.portion),
              })
          .toList());
      await DatabaseHelper.instance.recordPendingPayment(
        reference: reference,
        amount: _total,
        cartJson: cartJson,
        phoneNumber: result['phone'],
        staffName: state.currentStaffName,
        staffId: state.isOwnerSession ? null : cashierProfile?.id,
      );

      // Show waiting dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Processing M-Pesa Payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Check phone ${result['phone']} for STK push'),
                const SizedBox(height: 8),
                Text('Reference: $reference'),
              ],
            ),
          ),
        );
      }

      // Poll for status
      final outcome = await BackendService.pollPaymentStatus(reference);

      if (mounted) {
        Navigator.pop(context); // Close waiting dialog

        if (outcome == PaymentOutcome.success) {
          final state = context.read<AppState>();
          final localItems = _cart
              .map((c) => SaleItem(
                    saleId: 0,
                    productId: c.product.id!,
                    productName: c.product.name,
                    qty: c.qty,
                    unitPrice: c.unitPrice,
                    unitCost: c.unitCost,
                    portion: c.portion,
                    portionMl: c.product.mlFor(c.portion),
                  ))
              .toList();
          try {
            await DatabaseHelper.instance.recordSale(
              staffName: state.currentStaffName ?? 'Unknown',
              items: localItems,
              // The backend already confirmed payment and authoritative stock.
              // Keep the local ledger in sync even if its cached stock drifted.
              enforceStock: false,
              paymentMethod: 'mpesa',
              paymentReference: reference,
              staffId: state.isOwnerSession ? null : cashierProfile?.id,
            );
            await DatabaseHelper.instance.resolvePendingPayment(reference);
          } catch (_) {
            // Never imply the payment failed: the customer has already paid.
            // Clear the cart to prevent a second charge and surface the
            // ledger repair requirement clearly to the operator.
            _announceStatus(
                'M-Pesa payment succeeded, but the local sale record needs attention.');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Payment succeeded. Local recording failed — contact support before reconciling reports.')),
            );
            setState(() => _cart.clear());
            _loadProducts();
            return;
          }
          _announceStatus('M-Pesa payment successful. Sale recorded.');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment successful!')),
          );
          setState(() => _cart.clear());
          _loadProducts();
        } else {
          // Only a definitive decline means the push can safely be retried, so
          // only then does the guard row go. On a timeout the outcome is still
          // unknown: the customer may already have paid, so the row must
          // survive or the same basket can be charged twice.
          if (outcome == PaymentOutcome.failed) {
            await DatabaseHelper.instance.resolvePendingPayment(reference);
          }
          if (!mounted) return;
          _announceStatus(outcome == PaymentOutcome.failed
              ? 'M-Pesa payment failed.'
              : 'M-Pesa payment timed out. Do not charge again.');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(outcome == PaymentOutcome.failed
                    ? 'Payment failed - customer cancelled or insufficient funds'
                    : 'Payment timed out - do not charge again. '
                        'Reference $reference is saved and will be reconciled before another payment.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _announceStatus(
            'M-Pesa payment could not be started. Check your connection and try again.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Payment could not be started. Check your connection and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredProducts = _products
        .where((p) =>
            query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.category.toLowerCase().contains(query))
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return SafeArea(
          child: Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            children: [
              // Product catalog
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear product search',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : GridView.builder(
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    constraints.maxWidth < 480 ? 2 : 3,
                                childAspectRatio: 1.2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: filteredProducts.length,
                              itemBuilder: (ctx, i) {
                                final p = filteredProducts[i];
                                final matchingCart =
                                    _cart.where((c) => c.product.id == p.id);
                                final inCart = matchingCart.fold<double>(
                                    0, (sum, item) => sum + item.stockUnits);

                                return Semantics(
                                  button: p.stockQty > 0,
                                  label:
                                      '${p.name}, ${formatMoney(p.sellPrice)}, ${p.stockQty} in stock',
                                  hint: p.stockQty > 0
                                      ? 'Double tap to add to cart'
                                      : 'Out of stock',
                                  child: Card(
                                    child: InkWell(
                                      onTap: p.stockQty > 0
                                          ? () => _addToCart(p)
                                          : null,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Stack(
                                              children: [
                                                Text(
                                                  p.name,
                                                  textAlign: TextAlign.center,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                if (inCart > 0)
                                                  Positioned(
                                                    right: 0,
                                                    child: CircleAvatar(
                                                      radius: 10,
                                                      child: Text(inCart % 1 ==
                                                              0
                                                          ? '${inCart.toInt()}'
                                                          : '$inCart'),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              formatMoney(p.sellPrice),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              '${p.stockQty} in stock',
                                              style: TextStyle(
                                                color: p.isLow
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .error
                                                    : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // Vertical divider
              compact
                  ? const Divider(height: 1)
                  : const VerticalDivider(width: 1),

              // Cart
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_statusMessage != null)
                            Semantics(
                              liveRegion: true,
                              container: true,
                              label: _statusMessage,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(_statusMessage!,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Semantics(
                                  header: true,
                                  child: Text('Cart',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge!)),
                              Text('${_cart.length} items'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _cart.isEmpty
                          ? const Center(child: Text('Tap products to add'))
                          : ListView.builder(
                              itemCount: _cart.length,
                              itemBuilder: (ctx, i) {
                                final item = _cart[i];
                                return ListTile(
                                  title: Text(
                                      '${item.product.name} · ${item.portionLabel}'),
                                  subtitle: Text(
                                      '${item.product.mlFor(item.portion)} ml · ${formatMoney(item.total)}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove),
                                        tooltip:
                                            'Decrease ${item.product.name}',
                                        onPressed: () => _updateQty(i, -1),
                                      ),
                                      Text(
                                          '${item.qty % 1 == 0 ? item.qty.toInt() : item.qty}'),
                                      IconButton(
                                        icon: const Icon(Icons.add),
                                        tooltip:
                                            'Increase ${item.product.name}',
                                        onPressed: () => _updateQty(i, 1),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete),
                                        tooltip: 'Remove ${item.product.name}',
                                        onPressed: () => _removeFromCart(i),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total:',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              Text(
                                formatMoney(_total),
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _cart.isEmpty || _processingPayment
                                      ? null
                                      : _checkoutOffline,
                                  icon: const Icon(Icons.payments),
                                  label: const Text('Offline payment'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _cart.isEmpty || _processingPayment
                                      ? null
                                      : _checkoutMpesa,
                                  icon: const Icon(Icons.phone_iphone),
                                  label: const Text('M-Pesa'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CartItem {
  final Product product;
  final String portion;
  double qty;

  CartItem({required this.product, required this.portion, required this.qty});

  double get fraction => product.fractionFor(portion);
  double get stockUnits => qty * fraction;

  /// Money. A portion of a bottle is priced in whole cents and the portion of
  /// the *cost* is scaled the same way, so profit on a half bottle is derived
  /// from real amounts rather than from a float approximation of one.
  Money get unitPrice => product.priceFor(portion);
  Money get unitCost => product.costPrice.times(fraction);
  String get portionLabel => portion[0].toUpperCase() + portion.substring(1);

  /// The one rounding point per line: [qty] is a quantity and may be fractional,
  /// so the product is quantised here rather than at every intermediate step.
  Money get total => unitPrice.times(qty);
}
