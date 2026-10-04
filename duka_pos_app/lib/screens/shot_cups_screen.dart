// Configuring the fixed shot cups a till sells.
//
// A shot is the third way a drink can be sold, alongside a whole bottle and a
// variant. It is not a variant because it has no stock of its own — it is poured
// out of the parent bottle, and the stock that moves is the parent's. It is not a
// portion because 30 ml is neither a half nor a quarter.
//
// So a cup is a small configuration in its own right: which spirit it comes
// from, how many millilitres it holds, and what it costs. Those three answers
// are what the till needs to price a shot and to know how much of the bottle it
// just used, and they belong to the shop rather than to the product, which is
// why they are not another column on `products`.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import 'home_shell.dart';

/// Manages the shot cups a till can pour.
class ShotCupsScreen extends StatefulWidget {
  const ShotCupsScreen({super.key});

  @override
  State<ShotCupsScreen> createState() => _ShotCupsScreenState();
}

class _ShotCupsScreenState extends State<ShotCupsScreen> {
  List<ShotCup> _cups = const [];
  List<Product> _products = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    // Inactive cups too, so an owner can bring one back rather than finding it
    // gone and having to re-enter it.
    final cups = await db.getShotCups(activeOnly: false);
    final products = await db.getProducts(activeOnly: false);
    if (!mounted) return;
    setState(() {
      _cups = cups;
      _products = products;
      _loading = false;
    });
  }

  Future<void> _edit([ShotCup? existing]) async {
    final saved = await showModalBottomSheet<ShotCup>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ShotCupEditor(
        cup: existing,
        products: _products,
      ),
    );
    if (saved == null) return;
    // A new or changed cup has to reach the till, which is kept alive and would
    // otherwise keep offering the old shelf.
    if (mounted) context.read<HomeShellTabs>().markCatalogueChanged();
    await _load();
  }

  /// Soft-deletes, after asking.
  ///
  /// Soft rather than hard because the cup is referenced by nothing that has to
  /// be freed — a sale records the folded name and the capacity it was poured
  /// at — so removing it costs only the ability to pour it again. A cup that
  /// was sold from stays off the shelf and off the till.
  Future<void> _remove(ShotCup cup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Stop selling ${cup.label}?'),
        content: Text(
            '${cup.productName} shots stop appearing at the till. Sales already recorded are untouched.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop selling'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseHelper.instance.deleteShotCup(cup.id!);
    await _load();
  }

  /// How many shots one container of [product] yields at [cup]'s capacity.
  ///
  /// Null when the arithmetic does not work — a countable product has no
  /// millilitres to divide, and a cup bigger than its bottle yields nothing.
  /// Returning null rather than zero is what lets the list say *why* instead of
  /// showing a confident "0 shots per bottle".
  static int? shotsPerBottle(Product product, ShotCup cup) {
    if (cup.capacityMl <= 0 || product.bottleMl <= 0) return null;
    if (product.unit == ProductUnit.each) return null;
    return product.bottleMl ~/ cup.capacityMl;
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<AppState>().canManageStock;
    return Scaffold(
      appBar: AppBar(title: const Text('Shot cups')),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: () => _edit(),
              tooltip: 'Add a shot cup',
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _cups.isEmpty
                  ? _EmptyShots(canEdit: canEdit, onAdd: () => _edit())
                  : ListView.builder(
                      itemCount: _cups.length,
                      itemBuilder: (context, i) => _cupTile(_cups[i], canEdit),
                    ),
            ),
    );
  }

  Widget _cupTile(ShotCup cup, bool canEdit) {
    final product = _products.where((p) => p.id == cup.productId).firstOrNull;
    final perBottle = product == null ? null : shotsPerBottle(product, cup);
    final title = '${cup.label} · ${cup.capacityMl} ml';
    final detail = <String>[
      cup.productName,
      formatMoney(cup.price),
      // Said only when it can be worked out. "0 shots in the bottle" would look
      // like an out-of-stock bar; "the cup is bigger than the bottle" is the
      // truth and is fixable.
      if (perBottle != null) '$perBottle per bottle',
    ].join(' · ');

    return Semantics(
      label: '$title, $detail${cup.active ? '' : ', not sold'}',
      child: ListTile(
        title: Text(title),
        subtitle: Text(detail),
        leading: Icon(
          cup.active ? Icons.local_drink_outlined : Icons.remove_circle_outline,
          color: cup.active ? null : Theme.of(context).disabledColor,
        ),
        trailing: canEdit
            ? PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _edit(cup);
                  if (v == 'remove') _remove(cup);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                      value: 'remove', child: Text('Stop selling')),
                ],
              )
            : null,
        onTap: canEdit ? () => _edit(cup) : null,
      ),
    );
  }
}

