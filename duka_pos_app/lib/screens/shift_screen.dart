// Opening a shift, counting the till, and reconciling the difference.
//
// This is the screen that answers "where did the money go?". It is the only
// place in the app where a number nobody typed is compared against a number
// somebody did, and the whole design is arranged so that comparison cannot
// flatter the shop by accident.
//
// Three rules shape it, and all three are load-bearing:
//
//   * A shift belongs to **one named person**. Sales are attributed by
//     `staff_id`, and `expectedCashForShift` scopes by the shift's staff id, so
//     a shared till where two people ring into one drawer does not hand the
//     second person a variance they did not cause.
//   * One shop's shifts live in **that shop's database file**. Workspaces are one
//     SQLite file each, so there is deliberately no shop column: a shift cannot
//     leak across shops because the two shops cannot see each other's rows at
//     all.
//   * The expected figure is **composed in one place**, `expectedTillBalance`,
//     so no caller can forget the float and report it as a variance.
//
// The screen reads nothing itself — [loadShiftLedger] resolves the figures and
// this file renders them — and its own state is a sealed value with four cases.
// The interesting shape here is "a shift is open AND a previous count disagrees
// with the ledger", which three parallel booleans cannot represent without at
// some point showing a variance against a drawer nobody counted.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../models/audit_log.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../services/session_refresh_mixin.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/datetime_format.dart';
import '../utils/money.dart';
import 'shift_close_sheet.dart';
import 'shift_float_sheet.dart';
import 'shift_history_card.dart';
import 'shift_ledger.dart';
import 'shift_till_count_sheet.dart';
import 'shift_variance.dart';

sealed class _ShiftState {
  const _ShiftState();
}

final class _ShiftLoading extends _ShiftState {
  const _ShiftLoading();
}

final class _ShiftFailed extends _ShiftState {
  const _ShiftFailed();
}

final class _ShiftReady extends _ShiftState {
  const _ShiftReady({required this.ledger, required this.message});

  final ShiftLedger ledger;

