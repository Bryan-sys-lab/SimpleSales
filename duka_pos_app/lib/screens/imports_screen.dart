// The rows an import asked about, and the answer to them.
//
// ## What this screen is for
//
// An import refuses a row missing its price rather than inventing one — the
// right call, and until now a dead end. The row was kept on the
// needs-attention list, the dashboard said "re-import the spreadsheet to
// finish that update", and nothing in the app let the owner answer. They either
// edited the supplier's workbook on a desktop or lived with stock that was
// never imported.
//
// This is the answer. Each row opens as a draft already filled with whatever
// the file did say, and the owner supplies what it did not: the price, the
// name, the stock count. On save the product is written and the row is
// resolved, so the count on the dashboard falls by one and the catalogue gains
// an item the shop actually sells.
//
// ## Why the draft is a value built by a pure service
//
// What the form pre-fills must be exactly what the import would have written,
// and what it asks for must be exactly what the import refused on. Both go
// through `ImportReviewService`, which uses the import's own parsers, so the
// two cannot drift. The screen holds the draft as state and does no parsing of
// its own beyond the fields the owner is editing.
//
// ## The four states
//
// Loading while the list is read, empty when every problem is resolved (with a
// way back), error when the read fails with a retry, and the list. A blank body
// while the database is still answering is what this screen replaces.

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/import_review_service.dart';
import '../services/import_row_parser.dart';
import '../services/session_refresh_mixin.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/operation_result.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../utils/validation_utils.dart';

class ImportProblemRow {
  const ImportProblemRow({required this.problem, required this.draft});

  final ImportNeedsAttention problem;
  final ImportDraft draft;
}

class ImportsScreen extends StatefulWidget {
  const ImportsScreen({super.key});

  @override
  State<ImportsScreen> createState() => _ImportsScreenState();
}

class _ImportsScreenState extends State<ImportsScreen>
    with SessionRefresh<ImportsScreen> {
  List<ImportProblemRow> _rows = const <ImportProblemRow>[];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void clearForSession() {
    _rows = const <ImportProblemRow>[];
  }

  @override
  Future<void> reloadFromSession() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      final problems = await db.getImportProblems(limit: 500);
      if (!mounted) return;
      setState(() {
        _rows = <ImportProblemRow>[
          for (final problem in problems)
            ImportProblemRow(
              problem: problem,
              draft: ImportReviewService.draftFrom(problem),
            ),
        ];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);

    return Scaffold(
      appBar: AppBar(
        // The screen's NAME, not the brand lockup. The app bar is a title on
        // the canvas now — no filled band, no logo — and the brand mark lives
        // in the shell's bar.
        title: Text(l10n.importsTitle),
      ),
      body: switch ((_loading, _failed, _rows.isEmpty)) {
        (true, _, _) => const _ImportsSkeleton(),
        (_, true, _) => ErrorStateView(
            message: l10n.importsLoadFailed,
            onRetry: _load,
            retryLabel: l10n.actionRetry,
          ),
        (_, _, true) => EmptyStateView(
            title: l10n.importsEmptyTitle,
            message: l10n.importsEmptyMessage,
            actionLabel: l10n.actionCancel,
            onAction: () => Navigator.of(context).maybePop(),
          ),
        _ => RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: EdgeInsetsDirectional.all(spacing.md),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => SizedBox(height: spacing.sm),
              itemBuilder: (BuildContext context, int index) =>
                  _ProblemTile(row: _rows[index], onSaved: _load),
            ),
          ),
      },
    );
  }
}

class _ImportsSkeleton extends StatelessWidget {
  const _ImportsSkeleton();

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: EdgeInsetsDirectional.all(AppSpacing.of(context).md),
        itemCount: 4,
        separatorBuilder: (_, __) =>
            SizedBox(height: AppSpacing.of(context).sm),
        itemBuilder: (_, __) => const SurfaceCard(child: _SkeletonLine()),
      );
}

/// The placeholder for a row of imports that has not arrived yet.
///
/// SHAPED like the row it stands in for, at the text scale in force. A fixed
/// 72dp skeleton is shorter than the card that replaces it at 200% text, so
/// the list jumps when the data lands — a skeleton is a promise about what is
/// coming, and a promise that changes shape is worse than no promise.
class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    double line(TextStyle? style, double fallback) {
      final TextStyle resolved = style ?? const TextStyle();
      return scaler.scale(resolved.fontSize ?? fallback) *
          (resolved.height ?? 1.3);
    }

    final double title = line(type.titleSmall, 13);
    final double body = line(type.bodySmall, 12);

    return Container(
      height: spacing.md * 2 + title + spacing.xs + body,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: body,
        width: 180,
        decoration: BoxDecoration(
          // The semantic tier, not the Material container ladder: a sunken well
          // is what this placeholder is, and `surfaceSunken` is the token that
          // says so in both themes.
          color: AppColors.of(context).surfaceSunken,
          borderRadius: AppShapes.of(context).barRadius,
        ),
      ),
    );
  }
}

class _ProblemTile extends StatelessWidget {
  const _ProblemTile({required this.row, required this.onSaved});