/// Nothing configured yet.
class _EmptyShots extends StatelessWidget {
  const _EmptyShots({required this.canEdit, required this.onAdd});

  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 64),
        Icon(Icons.local_drink_outlined,
            size: 56, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            canEdit
                ? 'No shot cups yet. Add one to sell fixed-size shots of any drink in your inventory.'
                : 'No shot cups have been set up for this shop.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (canEdit) ...[
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add a shot cup'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Creates or edits one cup.
class _ShotCupEditor extends StatefulWidget {
  const _ShotCupEditor({required this.cup, required this.products});

  final ShotCup? cup;
  final List<Product> products;

  @override
  State<_ShotCupEditor> createState() => _ShotCupEditorState();
}

class _ShotCupEditorState extends State<_ShotCupEditor> {
  late final TextEditingController _capacity;
  late final TextEditingController _price;
  late final TextEditingController _label;
  int? _productId;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.cup?.id == null;

  /// Drink-shaped products only.
  ///
  /// A shot is a pour, so it needs something to pour. Offering a countable
  /// product would let an owner save a cup that can never be served, and the
  /// till would then offer it and fail at checkout.
  List<Product> get _drinkable =>
      widget.products.where((p) => p.unit != ProductUnit.each).toList();

  /// What the dropdown actually offers.
  ///
  /// The drinkable products, plus the one this cup is already attached to even if
  /// it is no longer one of them. A spirit switched to "each" after its cup was
  /// configured would otherwise leave the field holding a value that is not in
  /// the list, which is an assertion rather than a message — the owner editing
  /// the cup's price would crash instead of being told why.
  ///
  /// Kept selectable so they can move the cup to a real drink; the warning is in
  /// the label rather than in a disabled row, which would be a dead end.
  List<Product> get _options {
    final options = _drinkable;
    final currentId = widget.cup?.productId;
    if (currentId == null) return options;
    if (options.any((p) => p.id == currentId)) return options;
    final current =
        widget.products.where((p) => p.id == currentId).firstOrNull;
    return current == null ? options : [...options, current];
  }

  @override
  void initState() {
    super.initState();
    final cup = widget.cup;
    _productId = cup?.productId;
    _capacity = TextEditingController(
        text: cup == null ? '' : cup.capacityMl.toString());
    // Prices are stored as `Money`, never `double`. `Money.toString()` is the
    // debug representation in minor units, and seeding a field with it produced
    // an unreadable, unparseable price — the same trap the product editor hit.
    _price =
        TextEditingController(text: cup == null ? '' : _majorText(cup.price));
    _label = TextEditingController(text: cup?.label ?? 'Shot');
  }

  @override
  void dispose() {
    _capacity.dispose();
    _price.dispose();
    _label.dispose();
    super.dispose();
  }

  static String _majorText(Money value) {
    final major = value.minorUnits ~/ kMinorUnitsPerMajor;
    final cents = value.minorUnits % kMinorUnitsPerMajor;
    return cents == 0 ? '$major' : '$major.${cents.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_saving) return;
    final productId = _productId;
    if (productId == null) {
      setState(() => _error = 'Choose the drink this shot is poured from.');
      return;
    }
    final capacity = int.tryParse(_capacity.text.trim());
    if (capacity == null) {
      setState(() => _error = 'Capacity must be whole millilitres — 30, 45.');
      return;
    }
    if (capacity <= 0) {
      setState(() => _error = 'Capacity must be more than zero.');
      return;
    }
    if (capacity > Product.maxBottleMl) {
      setState(
          () => _error = 'Capacity must be ${Product.maxBottleMl} ml or less.');
      return;
    }
    final price = double.tryParse(_price.text.trim());
    if (price == null || !Money.isValidMajor(price)) {
      setState(() => _error = 'Price must be a number, 0 or more.');
      return;
    }
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Give the cup a name, like Shot or Double.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final product = _drinkable.where((p) => p.id == productId).firstOrNull ??
        widget.products.where((p) => p.id == productId).firstOrNull;
    final cup = ShotCup(
      id: widget.cup?.id,
      productId: productId,
      // The name is stored, not joined, so the cup survives the spirit being
      // renamed or removed and the till can still explain what it poured.
      productName: product?.name ?? widget.cup?.productName ?? '',
      capacityMl: capacity,
      price: Money.fromMajor(price),
      label: label,
      // Editing a cup that was stopped selling brings it back, rather than
      // silently leaving it off the till after the owner re-priced it.
      active: true,
      updatedAt: DateTime.now().toIso8601String(),
    );
    try {
      await DatabaseHelper.instance.upsertShotCup(cup);
      if (!mounted) return;
      Navigator.pop(context, cup);
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save the cup. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isNew ? 'Add a shot cup' : 'Edit shot cup',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (options.isEmpty)
              // Said rather than an empty dropdown: a shop with nothing measured
              // in millilitres cannot pour a shot, and that is worth saying once
              // instead of leaving a control that accepts anything.
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No drinks in millilitres yet. Set a product\'s unit to cup '
                  'or litre in Inventory first — a shot is a pour, so it needs '
                  'something to pour.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _productId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Poured from'),
                items: [
                  for (final p in options)
                    DropdownMenuItem(
                      value: p.id,
                      // A product that has since become countable is still
                      // listed, labelled with why it cannot be poured, rather
                      // than silently vanishing from under the selection.
                      child: Text(
                        p.unit == ProductUnit.each
                            ? '${p.name} · no volume set'
                            : '${p.name} · ${p.bottleMl} ml',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _productId = id),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _capacity,
                  autofocus: _isNew,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Capacity (ml)',
                    hintText: '30',
                    helperText: 'Fixed for this cup',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    helperText: 'For one shot',
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Name at the till',
                hintText: 'Shot, Double, Slim',
                helperText: 'What the cashier taps',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving || options.isEmpty ? null : _submit,
              child: Text(_isNew ? 'Add cup' : 'Save cup'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
