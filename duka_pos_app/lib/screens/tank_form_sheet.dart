/// A tank: a big container of something you pour out and sell by the cup.
///
/// ## WHAT THIS IS NOW
///
/// A tank used to be a beer-specific form: it asked what beer, how many taps,
/// how much in each tap, and a millilitres-per-kilogram factor — and it came
/// pre-filled with "Dark" and "Regular". A shop that keeps anything else in a
/// drum (soda, juice, cooking oil) had to answer questions about beer to add
/// it, and a shop that did understand the questions still met words like
/// "capacity" and "factor" that belong in a manual, not on a till.
///
/// It is a simple form now. Five things, in the words a shop uses:
///
///   * what is in the tank;
///   * how much the tank holds;
///   * what one full tank cost;
///   * how many full tanks are on the shelf;
///   * the cups it is sold in — each with a name, a size and a price, and the
///     size may be left out if the shop does not measure it.
///
/// Nothing is pre-filled: every box is the owner's own answer. The form can be
/// opened again and again to add as many tanks as the shop has.
///
/// ## THE TANK IS NEVER SOLD WHOLE
///
/// The `products` row a tank writes carries a sell price of ZERO. That is not
/// a missing number — it is the rule. A drum of soda is not an item a customer
/// buys at the counter; the CUPS are the items. The till reads a product's
/// price to decide whether "the whole thing" is on offer (`sellsWhole`), so a
/// zero price takes the tank out of the sale list and out of the sales
/// analytics, and leaves only its cups — which are ordinary priced servings
/// and are counted, and earn their profit, exactly like any other sale.
///
/// ## THE CUPS ARE THE STOCK
///
/// A cup sale deducts `cup ml ÷ tank capacity` from the tank count, through
/// the same measured-pour path a shot of a bottle uses. A 50-litre drum of
/// 100 cups-poured-out reads as 100 cups gone, not one. A cup whose size the
/// owner left empty is still sold at its price; the app simply does not guess
/// how much it took, and says so.
///
/// ## THE PROFIT IS PER CUP
///
/// Profit is not computed for the tank. It is computed for each cup the way it
/// is for every other sale — the cup's price minus the cup's share of what
/// the tank cost — because the cost lives in the liquid, and the liquid leaves
/// in cups.
library;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/stock_movement.dart';
import '../routing/home_shell.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../utils/crypto_utils.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../ui/components/screen_title.dart';

/// The category a tank's product row is filed under.
///
/// A fixed name rather than a picker: the tank is not a thing anybody shops
/// for by category, and a category the owner has to type is a category they
/// will get wrong. It is also what makes a tank findable later — the stock
/// list can show "the drums" as one group.
const String kTankCategory = 'Tanks';

/// Opens the tank form.
Future<void> showTankFormSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) => const TankFormSheet(),
  );
}

/// One way the tank is sold: a cup, a glass, anything the owner names.
class TankServingValues {
  const TankServingValues({
    required this.label,
    required this.sizeMl,
    required this.price,
  });

  /// What the serving is called: "Small cup", "Big cup", "Glass".
  final String label;

  /// How much is in one, in millilitres. ZERO means the owner did not say,
  /// which is allowed: the cup is still sold, only what it takes out of the
  /// tank is not counted.
  final int sizeMl;

  /// What one sells for, in shillings.
  final double price;
}

/// A whole tank, as the numbers the form collected.
class TankValues {
  const TankValues({
    required this.name,
    required this.capacityMl,
    required this.tankCount,
    required this.cost,
    required this.servings,
  });

  /// What is in the tank.
  final String name;

  /// How much the tank holds when it is full, in millilitres.
  final int capacityMl;

  /// How many full tanks the shop has.
  final int tankCount;

  /// What one full tank cost.
  final double cost;

  /// The cups it is sold in.
  final List<TankServingValues> servings;
}

