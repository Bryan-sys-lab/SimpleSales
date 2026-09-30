import 'package:flutter/material.dart';
import 'dart:async';
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
          String label, double price) =>
      ListTile(
        leading: const Icon(Icons.local_bar_outlined),
        title: Text('$label · ${product.mlFor(portion)} ml'),
        trailing: Text(formatMoney(price)),
        enabled: product.stockQty >= product.fractionFor(portion),
        subtitle: product.stockQty < product.fractionFor(portion)
            ? const Text('Not enough bottle stock')
            : null,
        onTap: product.stockQty >= product.fractionFor(portion)
            ? () => Navigator.pop(context, portion)
            : null,
      );

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

  double get _total => _cart.fold(0, (sum, item) => sum + item.total);

  static const _offlinePaymentLabels = <String, String>{
    'cash': 'Cash',
    'card': 'Card',
    'bank_transfer': 'Bank transfer',
    'mobile_money_manual': 'Mobile money (manual)',
  };

  Future<void> _checkoutOffline() async {
    if (_cart.isEmpty || _processingPayment) return;
    final amountController =
        TextEditingController(text: _total.toStringAsFixed(2));
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
                final amount = double.tryParse(amountController.text.trim());
                if (amount == null ||
                    !amount.isFinite ||
                    amount < _total ||
                    (method != 'cash' && (amount - _total).abs() > 0.01)) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                    content: Text(method == 'cash'
                        ? 'Amount received must be at least ${formatMoney(_total)}.'
                        : 'Amount confirmed must equal ${formatMoney(_total)}.'),
                  ));
                  return;
                }
                Navigator.pop(dialogContext, {
                  'method': method,
                  'amount': amount.toString(),
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
      amountTendered: double.parse(result['amount']!),
      paymentReference:
          result['reference']!.isEmpty ? null : result['reference'],
    );
  }

  Future<void> _checkout(
    String paymentMethod, {
    required double amountTendered,
    String? paymentReference,
  }) async {
    if (_cart.isEmpty || _processingPayment) return;

    final state = context.read<AppState>();

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
      );

      if (mounted) {
        _announceStatus('Sale recorded: ${formatMoney(_total)}');
        final change = amountTendered - _total;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(change > 0.009
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
            );
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
          _announceStatus(outcome == PaymentOutcome.failed
              ? 'M-Pesa payment failed.'
              : 'M-Pesa payment timed out. Check payment status.');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(outcome == PaymentOutcome.failed
                    ? 'Payment failed - customer cancelled or insufficient funds'
                    : 'Payment timed out - check status in reports')),
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
  double get unitPrice => product.priceFor(portion);
  double get unitCost => product.costPrice * fraction;
  String get portionLabel => portion[0].toUpperCase() + portion.substring(1);
  double get total => unitPrice * qty;
}
