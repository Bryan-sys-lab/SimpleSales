/// A tank of beer: stocked by weight, poured by the cup.
///
/// Why this is a form of its own and not another option on the product editor:
/// a tank is not a product with a different unit, it is a different SHAPE of
/// thing. Its stock arrives on a scale in kilograms, its capacity is in litres,
/// what it holds is two named taps that are poured and priced separately, and
/// not one of those numbers is the number a bottle's form asks for.
///
/// What it writes is ordinary catalogue, deliberately:
///
///   * one `products` row per tap, `unit = millilitre`, whose `bottle_ml` is
///     the tap's capacity in millilitres and whose `stockQty` is how full the
///     tap is (1.0 = full, 0.5 = half);
///   * two `ShotCup` rows per tap — Small and Big — each with its own price,
///     each deducting `cup ml ÷ bottle ml` from one shared stock.
///
/// The till's shot-cup machinery already supports several cup sizes per
/// product, each pouring from one shared stock, so every tap product is its own
/// pour-able thing with its own cups.
library;

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/home_shell.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../utils/money.dart';
import '../utils/units.dart';

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

/// One tap's worth of state: a name, an amount loaded, and the small/big cup
/// sizes and prices.
class _TapState {
  final TextEditingController name = TextEditingController();
  final TextEditingController amount = TextEditingController();
  final TextEditingController smallMl = TextEditingController(text: kSmallCupMl.toString());
  final TextEditingController smallPrice = TextEditingController();
  final TextEditingController bigMl = TextEditingController(text: kBigCupMl.toString());
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

class _TankFormSheetState extends State<TankFormSheet> {
  final TextEditingController _tankName = TextEditingController();
  final TextEditingController _capacityLitres = TextEditingController();
  final TextEditingController _tankCost = TextEditingController();
  final TextEditingController _mlPerKg = TextEditingController();

  final _taps = <_TapState>[_TapState(), _TapState()];

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Beer default: a litre of lager weighs a kilogram.
    _mlPerKg.text = defaultKilogramsToMillilitres.round().toString();
    _taps[0].name.text = 'Dark';
    _taps[1].name.text = 'Regular';
  }

  @override
  void dispose() {
    _tankName.dispose();
    _capacityLitres.dispose();
    _tankCost.dispose();
    _mlPerKg.dispose();
    for (final tap in _taps) {
      tap.dispose();
    }
    super.dispose();
  }

  double? get _capacityL {
    final text = _capacityLitres.text.trim();
    if (text.isEmpty) return null;
    return _finite(double.tryParse(text));
  }

  int? get _capacityMl {
    final litres = _capacityL;
    if (litres == null || !litres.isFinite) return null;
    final ml = litresToMillilitres(litres);
    if (ml < Product.minBottleMl || ml > Product.maxBottleMl) return null;
    return ml.round();
  }

  double? get _tankCostValue {
    final text = _tankCost.text.trim();
    if (text.isEmpty) return null;
    return _finite(double.tryParse(text));
  }

