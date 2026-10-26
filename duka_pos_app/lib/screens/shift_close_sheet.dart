// Closing a shift: what the ledger says should be in the drawer, what is, and the
// difference between them.
//
// This is the one screen in the app where a number nobody typed is compared
// against a number someone did, and the whole layout is arranged so the
// comparison cannot flatter the shop by accident:
//
//   * The EXPECTED figure is stated first and in the largest type, because it is
//     the figure the count is against. A sheet that led with the counted figure
//     lets the cashier confirm their own number back to themselves.
//   * The difference is recomputed on every keystroke and announced, so a
//     cashier who types 4,000 instead of 4,400 finds out before they commit
//     rather than in next week's report.
//   * The count taken by denomination is preferred over a typed figure and
//     prefills the field, which is what makes "Count the till" feed
//     reconciliation instead of being a separate chore.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../utils/money.dart';
import '../utils/text_input.dart';
import 'shift_float_sheet.dart' show parseAmount;
import 'shift_variance.dart';

/// Closes a shift and records the variance.
///
/// Returns the recorded reconciliation, or null when the cashier backed out.
///
/// `null` is unambiguous here, unlike a confirmation: nothing is written until
/// the sheet commits, so a dismissal and a cancel both mean the same honest
/// thing — the shift is still open and nothing was recorded.
Future<Reconciliation?> showCloseShiftSheet(
  BuildContext context, {
  required Shift shift,
  required Money expected,
}) {
  return showModalBottomSheet<Reconciliation>(
    context: context,
    isScrollControlled: true,
    // A decision that must resolve now, so a tap on the scrim does not silently
    // leave the shift half-closed in the cashier's head. There is a Cancel
    // button; there is no accidental way out.
    isDismissible: false,
    enableDrag: false,
    builder: (BuildContext context) => _CloseShiftSheet(
      shift: shift,
      expected: expected,
    ),
  );
}

class _CloseShiftSheet extends StatefulWidget {
  const _CloseShiftSheet({required this.shift, required this.expected});

  final Shift shift;
  final Money expected;

  @override
  State<_CloseShiftSheet> createState() => _CloseShiftSheetState();
}

class _CloseShiftSheetState extends State<_CloseShiftSheet> {
  late final TextEditingController _counted;
  late final TextEditingController _nextFloat;

  String? _error;
  bool _saving = false;
  Map<String, int>? _breakdown;

  @override
  void initState() {
    super.initState();
    // Prefilled once the recorded piles are known; blank until then, so the
    // field never shows a number the shop has not confirmed.
    _counted = TextEditingController();
    _nextFloat = TextEditingController();
    _loadBreakdown();
    _prefillFromRecordedCount();
  }

  Future<void> _loadBreakdown() async {
    final value =
        await DatabaseHelper.instance.expectedCashBreakdown(widget.shift);
    if (mounted) setState(() => _breakdown = value);
  }

  Future<void> _prefillFromRecordedCount() async {
    final int? shiftId = widget.shift.id;
    if (shiftId == null) return;

    final Money counted =
        await DatabaseHelper.instance.countedCashFromTillCounts(shiftId);
    if (!mounted || counted.isZero) return;

    final String typed = counted.asMajor.toStringAsFixed(2);
    _counted.text = typed;
    // The float the next shift opens with defaults to whatever was counted: the
    // usual close leaves the counted cash in the drawer, and making the cashier
    // retype it invites a transcription error on the one figure that carries into
    // tomorrow.
    _nextFloat.text = typed;
    setState(() {});
  }

  @override
  void dispose() {
    _counted.dispose();
    _nextFloat.dispose();
    super.dispose();
  }

  Money? get _typed => parseAmount(_counted.text);

  /// The difference as it stands right now.
  ///
  /// Zero when the field is empty, so the sheet shows "Not counted" rather than
  /// a confident "KSh 5,000 short" against a figure nobody typed.
  ShiftVariance get _variance {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Money? typed = _typed;
    if (typed == null) return ShiftVariance.notCounted(l10n);
    return ShiftVariance.between(l10n, typed, widget.expected);
  }

