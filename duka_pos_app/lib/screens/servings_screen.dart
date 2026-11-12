// Configuring the fixed servings a till sells.
//
// A serving is the third way a drink can be sold, alongside a whole bottle and a
// variant. It is not a variant because it has no stock of its own: it is poured
// out of the parent bottle, and the stock that moves is the parent's. It is not a
// portion because 30 ml is neither a half nor a quarter.
//
// So a serving is a small configuration in its own right: which drink it comes
// from, how many millilitres it holds, and what it costs. Those three answers
// are what the till needs to price a serving and to know how much of the bottle it
// just used, and they belong to the shop rather than to the product, which is
// why they are not another column on `products`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/session_refresh_mixin.dart';
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

/// A capacity field accepts digits and a decimal point, so a shop can enter
/// "0.5" (half a unit) or "0.25". Anything below zero is refused by the
/// validator, not by the formatter.
final TextInputFormatter _wholeDigitsOnly =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

/// A price field accepts digits and a decimal point, and nothing else. What is
/// removed is only what no amount can contain, so [Money.fromMajor] still does
/// the rounding it always did and the same refusal message is still reached for
/// input that was never a price.
final TextInputFormatter _amountDigitsOnly =
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

/// The capacity rule, as one function returning one message.
///
/// The field's inline validator and the submit guard both call this, so the two
/// cannot disagree.
///
/// The size is OPTIONAL. A shot cup is a name for a serving — "Single",
/// "Double" — and the size in millilitres is the owner's business. It is what
/// lets the app work out what the shot cost to pour, so a cup WITH a size
/// earns its cost and a cup WITHOUT one is counted at its full price.
///
/// An empty field is not a mistake; a NEGATIVE one is; and a size bigger than
/// any bottle in the shop is a typo.
String? _capacityErrorOf(AppLocalizations l10n, double? capacity) {
  if (capacity == null) {
    return null;
  }
  if (capacity < 0)     return l10n.servingsCapacityPositive;
  if (capacity > Product.maxBottleMl.toDouble()) {
    return l10n.servingsCapacityMax(Product.maxBottleMl);
  }
  return null;
}

String? _priceErrorOf(AppLocalizations l10n, double? price) {
  if (price == null || !Money.isValidMajor(price)) {
    return l10n.servingsPriceInvalid;
  }
  return null;
}

String? _labelErrorOf(AppLocalizations l10n, String? label) {
  if (label == null || label.trim().isEmpty) {
    return l10n.servingsNameRequired;
  }
  return null;
}

class ServingsScreen extends StatefulWidget {
  const ServingsScreen({super.key});

  @override
  State<ServingsScreen> createState() => _ServingsScreenState();
}

sealed class _ServingsLoadState {
  const _ServingsLoadState();
}

final class _ServingsLoading extends _ServingsLoadState {
  const _ServingsLoading();
}

final class _ServingsFailed extends _ServingsLoadState {
  const _ServingsFailed(this.message);

  final String message;
}

final class _ServingsLoaded extends _ServingsLoadState {
  const _ServingsLoaded();
}

