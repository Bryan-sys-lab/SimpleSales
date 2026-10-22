/// A tank of beer: stocked by the tank, poured by the keg cup.
///
/// A tank is a different SHAPE of thing from a bottled product. Its stock
/// arrives by weight on a scale, its capacity is in litres, and it holds named
/// taps that are poured and priced separately. Nothing about a tank is a
/// bottle: there is no `bottle_ml`, no tank sell price, and no shot cup.
///
/// What it writes is ordinary catalogue, deliberately:
///
///   * one `products` row per tap, `unit = millilitre`, whose `bottle_ml` is
///     the tank capacity in millilitres and whose `stockQty` is how many tanks
///     there are (1.0 = one tank, 0.5 = half a tank);
///   * two keg-cup rows per tap — Small and Big — each with its own price, each
///     deducting `cup ml ÷ tank capacity ml` from one shared tank stock.
///
/// There is no tank sell price: a tank is never sold whole. Only keg cups are
/// sold, at the small or big cup price, and profit is computed per cup from the
/// tank cost ÷ tank capacity × cup ml.
library;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/home_shell.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../ui/components/controls.dart';
import '../ui/components/screen_title.dart';

/// How many taps a tank has.
const int kTankTapCount = 2;

/// Default serving sizes, in millilitres.
const int kSmallCupMl = 330;
const int kBigCupMl = 500;

/// The ceiling on a millilitres-per-kilogram factor.
const double kMaxMillilitresPerKilogram = 100000;

/// Opens the tank form.
Future<void> showTankFormSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) => const TankFormSheet(),
  );
}

class TankFormSheet extends StatefulWidget {
  const TankFormSheet({super.key});

  @override
  State<TankFormSheet> createState() => _TankFormSheetState();
}

/// One tap's worth of state: a name, an amount loaded, and the small/big keg
/// cup sizes and prices.
class _TapState {
  final TextEditingController name = TextEditingController();
  final TextEditingController amount = TextEditingController();
  final TextEditingController smallMl =
      TextEditingController(text: kSmallCupMl.toString());
  final TextEditingController smallPrice = TextEditingController();
  final TextEditingController bigMl =
      TextEditingController(text: kBigCupMl.toString());
  final TextEditingController bigPrice = TextEditingController();
  bool isLitres = true;

  void dispose() {
    name.dispose();
    amount.dispose();
    smallMl.dispose();
    smallPrice.dispose();
    bigMl.dispose();
    bigPrice.dispose();
  }
}

/// One tap of a tank, as the numbers the form collected.
class TankTapValues {
  const TankTapValues({
    required this.name,
    required this.loadMl,
    required this.smallMl,
    required this.smallPrice,
    required this.bigMl,
    required this.bigPrice,
  });

  /// What this tap is called.
  final String name;

  /// How much of the tank is in this tap, in millilitres.
  final double loadMl;

  /// How much is in one small cup, in millilitres.
  final int smallMl;

  /// What one small cup sells for.
  final double smallPrice;

  /// How much is in one big cup, in millilitres.
  final int bigMl;

  /// What one big cup sells for.
  final double bigPrice;
}

/// A whole tank, as the numbers the form collected.
class TankValues {
  const TankValues({
    required this.name,
    required this.capacityMl,
    required this.tankCount,
    required this.cost,
    required this.taps,
  });

  /// The beer the tank holds.
  final String name;

  /// How much the tank holds when it is full.
  final int capacityMl;

  /// How many full tanks the shop has.
  final int tankCount;

  /// What one full tank cost.
  final double cost;

  /// The taps it is tapped into.
  final List<TankTapValues> taps;
}

