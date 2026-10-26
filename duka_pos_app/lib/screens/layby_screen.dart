import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/credit.dart';
import '../models/layby.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../ui/components/screen_title.dart';
import '../utils/money.dart';

/// Fashion's lay-by desk. The database owns all lifecycle invariants; this
/// screen is deliberately a thin operator surface over those transactions.
class LaybyScreen extends StatefulWidget {
  const LaybyScreen({super.key});

  @override
  State<LaybyScreen> createState() => _LaybyScreenState();
}

class _LaybyScreenState extends State<LaybyScreen> {
  final _db = DatabaseHelper.instance;
  final _qty = TextEditingController(text: '1');
  final _deposit = TextEditingController();
  final _dueDays = TextEditingController(text: '30');
  List<Customer> _customers = const [];
  List<Product> _products = const [];
  List<Layby> _laybys = const [];
  Customer? _customer;
  Product? _product;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String get _staffName =>
      context.read<AppState>().currentStaffName ?? 'Current staff';
  int? get _staffId => context.read<AppState>().currentStaffId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qty.dispose();
    _deposit.dispose();
    _dueDays.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final customers = await _db.getCustomers(sort: 'name');
      final products = await _db.getProducts(activeOnly: true);
      await _db.expireDueLaybys(staffName: _staffName, staffId: _staffId);
      final laybys = await _db.getLaybys();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _products = products;
        _laybys = laybys;
        _customer ??= customers.isEmpty ? null : customers.first;
        _product ??= products.isEmpty ? null : products.first;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create() async {
    final customer = _customer;
    final product = _product;
    final qty = double.tryParse(_qty.text.trim());
    final depositMajor = double.tryParse(_deposit.text.trim());
    final days = int.tryParse(_dueDays.text.trim());
    if (customer == null ||
        product == null ||
        product.id == null ||
        qty == null ||
        qty <= 0 ||
        depositMajor == null ||
        depositMajor <= 0 ||
        days == null ||
        days <= 0) {
      _message(
          'Choose a customer and product, then enter valid quantity, deposit and due days.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _db.createLayby(
        customerId: customer.id!,
        items: [
          SaleItem(
            saleId: 0,
            productId: product.id!,
            productName: product.name,
            qty: qty,
            unitPrice: product.sellPrice,
            unitCost: product.costPrice,
          )
        ],
        deposit: Money.fromMajor(depositMajor),
        depositMethod: 'cash',
        dueAt: DateTime.now().add(Duration(days: days)),
        staffName: _staffName,
        staffId: _staffId,
      );
      _deposit.clear();
      await _load();
      _message('Lay-by created and stock reserved.');
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pay(Layby layby) async {
    final amount = await _amountDialog('Record payment', layby.balance);
    if (amount == null) return;
    try {
      await _db.addLaybyPayment(
        laybyId: layby.id,
        amount: amount,
        method: 'cash',
        staffName: _staffName,
        staffId: _staffId,
      );
      await _load();
    } catch (error) {
      _message('$error');
    }
  }

  Future<Money?> _amountDialog(String title, Money maximum) async {
    final controller = TextEditingController();
    final value = await showDialog<Money>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'Amount (KES), max ${maximum.asMajor}'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                final major = double.tryParse(controller.text.trim());
                if (major == null || major <= 0) return;
                Navigator.pop(context, Money.fromMajor(major));
              },
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _complete(Layby layby) async {
    try {
      await _db.completeLayby(layby.id,
          staffName: _staffName, staffId: _staffId);
      await _load();
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _cancel(Layby layby) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel lay-by?'),
        content:
            Text('Refund ${layby.paid.asMajor} and release the reservation?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel lay-by')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.cancelLayby(
          laybyId: layby.id, staffName: _staffName, staffId: _staffId);
      await _load();
    } catch (error) {
      _message('$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading && _laybys.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    const ScreenTitle(
                      title: 'Fashion lay-bys',
                      subtitle:
                          'Reserve an item now; recognise revenue only when it is completed.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ),
                    _createCard(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text('Reservations',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    if (_laybys.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No lay-bys yet.'),
                      ),
                    ..._laybys.map(_laybyCard),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _createCard() => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('New lay-by',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            DropdownButtonFormField<Customer>(
              initialValue: _customer,
              decoration: const InputDecoration(labelText: 'Customer'),
              items: _customers
                  .map((customer) => DropdownMenuItem(
                      value: customer, child: Text(customer.name)))
                  .toList(),
              onChanged: (value) => setState(() => _customer = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Product>(
              initialValue: _product,
              decoration: const InputDecoration(labelText: 'Product'),
              items: _products
                  .map((product) => DropdownMenuItem(
                      value: product,
                      child: Text(
                          '${product.name} · ${product.sellPrice.asMajor}')))
                  .toList(),
              onChanged: (value) => setState(() => _product = value),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _qty,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Quantity'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: _deposit,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Deposit (KES)'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: _dueDays,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Due days'))),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
                onPressed: _saving ? null : _create,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(_saving ? 'Saving…' : 'Create lay-by')),
          ]),
        ),
      );

  Widget _laybyCard(Layby layby) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(
                      layby.items.map((item) => item.productName).join(', '),
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Chip(label: Text(layby.status.wire)),
            ]),
            Text(
                'Customer #${layby.customerId} · Due ${layby.dueAt.substring(0, 10)}'),
            const SizedBox(height: 6),
            Text(
                'Paid ${layby.paid.asMajor} / ${layby.total.asMajor} · Balance ${layby.balance.asMajor}'),
            if (layby.isOpen)
              Wrap(spacing: 8, children: [
                TextButton.icon(
                    onPressed: () => _pay(layby),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Payment')),
                if (layby.balance.isZero)
                  TextButton.icon(
                      onPressed: () => _complete(layby),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Complete')),
                TextButton.icon(
                    onPressed: () => _cancel(layby),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel')),
              ]),
          ]),
        ),
      );
}