class _ServingsScreenState extends State<ServingsScreen>
    with SessionRefresh<ServingsScreen> {
  List<Serving> _cups = const [];
  List<Product> _products = const [];
  String? _unitFilter; // null = all units
  int? _productFilter; // null = all products
  _ServingsLoadState _loadState = const _ServingsLoading();

  @override
  void clearForSession() {
    _cups = const [];
    _products = const [];
    _unitFilter = null;
    _productFilter = null;
    _loadState = const _ServingsLoading();
  }

  @override
  Future<void> reloadFromSession() => _load();

  /// Servings that pass both active filters (unit and master product).
  List<Serving> get _filteredServings {
    var result = _cups.where((s) => s.active);
    if (_unitFilter != null) {
      result = result.where((s) => s.unit == _unitFilter);
    }
    if (_productFilter != null) {
      result = result.where((s) => s.productId == _productFilter);
    }
    return result.toList()..sort((a, b) => a.label.compareTo(b.label));
  }

  /// Distinct units in use across all servings, for the unit filter chip row.
  List<String> get _unitsInUse {
    final units = <String>{};
    for (final s in _cups.where((s) => s.active)) {
      units.add(s.unit);
    }
    return units.toList()..sort();
  }

  /// Master products that have at least one active serving, for the product filter.
  List<Product> get _productsWithServings {
    final ids = _cups.where((s) => s.active).map((s) => s.productId).toSet();
    return _products.where((p) => ids.contains(p.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    // Inactive servings too, so an owner can bring one back rather than finding it
    // gone and having to re-enter it.
    final List<Serving> cups;
    final List<Product> products;
    try {
      cups = await db.getServings(activeOnly: false);
      products = await db.getProducts(activeOnly: false);
    } on Object {
      // A human sentence with a way forward, never the exception: a file path
      // and a stack trace are not help to the person standing at the till.
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _loadState = _ServingsFailed(l10n.servingsLoadFailed));
      return;
    }
    if (!mounted) return;
    setState(() {
      _cups = cups;
      _products = products;
      _loadState = const _ServingsLoaded();
    });
  }

  Future<void> _edit([Serving? existing]) async {
    final saved = await showModalBottomSheet<Serving>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ServingEditor(
        serving: existing,
        products: _products,
      ),
    );
    if (saved == null) return;
    // A new or changed serving has to reach the till, which is kept alive and would
    // otherwise keep offering the old shelf.
    //
    // The module-level signal, NOT `context.read<HomeShellTabs>()`: this route
    // is pushed on the root navigator, so it sits outside the provider the
    // shell mounts below it — and the lookup threw AFTER the serving was written,
    // which is why a created serving used to appear in no list and on no shelf.
    if (mounted) markCatalogueChanged();
    await _load();
  }

  Future<void> _remove(Serving serving) async {
    final l10n = AppLocalizations.of(context);
    // The typed outcome, not a bare `showDialog` result: `showDialog` returns
    // `Future<T?>`, so a dismissal and a refusal are the same null unless one of
    // them is named — and a null that collapses to "confirmed" is a serving deleted
    // by a tap in the wrong place.
    final ConfirmOutcome outcome = await confirmIrreversible(
      context,
      title: l10n.servingsStopSellingTitle(serving.label),
      message: l10n.servingsStopSellingMessage(serving.productName),
      confirmLabel: l10n.servingsStopSellingAction,
      cancelLabel: l10n.actionCancel,
      // Reversible: the row is hidden, not deleted, so this is not a
      // destructive-tone confirmation.
      isDestructive: false,
    );
    if (outcome is! ConfirmAccepted) return;
    final int? id = serving.id;
    if (id == null) return;
    await DatabaseHelper.instance.deleteServing(id);
    if (!mounted) return;
    HapticTheme.of(context).fire(HapticEvent.commit);
    await _load();
  }

  Future<void> _copyServing(Serving serving) async {
    if (_products.isEmpty) return;
    final Product? selected = await showDialog<Product>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).copyCupToProduct),
        children: <Widget>[
          for (final Product p in _products)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final DatabaseHelper db = DatabaseHelper.instance;
    final Serving copy = Serving(
      productId: selected.id!,
      productName: selected.name,
      capacity: serving.capacity,
      unit: serving.unit,
      price: serving.price,
      label: serving.label,
      active: serving.active,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await db.upsertServing(copy);
    markCatalogueChanged();
    await _load();
  }

  static int? servingsPerBottle(Product product, Serving serving) {
    if (serving.capacity <= 0 || product.bottleMl <= 0) return null;
    return product.bottleMl ~/ serving.capacity;
  }

  Product? _productOf(Serving serving) =>
      _products.where((p) => p.id == serving.productId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final bool canEdit = context.watch<AppState>().canManageStock;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.servingsTitle),
        actions: <Widget>[
          if (canEdit)
            TextButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(l10n.servingsAddAction),
            ),
        ],
      ),
      body: switch (_loadState) {
        _ServingsLoading() => const _ServingsLoadingView(),
        _ServingsFailed(:final String message) => ErrorStateView(
            message: message,
            onRetry: _load,
            retryLabel: l10n.servingsRetryLoading,
          ),
        _ServingsLoaded() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Unit filter: one chip per unit in use.
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _unitsInUse.length,
                  itemBuilder: (BuildContext context, int index) {
                    final unit = _unitsInUse[index];
                    final selected = _unitFilter == unit;
                    return FilterChip(
                      selected: selected,
                      label: Text(unit.toUpperCase()),
                      onSelected: (bool chosen) {
                        setState(() {
                          _unitFilter = chosen ? unit : null;
                          // Clearing a product filter when a unit is picked
                          // keeps the two filters from fighting each other.
                          if (chosen && _productFilter != null) {
                            _productFilter = null;
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              SizedBox(height: spacing.sm),
              // Master product filter: dropdown of products that have servings.
              if (_productsWithServings.isNotEmpty)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                      start: spacing.md, end: spacing.md),
                  child: DropdownButtonFormField<int>(
                    initialValue: _productFilter,
                    decoration: InputDecoration(
                      labelText: l10n.servingsFilterByProduct,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<int>>[
                      DropdownMenuItem<int>(
                        value: null,
                        child: Text(AppLocalizations.of(context).allProducts),
                      ),
                      ..._productsWithServings.map((Product p) =>
                          DropdownMenuItem<int>(
                            value: p.id,
                            child: Text(p.name),
                          )),
                    ],
                    onChanged: (int? id) {
                      setState(() {
                        _productFilter = id;
                      });
                    },
                  ),
                ),
              SizedBox(height: spacing.md),
              _ServingsList(
                servings: _filteredServings,
                servingsPerBottle: servingsPerBottle,
                productOf: _productOf,
                canEdit: canEdit,
                onRetry: _load,
                onAdd: _edit,
                onEdit: _edit,
                onStopSelling: _remove,
                onCopy: _copyServing,
              ),
            ],
          ),
      },
    );
  }
}

