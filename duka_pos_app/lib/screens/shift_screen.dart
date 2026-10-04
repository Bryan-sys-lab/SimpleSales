// Opening a shift, counting the till, and reconciling the difference.
//
// This is the screen that answers "where did the money go?". It is the only
// place in the app where a number the owner did not type is compared against a
// number the owner did type, and the whole design is arranged so that the
// comparison cannot flatter the shop by accident.
//
// Three rules shape it:
//
//   * A shift belongs to **one named person**. Sales are attributed by
//     `staff_id`, and `expectedCashForShift` scopes by the shift's staff id, so
//     a shared till where two people ring into one drawer does not hand the
//     second person a variance they did not cause.
//   * One shop's shifts live in **that shop's database file**. Workspaces are
//     one SQLite file each, so there is deliberately no shop column: a shift
//     cannot leak across shops because the two shops cannot see each other's
//     rows at all.
//   * The expected figure is **composed in one place**, `expectedTillBalance`,
//     so no caller can forget the float and report it as a variance.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../utils/money.dart';

/// The Kenyan notes and coins, largest first.
///
/// Fixed rather than configurable because a counting sheet that can be
/// reconfigured is a counting sheet that will be, and a denomination list is
/// not worth the settings it would cost. `[Product.maxBottleMl]`-style
/// extension points would only matter for a currency this app does not sell in.
const List<int> kTillDenominations = <int>[
  1000,
  500,
  200,
  100,
  50,
  20,
  10,
  5,
  1,
];