  final ImportProblemRow row;
  final Future<void> Function() onSaved;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);
    final typography = AppTypography.of(context);

    return SurfaceCard(
      child: InkWell(
        // Matches the card it sits in, so the ink ripple does not spill over
        // a rounded corner.
        borderRadius: AppShapes.of(context).cardRadius,
        onTap: () => _complete(context),
        child: Padding(
          padding: EdgeInsetsDirectional.all(spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(row.problem.label, style: typography.titleSmall),
              SizedBox(height: spacing.xs),
              Text(row.problem.problem, style: typography.bodySmall),
              SizedBox(height: spacing.sm),
              Row(
                children: <Widget>[
                  Icon(Icons.edit_outlined, size: 16),
                  SizedBox(width: spacing.xs),
                  Text(l10n.importsCompleteAction,
                      style: typography.labelMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _complete(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CompleteSheet(row: row, onSaved: onSaved),
    );
  }
}

class _CompleteSheet extends StatefulWidget {
  const _CompleteSheet({required this.row, required this.onSaved});

  final ImportProblemRow row;
  final Future<void> Function() onSaved;

  @override
  State<_CompleteSheet> createState() => _CompleteSheetState();
}

class _CompleteSheetState extends State<_CompleteSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.row.draft.name);
  late final TextEditingController _cost;
  late final TextEditingController _sell;
  late final TextEditingController _stock =
      TextEditingController(text: widget.row.draft.stockQty.toString());
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cost = TextEditingController(text: _majorText(widget.row.draft.costMinor));
    _sell = TextEditingController(text: _majorText(widget.row.draft.sellMinor));
  }

  static String _majorText(int? minor) =>
      minor == null ? '' : (minor / 100).toString();

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _sell.dispose();
    _stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: SingleChildScrollView(
          padding: EdgeInsetsDirectional.all(spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.importsCompleteTitle,
                  style: AppTypography.of(context).titleMedium),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _name,
                autocorrect: false,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.inventoryFieldName),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.fieldRequired(l10n.inventoryFieldName)
                    : null,
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: l10n.inventoryFieldCostPrice),
                validator: _priceValidator,
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _sell,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: l10n.inventoryFieldSellPrice),
                validator: _priceValidator,
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _stock,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: l10n.inventoryFieldStockQty),
                validator: (value) =>
                    double.tryParse((value ?? '').trim()) == null
                        ? l10n.fieldRequired(l10n.inventoryFieldStockQty)
                        : null,
              ),
              SizedBox(height: spacing.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.actionSave),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _priceValidator(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String text = (value ?? '').trim();
    if (text.isEmpty || SheetColumns.parseMinorUnits(text) == null) {
      return l10n.fieldRequired(l10n.importsPriceLabel);
    }
    return null;
  }

  String _localiseProblem(ProductProblem problem) =>
      ValidationUtils.productProblem(
        AppLocalizations.of(context),
        problem,
      );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final String name = _name.text.trim();
      final int cost = SheetColumns.parseMinorUnits(_cost.text)!;
      final int sell = SheetColumns.parseMinorUnits(_sell.text)!;
      final double stock = double.tryParse(_stock.text.trim()) ?? 0;

      // Built through the draft, not beside it: the draft's construction rules
      // (category inference, the import's defaults) are the import's own, and
      // the form supplies the values the owner edited.
      final ImportDraft draft = widget.row.draft;

      // Match on the name the file used — but only against active products.
      // A repaired row must not land on an inactive duplicate and vanish from
      // the till; inactive products are not matched at all, so a name that
      // exists only among inactive rows gets a new active product instead.
      final DatabaseHelper db = DatabaseHelper.instance;
      final String fileNamed = draft.name.trim().toLowerCase();
      Product? existing;
      for (final Product candidate in await db.getProducts(activeOnly: true)) {
        if (candidate.name.trim().toLowerCase() == fileNamed) {
          existing = candidate;
          break;
        }
      }
      final product = draft.build(
        name: name,
        costMinor: cost,
        sellMinor: sell,
        stockQty: stock,
        existing: existing,
      );

      // The shared rule set, identical to the editor and both importers, so the
      // form cannot persist a row every other write path refuses. Minor units
      // answer the validator's finite-and-not-negative questions the same way
      // majors do; the stock quantity is where the difference shows (NaN and
      // Infinity pass `double.tryParse` and are poison to every total).
      final ProductProblem? invalid = Product.validate(
        name: product.name,
        category: product.category,
        costPrice: product.costPrice.minorUnits,
        sellPrice: product.sellPrice.minorUnits,
        stockQty: product.stockQty,
        reorderLevel: product.reorderLevel,
        bottleMl: product.bottleMl,
      );
      if (invalid != null) {
        messenger
            .showSnackBar(SnackBar(content: Text(_localiseProblem(invalid))));
        return;
      }

      await db.upsertProduct(product);

      // Carry the existing product's barcodes over: a repaired row describes
      // the same product the import already wrote, and its codes are the
      // product's identity at the till. `upsertProduct` rewrites the whole
      // product row but does not touch `product_barcodes`, which lives in its
      // own table — so the codes survive on the existing row, but only if we
      // do not lose the existing row to a name-match against an inactive one.
      if (existing != null) {
        final codes = await db.getBarcodesForProduct(existing.id!);
        if (codes.isNotEmpty) {
          await db.addBarcodes(codes
              .map((c) => ProductBarcode(
                    productId: product.id!,
                    barcode: c.barcode,
                    kind: c.kind,
                  ))
              .toList());
        }
      }

      await db.resolveImportProblem(widget.row.problem.id!);

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onSaved();
      if (!mounted) return;
      // The row was repaired and saved. Said on a screen, because the owner
      // came here to fix ONE row and wants to know that it is fixed and can
      // move on to the next.
      showOperationSuccess(
        context,
        title: AppLocalizations.of(context).importRepairedTitle,
        message: product.name,
        detailIcon: Icons.build_outlined,
      );
    } catch (error) {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: AppLocalizations.of(context).importRepairFailedTitle,
        message: AppLocalizations.of(context).importSaveFailed,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