/// Writes a tank: one product row, and one cup row per serving.
///
/// ## ONE TRANSACTION, OR NOTHING
///
/// A tank is several rows that only mean something together: the container and
/// the cups poured from it. A half-written tank is a drum with no cups to sell
/// it by — and the shop finds out at the till, with a customer waiting.
///
/// ## THE STOCK IS IN TANKS
///
/// `stock_qty` counts tanks, not litres, because that is what the owner thinks
/// in ("I have two drums left"). A cup sale takes its own fraction out of it
/// through the measured-pour path, so 330 ml out of a 50-litre drum is 330/50000
/// of a tank.
Future<void> saveTank(Database database, TankValues values) async {
  await database.transaction((txn) async {
    final int productId = await txn.insert('products', <String, Object?>{
      'name': values.name,
      'category': kTankCategory,
      'cost_price': Money.fromMajor(values.cost).minorUnits,
      // Zero on purpose: a tank is never sold whole — only the cups are.
      'sell_price': 0,
      'stock_qty': values.tankCount.toDouble(),
      'reorder_level': 0,
      'bottle_ml': values.capacityMl,
      // The tank is a pourable product. It is never sold whole; its cups are
      // the configured servings, and the unit keeps it volumetric on every
      // other till after catalogue sync.
      'unit': ProductUnit.cup.wire,
      // 0, not false: sqflite carries no boolean, and a bool handed to it is a
      // type error at the moment of the write.
      'track_variants': 0,
      'active': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // The tank is a product with an opening balance, not an exception to the
    // stock ledger. Keep this in the same transaction as the product and its
    // servings so a newly-created tank is immediately reconcileable and its
    // baseline can be sent to the backend on the first product sync.
    await txn.insert('stock_movements', <String, Object?>{
      'uuid': generateUuid(),
      'created_at': DateTime.now().toIso8601String(),
      'product_id': productId,
      'variant_id': null,
      'movement_type': StockMovementType.opening.wire,
      'qty_delta': values.tankCount.toDouble(),
      'unit_cost_minor': null,
      'reference_type': null,
      'reference_id': null,
      'batch_id': null,
      'staff_id': null,
      'staff_name': null,
      'note': 'Opening balance',
      'balance_after': values.tankCount.toDouble(),
    });

    for (final TankServingValues serving in values.servings) {
      await txn.insert('shot_cups', <String, Object?>{
        'product_id': productId,
        'product_name': values.name,
        'capacity_ml': serving.sizeMl,
        'price': Money.fromMajor(serving.price).minorUnits,
        'label': serving.label,
        'active': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  });
}

class TankFormSheet extends StatefulWidget {
  const TankFormSheet({super.key});

  @override
  State<TankFormSheet> createState() => _TankFormSheetState();
}

/// One serving row's controllers. Empty by default — the owner fills it in.
class _ServingState {
  final TextEditingController name = TextEditingController();
  final TextEditingController sizeMl = TextEditingController();
  final TextEditingController price = TextEditingController();

  void dispose() {
    name.dispose();
    sizeMl.dispose();
    price.dispose();
  }
}

class _TankFormSheetState extends State<TankFormSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _capacityCtrl = TextEditingController();
  final TextEditingController _countCtrl = TextEditingController();
  final TextEditingController _costCtrl = TextEditingController();

  /// Starts with ONE empty cup row: the form asks how the tank is sold, and
  /// an empty list would be a question with nowhere to answer it. Nothing is
  /// pre-filled — the name, the size and the price are all the owner's.
  final List<_ServingState> _servings = <_ServingState>[_ServingState()];

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    _countCtrl.dispose();
    _costCtrl.dispose();
    for (final _ServingState serving in _servings) {
      serving.dispose();
    }
    super.dispose();
  }

  int? get _capacityMl {
    final litres = _finite(double.tryParse(_capacityCtrl.text.trim()));
    if (litres == null || litres <= 0) return null;
    return litresToMillilitres(litres).round();
  }

  int? get _tankCount {
    final value = int.tryParse(_countCtrl.text.trim());
    // A product can be created before the delivery arrives. Zero is a real
    // opening balance; the owner can then record the delivery through the
    // ordinary manual receiving flow without inventing stock.
    if (value == null || value < 0) return null;
    return value;
  }

  double? get _cost {
    final value = _finite(double.tryParse(_costCtrl.text.trim()));
    if (value == null || value < 0) return null;
    return value;
  }

  static double? _finite(double? value) =>
      value != null && value.isFinite ? value : null;

  void _addServing() {
    setState(() => _servings.add(_ServingState()));
  }

  void _removeServing(int index) {
    setState(() {
      _servings.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    final capacityMl = _capacityMl;
    final tankCount = _tankCount;
    final cost = _cost;

    if (name.isEmpty) {
      setState(() => _error = l10n.tankNameRequired);
      return;
    }
    if (capacityMl == null) {
      setState(() => _error = l10n.tankCapacityInvalid);
      return;
    }
    if (tankCount == null) {
      setState(() => _error = l10n.tankCountRequired);
      return;
    }
    if (cost == null) {
      setState(() => _error = l10n.tankPriceInvalid);
      return;
    }
    if (_servings.isEmpty) {
      setState(() => _error = l10n.tankServingMinOne);
      return;
    }

    final servings = <TankServingValues>[];
    for (final _ServingState serving in _servings) {
      final label = serving.name.text.trim();
      if (label.isEmpty) {
        setState(() => _error = l10n.tankServingNameRequired);
        return;
      }
      final priceText = serving.price.text.trim();
      final price = _finite(double.tryParse(priceText));
      if (price == null || price < 0) {
        setState(() => _error = l10n.tankServingPriceInvalid);
        return;
      }
      // The size may be left out. An empty box is "I do not measure it", not
      // a mistake; anything that is not a whole positive number is.
      final sizeText = serving.sizeMl.text.trim();
      int sizeMl = 0;
      if (sizeText.isNotEmpty) {
        final parsed = int.tryParse(sizeText);
        if (parsed == null || parsed < 0) {
          setState(() => _error = l10n.tankServingSizeInvalid);
          return;
        }
        sizeMl = parsed;
      }
      // A cup bigger than the drum it comes out of is a typed mistake, and it
      // is cheap to catch here and expensive to discover in the stock count.
      if (sizeMl > capacityMl) {
        setState(() => _error = l10n.tankServingTooBig);
        return;
      }
      servings.add(
        TankServingValues(label: label, sizeMl: sizeMl, price: price),
      );
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final database = await DatabaseHelper.instance.database;
      await saveTank(
        database,
        TankValues(
          name: name,
          capacityMl: capacityMl,
          tankCount: tankCount,
          cost: cost,
          servings: servings,
        ),
      );

      markCatalogueChanged();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tankCreated(name))),
      );
    } catch (_) {
      if (mounted) setState(() => _error = l10n.tankSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);
    final shapes = AppShapes.of(context);
    final type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.lg,
        end: spacing.lg,
        top: spacing.lg,
        bottom: spacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The sheet's NAME, large and on the canvas — the same title block
            // every other screen opens with.
            ScreenTitle(
              title: l10n.tankFormTitle,
              subtitle: l10n.tankFormSubtitle,
              padding: EdgeInsets.zero,
            ),
            SizedBox(height: spacing.lg),
            _field(_nameCtrl, l10n.tankFieldName, l10n.tankFieldNameHint),
            SizedBox(height: spacing.md),
            _field(
              _capacityCtrl,
              l10n.tankFieldCapacityL,
              l10n.tankFieldCapacityLHint,
              const TextInputType.numberWithOptions(decimal: true),
            ),
            SizedBox(height: spacing.md),
            _field(
              _costCtrl,
              l10n.tankFieldTankCost,
              l10n.tankFieldTankCostHint,
              const TextInputType.numberWithOptions(decimal: true),
            ),
            SizedBox(height: spacing.md),
            _field(
              _countCtrl,
              l10n.tankFieldTankCount,
              l10n.tankFieldTankCountHint,
              const TextInputType.numberWithOptions(decimal: false),
            ),
            SizedBox(height: spacing.lg),
            Text(l10n.tankServingsTitle, style: type.titleMedium),
            SizedBox(height: spacing.xs),
            Text(l10n.tankServingsHint, style: type.bodySmall),
            SizedBox(height: spacing.sm),
            for (var i = 0; i < _servings.length; i++) ...<Widget>[
              _servingRow(context, l10n, spacing, i),
              SizedBox(height: spacing.sm),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _addServing,
                icon: const Icon(Icons.add),
                label: Text(l10n.tankServingAdd),
              ),
            ),
            if (_error != null) ...<Widget>[
              SizedBox(height: spacing.md),
              Text(
                _error!,
                style: type.bodyMedium
                    ?.copyWith(color: AppColors.of(context).danger),
              ),
            ],
            SizedBox(height: spacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, spacing.minTapTarget),
                  shape: RoundedRectangleBorder(
                    borderRadius: shapes.controlRadius,
                  ),
                ),
                child: Text(_saving ? l10n.pinResetSaving : l10n.tankAddAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One cup row: a name, a size that may be left out, and a price.
  Widget _servingRow(
    BuildContext context,
    AppLocalizations l10n,
    AppSpacing spacing,
    int index,
  ) {
    final serving = _servings[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(l10n.tankServingLabel(index + 1))),
            // A row can only be removed while at least one is left standing:
            // a tank with no cups cannot be sold at all.
            if (_servings.length > 1)
              IconButton(
                tooltip: l10n.tankServingRemove,
                onPressed: () => _removeServing(index),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        SizedBox(height: spacing.xs),
        _field(serving.name, l10n.tankFieldServingName,
            l10n.tankFieldServingNameHint),
        SizedBox(height: spacing.xs),
        Row(
          children: <Widget>[
            Expanded(
              child: _field(
                serving.sizeMl,
                l10n.tankFieldServingMl,
                l10n.tankFieldServingMlHint,
                const TextInputType.numberWithOptions(decimal: false),
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: _field(
                serving.price,
                l10n.tankFieldServingPrice,
                l10n.tankFieldServingPriceHint,
                const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      [String? hint, TextInputType? keyboard]) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
      ),
      keyboardType: keyboard,
      onChanged: (_) => setState(() {}),
    );
  }
}
