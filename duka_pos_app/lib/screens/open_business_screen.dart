import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../profile/profile_product_forms.dart';
import '../profile/shop_profile.dart';
import '../screens/receive_stock_sheet.dart';
import '../services/app_state.dart';
import '../utils/money.dart';

/// Money-first tools for the Open profile.
///
/// The screen is a thin UI over the same DatabaseHelper writers used by the
/// shared finance engine: pools, jobs, payments and owner-money movements all
/// append canonical financial events transactionally.
class OpenBusinessScreen extends StatefulWidget {
  const OpenBusinessScreen({super.key});

  @override
  State<OpenBusinessScreen> createState() => _OpenBusinessScreenState();
}

class _OpenBusinessScreenState extends State<OpenBusinessScreen> {
  List<Map<String, dynamic>> _pools = const [];
  List<Map<String, dynamic>> _jobs = const [];
  List<Map<String, dynamic>> _ownerTransactions = const [];
  List<Product> _products = const [];
  List<Supplier> _suppliers = const [];
  bool _loading = true;
  String? _error;

  DatabaseHelper get _db => DatabaseHelper.instance;

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
      final values = await Future.wait<Object>([
        _db.getCostPools(),
        _db.getOpenJobs(),
        _db.getOwnerTransactions(),
        _db.getProducts(),
        _db.getSuppliers(),
      ]);
      if (!mounted) return;
      setState(() {
        _pools = values[0] as List<Map<String, dynamic>>;
        _jobs = values[1] as List<Map<String, dynamic>>;
        _ownerTransactions = values[2] as List<Map<String, dynamic>>;
        _products = values[3] as List<Product>;
        _suppliers = values[4] as List<Supplier>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _newPool() async {
    final values = await _form('New cost pot', [
      const _Field('name', 'Name'),
      const _Field('note', 'Note (optional)', required: false),
    ], choices: const {
      'type': ['lot', 'rolling_stock']
    });
    if (values == null) return;
    await _run(() => _db.createCostPool(
          uuid: 'pool-${DateTime.now().microsecondsSinceEpoch}',
          name: values['name']!,
          poolType: values['type'] ?? 'lot',
          note: values['note'],
        ));
  }

  Future<void> _addPoolCost(Map<String, dynamic> pool) async {
    final values = await _form('Add pot cost', [
      const _Field('amount', 'Amount (KES)'),
      const _Field('description', 'Description', required: false),
    ], choices: const {
      'type': ['purchase', 'transport', 'packaging', 'sorting', 'other'],
      'paidFrom': ['other', 'till_cash', 'credit'],
    });
    if (values == null) return;
    final amount = _money(values['amount']);
    if (amount == null) return _showError('Enter a valid positive amount.');
    await _run(() => _db.addCostPoolEntry(
          uuid: 'pool-entry-${DateTime.now().microsecondsSinceEpoch}',
          poolId: (pool['id'] as num).toInt(),
          entryType: values['type'] ?? 'other',
          amount: amount,
          paidFrom: values['paidFrom'] ?? 'other',
          description: values['description'],
        ));
  }

  Future<void> _applyOldestPoolCost() async {
    final values = await _form('Apply stock cost to a sale', [
      const _Field('saleId', 'Sale number'),
      const _Field('amount', 'Amount (KES)'),
    ]);
    if (values == null) return;
    final saleId = int.tryParse(values['saleId'] ?? '');
    final amount = _money(values['amount']);
    if (saleId == null || amount == null) {
      return _showError('Enter a valid sale number and amount.');
    }
    final pools = (await _db.getCostPools())
      ..sort((a, b) => (a['created_at'] as String? ?? '')
          .compareTo(b['created_at'] as String? ?? ''));
    Map<String, dynamic>? chosen;
    for (final pool in pools) {
      final invested = (pool['invested_minor'] as num).toInt();
      final recovered = (pool['recovered_minor'] as num).toInt();
      if (invested - recovered >= amount.minorUnits) {
        chosen = pool;
        break;
      }
    }
    if (chosen == null) {
      return _showError('No cost group has enough left for that amount.');
    }
    await _run(() => _db.allocateCostPoolToSale(
          poolId: (chosen!['id'] as num).toInt(),
          saleId: saleId,
          amount: amount,
        ));
  }

  Future<void> _newJob() async {
    final values = await _form('New job', [
      const _Field('title', 'Job title'),
      const _Field('customer', 'Customer (optional)', required: false),
      const _Field('quote', 'Quote (KES, optional)', required: false),
    ]);
    if (values == null) return;
    final quote = values['quote']?.trim().isEmpty == true
        ? null
        : _money(values['quote']);
    await _run(() => _db.createJob(
          uuid: 'job-${DateTime.now().microsecondsSinceEpoch}',
          title: values['title']!,
          customerName: values['customer'],
          quote: quote,
        ));
  }

  Future<void> _addJobCost(Map<String, dynamic> job) async {
    final values = await _form('Add job direct cost', [
      const _Field('amount', 'Amount (KES)'),
      const _Field('description', 'Description', required: false),
    ], choices: const {
      'type': ['materials', 'helper', 'transport', 'other'],
      'paidFrom': ['other', 'till_cash', 'credit'],
    });
    if (values == null) return;
    final amount = _money(values['amount']);
    if (amount == null) return _showError('Enter a valid positive amount.');
    await _run(() => _db.addJobCost(
          uuid: 'job-cost-${DateTime.now().microsecondsSinceEpoch}',
          jobId: (job['id'] as num).toInt(),
          costType: values['type'] ?? 'other',
          amount: amount,
          paidFrom: values['paidFrom'] ?? 'other',
          description: values['description'],
        ));
  }

  Future<void> _takeJobPayment(Map<String, dynamic> job) async {
    final values = await _form('Take job payment', [
      const _Field('amount', 'Amount (KES)'),
      const _Field('reference', 'Reference (optional)', required: false),
    ], choices: const {
      'method': ['cash', 'mpesa', 'bank_transfer']
    });
    if (values == null) return;
    final amount = _money(values['amount']);
    if (amount == null) return _showError('Enter a valid positive amount.');
    final shift = await _db.getAnyOpenShift();
    if (values['method'] == 'cash' && shift == null) {
      return _showError('Open a shift before taking cash.');
    }
    await _run(() => _db.recordJobPayment(
          uuid: 'job-payment-${DateTime.now().microsecondsSinceEpoch}',
          jobId: (job['id'] as num).toInt(),
          amount: amount,
          paymentMethod: values['method'] ?? 'cash',
          reference: values['reference'],
          shiftId: shift?.id,
        ));
  }

  Future<void> _completeJob(Map<String, dynamic> job) async {
    final values = await _form(
        'Complete job', [const _Field('amount', 'Final price (KES)')]);
    if (values == null) return;
    final amount = _money(values['amount']);
    if (amount == null) return _showError('Enter a valid positive amount.');
    await _run(() =>
        _db.completeJob(jobId: (job['id'] as num).toInt(), finalPrice: amount));
  }

  Future<void> _ownerMoney() async {
    final values = await _form('Owner money movement', [
      const _Field('amount', 'Amount (KES)'),
      const _Field('note', 'Note (optional)', required: false),
    ], choices: const {
      'type': ['capital_in', 'drawing', 'loan_received', 'loan_repayment']
    });
    if (values == null) return;
    final amount = _money(values['amount']);
    final shift = await _db.getAnyOpenShift();
    if (amount == null) {
      return _showError('Enter a valid positive amount.');
    }
    if (shift == null) {
      return _showError('Open a shift before recording owner money.');
    }
    if (!mounted) return;
    final state = context.read<AppState>();
    await _run(() => _db.recordOwnerTransaction(
          uuid: 'owner-${DateTime.now().microsecondsSinceEpoch}',
          transactionType: values['type'] ?? 'capital_in',
          amount: amount,
          shiftId: shift.id!,
          staffId: state.currentStaffId,
          staffName: state.currentStaffName ?? 'Owner',
          note: values['note'],
        ));
  }

  Future<void> _quickSale() async {
    final values = await _form('Quick sale', [
      const _Field('amount', 'Amount (KES)'),
      const _Field('reference', 'Reference (optional)', required: false),
    ], choices: const {
      'method': ['cash', 'mpesa', 'bank_transfer']
    });
    if (values == null) return;
    final amount = _money(values['amount']);
    if (amount == null) return _showError('Enter a valid positive amount.');
    if (!mounted) return;
    final state = context.read<AppState>();
    await _run(() => _db.recordOpenQuickSale(
          amount: amount,
          paymentMethod: values['method'] ?? 'cash',
          paymentReference: values['reference'],
          staffId: state.currentStaffId,
          staffName: state.currentStaffName ?? 'Owner',
        ));
  }

  Future<void> _addOptionalProduct() async {
    final values = await ProfileProductForms.showForm(
      context: context,
      profile: ShopProfile.open,
    );
    if (values == null) return;
    final name = values['name'] as String?;
    final priceMajor = (values['price'] as num?)?.toDouble();
    if (name == null || name.trim().isEmpty || priceMajor == null) {
      return _showError('Enter a valid name and selling price.');
    }
    final price = Money.fromMajor(priceMajor);
    final optionalStock = values['optional_stock'] == true;
    final costMajor = (values['cost'] as num?)?.toDouble() ?? 0;
    final stock = (values['stock'] as num?)?.toDouble() ?? 0;
    final now = DateTime.now().toIso8601String();
    final product = Product(
      name: name.trim(),
      category: 'Optional stock',
      costPrice: Money.fromMajor(costMajor),
      sellPrice: price,
      stockQty: optionalStock ? stock : 0,
      reorderLevel: 0,
      updatedAt: now,
    );
    await _run(() => _db.upsertProduct(product));
  }

  Future<void> _receiveOptionalStock() async {
    if (_products.isEmpty) {
      return _showError('Add an item first.');
    }
    await showReceiveStockSheet(
      context,
      products: _products,
      suppliers: _suppliers,
      lastCostFor: (productId) async {
        final product = _products.firstWhere((p) => p.id == productId,
            orElse: () => _products.first);
        return product.costPrice;
      },
      staffName: context.read<AppState>().currentStaffName ?? 'Owner',
      staffId: context.read<AppState>().currentStaffId,
    );
    await _load();
  }

  Future<void> _run(Future<Object?> Function() action) async {
    try {
      await action();
      await _load();
    } catch (error) {
      _showError(error.toString());
    }
  }

  Money? _money(String? raw) {
    final value = double.tryParse((raw ?? '').trim());
    if (value == null || value <= 0) return null;
    return Money.fromMajor(value);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Map<String, String>?> _form(String title, List<_Field> fields,
      {Map<String, List<String>> choices = const {}}) async {
    final controllers = <String, TextEditingController>{
      for (final field in fields) field.key: TextEditingController(),
    };
    final selected = <String, String>{
      for (final entry in choices.entries) entry.key: entry.value.first,
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final field in fields)
                TextField(
                    controller: controllers[field.key],
                    decoration: InputDecoration(labelText: field.label),
                    autofocus: field == fields.first),
              for (final entry in choices.entries)
                DropdownButtonFormField<String>(
                    initialValue: selected[entry.key],
                    decoration: InputDecoration(labelText: entry.key),
                    items: [
                      for (final value in entry.value)
                        DropdownMenuItem(value: value, child: Text(value))
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selected[entry.key] = value);
                      }
                    }),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  for (final field in fields) {
                    if (field.required &&
                        controllers[field.key]!.text.trim().isEmpty) {
                      return;
                    }
                  }
                  Navigator.pop(context, {
                    for (final field in fields)
                      field.key: controllers[field.key]!.text.trim(),
                    ...selected
                  });
                },
                child: const Text('Save')),
          ],
        );
      }),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open business record')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    const Text('Money-first records',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                        'Use cost groups for lots or rolling stock, jobs for work, and owner money for capital and drawings. Each action posts to the shared finance ledger.'),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: FilledButton.icon(
                              onPressed: _quickSale,
                              icon: const Icon(Icons.point_of_sale),
                              label: const Text('Quick sale'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: FilledButton.icon(
                              onPressed: _newPool,
                              icon: const Icon(
                                  Icons.account_balance_wallet_outlined),
                              label: const Text('New cost group'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: FilledButton.icon(
                              onPressed: _newJob,
                              icon: const Icon(Icons.work_outline),
                              label: const Text('New job')))
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: _applyOldestPoolCost,
                              icon: const Icon(Icons.link_outlined),
                              label: const Text('Apply cost to sale'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: _ownerMoney,
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Owner money')))
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                        'Quick sales record revenue and payment only; no stock cost or tax is inferred. Add a pot or job cost separately when known.'),
                    const SizedBox(height: 8),
                    const SizedBox(height: 24),
                    _section(
                      'Stock costs',
                      _pools.isEmpty
                          ? [
                              const ListTile(
                                title: Text('No stock costs yet'),
                                subtitle: Text(
                                    'Create a lot or rolling stock cost group when you buy working stock.'),
                              ),
                            ]
                          : [
                              for (final pool in _pools)
                                Card(
                                  child: ListTile(
                                    title: Text(
                                        '${pool['name']} · ${pool['pool_type']}'),
                                    subtitle: Text(
                                      'Paid in ${formatMoney(Money.fromMinor((pool['invested_minor'] as num).toInt()))} · Recovered ${formatMoney(Money.fromMinor((pool['recovered_minor'] as num).toInt()))} · Left ${formatMoney(Money.fromMinor((pool['invested_minor'] as num).toInt() - (pool['recovered_minor'] as num).toInt()))} · Profit ${formatMoney(Money.fromMinor((pool['recovered_minor'] as num).toInt() - (pool['invested_minor'] as num).toInt() > 0 ? (pool['recovered_minor'] as num).toInt() - (pool['invested_minor'] as num).toInt() : 0))}',
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Add pot cost',
                                      onPressed: () => _addPoolCost(pool),
                                      icon: const Icon(Icons.add),
                                    ),
                                  ),
                                ),
                            ],
                    ),
                    _section(
                      'Jobs',
                      _jobs.isEmpty
                          ? [
                              const ListTile(
                                title: Text('No jobs yet'),
                                subtitle: Text(
                                    'Create a job to track quote, payments and direct costs.'),
                              ),
                            ]
                          : [
                              for (final job in _jobs)
                                Card(
                                  child: ListTile(
                                    title: Text(job['title'] as String),
                                    subtitle: Text(
                                        '${job['customer_name'] ?? 'No customer'} · ${job['status']}'),
                                    isThreeLine: true,
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (action) {
                                        if (action == 'cost') {
                                          _addJobCost(job);
                                        }
                                        if (action == 'payment') {
                                          _takeJobPayment(job);
                                        }
                                        if (action == 'complete') {
                                          _completeJob(job);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'cost',
                                            child: Text('Add direct cost')),
                                        PopupMenuItem(
                                            value: 'payment',
                                            child: Text('Take payment')),
                                        PopupMenuItem(
                                            value: 'complete',
                                            child: Text('Complete job')),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                    ),
                    _section(
                      'Optional stock',
                      <Widget>[
                        Row(children: [
                          Expanded(
                              child: FilledButton.icon(
                                  onPressed: _addOptionalProduct,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add item'))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: OutlinedButton.icon(
                                  onPressed: _receiveOptionalStock,
                                  icon: const Icon(Icons.inventory_2_outlined),
                                  label: const Text('Receive stock'))),
                        ]),
                        if (_products.isEmpty)
                          const ListTile(
                            title: Text('No optional stock items yet'),
                            subtitle: Text(
                                'Add an item when you want to track stock for an open business.'),
                          )
                        else
                          for (final product in _products)
                            ListTile(
                              title: Text(product.name),
                              subtitle: Text(
                                  '${product.stockQty} in stock · ${formatMoney(product.sellPrice)}'),
                            ),
                      ],
                    ),
                    _section(
                      'Owner money',
                      _ownerTransactions.isEmpty
                          ? [
                              const ListTile(
                                title: Text('No owner movements yet'),
                                subtitle: Text(
                                    'Capital, drawings and loans are separate from profit.'),
                              ),
                            ]
                          : [
                              for (final row in _ownerTransactions.take(10))
                                ListTile(
                                  title:
                                      Text(row['transaction_type'] as String),
                                  subtitle: Text(row['note'] as String? ?? ''),
                                  trailing: Text(formatMoney(Money.fromMinor(
                                      (row['amount_minor'] as num).toInt()))),
                                ),
                            ],
                    ),
                  ]),
                ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...children
      ]));
}

class _Field {
  const _Field(this.key, this.label, {this.required = true});
  final String key;
  final String label;
  final bool required;
}