  final String? message;
}

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen>
    with SessionRefresh<ShiftScreen> {
  _ShiftState? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void clearForSession() {
    _state = null;
  }

  @override
  Future<void> reloadFromSession() => _load();

  AppState get _appState => context.read<AppState>();

  int? get _staffId => _appState.currentStaffId;

  Future<void> _load() async {
    // The first load has nothing to keep; a later reload leaves `_state` alone,
    // which is what keeps the figures on screen while a cashier pulls to refresh
    // mid-queue.
    setState(() => _state ??= const _ShiftLoading());

    final AppState appState = _appState;
    // Whose shift this read is for. A ledger that outlives its session is
    // dropped rather than painted: it is one person's reconciliation, and the
    // next person's must come from the next person's read.
    final int session = appState.sessionGeneration;
    try {
      final ShiftLedger ledger = await loadShiftLedger(
        viewerStaffId: appState.currentStaffId,
        seesAllSales: appState.seesAllSales,
      );
      if (!mounted || appState.sessionGeneration != session) return;
      setState(() => _ShiftReady(ledger: ledger, message: null));
    } on Object {
      if (!mounted || appState.sessionGeneration != session) return;
      // A refresh that fails keeps what it had: the figures on screen are still
      // true as of the last successful read, and blanking them turns a dropped
      // read into an empty shift ledger.
      setState(() => _state ??= const _ShiftFailed());
    }
  }

  /// Puts a business failure on screen instead of throwing it away.
  void _reportBusinessFailure(String message) {
    setState(() {
      final _ShiftReady? ready = _state as _ShiftReady?;
      if (ready == null) return;
      _state = _ShiftReady(ledger: ready.ledger, message: message);
    });
  }

  Future<void> _openShift() async {
    if (_staffId == null) {
      await _createStaffRowForShift();
      return;
    }
    await _openShiftForStaffId(
      _staffId!,
      _appState.currentStaffName ?? 'Unknown',
    );
  }

  /// Creates a `staff` row for someone who has none, so they can hold a shift.
  Future<void> _createStaffRowForShift() async {
    final String? name = _appState.currentStaffName;
    if (name == null) return;

    final _RosterOffer? offer = await showDialog<_RosterOffer>(
      context: context,
      builder: (BuildContext context) => _AddRosterEntryDialog(name: name),
    );
    if (offer != null) {
      await _openShiftForStaffId(
        offer.staffId,
        name,
      );
      return;
    }
    if (!mounted) return;
    // Dialog dismissed or declined: the screen still has to say why nothing
    // happened, or the button looks broken.
    showAppSnackBar(
      context,
      message: 'A shift needs a staff entry. Add yourself in Settings, then '
          'open the shift.',
    );
  }

  /// Asks for the float and opens a shift against [staffId].
  ///
  /// One path for both callers, because the two places it used to be duplicated
  /// had already drifted. It asks for the figure and nothing else: the sheet's

  Future<void> _openShiftForStaffId(int staffId, String name) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Money? openingFloat = await showFloatSheet(
      context,
      title: l10n.shiftCloseTitle,
      confirmLabel: l10n.shiftNoShiftAction,
    );
    if (openingFloat == null || !mounted) return;

    try {
      await DatabaseHelper.instance.openShift(
        staffId: staffId,
        staffName: name,
        startFloat: openingFloat,
      );
      // A shift is the unit everything else is accounted against: which sales
      // belong to which drawer, and whose float it was. Recording the FLOAT is
      // what makes a short drawer reconstructible later.
      await recordActionAudit(
        _appState,
        action: AuditAction.shiftOpened,
        entity: AuditEntity.shift,
        entityId: 'id-$staffId',
        detail: 'float ${formatMoney(openingFloat)}',
      );
      if (!mounted) return;
      HapticTheme.of(context).fire(HapticEvent.commit);
      await _load();
    } on StateError catch (error) {
      if (mounted) _reportBusinessFailure(error.message);
    }
  }

  Future<void> _countTill() async {
    final int? shiftId = (_state as _ShiftReady?)?.ledger.open?.id;
    if (shiftId == null) return;

    final Money? counted = await showTillCountSheet(context, shiftId: shiftId);
    if (counted == null || !mounted) return;

    await _load();
    if (!mounted) return;
    showAppSnackBar(
      context,
      message:
          AppLocalizations.of(context).shiftCountedSnack(formatMoney(counted)),
    );
  }

  Future<void> _closeShift() async {
    final ShiftLedger? ledger = (_state as _ShiftReady?)?.ledger;
    final Shift? open = ledger?.open;
    if (open == null || !mounted) return;

    final Reconciliation? result = await showCloseShiftSheet(
      context,
      shift: open,
      expected: ledger!.expected,
    );
    if (result == null || !mounted) return;

    final AppLocalizations l10n = AppLocalizations.of(context);
    final ShiftVariance variance =
        ShiftVariance.between(l10n, result.countedCash, result.expectedCash);
    // `milestone` only when the drawer balanced. A shortage is a problem to work
    // through, and spending the one distinct buzz level the app owns on it would
    // teach an operator to ignore it.
    HapticTheme.of(context).fire(
      variance.isZero ? HapticEvent.milestone : HapticEvent.commit,
    );

    // Logged before the snackbar and the reload, both of which are UI-only:
    // the reconciliation is the fact, and a variance on it is the number an
    // owner reviews first.
    await recordActionAudit(
      _appState,
      action: AuditAction.shiftClosed,
      entity: AuditEntity.shift,
      entityId: 'id-${open.id}',
      detail: 'counted ${formatMoney(result.countedCash)}, '
          'expected ${formatMoney(result.expectedCash)}',
    );

    if (!mounted) return;
    showAppSnackBar(
      context,
      message: describeClosedShift(l10n, variance),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // A `Scaffold`, and not a bare `AdaptivePage`.
    //
    // This screen is PUSHED on the root navigator, so it owns its back button and
    // its title — a branch-root screen gets both from the shell, a pushed one
    // does not. The `Scaffold` is also what gives `showAppSnackBar` a
    // `ScaffoldMessenger` to reach: without one, every confirmation on this screen
    // silently goes nowhere.
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).shiftScreenTitle),
      ),
      body: switch (_state) {
        null || _ShiftLoading() => const _ShiftSkeleton(),
        _ShiftFailed() => ErrorStateView(
            message: AppLocalizations.of(context).shiftLoadFailedTitle,
            detail: AppLocalizations.of(context).shiftLoadFailedDetail,
            onRetry: _load,
          ),
        _ShiftReady() => _ShiftBody(
            data: _state! as _ShiftReady,
            onRefresh: _load,
            onOpen: _openShift,
            onCount: _countTill,
            onClose: _closeShift,
          ),
      },
    );
  }
}

String describeClosedShift(AppLocalizations l10n, ShiftVariance variance) {
  if (variance.isZero) return l10n.shiftClosedBalanced;
  final String amount = formatMoney(variance.magnitude);
  return variance.isShort
      ? l10n.shiftClosedShort(amount)
      : l10n.shiftClosedOver(amount);
}

class _ShiftSkeleton extends StatelessWidget {
  const _ShiftSkeleton();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return AdaptivePage(
      maxContentWidth: spacing.readableMaxWidth,
      padding: EdgeInsets.all(spacing.md),
      child: const SkeletonList(itemCount: 4, linesPerItem: 2),
    );
  }
}

class _ShiftBody extends StatelessWidget {
  const _ShiftBody({
    required this.data,
    required this.onRefresh,
    required this.onOpen,
    required this.onCount,
    required this.onClose,
  });