/// Reconcile the till for the signed-in person.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  Shift? _open;
  List<Shift> _history = const [];
  List<Reconciliation> _recentReconciliations = const [];
  Money _expected = Money.zero;
  bool _loading = true;
  String? _error;

  AppState get _state => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final staffId = _state.currentStaffId;
    // Managers and owners see the whole shop's shifts; a cashier sees only
    // their own, because "your shift balanced" is not a question anyone else
    // gets to audit from this screen.
    final scope = _state.seesAllSales ? null : staffId;
    final shifts = await db.getShifts(staffId: scope);
    if (!mounted) return;
    setState(() {
      _history = shifts.where((s) => s.status != 'open').toList();
      _open = shifts.where((s) => s.status == 'open').firstOrNull;
      _loading = false;
      _error = null;
    });
    await _refreshExpected();
    await _loadReconciliations();
  }

  Future<void> _refreshExpected() async {
    final shift = _open;
    if (shift == null) return;
    final expected = await DatabaseHelper.instance.expectedTillBalance(shift);
    if (!mounted) return;
    setState(() => _expected = expected);
  }

  Future<void> _loadReconciliations() async {
    final db = DatabaseHelper.instance;
    final loaded = <Reconciliation>[];
    for (final shift in _history.take(20)) {
      if (shift.id == null) continue;
      loaded.addAll(await db.getReconciliationsForShift(shift.id!));
    }
    if (!mounted) return;
    setState(() => _recentReconciliations = loaded);
  }

  /// The person a shift will be recorded against.
  ///
  /// An owner has no `staff` row — the owner lives in the `owner` table — so
  /// without one there is no id to attribute a shift to and no way to scope the
  /// expected figure. Rather than invent an id, the screen says so and offers to
  /// create the staff row, which is the same thing the roster already does.
  int? get _staffId => _state.currentStaffId;

  Future<void> _openShift() async {
    final state = _state;
    if (_staffId == null) {
      await _createStaffRowForShift();
      return;
    }
    final float = await askForFloat(
      context,
      title: 'Open shift',
      help: 'Cash in the drawer when you start. Count it now — it is what the '
          'closing count is measured against.',
      confirmLabel: 'Open shift',
    );
    if (float == null || !mounted) return;
    try {
      await DatabaseHelper.instance.openShift(
        staffId: _staffId!,
        staffName: state.currentStaffName ?? 'Unknown',
        startFloat: float,
      );
      await _load();
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Creates a `staff` row for someone who has none, so they can hold a shift.
  Future<void> _createStaffRowForShift() async {
    final name = _state.currentStaffName;
    if (name == null) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add yourself to the staff list'),
        content: Text(
            '$name signs in as the shop owner, and the owner is not on the '
            'staff roster. A shift is recorded against a staff entry so sales '
            'can be counted against it, so $name needs a roster entry of their '
            'own. No PIN is set, so this cannot be signed in to on its own.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add me'),
          ),
        ],
      ),
    );
    if (created != true) return;
    final id = await DatabaseHelper.instance.addStaff(
      Staff(
        name: name,
        // Unusable as a PIN: this row exists so an owner can hold and reconcile
        // a shift, not so anyone can sign in as it. A blank hash cannot be
        // derived, so the entry can never be selected at the PIN pad.
        pinHash: '',
        role: _state.currentRole,
      ),
    );
    // `signInAsOwner(staffId:)` is the only path that keeps the owner flag
    // *and* attaches a roster id. The generic `signIn` clears the id, which
    // would put the owner straight back where they started.
    _state.signInAsOwner(staffId: id);
    if (!mounted) return;
    await _openShiftForStaffId(id, name);
  }

  /// Opens a shift for a specific roster id, after the owner has no id of their
  /// own.
  Future<void> _openShiftForStaffId(int staffId, String name) async {
    final float = await askForFloat(
      context,
      title: 'Open shift',
      help: 'Cash in the drawer when you start.',
      confirmLabel: 'Open shift',
    );
    if (float == null || !mounted) return;
    try {
      await DatabaseHelper.instance.openShift(
        staffId: staffId,
        staffName: name,
        startFloat: float,
      );
      await _load();
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _countTill() async {
    final shift = _open;
    if (shift?.id == null) return;
    final counted = await showTillCountSheet(context, shiftId: shift!.id!);
    if (counted == null) return;
    await _refreshExpected();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Counted ${formatMoney(counted)} in the drawer.'),
    ));
  }

  Future<void> _closeShift() async {
    final shift = _open;
    if (shift?.id == null) return;
    final result = await showCloseShiftSheet(
      context,
      shift: shift!,
      expected: _expected,
    );
    if (result == null) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Shift closed. ${_describeVariance(result.variance)}'),
    ));
  }

  static String _describeVariance(Money variance) {
    if (variance.minorUnits == 0) return 'The drawer balanced exactly.';
    final amount = formatMoney(variance.abs);
    return variance.isNegative
        ? '$amount short of the expected figure.'
        : '$amount over the expected figure.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shift & reconciliation')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) _ErrorPanel(_error!),
                  if (_open != null)
                    _OpenShiftPanel(
                      shift: _open!,
                      expected: _expected,
                      onCount: _countTill,
                      onClose: _closeShift,
                    )
                  else
                    _NoShiftPanel(
                      canOpen: _state.currentStaffName != null,
                      onOpen: _openShift,
                    ),
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Past shifts',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final shift in _history.take(20))
                      _ShiftTile(shift: shift),
                  ],
                  if (_recentReconciliations.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Reconciliations',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final r in _recentReconciliations.take(20))
                      _ReconciliationTile(reconciliation: r),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Asks for a cash amount, returning it, or null if cancelled.
///
/// Rejects a negative amount in the dialog rather than on save, because a
/// negative float is not a state a shift can be in and the message is clearer
/// where the number was typed.
Future<Money?> askForFloat(
  BuildContext context, {
  required String title,
  required String help,
  required String confirmLabel,
  String? initialText,
}) async {
  final controller = TextEditingController(text: initialText ?? '');
  String? error;
  final result = await showDialog<Money>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (KSh)',
            helperText: help,
            errorText: error,
          ),
          onSubmitted: (_) {
            final money = parseAmount(controller.text);
            if (money == null) {
              setDialogState(() => error = 'Enter a number, 0 or more.');
              return;
            }
            Navigator.pop(dialogContext, money);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final money = parseAmount(controller.text);
              if (money == null) {
                setDialogState(() => error = 'Enter a number, 0 or more.');
                return;
              }
              Navigator.pop(dialogContext, money);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

Money? parseAmount(String raw) {
  final parsed = double.tryParse(raw.trim());
  if (parsed == null || !Money.isValidMajor(parsed)) return null;
  return Money.fromMajor(parsed);
}

/// Counts the drawer by denomination and returns the total.
///
/// The piles are written to `till_counts` so the *how* of the count survives,
/// not only the sum — which is the difference between "the drawer was short 400"
/// and a number an auditor can look at. A previous count is cleared first: see
/// `clearTillCounts` for why two attempts must not add together.
Future<Money?> showTillCountSheet(
  BuildContext context, {
  required int shiftId,
}) =>
    showModalBottomSheet<Money>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TillCountSheet(shiftId: shiftId),
    );

/// The counting sheet itself.
///
/// A widget rather than a `StatefulBuilder` with controllers built outside it,
/// because a controller created in a builder outlives nothing: disposing it as
/// soon as `showModalBottomSheet` returns races the route's exit transition and
/// throws "used after being disposed" on the way out of the sheet. Owning the
/// controllers here means they live exactly as long as the fields that read
/// them.
class _TillCountSheet extends StatefulWidget {
  const _TillCountSheet({required this.shiftId});

  final int shiftId;

  @override
  State<_TillCountSheet> createState() => _TillCountSheetState();
}

class _TillCountSheetState extends State<_TillCountSheet> {
  final Map<int, TextEditingController> _counts = {
    for (final d in kTillDenominations) d: TextEditingController(),
  };

  bool _saving = false;

  /// What the drawer holds according to what has been typed so far.
  Money get _total {
    var sum = Money.zero;
    for (final entry in _counts.entries) {
      final n = int.tryParse(entry.value.text.trim()) ?? 0;
      if (n > 0) sum = sum + Money.fromMajor(entry.key * n);
    }
    return sum;
  }

  Money _valueOf(int denomination) => Money.fromMajor(
      denomination * (int.tryParse(_counts[denomination]!.text.trim()) ?? 0));

  @override
  void initState() {
    super.initState();
    _seedFromLastCount();
  }

  /// Fills the fields from the last count, so a cashier who reopened the sheet
  /// corrects a number rather than re-entering every pile from memory.
  Future<void> _seedFromLastCount() async {
    final previous =
        await DatabaseHelper.instance.getTillCounts(widget.shiftId);
    if (!mounted) return;
    for (final pile in previous) {
      final denomination = pile.value.minorUnits ~/ kMinorUnitsPerMajor;
      final controller = _counts[denomination];
      if (controller == null || controller.text.isNotEmpty) continue;
      if (pile.count > 0) controller.text = '${pile.count}';
    }
  }

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final db = DatabaseHelper.instance;
    try {
      // Cleared before it is written again: a second attempt must replace the
      // first rather than add to it, which would report roughly double the
      // cash in the drawer.
      await db.clearTillCounts(widget.shiftId);
      for (final entry in _counts.entries) {
        final n = int.tryParse(entry.value.text.trim()) ?? 0;
        if (n <= 0) continue;
        await db.addTillCount(
          shiftId: widget.shiftId,
          denomination: 'KSh ${entry.key}',
          count: n,
          value: Money.fromMajor(entry.key * n),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, _total);
    } catch (_) {
      if (!mounted) return;
      // The count is not lost on a failed write — it stays in the fields — so
      // the message says what to do rather than what went wrong internally.
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't save the count. Try again."),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Count the till',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Enter how many of each note and coin is in the drawer.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final d in kTillDenominations)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text('KSh $d',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _counts[d],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'How many',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 96,
                        child: Text(
                          formatMoney(_valueOf(d)),
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                      child: Text('Counted',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  // Announced, because the total is the figure the cashier is
                  // about to commit to and it changes with every keystroke.
                  Semantics(
                    liveRegion: true,
                    label: 'Counted so far',
                    child: Text(
                      formatMoney(_total),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving' : 'Save count'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Closes a shift: shows the expected figure, takes the count, and records the
/// variance.
///
/// Returns the recorded variance so the caller can say what happened, or null if
/// the cashier backed out.
///
/// A widget rather than a dialog built around locally-created controllers, for
/// the same reason as the counting sheet: disposing a controller while its route
/// is still animating out throws. `showDialog` returning is not the route being
/// gone.
Future<Reconciliation?> showCloseShiftSheet(
  BuildContext context, {
  required Shift shift,
  required Money expected,
}) =>
    showDialog<Reconciliation>(
      context: context,
      builder: (_) => _CloseShiftDialog(shift: shift, expected: expected),
    );

class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog({required this.shift, required this.expected});

  final Shift shift;
  final Money expected;

  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  late final TextEditingController _counted;
  late final TextEditingController _nextFloat;
  String? _error;
  bool _saving = false;

  /// The count taken by denomination, preferred over a typed figure: it is the
  /// one the cashier can be asked to justify line by line. Prefilling from it is
  /// also what makes "Count the till" feed reconciliation rather than being a
  /// separate chore.
  Future<Money> _recordedCount() async =>
      DatabaseHelper.instance.countedCashFromTillCounts(widget.shift.id!);

  @override
  void initState() {
    super.initState();
    // Prefilled once the recorded piles are known; blank until then so the
    // field never shows a number the shop has not confirmed.
    _counted = TextEditingController();
    _nextFloat = TextEditingController();
    _recordedCount().then((counted) {
      if (!mounted || counted.minorUnits == 0) return;
      _counted.text = counted.asMajor.toStringAsFixed(2);
      _nextFloat.text = counted.asMajor.toStringAsFixed(2);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _counted.dispose();
    _nextFloat.dispose();
    super.dispose();
  }

  Money? get _typed => parseAmount(_counted.text);

  Money get _variance => (_typed ?? Money.zero) - widget.expected;

  Future<void> _close() async {
    if (_saving) return;
    final typed = _typed;
    if (typed == null) {
      setState(() => _error = 'Enter what is actually in the drawer.');
      return;
    }
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
      if (!mounted) return;
      Navigator.pop(
        context,
        Reconciliation(
          shiftId: widget.shift.id!,
          countedCash: typed,
          expectedCash: widget.expected,
          variance: typed - widget.expected,
          recordedAt: DateTime.now().toIso8601String(),
        ),
      );
    } on StateError catch (e) {
      // A closed shift says so here rather than failing somewhere deeper.
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
          _error = "Couldn't close the shift. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Close shift'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MoneyRow(label: 'Opening float', value: widget.shift.startFloat),
            _MoneyRow(
              label: 'Cash sales this shift',
              value: widget.expected - widget.shift.startFloat,
            ),
            const Divider(),
            _MoneyRow(label: 'Expected in drawer', value: widget.expected),
            const SizedBox(height: 12),
            TextField(
              controller: _counted,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Counted in the drawer',
                helperText:
                    'Pre-filled from your count. Correct it if it changed.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              label: 'Difference between counted and expected',
              child: Row(
                children: [
                  const Expanded(
                      child: Text('Difference',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  Text(_varianceText(_variance),
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nextFloat,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Float for the next shift',
                helperText: 'What stays in the drawer',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _close,
          child: const Text('Close shift'),
        ),
      ],
    );
  }
}

String _varianceText(Money variance) {
  if (variance.minorUnits == 0) return 'Balanced';
  return variance.isNegative
      ? '${formatMoney(variance.abs)} short'
      : '${formatMoney(variance.abs)} over';
}

/// One labelled money figure. The label carries the meaning, so the row does not
/// rely on position or colour to say which number it is.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.value});

  final String label;
  final Money value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(formatMoney(value),
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}

/// The shift currently open, with the two things that end it.
class _OpenShiftPanel extends StatelessWidget {
  const _OpenShiftPanel({
    required this.shift,
    required this.expected,
    required this.onCount,
    required this.onClose,
  });

  final Shift shift;
  final Money expected;
  final VoidCallback onCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = _readableTime(shift.startTime);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.play_circle_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Shift open', style: theme.textTheme.titleMedium),
                ),
                Semantics(
                  label: 'Cashier ${shift.staffName}',
                  child: Text(shift.staffName),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Started $started', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            _MoneyRow(label: 'Opening float', value: shift.startFloat),
            _MoneyRow(label: 'Expected in drawer now', value: expected),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onCount,
              icon: const Icon(Icons.pin_outlined),
              label: const Text('Count the till'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Close and reconcile'),
            ),
          ],
        ),
      ),
    );
  }
}

/// No shift open for this person.
class _NoShiftPanel extends StatelessWidget {
  const _NoShiftPanel({required this.canOpen, required this.onOpen});

  final bool canOpen;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.pause_circle_outline),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('No shift open',
                        style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            // Said plainly, because the consequence is not obvious: without an
            // open shift there is nothing to reconcile this cashier's cash
            // against when they finish.
            Text(
              'Open a shift to count the cash you start and end the day with. '
              'Without one there is nothing to reconcile against.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (canOpen)
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Open shift'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftTile extends StatelessWidget {
  const _ShiftTile({required this.shift});

  final Shift shift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_circle_outline),
      title: Text(shift.staffName),
      subtitle: Text(
          '${_readableTime(shift.startTime)} · float ${formatMoney(shift.startFloat)}'),
      trailing:
          Text(formatMoney(shift.endFloat), style: theme.textTheme.bodySmall),
    );
  }
}

class _ReconciliationTile extends StatelessWidget {
  const _ReconciliationTile({required this.reconciliation});

  final Reconciliation reconciliation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = reconciliation.variance;
    // The word carries the state as well as the number, so it is never colour
    // alone and it is what a screen reader announces.
    final verdict = v.minorUnits == 0
        ? 'Balanced'
        : v.isNegative
            ? '${formatMoney(v.abs)} short'
            : '${formatMoney(v.abs)} over';
    return ListTile(
      dense: true,
      leading: Icon(
        v.minorUnits == 0
            ? Icons.check_circle_outline
            : v.isNegative
                ? Icons.trending_down
                : Icons.trending_up,
      ),
      title:
          Text('$verdict · counted ${formatMoney(reconciliation.countedCash)}'),
      subtitle: Text('Expected ${formatMoney(reconciliation.expectedCash)}',
          style: theme.textTheme.bodySmall),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          liveRegion: true,
          child: Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(message,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// An ISO timestamp as the owner reads it, or the raw value if unparseable.
///
/// Never throws: a timestamp this app did not write must not be the reason a
/// cashier cannot see their shift.
String _readableTime(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}