/// Writes a tank: one product per tap, and two cup rows per tap.
///
/// ## ONE TRANSACTION, OR NOTHING
///
/// A tank is several rows that only mean anything together: the tap product,
/// its small cup and its big cup. A half-written tank is a product with no
/// cups, or a cup pointing at a product that is not there — and the shop
/// finds out at the till, when the drink it has sold cannot be poured.
///
/// ## THE LOAD IS THE POINT
///
/// A tap holds PART of the tank. Two taps on one tank split the beer between
/// them, and a tap that has been emptied holds none.
///
/// So the stock of a tap is the share of the tank that is in it: a tap with
/// half a tank in it can pour half as many cups as a tap with a whole one,
/// and a tap with nothing in it can pour none. The cost follows the beer for
/// the same reason — the money is in the millilitres, so a tap holding a
/// quarter of the tank carries a quarter of the tank's cost. It comes out
/// the same as an even split whenever the taps are even, and it is right when
/// they are not.
///
/// The stock is in TANKS, because that is what a cup sale deducts from: a
/// 330 ml cup out of a 50-litre tank takes 330/50000 of a tank, and the
/// ledger, the reports and the stock count all speak in tanks.
Future<void> saveTank(
  Database database,
  TankValues values, {
  required String smallCupLabel,
  required String bigCupLabel,
}) async {
  await database.transaction((txn) async {
    for (final TankTapValues tap in values.taps) {
      final double share =
          values.capacityMl == 0 ? 0.0 : tap.loadMl / values.capacityMl;
      final double stockQty = values.tankCount * share;
      final double perTapCost = values.cost * share;
      final String productName = '${values.name} — ${tap.name}';

      final int productId = await txn.insert('products', <String, Object?>{
        'name': productName,
        'category': 'Beer',
        'cost_price': Money.fromMajor(perTapCost).minorUnits,
        // A tank is never sold whole — only keg cups are sold at the small
        // or big cup price. sell_price stays 0; profit is per cup.
        'sell_price': 0,
        'stock_qty': stockQty,
        'reorder_level': 0,
        'bottle_ml': values.capacityMl,
        'unit': ProductUnit.millilitre.wire,
        // 0, not false: sqflite carries no boolean, and a bool handed to it
        // is a type error at the moment of the write.
        'track_variants': 0,
        'active': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Small cup.
      await txn.insert('shot_cups', <String, Object?>{
        'product_id': productId,
        'product_name': productName,
        'capacity_ml': tap.smallMl,
        'price': Money.fromMajor(tap.smallPrice).minorUnits,
        'label': smallCupLabel,
        'active': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Big cup.
      await txn.insert('shot_cups', <String, Object?>{
        'product_id': productId,
        'product_name': productName,
        'capacity_ml': tap.bigMl,
        'price': Money.fromMajor(tap.bigPrice).minorUnits,
        'label': bigCupLabel,
        'active': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  });
}

class _TankFormSheetState extends State<TankFormSheet> {
  final TextEditingController _tankNameCtrl = TextEditingController();
  final TextEditingController _capacityLitresCtrl = TextEditingController();
  final TextEditingController _tankCountCtrl = TextEditingController();
  final TextEditingController _tankCostCtrl = TextEditingController();
  final TextEditingController _mlPerKgCtrl = TextEditingController();

  final _taps = <_TapState>[_TapState(), _TapState()];

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Beer default: a litre of lager weighs a kilogram.
    _mlPerKgCtrl.text = defaultKilogramsToMillilitres.round().toString();
    _taps[0].name.text = 'Dark';
    _taps[1].name.text = 'Regular';
  }

  @override
  void dispose() {
    _tankNameCtrl.dispose();
    _capacityLitresCtrl.dispose();
    _tankCountCtrl.dispose();
    _tankCostCtrl.dispose();
    _mlPerKgCtrl.dispose();
    for (final tap in _taps) {
      tap.dispose();
    }
    super.dispose();
  }

  double? get _capacityL {
    final text = _capacityLitresCtrl.text.trim();
    if (text.isEmpty) return null;
    return _finite(double.tryParse(text));
  }

  int? get _capacityMl {
    final litres = _capacityL;
    if (litres == null || !litres.isFinite) return null;
    final ml = litresToMillilitres(litres);
    if (ml <= 0) return null;
    return ml.round();
  }

  int? get _tankCount {
    final text = _tankCountCtrl.text.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value <= 0) return null;
    return value;
  }

  double? get _tankCostValue {
    final text = _tankCostCtrl.text.trim();
    if (text.isEmpty) return null;
    return _finite(double.tryParse(text));
  }

  double? get _perKg {
    final text = _mlPerKgCtrl.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value <= 0) return null;
    if (value > kMaxMillilitresPerKilogram) return null;
    return value;
  }

  static double? _finite(double? value) =>
      value != null && value.isFinite ? value : null;

  /// One tap's load converted to millilitres, using its own unit choice.
  double? _tapMl(_TapState tap) {
    final text = tap.amount.text.trim();
    if (text.isEmpty) return null;
    final value = _finite(double.tryParse(text));
    if (value == null || value < 0) return null;
    return tap.isLitres ? litresToMillilitres(value) : value;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _tankNameCtrl.text.trim();
    final capacityMl = _capacityMl;
    final tankCount = _tankCount;
    final tankCost = _tankCostValue;
    final perKg = _perKg;

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
    if (tankCost == null || !tankCost.isFinite || tankCost < 0) {
      setState(() => _error = l10n.tankPriceInvalid);
      return;
    }
    if (perKg == null) {
      setState(() => _error = l10n.tankMlPerKgInvalid);
      return;
    }

    // Validate every tap before touching the database.
    final tapLoads = <double>[];
    for (final tap in _taps) {
      final tapName = tap.name.text.trim();
      if (tapName.isEmpty) {
        setState(() => _error = l10n.tankTapNameRequired);
        return;
      }
      final tapMl = _tapMl(tap);
      if (tapMl == null || tapMl < 0) {
        setState(() => _error = l10n.tankTapAmountInvalid);
        return;
      }
      // A tap cannot hold more than the tank it is part of.
      //
      // It is not a strange thing to type: a tap is filled from the tank, and
      // a person who has just written "50" for the tank and "50" for the tap
      // has made a mistake the form can catch in a second. Without the check
      // the tank is saved with a tap that holds more beer than the tank does,
      // and the error only shows up later as a stock count that will not add
      // up.
      if (tapMl > capacityMl) {
        setState(() => _error = l10n.tankTapOverCapacity);
        return;
      }
      tapLoads.add(tapMl);

      final smallMl = int.tryParse(tap.smallMl.text.trim());
      final bigMl = int.tryParse(tap.bigMl.text.trim());
      if (smallMl == null || smallMl <= 0) {
        setState(() => _error = l10n.tankSmallCupInvalid);
        return;
      }
      if (bigMl == null || bigMl <= 0) {
        setState(() => _error = l10n.tankBigCupInvalid);
        return;
      }
      final smallPrice = double.tryParse(tap.smallPrice.text.trim());
      final bigPrice = double.tryParse(tap.bigPrice.text.trim());
      if (smallPrice == null || smallPrice < 0) {
        setState(() => _error = l10n.tankSmallPriceInvalid);
        return;
      }
      if (bigPrice == null || bigPrice < 0) {
        setState(() => _error = l10n.tankBigPriceInvalid);
        return;
      }
    }

    // The taps together cannot hold more than the tank does.
    //
    // A tank of beer is tapped into taps, and the beer in them is the same
    // beer. Two taps each holding "50" in a 50-litre tank is one full tank
    // counted twice, and it would let the shop pour twice what it owns.
    final double loaded = tapLoads.fold<double>(
      0,
      (double sum, double ml) => sum + ml,
    );
    if (loaded > capacityMl) {
      setState(() => _error = l10n.tankTapsOverCapacity);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = DatabaseHelper.instance;
      final database = await db.database;
      await saveTank(
        database,
        TankValues(
          name: name,
          capacityMl: capacityMl,
          tankCount: tankCount,
          cost: tankCost,
          taps: <TankTapValues>[
            for (var i = 0; i < kTankTapCount; i++)
              TankTapValues(
                name: _taps[i].name.text.trim(),
                loadMl: tapLoads[i],
                smallMl: int.parse(_taps[i].smallMl.text.trim()),
                smallPrice: double.parse(_taps[i].smallPrice.text.trim()),
                bigMl: int.parse(_taps[i].bigMl.text.trim()),
                bigPrice: double.parse(_taps[i].bigPrice.text.trim()),
              ),
          ],
        ),
        smallCupLabel: l10n.tankCupSmallLabel,
        bigCupLabel: l10n.tankCupBigLabel,
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

    final tapSections = <Widget>[];
    for (var i = 0; i < kTankTapCount; i++) {
      tapStack(context, l10n, spacing, type, i, tapSections);
      if (i < kTankTapCount - 1) {
        tapSections.add(SizedBox(height: spacing.lg));
      }
    }

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
            _field(_tankNameCtrl, l10n.tankFieldName, l10n.tankFieldNameHint),
            SizedBox(height: spacing.md),
            _field(
                _capacityLitresCtrl,
                l10n.tankFieldCapacityL,
                l10n.tankFieldCapacityLHint,
                const TextInputType.numberWithOptions(decimal: true)),
            SizedBox(height: spacing.md),
            _field(
                _tankCountCtrl,
                l10n.tankFieldTankCount,
                l10n.tankFieldTankCountHint,
                const TextInputType.numberWithOptions(decimal: false)),
            SizedBox(height: spacing.md),
            _field(
                _mlPerKgCtrl,
                l10n.tankFieldMlPerKg,
                l10n.tankFieldMlPerKgHint,
                const TextInputType.numberWithOptions(decimal: true)),
            SizedBox(height: spacing.md),
            _field(
                _tankCostCtrl,
                l10n.tankFieldTankCost,
                l10n.tankFieldTankCostHint,
                const TextInputType.numberWithOptions(decimal: true)),
            SizedBox(height: spacing.lg),
            ...tapSections,
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

  void tapStack(BuildContext context, AppLocalizations l10n, AppSpacing spacing,
      TextTheme type, int i, List<Widget> out) {
    final tap = _taps[i];
    out.add(Text(
      // The l10n CALL, not the key: `tankTapLabel` is "Tap {n}", a template
      // with a hole in it. Interpolating the getter instead of calling it put
      // the template's own machinery on the screen —
      // "Closure: (Object) => String from Function 'tankTapLabel':. 1" — which
      // is what the shop was looking at.
      l10n.tankTapLabel(i + 1),
      style: type.titleMedium,
    ));
    out.add(SizedBox(height: spacing.xs));
    out.add(_field(
        _taps[i].name, l10n.tankFieldTapName, l10n.tankFieldTapNameHint));
    out.add(SizedBox(height: spacing.xs));
    out.add(Row(
      children: <Widget>[
        Expanded(
          child: _field(
            tap.amount,
            l10n.tankFieldTapAmount,
            l10n.tankFieldTapAmountHint,
            const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        SizedBox(width: spacing.sm),
        // The unit is a SELECTION, so the selected one is a solid accent fill
        // with the accent's own ink on it. A border around the chosen option
        // reads as an outline, not as "this is the one you picked".
        SelectablePill(
          label: l10n.tankUnitLitres,
          selected: tap.isLitres,
          onTap: () => setState(() => tap.isLitres = true),
        ),
        SizedBox(width: spacing.sm),
        SelectablePill(
          label: l10n.tankUnitKg,
          selected: !tap.isLitres,
          onTap: () => setState(() => tap.isLitres = false),
        ),
      ],
    ));
    out.add(SizedBox(height: spacing.md));
    out.add(Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.tankCupSmallLabel, style: type.labelSmall),
              SizedBox(height: spacing.xs),
              _field(
                  tap.smallMl,
                  l10n.tankFieldSmallMl,
                  l10n.tankFieldSmallMlHint,
                  const TextInputType.numberWithOptions(decimal: true)),
              SizedBox(height: spacing.xs),
              _field(
                  tap.smallPrice,
                  l10n.tankFieldSmallPrice,
                  l10n.tankFieldSmallPriceHint,
                  const TextInputType.numberWithOptions(decimal: true)),
            ],
          ),
        ),
        SizedBox(width: spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.tankCupBigLabel, style: type.labelSmall),
              SizedBox(height: spacing.xs),
              _field(tap.bigMl, l10n.tankFieldBigMl, l10n.tankFieldBigMlHint,
                  const TextInputType.numberWithOptions(decimal: true)),
              SizedBox(height: spacing.xs),
              _field(
                  tap.bigPrice,
                  l10n.tankFieldBigPrice,
                  l10n.tankFieldBigPriceHint,
                  const TextInputType.numberWithOptions(decimal: true)),
            ],
          ),
        ),
      ],
    ));
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
