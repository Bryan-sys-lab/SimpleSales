// Configuring the fixed shot cups a till sells.
//
// A shot is the third way a drink can be sold, alongside a whole bottle and a
// variant. It is not a variant because it has no stock of its own: it is poured
// out of the parent bottle, and the stock that moves is the parent's. It is not a
// portion because 30 ml is neither a half nor a quarter.
//
// So a cup is a small configuration in its own right: which spirit it comes
// from, how many millilitres it holds, and what it costs. Those three answers
// are what the till needs to price a shot and to know how much of the bottle it
// just used, and they belong to the shop rather than to the product, which is
// why they are not another column on `products`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../routing/home_shell.dart';

/// A capacity field is whole millilitres, so no decimal point can ever be an
/// answer: the field refuses one before the parser has to explain why.
final TextInputFormatter _wholeDigitsOnly =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9]'));

/// A price field accepts digits and a decimal point, and nothing else. What is
/// removed is only what no amount can contain, so [Money.fromMajor] still does
/// the rounding it always did and the same refusal message is still reached for
/// input that was never a price.
final TextInputFormatter _amountDigitsOnly =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

/// The capacity rule, as one function returning one message.
///
/// The field's inline validator and the submit guard both call this, so the two
/// can never drift into disagreeing about what a rejected capacity looks like,
/// and neither of them has to reach the other's strings.
String? _capacityErrorOf(AppLocalizations l10n, int? capacityMl) {
  if (capacityMl == null) {
    return l10n.shotCupsCapacityWholeMl;
  }
  if (capacityMl <= 0) return l10n.shotCupsCapacityPositive;
  if (capacityMl > Product.maxBottleMl) {
    return l10n.shotCupsCapacityMax(Product.maxBottleMl);
  }
  return null;
}

/// The price rule, as one function returning one message.
String? _priceErrorOf(AppLocalizations l10n, double? price) {
  if (price == null || !Money.isValidMajor(price)) {
    return l10n.shotCupsPriceInvalid;
  }
  return null;
}

/// The name rule, as one function returning one message.
String? _labelErrorOf(AppLocalizations l10n, String? label) {
  if (label == null || label.trim().isEmpty) {
    return l10n.shotCupsNameRequired;
  }
  return null;
}

/// Manages the shot cups a till can pour.
class ShotCupsScreen extends StatefulWidget {
  const ShotCupsScreen({super.key});

  @override
  State<ShotCupsScreen> createState() => _ShotCupsScreenState();
}

/// What the screen has to show.
///
/// One sealed value rather than a `loading` flag next to a list, which can be
/// "loading and empty" and "loaded and empty" at the same time.
sealed class _CupsLoadState {
  const _CupsLoadState();
}

final class _CupsLoading extends _CupsLoadState {
  const _CupsLoading();
}

final class _CupsFailed extends _CupsLoadState {
  const _CupsFailed(this.message);

  final String message;
}

final class _CupsLoaded extends _CupsLoadState {
  const _CupsLoaded();
}

