import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../models/product_pack.dart';
import '../services/app_state.dart';
import '../utils/money.dart';

/// A manual reorder list. It deliberately creates drafts only: nothing here
/// sends an order or turns on automatic purchasing.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key});

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderLine {
  _ReorderLine({
    required this.product,
    required this.supplier,
    required this.quantity,
    this.pack,
  }) : controller = TextEditingController(text: _quantityText(quantity));

  final Product product;
  final Supplier? supplier;
  final ProductPack? pack;
  final TextEditingController controller;
  double quantity;

  static String _quantityText(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  void dispose() => controller.dispose();
}

class _ReorderScreenState extends State<ReorderScreen> {
  final List<_ReorderLine> _lines = <_ReorderLine>[];
  List<Map<String, dynamic>> _orders = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final products = await db.getProducts();
    final suppliers = await db.getSuppliers();
    final velocity = await db.getSalesVelocity();
    final orders = <Map<String, dynamic>>[
      ...await db.getPurchaseOrders(status: 'draft'),
      ...await db.getPurchaseOrders(status: 'partial'),
    ];
    final byId = <int, Supplier>{
      for (final supplier in suppliers)
        if (supplier.id != null) supplier.id!: supplier,
    };
    // Batch-load supplier links and packs for every product once, instead of
    // querying per low-stock product.
    final allSupplierLinks = await (await db.database).rawQuery('''
      SELECT ps.*, s.name AS supplier_name, s.phone AS supplier_phone
      FROM product_suppliers ps JOIN suppliers s ON s.id = ps.supplier_id
      ORDER BY ps.preferred DESC, s.name
    ''');
    final supplierLinksByProduct = <int, List<Map<String, dynamic>>>{};
    for (final link in allSupplierLinks) {
      final pid = link['product_id'] as int;
      (supplierLinksByProduct[pid] ??= <Map<String, dynamic>>[]).add(link);
    }
    final allPacks = await db.getProductPacksForAll();
    final packsByProduct = <int, List<ProductPack>>{};
    for (final pack in allPacks) {
      (packsByProduct[pack.productId] ??= <ProductPack>[]).add(pack);
    }
    final next = <_ReorderLine>[];
    for (final product in products) {
      if (product.id == null || product.reorderLevel <= product.stockQty) {
        continue;
      }
      final links = supplierLinksByProduct[product.id!] ?? const [];
      final link = links.isEmpty ? null : links.first;
      final supplier = link == null ? null : byId[link['supplier_id'] as int];
      ProductPack? pack;
      if (link?['pack_id'] != null) {
        final packs = packsByProduct[product.id!] ?? const [];
        for (final candidate in packs) {
          if (candidate.id == link!['pack_id']) pack = candidate;
        }
      }
      final leadDays = supplier?.leadTimeDays ?? 0;
      final dailyUnits = velocity[product.id!] ?? 0;
      final target = product.reorderLevel + (dailyUnits * leadDays).ceil();
      final gap = (target - product.stockQty).clamp(0, double.infinity).toDouble();
      final units = pack?.unitsPerPack ?? 1;
      final suggested = (gap / units).ceil() * units;
      next.add(_ReorderLine(
        product: product,
        supplier: supplier,
        pack: pack,
        quantity: suggested,
      ));
    }
    if (!mounted) {
      for (final line in next) {
        line.dispose();
      }
      return;
    }
    setState(() {
      _loading = false;
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..addAll(next);
      _orders = orders;
    });
  }

  Map<Supplier?, List<_ReorderLine>> get _grouped {
    final result = <Supplier?, List<_ReorderLine>>{};
    for (final line in _lines) {
      result.putIfAbsent(line.supplier, () => <_ReorderLine>[]).add(line);
    }
    return result;
  }

  Future<void> _saveSupplierOrder(Supplier supplier, List<_ReorderLine> lines,
      {bool share = false}) async {
    final valid = <_ReorderLine>[];
    for (final line in lines) {
      final quantity = double.tryParse(line.controller.text.trim()) ?? 0;
      if (quantity > 0) {
        line.quantity = quantity;
        valid.add(line);
      }
    }
    if (valid.isEmpty) return;
    setState(() => _saving = true);
    try {
      final state = context.read<AppState>();
      final id = await DatabaseHelper.instance.createPurchaseOrder(
        uuid: 'po-${DateTime.now().microsecondsSinceEpoch}',
        supplierId: supplier.id!,
        staffId: state.currentStaffId,
        staffName: state.currentStaffName ?? 'Owner',
        lines: valid
            .map((line) => <String, Object?>{
                  'product_id': line.product.id!,
                  'product_name': line.product.name,
                  'qty': line.quantity,
                  'unit_cost_minor': line.product.costPrice.minorUnits,
                })
            .toList(),
      );
      final orders = await DatabaseHelper.instance.getPurchaseOrders();
      final order = orders.firstWhere((row) => row['id'] == id);
      final number = order['order_number'] as String;
      if (share) {
        final body = StringBuffer('Order $number\nSupplier: ${supplier.name}\n');
        for (final line in valid) {
          body.writeln('${line.product.name}: ${_ReorderLine._quantityText(line.quantity)}');
        }
        await SharePlus.instance.share(ShareParams(text: body.toString()));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$number saved for ${supplier.name}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _receiveOrder(Map<String, dynamic> order) async {
    final db = DatabaseHelper.instance;
    final allLines = await db.getPurchaseOrderLines(order['id'] as int);
    final remaining = allLines.where((line) {
      final qty = (line['qty'] as num).toDouble();
      final received = (line['received_qty'] as num?)?.toDouble() ?? 0;
      return qty > received;
    }).toList();
    if (remaining.isEmpty || !mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Receive ${order['order_number']}?'),
        content: Text(remaining
            .map((line) => '${line['product_name']}: ${((line['qty'] as num).toDouble() - ((line['received_qty'] as num?)?.toDouble() ?? 0))}')
            .join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppLocalizations.of(context).receiveAllRemaining)),
        ],
      ),
    );
    if (accept != true || !mounted) return;
    final state = context.read<AppState>();
    setState(() => _saving = true);
    try {
      await db.postStockReceipt(
        purchaseOrderId: order['id'] as int,
        supplierId: order['supplier_id'] as int,
        supplierRef: order['order_number'] as String,
        note: 'Received against ${order['order_number']}',
        staffId: state.currentStaffId,
        staffName: state.currentStaffName ?? 'Owner',
        lines: [
          for (final line in remaining)
            StockReceiptLine(
              productId: line['product_id'] as int,
              productName: line['product_name'] as String,
              qty: (line['qty'] as num).toDouble() -
                  ((line['received_qty'] as num?)?.toDouble() ?? 0),
              unitCost: Money.fromMinor((line['unit_cost_minor'] as num).toInt()),
            ),
        ],
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).reorderSuggestions)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : groups.isEmpty
              ? Center(child: Text(AppLocalizations.of(context).noProductsAreBelowTheirReorderLevel))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ...groups.entries.map((entry) {
                    final supplier = entry.key;
                    final lines = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(supplier?.name ?? 'Supplier not linked',
                                style: Theme.of(context).textTheme.titleMedium),
                            if (supplier == null)
                              Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(AppLocalizations.of(context).linkASupplierBeforeCreatingAnOrder),
                              ),
                            ...lines.map((line) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(line.product.name),
                                  subtitle: Text(
                                      '${line.product.stockQty} in stock · reorder at ${line.product.reorderLevel}'),
                                  trailing: SizedBox(
                                    width: 78,
                                    child: TextField(
                                      controller: line.controller,
                                      enabled: supplier != null && !_saving,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(labelText: 'Qty'),
                                    ),
                                  ),
                                )),
                            if (supplier != null)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: _saving
                                        ? null
                                        : () => _saveSupplierOrder(supplier, lines,
                                            share: true),
                                    icon: const Icon(Icons.share_outlined),
                                    label: Text(AppLocalizations.of(context).saveShare),
                                  ),
                                  FilledButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _saveSupplierOrder(supplier, lines),
                                    child: Text(AppLocalizations.of(context).saveDraft),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                    }),
                    if (_orders.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Saved purchase orders',
                          style: Theme.of(context).textTheme.titleLarge),
                      ..._orders.map((order) => Card(
                            child: ListTile(
                              title: Text(order['order_number'] as String),
                              subtitle: Text('Status: ${order['status']}'),
                              trailing: TextButton(
                                onPressed: _saving ? null : () => _receiveOrder(order),
                                child: Text(AppLocalizations.of(context).receive),
                              ),
                            ),
                          )),
                    ],
                  ],
                ),
    );
  }
}
