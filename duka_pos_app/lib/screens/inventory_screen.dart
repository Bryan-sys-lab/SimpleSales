import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../utils/money.dart';
import '../theme/app_theme.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _products = []);
    final p = await DatabaseHelper.instance.getProducts();
    if (mounted) setState(() => _products = p);
  }

  Future<void> _openEditor([Product? existing]) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductEditor(existing: existing, onSaved: _load),
    );
  }

  Future<void> _adjustStock(Product p) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AdjustDialog(product: p),
    );
    if (result == null) return;
    final delta = int.tryParse(result['delta'] ?? '');
    if (delta == null || delta == 0) return;
    if (!mounted) return;
    final state = context.read<AppState>();
    final staffName = state.currentStaffName!;
    // Shrinkage is reviewed per cashier, and `deleteStaffWithTombstone`
    // anonymises the ledger by `staff_id`. Recording only the display name
    // leaves the removed cashier named on every adjustment they made.
    int? staffId;
    String? staffRemoteId;
    if (!state.isOwnerSession) {
      final staff = await DatabaseHelper.instance.getStaff();
      final match = staff.where((s) => s.name == staffName);
      staffId = match.isEmpty ? null : match.first.id;
      staffRemoteId = match.isEmpty ? null : match.first.remoteId;
    }
    try {
      await DatabaseHelper.instance.adjustStock(StockAdjustment(
        productId: p.id!,
        productName: p.name,
        delta: delta,
        reason: result['reason'] ?? '',
        staffName: staffName,
        createdAt: DateTime.now().toIso8601String(),
      ), staffId: staffId);
      await _load();
      // The server owns the authoritative stock count, so the correction has to
      // be pushed as an adjustment rather than folded into the next catalogue
      // sync. Reported, not silent: the local count is already correct, but the
      // shop's other devices will not see this change until it lands.
      if (mounted) {
        final pushed = await BackendService.adjustStockOnBackend(
          product: p,
          delta: delta,
          reason: result['reason'],
          staffProfileId: staffRemoteId,
        );
        if (!pushed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Stock updated on this till. The online count will catch up on the next sync.')));
        }
      }
    } on StateError catch (error) {
      if (mounted) {
        final message = error.toString().contains('below zero')
            ? 'Stock cannot go below zero. Check the current quantity and try again.'
            : 'Stock update failed. Refresh the inventory and try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Couldn’t adjust stock. Try again.')));
      }
    }
  }

  Future<void> _delete(Product p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove ${p.name} from inventory?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.deactivateProduct(p.id!);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = context.watch<AppState>().isOwnerSession;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: 'Add product',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          itemCount: _products.length,
          itemBuilder: (_, i) {
            final p = _products[i];
            return Semantics(
              label:
                  '${p.name}, ${formatMoney(p.sellPrice)}, ${p.stockQty} in stock',
              child: ListTile(
                title: Text(p.name),
                subtitle: Text(
                    '${p.category} · ${formatMoney(p.sellPrice)} · margin ${p.marginPct.toStringAsFixed(0)}%'),
                leading: CircleAvatar(
                  backgroundColor:
                      p.isLow ? DukaColors.surfaceWarm : DukaColors.surface,
                  child: Text('${p.stockQty}',
                      style: TextStyle(
                          fontSize: 12,
                          color: p.isLow
                              ? DukaColors.danger
                              : DukaColors.success)),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _openEditor(p);
                    if (v == 'adjust') _adjustStock(p);
                    if (v == 'delete') _delete(p);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                        value: 'adjust', child: Text('Adjust stock')),
                    if (isOwner)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProductEditor extends StatefulWidget {
  final Product? existing;
  final VoidCallback onSaved;
  const _ProductEditor({this.existing, required this.onSaved});
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  late final TextEditingController _name,
      _category,
      _cost,
      _price,
      _stock,
      _reorder,
      _stamp,
      _bottleMl,
      _halfPrice,
      _quarterPrice;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _cost.dispose();
    _price.dispose();
    _stock.dispose();
    _reorder.dispose();
    _stamp.dispose();
    _bottleMl.dispose();
    _halfPrice.dispose();
    _quarterPrice.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    _cost = TextEditingController(text: e?.costPrice.toString() ?? '');
    _price = TextEditingController(text: e?.sellPrice.toString() ?? '');
    _stock = TextEditingController(text: e?.stockQty.toString() ?? '');
    _reorder = TextEditingController(text: e?.reorderLevel.toString() ?? '5');
    _stamp = TextEditingController(text: e?.exciseStampBatch ?? '');
    _bottleMl = TextEditingController(text: e?.bottleMl.toString() ?? '750');
    _halfPrice = TextEditingController(text: e?.halfPrice?.toString() ?? '');
    _quarterPrice =
        TextEditingController(text: e?.quarterPrice?.toString() ?? '');
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final category =
        _category.text.trim().isEmpty ? 'General' : _category.text.trim();

    final cost = double.tryParse(_cost.text.trim());
    final price = double.tryParse(_price.text.trim());
    final stock = double.tryParse(_stock.text.trim());
    final reorder = int.tryParse(_reorder.text.trim());
    final bottleMl = int.tryParse(_bottleMl.text.trim());
    final halfPrice = _halfPrice.text.trim().isEmpty
        ? null
        : double.tryParse(_halfPrice.text.trim());
    final quarterPrice = _quarterPrice.text.trim().isEmpty
        ? null
        : double.tryParse(_quarterPrice.text.trim());

    // Single shared rule set, identical to the Excel and Sheets importers, so
    // the editor cannot persist a row the app's own backup format rejects.
    final problem = Product.validate(
      name: name,
      category: category,
      costPrice: cost ?? double.nan,
      sellPrice: price ?? double.nan,
      stockQty: stock ?? double.nan,
      reorderLevel: reorder ?? -1,
      bottleMl: bottleMl ?? 0,
      halfPrice: halfPrice,
      quarterPrice: quarterPrice,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    // The shared validator has already rejected null/NaN for these fields.
    if (price! < cost!) {
      final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Sell price is below cost'),
                content: Text(
                    '$name would sell at a loss (KSh $price vs cost KSh $cost). Save anyway?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Go back')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save anyway')),
                ],
              ));
      if (proceed != true) return;
    }

    setState(() => _error = null);
    final product = Product(
      id: widget.existing?.id,
      name: name,
      category: category,
      costPrice: cost,
      sellPrice: price,
      stockQty: stock!,
      reorderLevel: reorder!,
      bottleMl: bottleMl!,
      halfPrice: halfPrice,
      quarterPrice: quarterPrice,
      exciseStampBatch: _stamp.text.trim(),
      updatedAt: DateTime.now().toIso8601String(),
      remoteId: widget.existing?.remoteId,
    );
    try {
      await DatabaseHelper.instance.upsertProduct(product);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
      // Push just this row to the backend after the editor closes. A price
      // change left only on the till would let the next till — or the web
      // report — keep selling at the old price until the next auto-sync, which
      // is up to six hours away. Best effort: a failed push is retried by the
      // next bulk sync, and must not turn a local save into an error.
      unawaited(_pushProductInBackground(product));
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            "Couldn't save — check the phone has storage space free, then try again.");
      }
    }
  }

  /// Pushes the saved row to the backend, re-reading it so the local id and any
  /// newly assigned remote id are included.
  static Future<void> _pushProductInBackground(Product saved) async {
    try {
      if (saved.id == null) return;
      final all = await DatabaseHelper.instance.getProducts(activeOnly: false);
      final fresh = all.where((p) => p.id == saved.id).firstOrNull;
      await BackendService.syncProductToBackend(fresh ?? saved);
    } catch (_) {
      // Offline, unlinked or the backend rejected it: the bulk auto-sync path
      // will pick the change up. Never block the local save on the network.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null ? 'Add product' : 'Edit product',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category')),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _cost,
                        decoration:
                            const InputDecoration(labelText: 'Cost price'),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _price,
                        decoration:
                            const InputDecoration(labelText: 'Sell price'),
                        keyboardType: TextInputType.number)),
              ]),
              TextField(
                  controller: _bottleMl,
                  decoration:
                      const InputDecoration(labelText: 'Full bottle size (ml)'),
                  keyboardType: TextInputType.number),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _halfPrice,
                        decoration: const InputDecoration(
                            labelText: 'Half price (optional)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _quarterPrice,
                        decoration: const InputDecoration(
                            labelText: 'Quarter price (optional)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
              ]),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _stock,
                        decoration:
                            const InputDecoration(labelText: 'Stock qty'),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _reorder,
                        decoration:
                            const InputDecoration(labelText: 'Reorder level'),
                        keyboardType: TextInputType.number)),
              ]),
              TextField(
                  controller: _stamp,
                  decoration: const InputDecoration(
                      labelText: 'Excise stamp batch (optional)')),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _save, child: const Text('Save product')),
              const SizedBox(height: 16),
            ]),
      ),
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  final Product product;
  const _AdjustDialog({required this.product});
  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _delta = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _delta.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Adjust stock — ${widget.product.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: _delta,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(
                labelText: 'Change (+50 restock, -2 breakage)')),
        TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason')),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, {'delta': _delta.text, 'reason': _reason.text}),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