  Future<void> _close() async {
    if (_saving) return;
    final Money? typed = _typed;

    if (typed == null) {
      HapticTheme.of(context).fire(HapticEvent.reject);
      setState(
          () => _error = AppLocalizations.of(context).shiftCloseCountedMissing);
      return;
    }

    final NavigatorState navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await DatabaseHelper.instance.reconcileShift(
        shiftId: widget.shift.id!,
        countedCash: typed,
        expectedCash: widget.expected,
        // What stays in the drawer becomes the next shift's float. Omitting it
        // records the counted cash, which is the same thing; the field is there
        // for the shift that ends with the drawer emptied.
        endFloat: parseAmount(_nextFloat.text) ?? typed,
      );
    } on StateError catch (error) {
      // A closed shift says so here rather than failing somewhere deeper, and
      // the exception's own message is one this app wrote for exactly this case.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppLocalizations.of(context).shiftCloseFailed;
      });
      return;
    }

    if (!mounted) return;
    HapticTheme.of(context).fire(HapticEvent.milestone);
    navigator.pop(
      Reconciliation(
        shiftId: widget.shift.id!,
        countedCash: typed,
        expectedCash: widget.expected,
        variance: typed - widget.expected,
        recordedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                spacing.md,
                spacing.md,
                spacing.md,
                0,
              ),
              child: Text(
                AppLocalizations.of(context).shiftCloseTitle,
                style: AppTypography.of(context).titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _ExpectedPanel(
                      startFloat: widget.shift.startFloat,
                      expected: widget.expected,
                      breakdown: _breakdown,
                    ),
                    SizedBox(height: spacing.lg),
                    TextField(
                      controller: _counted,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(userNumberPattern),
                      ],
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context).shiftCloseCountedLabel,
                        helperText:
                            AppLocalizations.of(context).shiftCloseCountedHelp,
                        prefixIcon: const Icon(Icons.point_of_sale_outlined),
                      ),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                        setState(() {});
                      },
                    ),
                    SizedBox(height: spacing.md),
                    VarianceStrip(variance: _variance),
                    SizedBox(height: spacing.lg),
                    TextField(
                      controller: _nextFloat,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(userNumberPattern),
                      ],
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)
                            .shiftCloseNextFloatLabel,
                        helperText: AppLocalizations.of(context)
                            .shiftCloseNextFloatHelp,
                        prefixIcon: const Icon(Icons.savings_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_error != null)
                      Padding(
                        padding: EdgeInsets.only(top: spacing.md),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style:
                                AppTypography.of(context).bodyMedium?.copyWith(
                                      color: AppColors.of(context).danger,
                                    ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ActionBar(
              secondary: TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child:
                    Text(AppLocalizations.of(context).shiftCloseKeepCounting),
              ),
              primary: FilledButton(
                onPressed: _saving ? null : _close,
                child: Text(
                  _saving
                      ? AppLocalizations.of(context).shiftCloseCommitting
                      : AppLocalizations.of(context).shiftCloseCommit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the ledger says should be in the drawer, and how it got there.
///
/// The composition is shown rather than only its result. An owner who reconciles
/// a variance of KSh 5,000 needs to see whether it came out of the float or out
/// of the takings, and that is visible here and nowhere else.
class _ExpectedPanel extends StatelessWidget {
  const _ExpectedPanel({
    required this.startFloat,
    required this.expected,
    this.breakdown,
  });

  final Money startFloat;
  final Money expected;
  final Map<String, int>? breakdown;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SurfaceCard(
      color: AppColors.of(context).surfaceSunken,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          KeyValueRow(
            label: AppLocalizations.of(context).shiftOpeningFloat,
            value: formatMoney(startFloat),
            showDivider: true,
          ),
          KeyValueRow(
            label: AppLocalizations.of(context).shiftCloseCashRungUp,
            value: formatMoney(expected - startFloat),
            showDivider: true,
          ),
          if (breakdown != null) ...<Widget>[
            _BreakdownRow(
                label: 'Cash sales', minor: breakdown!['cash_sales'] ?? 0),
            _BreakdownRow(
                label: 'Cash refunds',
                minor: -(breakdown!['cash_refunds'] ?? 0)),
            _BreakdownRow(
                label: 'Credit repayments',
                minor: breakdown!['credit_repayments'] ?? 0),
            _BreakdownRow(
                label: 'Till expenses',
                minor: -(breakdown!['till_expenses'] ?? 0)),
            _BreakdownRow(
                label: 'Till movements',
                minor: breakdown!['till_movements'] ?? 0),
          ],
          Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).shiftExpectedLabel,
                    style: type.titleSmall,
                  ),
                ),
                MoneyText(
                  amount: formatMoney(expected),
                  size: 22,
                  weight: FontWeight.w800,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.label, required this.minor});

  final String label;
  final int minor;

  @override
  Widget build(BuildContext context) => KeyValueRow(
        label: label,
        value: formatMoney(Money.fromMinor(minor)),
        showDivider: true,
      );
}

/// A variance, as glyph + word + figure, announced on every change.
///
/// One component rather than three call sites' worth of inline rows: the whole
/// point of the screen is that the difference is legible, and three hand-rolled
/// versions of the same strip is how one of them ends up colour-only.
class VarianceStrip extends StatelessWidget {
  const VarianceStrip({required this.variance, super.key});

  final ShiftVariance variance;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Semantics(
      liveRegion: true,
      container: true,
      label: l10n.varianceStripSpoken(variance.spoken),
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: variance.tone.container(colors),
            borderRadius: AppShapes.of(context).controlRadius,
            border: Border.all(color: variance.tone.color(colors)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        variance.isZero
                            ? l10n.varianceDifferenceLabel
                            : variance.isShort
                                ? l10n.varianceShortByLabel
                                : l10n.varianceOverByLabel,
                        style: AppTypography.of(context).titleSmall?.copyWith(
                              color: variance.tone.onContainer(colors),
                            ),
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    StatusChip(tone: variance.tone, text: variance.word),
                  ],
                ),
                // The figure on its OWN line, right-aligned, rather than beside
                // the chip. At 200% text on a 320dp till "KSh 12,340.00 short
                // by Balanced" does not fit in a row, and a `Row` that overflows
                // is a BLOCKER; a `Column` cannot overflow at all. It also reads
                // better: the number is the thing being looked at.
                if (!variance.isZero) ...<Widget>[
                  SizedBox(height: spacing.sm),
                  MoneyText(
                    amount: formatMoney(variance.magnitude),
                    size: 22,
                    weight: FontWeight.w800,
                    textAlign: TextAlign.end,
                    color: variance.tone.onContainer(colors),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