  final _ShiftReady data;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpen;
  final VoidCallback onCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppState appState = context.watch<AppState>();
    final ShiftLedger ledger = data.ledger;
    final Shift? open = ledger.open;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: spacing.readableMaxWidth,
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (data.message != null)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.md),
                child: PersistentBanner(
                  message: data.message!,
                  icon: Icons.error_outline,
                  tone: StatusTone.warning,
                  actionLabel: l10n.shiftBannerRefresh,
                  onAction: onRefresh,
                ),
              ),
            if (open == null)
              NoShiftCard(
                canOpen: appState.currentStaffName != null,
                onOpen: onOpen,
              )
            else
              OpenShiftCard(
                shift: open,
                expected: ledger.expected,
                variance: ledger.variance(l10n),
                onCount: onCount,
                onClose: onClose,
              ),
            if (ledger.history.isNotEmpty) ...<Widget>[
              SizedBox(height: spacing.xl),
              ShiftHistoryCard(
                shifts: ledger.history,
                totalShifts: ledger.historyTotal,
              ),
            ],
            if (ledger.reconciliations.isNotEmpty) ...<Widget>[
              SizedBox(height: spacing.xl),
              ReconciliationHistoryCard(
                reconciliations: ledger.reconciliations,
              ),
            ],
            // A till that has never been reconciled gets the empty state that
            // explains what will fill this screen, not a blank column under the
            // card.
            if (open == null && ledger.history.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: spacing.xl),
                child: const EmptyStateView(
                  kind: EmptyKind.collection,
                  title: 'No shifts on record yet',
                  message:
                      'Open a shift, count the drawer when you finish, and '
                      'this becomes the record of every till day.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OpenShiftCard extends StatelessWidget {
  const OpenShiftCard({
    required this.shift,
    required this.expected,
    required this.variance,
    required this.onCount,
    required this.onClose,
    super.key,
  });

  final Shift shift;
  final Money expected;
  final ShiftVariance variance;
  final VoidCallback onCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          label: l10n.shiftOpenSection,
          trailing: StatusChip(
            tone: StatusTone.success,
            text: l10n.shiftOpenChip,
          ),
        ),
        SurfaceCard(
          // gen-l10n sorts the generated parameters ALPHABETICALLY by
          // placeholder name — expected, name, variance, when — which is not the
          // order the sentence reads in. Passing them in reading order bound
          // the staff name to `expected` and the variance to `when`.
          semanticLabel: l10n.shiftOpenCardSpoken(
            formatMoney(expected),
            shift.staffName,
            variance.spoken,
            formatInstant(shift.startTime),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(shift.staffName, style: type.titleSmall),
              SizedBox(height: spacing.xs),
              Text(
                l10n.shiftStartedAt(formatInstant(shift.startTime)),
                style: type.bodySmall,
              ),
              SizedBox(height: spacing.md),
              StatTile(
                label: l10n.shiftExpectedLabel,
                value: formatMoney(expected),
                emphasis: StatEmphasis.strong,
              ),
              SizedBox(height: spacing.xs),
              KeyValueRow(
                label: l10n.shiftOpeningFloat,
                value: formatMoney(shift.startFloat),
                showDivider: false,
              ),
              SizedBox(height: spacing.md),
              VarianceStrip(variance: variance),
              SizedBox(height: spacing.md),
              // Count first: it is the lower-stakes action and it FEEDS the
              // close, so it is the one a cashier needs before either.
              OutlinedButton.icon(
                onPressed: onCount,
                icon: const Icon(Icons.pin_outlined),
                label: Text(l10n.shiftCountAction),
              ),
              SizedBox(height: spacing.sm),
              FilledButton.icon(
                onPressed: onClose,
                icon: const Icon(Icons.lock_outline),
                label: Text(l10n.shiftCloseAction),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NoShiftCard extends StatelessWidget {
  const NoShiftCard({required this.canOpen, required this.onOpen, super.key});

  final bool canOpen;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(label: l10n.shiftNoShiftSection),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(l10n.shiftNoShiftTitle, style: type.titleMedium),
              SizedBox(height: spacing.sm),
              Text(l10n.shiftNoShiftMessage, style: type.bodyMedium),
              SizedBox(height: spacing.md),
              if (canOpen)
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.shiftNoShiftAction),
                )
              else
                Text(
                  l10n.shiftNoShiftNoRoster,
                  style: type.bodySmall?.copyWith(
                    color: AppColors.of(context).onSurfaceMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddRosterEntryDialog extends StatelessWidget {
  const _AddRosterEntryDialog({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.shiftRosterDialogTitle(name)),
      content: Text(l10n.shiftRosterDialogMessage(name)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.shiftRosterDialogDecline),
        ),
        FilledButton(
          onPressed: () => _create(context),
          child: Text(l10n.shiftRosterDialogConfirm),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    final AppState appState = Provider.of<AppState>(context, listen: false);

    final int id = await DatabaseHelper.instance.addStaff(
      Staff(
        name: name,
        // Unusable as a PIN: this row exists so an owner can hold and reconcile a
        // shift, not so anyone can sign in as it. A blank hash cannot be derived,
        // so the entry can never be selected at the PIN pad.
        pinHash: '',
        role: appState.currentRole,
      ),
    );

    // `signInAsOwner(staffId:)` is the only path that keeps the owner flag *and*
    // attaches a roster id. The generic `signIn` clears the id, which would put
    // the owner straight back where they started.
    appState.signInAsOwner(staffId: id);
    navigator.pop(_RosterOffer(id));
  }
}

class _RosterOffer {
  const _RosterOffer(this.staffId);

  final int staffId;
}
