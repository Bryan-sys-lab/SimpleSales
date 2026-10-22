// Counting the drawer, one denomination at a time.
//
// The piles are written to `till_counts` so the HOW of the count survives, not
// only the sum. That is the whole difference between "the drawer was short 400"
// and a number an auditor can look at and agree with.
//
// The running total is a live region and the largest figure on the sheet. That is
// deliberate: a cashier counting a drawer is working out one question — how much
// is in here — and every keystroke changes the answer to it. Making them add nine
// rows in their head to get it is the single most common way a manual till count
// goes wrong.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../utils/money.dart';
import '../utils/text_input.dart';

/// The Kenyan notes and coins, largest first.
///
/// Fixed rather than configurable because a counting sheet that can be
/// reconfigured is a counting sheet that will be, and a denomination list is not
/// worth the settings it would cost. A `[Product.maxBottleMl]`-style extension
/// point would only matter for a currency this app does not sell in.
const List<int> kTillDenominations = <int>[
  1000,
  500,
  200,
  100,
  50,
  20,
  10,
  5,
  1
];

/// Counts the drawer by denomination and returns the total, or null if backed
/// out.
///
/// A widget owns its own controllers, for the reason `shift_float_sheet.dart`
/// states: a controller disposed while the sheet is still animating out throws on
/// the way out, and only on some devices.
Future<Money?> showTillCountSheet(
  BuildContext context, {
  required int shiftId,
}) {
  return showModalBottomSheet<Money>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) => _TillCountSheet(shiftId: shiftId),
  );
}

class _TillCountSheet extends StatefulWidget {
  const _TillCountSheet({required this.shiftId});

  final int shiftId;

  @override
  State<_TillCountSheet> createState() => _TillCountSheetState();
}

class _TillCountSheetState extends State<_TillCountSheet> {
  final Map<int, TextEditingController> _counts = <int, TextEditingController>{
    for (final int denomination in kTillDenominations)
      denomination: TextEditingController(),
  };

  bool _saving = false;

  /// What the drawer holds according to what has been typed so far.
  Money get _total {
    Money sum = Money.zero;
    for (final int denomination in kTillDenominations) {
      final int? count = _pile(denomination);
      if (count == null || count <= 0) continue;
      sum = sum + Money.fromMajor(denomination * count);
    }
    return sum;
  }

  int? _pile(int denomination) => parseUserCount(_counts[denomination]!.text);

  Money _valueOf(int denomination) {
    final int? count = _pile(denomination);
    if (count == null || count <= 0) return Money.zero;
    return Money.fromMajor(denomination * count);
  }

  @override
  void initState() {
    super.initState();
    _seedFromLastCount();
  }

  /// Fills the fields from the last count, so a cashier who reopened the sheet
  /// corrects a number rather than re-entering every pile from memory.
  ///
  /// Outside `build()` and deliberately not awaited by it: this is real database
  /// I/O, and doing it inline would mean a query on every rebuild of a sheet
  /// whose whole point is that it responds to every keystroke.
  Future<void> _seedFromLastCount() async {
    final List<TillCount> previous =
        await DatabaseHelper.instance.getTillCounts(widget.shiftId);
    if (!mounted) return;
    for (final TillCount pile in previous) {
      final int denomination = pile.value.minorUnits ~/ kMinorUnitsPerMajor;
      final TextEditingController? controller = _counts[denomination];
      if (controller == null || controller.text.isNotEmpty) continue;
      if (pile.count > 0) controller.text = '${pile.count}';
    }
    setState(() {});
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _counts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final DatabaseHelper db = DatabaseHelper.instance;
      // Cleared before it is written again: a second attempt must REPLACE the
      // first rather than add to it, which would report roughly double the cash
      // in the drawer.
      await db.clearTillCounts(widget.shiftId);
      for (final int denomination in kTillDenominations) {
        final int? count = _pile(denomination);
        if (count == null || count <= 0) continue;
        await db.addTillCount(
          shiftId: widget.shiftId,
          // The stored label is what an auditor reads back later, so it is the
          // formatted amount rather than a bare number. `formatMoney` already
          // carries the currency symbol; prefixing one here writes "KSh KSh 50".
          denomination: formatMoney(Money.fromMajor(denomination)),
          count: count,
          value: Money.fromMajor(denomination * count),
        );
      }
    } on Object {
      if (!mounted) return;
      // The count is not lost on a failed write — it stays in the fields — so the
      // message says what to do rather than what went wrong internally.
      setState(() => _saving = false);
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context).shiftCountSaveFailed,
      );
      return;
    }

    if (!mounted) return;
    HapticTheme.of(context).fire(HapticEvent.commit);
    Navigator.of(context).pop(_total);
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final Money total = _total;

    return Padding(
      // `viewInsetsOf`, not `MediaQuery.of(context).viewInsets`: the aspect
      // getter rebuilds only when the keyboard appears or hides.
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
                spacing.sm,
                spacing.md,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    AppLocalizations.of(context).shiftCountTitle,
                    style: AppTypography.of(context).titleLarge,
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    AppLocalizations.of(context).shiftCountSubtitle,
                    style: AppTypography.of(context)
                        .bodyMedium
                        ?.copyWith(color: colors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            // Flexible, not a fixed height: nine rows at 200% text are roughly
            // twice this tall, and a fixed box would clip the last denominations
            // — which are the coins, and a clipped coin row is a silently wrong
            // count.
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < kTillDenominations.length; i++)
                      TillDenominationRow(
                        denomination: kTillDenominations[i],
                        controller: _counts[kTillDenominations[i]]!,
                        value: _valueOf(kTillDenominations[i]),
                        showDivider: i != kTillDenominations.length - 1,
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
              ),
            ),
            TillCountTotal(total: total),
            ActionBar(
              secondary: TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(AppLocalizations.of(context).actionCancel),
              ),
              primary: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? AppLocalizations.of(context).shiftCountSaving
                      : AppLocalizations.of(context).shiftCountSave,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One note or coin: its face value, how many, and what that pile is worth.