class _ShotCupsScreenState extends State<ShotCupsScreen> {
  List<ShotCup> _cups = const [];
  List<Product> _products = const [];
  _CupsLoadState _loadState = const _CupsLoading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    // Inactive cups too, so an owner can bring one back rather than finding it
    // gone and having to re-enter it.
    final List<ShotCup> cups;
    final List<Product> products;
    try {
      cups = await db.getShotCups(activeOnly: false);
      products = await db.getProducts(activeOnly: false);
    } on Object {
      // A human sentence with a way forward, never the exception: a file path
      // and a stack trace are not help to the person standing at the till.
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _loadState = _CupsFailed(l10n.shotCupsLoadFailed));
      return;
    }
    if (!mounted) return;
    setState(() {
      _cups = cups;
      _products = products;
      _loadState = const _CupsLoaded();
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
  /// be freed (a sale records the folded name and the capacity it was poured
  /// at), so removing it costs only the ability to pour it again. A cup that
  /// was sold from stays off the shelf and off the till.
  Future<void> _remove(ShotCup cup) async {
    final l10n = AppLocalizations.of(context);
    // The typed outcome, not a bare `showDialog` result: `showDialog` returns
    // `Future<T?>`, so a dismissal and a refusal are the same null unless one of
    // them is named — and a null that collapses to "confirmed" is a cup deleted
    // by a tap in the wrong place.
    final ConfirmOutcome outcome = await confirmIrreversible(
      context,
      title: l10n.shotCupsStopSellingTitle(cup.label),
      message: l10n.shotCupsStopSellingMessage(cup.productName),
      confirmLabel: l10n.shotCupsStopSellingAction,
      cancelLabel: l10n.actionCancel,
      // Reversible: the row is hidden, not deleted, so this is not a
      // destructive-tone confirmation.
      isDestructive: false,
    );
    if (outcome is! ConfirmAccepted) return;
    final int? id = cup.id;
    if (id == null) return;
    await DatabaseHelper.instance.deleteShotCup(id);
    if (!mounted) return;
    HapticTheme.of(context).fire(HapticEvent.commit);
    await _load();
  }

  /// How many shots one container of [product] yields at [cup]'s capacity.
  ///
  /// Null when the arithmetic does not work: a countable product has no
  /// millilitres to divide, and a cup bigger than its bottle yields nothing.
  /// Returning null rather than zero is what lets the list say *why* instead of
  /// showing a confident "0 shots per bottle".
  static int? shotsPerBottle(Product product, ShotCup cup) {
    if (cup.capacityMl <= 0 || product.bottleMl <= 0) return null;
    if (product.unit == ProductUnit.each) return null;
    return product.bottleMl ~/ cup.capacityMl;
  }

  /// The product this cup is poured from, if it is still on the roster.
  Product? _productOf(ShotCup cup) =>
      _products.where((p) => p.id == cup.productId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final bool canEdit = context.watch<AppState>().canManageStock;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shotCupsTitle)),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: () => _edit(),
              tooltip: l10n.shotCupsAddAction,
              child: Icon(Icons.add, semanticLabel: l10n.shotCupsAddAction),
            )
          : null,
      body: switch (_loadState) {
        _CupsLoading() => const _CupsLoadingView(),
        _CupsFailed(:final String message) => ErrorStateView(
            message: message,
            onRetry: _load,
            retryLabel: l10n.shotCupsRetryLoading,
          ),
        _CupsLoaded() => _ShotCupsList(
            cups: _cups,
            shotsPerBottle: shotsPerBottle,
            productOf: _productOf,
            canEdit: canEdit,
            onRetry: _load,
            onAdd: _edit,
            onEdit: _edit,
            onStopSelling: _remove,
          ),
      },
    );
  }
}

/// The first load, shaped like the cards that are coming.
class _CupsLoadingView extends StatelessWidget {
  const _CupsLoadingView();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return ColoredBox(
      color: colors.canvas,
      child: SkeletonList(
        itemCount: 4,
        linesPerItem: 1,
        itemBuilder: (BuildContext context, int index) => Container(
          constraints: const BoxConstraints(minHeight: 72),
          margin: EdgeInsets.only(bottom: spacing.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppShapes.of(context).cardRadius,
            border: Border.all(color: colors.outline),
          ),
        ),
      ),
    );
  }
}

/// The configured cups, or the invitation to configure the first one.
class _ShotCupsList extends StatelessWidget {
  const _ShotCupsList({
    required this.cups,
    required this.shotsPerBottle,
    required this.productOf,
    required this.canEdit,
    required this.onRetry,
    required this.onAdd,
    required this.onEdit,
    required this.onStopSelling,
  });

  final List<ShotCup> cups;
  final int? Function(Product product, ShotCup cup) shotsPerBottle;
  final Product? Function(ShotCup cup) productOf;
  final bool canEdit;
  final Future<void> Function() onRetry;
  final VoidCallback onAdd;
  final void Function(ShotCup cup) onEdit;
  final void Function(ShotCup cup) onStopSelling;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    if (cups.isEmpty) {
      return AdaptivePage(
        padding: EdgeInsets.zero,
        child: RefreshIndicator(
          onRefresh: onRetry,
          child: _EmptyShots(canEdit: canEdit, onAdd: onAdd),
        ),
      );
    }