  double? get _perKg {
    final text = _mlPerKg.text.trim();
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
    final name = _tankName.text.trim();
    final capacityMl = _capacityMl;
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
    if (tankCost == null || !tankCost.isFinite || tankCost < 0) {
      setState(() => _error = l10n.tankPriceInvalid);
      return;
    }
    if (perKg == null) {
      setState(() => _error = l10n.tankMlPerKgInvalid);
      return;
    }

    // Validate every tap before touching the database.
    final tapLoads = <double?>[];
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
      if (tapMl > capacityMl) {
        setState(() => _error = l10n.tankTapOverCapacity);
        return;
      }
      tapLoads.add(tapMl);

      final smallMl = int.tryParse(tap.smallMl.text.trim());
      final bigMl = int.tryParse(tap.bigMl.text.trim());
      if (smallMl == null || smallMl <= 0 || smallMl > capacityMl) {
        setState(() => _error = l10n.tankSmallCupInvalid);
        return;
      }
      if (bigMl == null || bigMl <= 0 || bigMl > capacityMl) {
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

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final db = DatabaseHelper.instance;
      final perTapCost = tankCost / kTankTapCount;

      // One transaction: each tap is its own product, each with two ShotCup
      // rows pouring from one shared stock.
      final database = await db.database;
      await database.transaction((txn) async {
        for (var i = 0; i < kTankTapCount; i++) {
          final tap = _taps[i];
          final loadedMl = tapLoads[i]!;
          final bottleMl = capacityMl;
          final stockQty = loadedMl / bottleMl;
          final smallPrice = double.tryParse(tap.smallPrice.text.trim()) ?? 0;
          final bigPrice = double.tryParse(tap.bigPrice.text.trim()) ?? 0;

          final productId = await txn.insert('products', {
            'name': '$name — ${tap.name.text.trim()}',
            'category': 'Beer',
            'cost_price': Money.fromMajor(perTapCost).minorUnits,
            'sell_price': Money.fromMajor(bigPrice).minorUnits,
            'stock_qty': stockQty,
            'reorder_level': 0,
            'bottle_ml': bottleMl,
            'unit': ProductUnit.millilitre.wire,
            'track_variants': false,
            'active': 1,
            'updated_at': DateTime.now().toIso8601String(),
          });

          // Small cup.
          await txn.insert('shot_cups', {
            'product_id': productId,
            'product_name': '$name — ${tap.name.text.trim()}',
            'capacity_ml': int.parse(tap.smallMl.text.trim()),
            'price': Money.fromMajor(smallPrice).minorUnits,
            'label': l10n.tankCupSmallLabel,
            'active': 1,
            'updated_at': DateTime.now().toIso8601String(),
          });

          // Big cup.
          await txn.insert('shot_cups', {
            'product_id': productId,
            'product_name': '$name — ${tap.name.text.trim()}',
            'capacity_ml': int.parse(tap.bigMl.text.trim()),
            'price': Money.fromMajor(bigPrice).minorUnits,
            'label': l10n.tankCupBigLabel,
            'active': 1,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      });

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
            Text(l10n.tankFormTitle, style: type.headlineSmall),
            SizedBox(height: spacing.xs),
            Text(
              l10n.tankFormSubtitle,
              style: type.bodySmall
                  ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
            ),
            SizedBox(height: spacing.lg),
            _field(_tankName, l10n.tankFieldName, l10n.tankFieldNameHint),
            SizedBox(height: spacing.md),
            _field(_capacityLitres, l10n.tankFieldCapacityL,
                l10n.tankFieldCapacityLHint,
                const TextInputType.numberWithOptions(decimal: true)),
            SizedBox(height: spacing.md),
            _field(_mlPerKg, l10n.tankFieldMlPerKg,
                l10n.tankFieldMlPerKgHint,
                const TextInputType.numberWithOptions(decimal: true)),
            SizedBox(height: spacing.md),
            _field(_tankCost, l10n.tankFieldTankCost,
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

  void tapStack(BuildContext context, AppLocalizations l10n,
      AppSpacing spacing, TextTheme type, int i, List<Widget> out) {
    final tap = _taps[i];
    out.add(Text(
      '${l10n.tankTapLabel} ${
        i + 1}',
      style: type.titleMedium,
    ));
    out.add(SizedBox(height: spacing.xs));
    out.add(_field(_taps[i].name, l10n.tankFieldTapName,
        l10n.tankFieldTapNameHint));
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
        ChoiceChip(
          label: Text(l10n.tankUnitLitres),
          selected: tap.isLitres,
          onSelected: (v) => setState(() => tap.isLitres = v),
        ),
        SizedBox(width: spacing.sm),
        ChoiceChip(
          label: Text(l10n.tankUnitKg),
          selected: !tap.isLitres,
          onSelected: (v) => setState(() => tap.isLitres = !v),
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
              _field(tap.smallMl, l10n.tankFieldSmallMl,
                  l10n.tankFieldSmallMlHint,
                  const TextInputType.numberWithOptions(decimal: true)),
              SizedBox(height: spacing.xs),
              _field(tap.smallPrice, l10n.tankFieldSmallPrice,
                  l10n.tankFieldSmallPriceHint,
                  const TextInputType.numberWithOptions(
                      decimal: true)),
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
              _field(tap.bigMl, l10n.tankFieldBigMl,
                  l10n.tankFieldBigMlHint,
                  const TextInputType.numberWithOptions(decimal: true)),
              SizedBox(height: spacing.xs),
              _field(tap.bigPrice, l10n.tankFieldBigPrice,
                  l10n.tankFieldBigPriceHint,
                  const TextInputType.numberWithOptions(
                      decimal: true)),
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