///
/// Public rather than private so the layout can be swept on its own across the
/// device x scale matrix. Nine of these is the widest table in the app, and it
/// is the one whose overflow would silently produce a WRONG count rather than a
/// visible error.
///
/// The pile value is on the same row as the count rather than below it, because
/// the question at a drawer is "what is that pile worth", and making the eye
/// travel between two rows once per denomination is nine extra saccades per count.
class TillDenominationRow extends StatelessWidget {
  const TillDenominationRow({
    required this.denomination,
    required this.controller,
    required this.value,
    required this.showDivider,
    required this.onChanged,
    super.key,
  });

  final int denomination;
  final TextEditingController controller;
  final Money value;
  final bool showDivider;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final String face = formatMoney(Money.fromMajor(denomination));

    final Widget row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        // `sm` vertical rather than a fixed `SizedBox(height: n)`: the row holds
        // text, and a fixed height is what clips it at 200%.
        vertical: spacing.sm,
      ),
      child: Row(
        children: <Widget>[
          // Every column is `Flexible`, not a fixed width with one `Expanded`
          // between it. At 200% text on a 320dp till a fixed denomination column
          // plus a fixed money column leaves the input field ~80px — too narrow
          // for its own floating label — and the row is then either an overflow
          // or an unreadable field. Flexing all three lets the row reflow instead.
          Flexible(
            flex: 5,
            child: Text(
              face,
              style: AppTypography.of(context)
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: spacing.sm),
          Flexible(
            flex: 4,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(userDigitsPattern),
              ],
              // A number column reads down its end edge in LTR and its start edge
              // in RTL. `.end` follows the locale; `.right` would misalign the
              // whole column under RTL.
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                isDense: true,
                labelText: AppLocalizations.of(context).shiftCountPileLabel,
                contentPadding: EdgeInsets.symmetric(horizontal: spacing.md),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          SizedBox(width: spacing.sm),
          Flexible(
            flex: 5,
            child: MoneyText(
              amount: formatMoney(value),
              size: 15,
              weight: FontWeight.w600,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );

    if (!showDivider) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        row,
        Divider(height: 1, color: colors.outline),
      ],
    );
  }
}

/// The running total, announced on every change.
class TillCountTotal extends StatelessWidget {
  const TillCountTotal({required this.total, super.key});

  final Money total;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: Border(
          top: BorderSide(color: colors.outline),
          bottom: BorderSide(color: colors.outline),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                AppLocalizations.of(context).shiftCountTotalLabel,
                style: AppTypography.of(context).titleSmall,
              ),
            ),
            // A live region: the figure changes with every keystroke, and a
            // cashier who cannot see the screen changing still needs to know the
            // running total moved.
            Semantics(
              liveRegion: true,
              label: AppLocalizations.of(context)
                  .shiftCountTotalSpoken(formatMoney(total)),
              excludeSemantics: true,
              child: ExcludeSemantics(
                child: MoneyText(
                  amount: formatMoney(total),
                  size: 24,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