    return AdaptivePage(
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        onRefresh: onRetry,
        child: ListView.builder(
          // Always scrollable so pull-to-refresh works on a short list.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(spacing.md),
          itemCount: cups.length,
          itemBuilder: (BuildContext context, int index) {
            final ShotCup cup = cups[index];
            final Product? product = productOf(cup);
            return _ShotCupCard(
              cup: cup,
              shotsPerBottle:
                  product == null ? null : shotsPerBottle(product, cup),
              canEdit: canEdit,
              onEdit: () => onEdit(cup),
              onStopSelling: () => onStopSelling(cup),
            );
          },
        ),
      ),
    );
  }
}

/// One configured cup: the spirit, the size, the price, the yield.
///
/// Dense, one card per cup, because a shop has a handful of cups rather than a
/// hundred products, and each of these rows carries four separate facts. The
/// price is the only figure a cashier compares vertically, so it is the only one
/// that gets tabular figures and an end-aligned column.
class _ShotCupCard extends StatelessWidget {
  const _ShotCupCard({
    required this.cup,
    required this.shotsPerBottle,
    required this.canEdit,
    required this.onEdit,
    required this.onStopSelling,
  });

  final ShotCup cup;

  /// Null when the yield cannot be worked out, which is not the same as zero.
  final int? shotsPerBottle;

  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onStopSelling;

  /// What the row says at the start, where the facts about the pour live.
  ///
  /// The yield is said only when it can be worked out: "0 shots in the bottle"
  /// would look like an out-of-stock bar, while "the cup is bigger than the
  /// bottle" is the truth and is fixable.
  String _detail(AppLocalizations l10n) {
    final int? perBottle = shotsPerBottle;
    return <String>[
      cup.productName,
      l10n.shotCupsCapacityValue(cup.capacityMl),
      if (perBottle != null) l10n.shotCupsPerBottle(perBottle),
    ].join(' · ');
  }

  // gen-l10n sorts the parameters ALPHABETICALLY — capacity, label — which is
  // the reverse of the label's own order "{label} · {capacity} ml". The
  // capacity came first and the label second, so the card read "30 · Shot ml".
  String _name(AppLocalizations l10n) =>
      l10n.shotCupsCardName(cup.capacityMl, cup.label);

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final String price = formatMoney(cup.price);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _name(l10n);
    final String detail = _detail(l10n);

    return SurfaceCard(
      margin: EdgeInsets.only(bottom: spacing.sm),
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: canEdit ? spacing.xs : spacing.md,
        top: spacing.md,
        bottom: spacing.md,
      ),
      onTap: canEdit ? onEdit : null,
      // The row's own words, read as one phrase. A screen-reader user stepping
      // through the shelf should hear "Shot, 30 ml, Tusker, 14 per bottle, KSh
      // 80" as one stop, not five.
      // Both row labels take (detail, name, price) — gen-l10n sorts the three
      // ALPHABETICALLY, which is the reverse of the sentence's own order
      // "{name}, {detail}, {price}". These were passed name-first.
      semanticLabel: cup.active
          ? l10n.shotCupsCardSpoken(detail, name, price)
          : l10n.shotCupsCardSpokenInactive(detail, name, price),
      child: Row(
        children: <Widget>[
          // Decorative: the name and the price beside it say everything the
          // glyph was saying, and an unlabelled icon is silence.
          ExcludeSemantics(
            child: Icon(
              cup.active
                  ? Icons.local_drink_outlined
                  : Icons.remove_circle_outline,
              color:
                  cup.active ? colors.onSurfaceMuted : colors.onSurfaceVariant,
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  style: type.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(detail, style: type.bodySmall),
              ],
            ),
          ),
          SizedBox(width: spacing.sm),
          // Excluded from the row's phrase so the price is not announced twice,
          // and so the "Not sold" chip stays its own node rather than being
          // swallowed by the card's label.
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                MoneyText(amount: price, size: 15),
                if (!cup.active)
                  StatusChip(
                    tone: StatusTone.neutral,
                    text: l10n.shotCupsNotSold,
                    dense: true,
                  ),
              ],
            ),
          ),
          if (canEdit)
            _ShotCupMenu(onEdit: onEdit, onStopSelling: onStopSelling),
        ],
      ),
    );
  }
}

/// The overflow menu on one cup.
///
/// An explicit [Semantics] wrapper rather than relying on the tooltip alone: a
/// popup button whose only name is a three-dot glyph announces as "button" in
/// most screen readers.
class _ShotCupMenu extends StatelessWidget {
  const _ShotCupMenu({required this.onEdit, required this.onStopSelling});