class _ServingsLoadingView extends StatelessWidget {
  const _ServingsLoadingView();

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

class _ServingsList extends StatelessWidget {
  const _ServingsList({
    required this.servings,
    required this.servingsPerBottle,
    required this.productOf,
    required this.canEdit,
    required this.onRetry,
    required this.onAdd,
    required this.onEdit,
    required this.onStopSelling,
    required this.onCopy,
  });

  final List<Serving> servings;
  final int? Function(Product product, Serving serving) servingsPerBottle;
  final Product? Function(Serving serving) productOf;
  final bool canEdit;
  final Future<void> Function() onRetry;
  final VoidCallback onAdd;
  final void Function(Serving serving) onEdit;
  final void Function(Serving serving) onStopSelling;
  final void Function(Serving serving) onCopy;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    if (servings.isEmpty) {
      return AdaptivePage(
        padding: EdgeInsets.zero,
        child: RefreshIndicator(
          onRefresh: onRetry,
          child: _EmptyServings(canEdit: canEdit, onAdd: onAdd),
        ),
      );
    }

    return AdaptivePage(
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        onRefresh: onRetry,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Search field at the top of the list, mirroring the mockup.
            Padding(
              padding: EdgeInsets.all(spacing.md),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search serving definitions',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  constraints: BoxConstraints(
                    minHeight: spacing.minTapTarget,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                // Always scrollable so pull-to-refresh works on a short list.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(spacing.md),
                itemCount: servings.length,
                itemBuilder: (BuildContext context, int index) {
                  final Serving serving = servings[index];
                  final Product? product = productOf(serving);
                  return _ServingCard(
                    serving: serving,
                    servingsPerBottle:
                        product == null ? null : servingsPerBottle(product, serving),
                    canEdit: canEdit,
                    onEdit: () => onEdit(serving),
                    onStopSelling: () => onStopSelling(serving),
                    onCopy: () => onCopy(serving),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServingCard extends StatelessWidget {
  const _ServingCard({
    required this.serving,
    required this.servingsPerBottle,
    required this.canEdit,
    required this.onEdit,
    required this.onStopSelling,
    required this.onCopy,
  });

  final Serving serving;

  final int? servingsPerBottle;

  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onStopSelling;
  final VoidCallback onCopy;

  String _detail(AppLocalizations l10n) {
    final int? perBottle = servingsPerBottle;
    return <String>[
      serving.productName,
      l10n.servingsCapacityValue(serving.capacity),
      if (perBottle != null) l10n.servingsPerBottle(perBottle),
    ].join(' · ');
  }

  // gen-l10n sorts the parameters ALPHABETICALLY — capacity, label — which is
  // the reverse of the label's own order "{label} · {capacity} ml". The
  // capacity came first and the label second, so the card read "30 · Shot ml".
  String _name(AppLocalizations l10n) =>
      l10n.servingsCardName(serving.capacity, serving.label);

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final String price = formatMoney(serving.price);
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
      // through the shelf should hear "Serving, 30 ml, Tusker, 14 per bottle, KSh
      // 80" as one stop, not five.
      // Both row labels take (detail, name, price) — gen-l10n sorts the three
      // ALPHABETICALLY, which is the reverse of the sentence's own order
      // "{name}, {detail}, {price}". These were passed name-first.
      semanticLabel: serving.active
          ? l10n.servingsCardSpoken(detail, name, price)
          : l10n.servingsCardSpokenInactive(detail, name, price),
      child: Row(
        children: <Widget>[
          // Circular icon badge like the mockup.
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                shape: BoxShape.circle,
              ),
              child: Icon(
                serving.active
                    ? Icons.local_drink_outlined
                    : Icons.remove_circle_outline,
                size: 20,
                color:
                    serving.active ? colors.onSurfaceMuted : colors.onSurfaceVariant,
              ),
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
                if (!serving.active)
                  StatusChip(
                    tone: StatusTone.neutral,
                    text: l10n.servingsNotSold,
                    dense: true,
                  ),
              ],
            ),
          ),
          if (canEdit)
            _ServingMenu(onEdit: onEdit, onStopSelling: onStopSelling, onCopy: onCopy),
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
class _ServingMenu extends StatelessWidget {
  const _ServingMenu({
    required this.onEdit,
    required this.onStopSelling,
    required this.onCopy,
  });

  final VoidCallback onEdit;
  final VoidCallback onStopSelling;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.servingsActionsLabel,
      child: ExcludeSemantics(
        child: PopupMenuButton<String>(
          tooltip: l10n.servingsActionsLabel,
          onSelected: (String value) {
            if (value == 'edit') onEdit();
            if (value == 'remove') onStopSelling();
            if (value == 'copy') onCopy();
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
                value: 'edit', child: Text(l10n.servingsEditAction)),
            PopupMenuItem<String>(
              value: 'remove',
              child: Text(l10n.servingsStopSellingAction),
            ),
            PopupMenuItem<String>(
              value: 'copy',
              child: Text(AppLocalizations.of(context).copyToAnotherProduct),
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
class _EmptyServings extends StatelessWidget {
  const _EmptyServings({required this.canEdit, required this.onAdd});

  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return EmptyStateView(
      kind: EmptyKind.collection,
      title: l10n.servingsEmptyTitle,
      message: canEdit
          ? l10n.servingsEmptyMessageOwner
          : l10n.servingsEmptyMessageNoPermission,
      actionLabel: canEdit ? l10n.servingsAddAction : null,
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
class _ServingEditor extends StatefulWidget {
  const _ServingEditor({required this.serving, required this.products});

  final Serving? serving;
  final List<Product> products;

  @override
  State<_ServingEditor> createState() => _ServingEditorState();
}

class _ServingEditorState extends State<_ServingEditor> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _capacity;
  late final TextEditingController _price;
  late final TextEditingController _label;
  int? _productId;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.serving?.id == null;

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

  List<Product> get _options {
    final options = _drinkable;
    final currentId = widget.serving?.productId;
    if (currentId == null) return options;
    if (options.any((p) => p.id == currentId)) return options;
    final current = widget.products.where((p) => p.id == currentId).firstOrNull;
    return current == null ? options : [...options, current];
  }

  @override
  void initState() {
    super.initState();
    final serving = widget.serving;
    _productId = serving?.productId;
    _capacity = TextEditingController(
        text: serving == null ? '' : serving.capacity.toString());
    // Prices are stored as `Money`, never `double`. `Money.toString()` is the
    // debug representation in minor units, and seeding a field with it produced
    // an unreadable, unparseable price, the same trap the product editor hit.
    _price =
        TextEditingController(text: serving == null ? '' : _majorText(serving.price));
    _label = TextEditingController(
        text: serving?.label ?? AppLocalizations.of(context).servingsDefaultName);
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
    // An EMPTY size is allowed, and means "not known". It is stored as zero,
    // and zero is what the till reads as "no size".
    final double? capacity = double.tryParse(_capacity.text.trim());
    final double? price = double.tryParse(_price.text.trim());
    final String label = _label.text.trim();
    final AppLocalizations l10n = AppLocalizations.of(context);
    // The same rules, in the same order as the fields, so what the sheet refuses
    // is exactly what the guard refuses.
    final String? problem = productId == null
        ? l10n.servingsChooseDrink
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
    final cup = Serving(
      id: widget.serving?.id,
      productId: productId!,
      // The name is stored, not joined, so the cup survives the spirit being
      // renamed or removed and the till can still explain what it poured.
      productName: product?.name ?? widget.serving?.productName ?? '',
      capacity: capacity?.toDouble() ?? 0,
      unit: 'ml',
      price: Money.fromMajor(price!),
      label: label,
      // Editing a cup that was stopped selling brings it back, rather than
      // silently leaving it off the till after the owner re-priced it.
      active: true,
      updatedAt: DateTime.now().toIso8601String(),
    );
    try {
      await DatabaseHelper.instance.upsertServing(cup);
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
          _error = AppLocalizations.of(context).servingsSaveFailed;
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
                  _isNew ? l10n.servingsAddAction : l10n.servingsEditAction,
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
                        double.tryParse(raw?.trim() ?? ''),
                      ),
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context).servingsCapacityLabel,
                        hintText:
                            AppLocalizations.of(context).servingsCapacityHint,
                        helperText:
                            AppLocalizations.of(context).servingsCapacityHelper,
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
                            AppLocalizations.of(context).servingsPriceLabel,
                        helperText:
                            AppLocalizations.of(context).servingsPriceHelper,
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
                      AppLocalizations.of(context).servingsNameAtTillLabel,
                  hintText: AppLocalizations.of(context).servingsNameHint,
                  helperText: AppLocalizations.of(context).servingsNameHelper,
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
                child: Text(_isNew ? 'Add serving' : 'Save serving'),
              ),
              SizedBox(height: spacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

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
        labelText: AppLocalizations.of(context).servingsPouredFromLabel,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      validator: (int? id) =>
          id == null ? AppLocalizations.of(context).servingsChooseDrink : null,
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