  final VoidCallback onEdit;
  final VoidCallback onStopSelling;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.shotCupsActionsLabel,
      child: ExcludeSemantics(
        child: PopupMenuButton<String>(
          tooltip: l10n.shotCupsActionsLabel,
          onSelected: (String value) {
            if (value == 'edit') onEdit();
            if (value == 'remove') onStopSelling();
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
                value: 'edit', child: Text(l10n.shotCupsEditAction)),
            PopupMenuItem<String>(
              value: 'remove',
              child: Text(l10n.shotCupsStopSellingAction),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing configured yet.
///
/// A collection empty state, not a filtered one: no shelf has been searched and
/// nothing has been hidden, so the action offered is the one that creates.
class _EmptyShots extends StatelessWidget {
  const _EmptyShots({required this.canEdit, required this.onAdd});

  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return EmptyStateView(
      kind: EmptyKind.collection,
      title: l10n.shotCupsEmptyTitle,
      message: canEdit
          ? l10n.shotCupsEmptyMessageOwner
          : l10n.shotCupsEmptyMessageNoPermission,
      actionLabel: canEdit ? l10n.shotCupsAddAction : null,
      onAction: canEdit ? onAdd : null,
    );
  }
}

/// Creates or edits one cup.
///
/// A real [Form]: the rules below are declared once as validators so each field
/// shows its own refusal next to itself, and the submit guard calls the same
/// functions so there is no second, drifting copy of a rule. Validation runs on
/// interaction rather than on submit so a cashier learns a field is wrong while
/// they are still looking at it.
class _ShotCupEditor extends StatefulWidget {
  const _ShotCupEditor({required this.cup, required this.products});

  final ShotCup? cup;
  final List<Product> products;

  @override
  State<_ShotCupEditor> createState() => _ShotCupEditorState();
}

class _ShotCupEditorState extends State<_ShotCupEditor> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
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
  /// the list, which is an assertion rather than a message: the owner editing
  /// the cup's price would crash instead of being told why.
  ///
  /// Kept selectable so they can move the cup to a real drink; the warning is in
  /// the label rather than in a disabled row, which would be a dead end.
  List<Product> get _options {
    final options = _drinkable;
    final currentId = widget.cup?.productId;
    if (currentId == null) return options;
    if (options.any((p) => p.id == currentId)) return options;
    final current = widget.products.where((p) => p.id == currentId).firstOrNull;
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
    // an unreadable, unparseable price, the same trap the product editor hit.
    _price =
        TextEditingController(text: cup == null ? '' : _majorText(cup.price));
    _label = TextEditingController(
        text: cup?.label ?? AppLocalizations.of(context).shotCupsDefaultName);
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
    final FormState? form = _formKey.currentState;
    // Run the validators first so every refusal appears beside the field that
    // caused it, rather than as one line at the bottom of a sheet.
    if (form != null && !form.validate()) {
      setState(() => _error = null);
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }
    final productId = _productId;
    final int? capacity = int.tryParse(_capacity.text.trim());
    final double? price = double.tryParse(_price.text.trim());
    final String label = _label.text.trim();
    final AppLocalizations l10n = AppLocalizations.of(context);
    // The same rules, in the same order as the fields, so what the sheet refuses
    // is exactly what the guard refuses.
    final String? problem = productId == null
        ? l10n.shotCupsChooseDrink
        : _capacityErrorOf(l10n, capacity) ??
            _priceErrorOf(l10n, price) ??
            _labelErrorOf(l10n, label);
    if (problem != null) {
      setState(() => _error = problem);
      HapticTheme.of(context).fire(HapticEvent.reject);
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
      productId: productId!,
      // The name is stored, not joined, so the cup survives the spirit being
      // renamed or removed and the till can still explain what it poured.
      productName: product?.name ?? widget.cup?.productName ?? '',
      capacityMl: capacity!,
      price: Money.fromMajor(price!),
      label: label,
      // Editing a cup that was stopped selling brings it back, rather than
      // silently leaving it off the till after the owner re-priced it.
      active: true,
      updatedAt: DateTime.now().toIso8601String(),
    );
    try {
      await DatabaseHelper.instance.upsertShotCup(cup);
      if (!mounted) return;
      HapticTheme.of(context).fire(HapticEvent.commit);
      Navigator.pop(context, cup);
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AppLocalizations.of(context).shotCupsSaveFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Product> options = _options;

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.xl,
        end: spacing.xl,
        top: spacing.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  _isNew ? 'Add a shot cup' : 'Edit shot cup',
                  style: AppTypography.of(context).titleLarge,
                ),
              ),
              SizedBox(height: spacing.lg),
              if (options.isEmpty)
                const _NoDrinksNotice()
              else
                _PourFromField(
                  value: _productId,
                  options: options,
                  onChanged: (int? id) => setState(() => _productId = id),
                ),
              SizedBox(height: spacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _capacity,
                      autofocus: _isNew,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: <TextInputFormatter>[_wholeDigitsOnly],
                      validator: (String? raw) => _capacityErrorOf(
                        l10n,
                        int.tryParse(raw?.trim() ?? ''),
                      ),
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context).shotCupsCapacityLabel,
                        hintText:
                            AppLocalizations.of(context).shotCupsCapacityHint,
                        helperText:
                            AppLocalizations.of(context).shotCupsCapacityHelper,
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      inputFormatters: <TextInputFormatter>[_amountDigitsOnly],
                      validator: (String? raw) => _priceErrorOf(
                        l10n,
                        double.tryParse(raw?.trim() ?? ''),
                      ),
                      style: AppTypography.money(context, size: 15),
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context).shotCupsPriceLabel,
                        helperText:
                            AppLocalizations.of(context).shotCupsPriceHelper,
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _label,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                validator: (String? raw) => _labelErrorOf(l10n, raw),
                decoration: InputDecoration(
                  labelText:
                      AppLocalizations.of(context).shotCupsNameAtTillLabel,
                  hintText: AppLocalizations.of(context).shotCupsNameHint,
                  helperText: AppLocalizations.of(context).shotCupsNameHelper,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                onFieldSubmitted: (String _) => _submit(),
              ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: spacing.md),
                  child: _EditorError(message: _error!),
                ),
              SizedBox(height: spacing.xl),
              FilledButton(
                onPressed: _saving || options.isEmpty ? null : _submit,
                child: Text(_isNew ? 'Add cup' : 'Save cup'),
              ),
              SizedBox(height: spacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

/// Said rather than an empty dropdown: a shop with nothing measured in
/// millilitres cannot pour a shot, and that is worth saying once instead of
/// leaving a control that accepts anything.
class _NoDrinksNotice extends StatelessWidget {
  const _NoDrinksNotice();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Semantics(
      container: true,
      child: Text(
        'No drinks in millilitres yet. Set a product\'s unit to cup or litre in '
        'Inventory first: a shot is a pour, so it needs something to pour.',
        style: AppTypography.of(context)
            .bodyMedium
            ?.copyWith(color: colors.onSurfaceMuted),
      ),
    );
  }
}

/// Which spirit the shot is poured from.
///
/// A validator rather than a plain dropdown: with nothing selected the sheet
/// used to refuse at submit time with a line of text at the bottom, which reads
/// as a failed save rather than as "you have not chosen yet".
class _PourFromField extends StatelessWidget {
  const _PourFromField({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final int? value;
  final List<Product> options;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).shotCupsPouredFromLabel,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      validator: (int? id) =>
          id == null ? AppLocalizations.of(context).shotCupsChooseDrink : null,
      items: <DropdownMenuItem<int>>[
        for (final p in options)
          DropdownMenuItem<int>(
            value: p.id,
            // A product that has since become countable is still listed, labelled
            // with why it cannot be poured, rather than silently vanishing from
            // under the selection. The menu row is a fixed height, so the name is
            // allowed to clip here while `semanticsLabel` keeps the whole thing
            // available to assistive tech.
            child: Text(
              p.unit == ProductUnit.each
                  ? '${p.name} · no volume set'
                  : '${p.name} · ${p.bottleMl} ml',
              overflow: TextOverflow.ellipsis,
              semanticsLabel: p.unit == ProductUnit.each
                  ? '${p.name}, no volume set'
                  : '${p.name}, ${p.bottleMl} ml',
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// A refusal the user has to notice: a live region, in the danger tone.
class _EditorError extends StatelessWidget {
  const _EditorError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline,
              size: 18, color: colors.danger, semanticLabel: ''),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.of(context)
                  .bodyMedium
                  ?.copyWith(color: colors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
