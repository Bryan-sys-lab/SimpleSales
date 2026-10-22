import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_state.dart';
import '../services/excel_service.dart';
import '../services/import_row_parser.dart';
import '../services/workspace_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/screen_title.dart';

/// First-run walkthrough. Shown once per shop workspace, after local account
/// creation and before the shell.
///
/// Every step is skippable and works with no internet: nothing here calls the
/// backend. Google Sheets import is intentionally NOT offered because it
/// requires a Google account connection that is set up later in Settings;
/// offering it on a fresh install would always fail.
class OnboardingScreen extends StatefulWidget {
  /// Finishing the walkthrough, whether by the last step or by Skip.
  ///
  /// Awaited, because the thing it does is the whole reason this screen can be
  /// dismissed: it records the walkthrough as seen and the router takes the
  /// person onward. A callback that returns `void` here is a callback whose
  /// result nobody can wait for, and a person who presses Continue twice gets
  /// two walkthroughs' worth of racing work.
  final Future<void> Function()? onComplete;

  const OnboardingScreen({super.key, this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// The last step index. Four steps, zero to three.
  static const int _lastStep = 3;

  int _step = 0;

  /// An import is running.
  bool _busy = false;

  /// The walkthrough is being closed: the preference write and whatever the
  /// router does next. Separate from [_busy] because one blocks a button and
  /// the other blocks the whole footer.
  bool _finishing = false;

  String? _message;
  bool _messageIsError = false;

  bool get _isFirst => _step == 0;
  bool get _isLast => _step == _lastStep;

  /// Whether the footer may act at all.
  bool get _locked => _busy || _finishing;

  Future<void> _importExcel() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final InventoryImportResult result =
          await ExcelService().importInventory();
      if (!mounted) return;
      final int refused = result.refusedBarcodes.length;
      setState(() {
        _messageIsError = result.products == 0;
        _message = result.products == 0
            ? 'No products were found in that workbook.'
            : refused == 0
                // Refused barcodes are named by product, because "duplicate
                // barcode" tells the owner nothing about which row to fix.
                ? AppLocalizations.of(context)
                    .onboardingImportedProducts(result.products)
                : 'Imported ${result.products} products. '
                    '$refused barcode(s) were already on another '
                    'product and were left alone.';
      });
    } on UnreadableLayoutException {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = AppLocalizations.of(context).importNotOurFormat;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message =
            'That workbook has invalid inventory data. Nothing was imported.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'That file could not be read. Check it and try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      // Written here as well as by the router's stage controller: this screen
      // is the only thing that knows a walkthrough was actually shown, and a
      // caller that passes no callback still gets a device that stops showing
      // it.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'onboarding_completed_${await WorkspaceService.activeWorkspaceKey()}',
        true,
      );
      if (!mounted) return;
      HapticTheme.of(context).fire(HapticEvent.commit);
      await widget.onComplete?.call();
      if (!mounted) return;
      context.read<AppState>().refresh();
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    HapticTheme.of(context).fire(HapticEvent.select);
    setState(() => _step++);
  }

  void _back() {
    if (_isFirst) return;
    HapticTheme.of(context).fire(HapticEvent.select);
    setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _kWalkthroughWidth),
            child: Column(
              children: <Widget>[
                _ProgressHeader(step: _step, total: _lastStep + 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      spacing.xl,
                      spacing.md,
                      spacing.xl,
                      spacing.xl,
                    ),
                    child: switch (_step) {
                      0 => const _InfoStep(
                          icon: Icons.storefront_outlined,
                          title: 'Welcome to your till',
                          body:
                              'This till keeps selling when the internet does '
                              'not. Sales, stock, staff, and reports are stored on '
                              'this phone first, so the shop keeps working with no '
                              'signal.',
                        ),
                      1 => const _InfoStep(
                          icon: Icons.verified_user_outlined,
                          title: 'Your account and your shop',
                          body:
                              'The email you entered identifies this shop to the '
                              'online services. Your 6-digit PIN is what unlocks '
                              'the till on this device, and it never leaves the '
                              'phone.\n\nM-Pesa and analytics need an internet '
                              'connection the first time. Until then, cash sales '
                              'work exactly the same, and you can connect later '
                              'from Settings.',
                        ),
                      2 => _InventoryStep(
                          busy: _busy,
                          message: _message,
                          messageIsError: _messageIsError,
                          onImport: _busy ? null : _importExcel,
                        ),
                      _ => const _InfoStep(
                          icon: Icons.check_circle_outline,
                          title: 'You are ready',
                          body:
                              'Start selling straight away. You can import more '
                              'inventory, add managers and cashiers, and connect '
                              'optional online services from Settings at any '
                              'time.',
                        ),
                    },
                  ),
                ),
                _Footer(
                  isFirst: _isFirst,
                  isLast: _isLast,
                  locked: _locked,
                  onBack: _back,
                  onNext: _next,
                  onSkip: _finish,
                ),
                // A step change is eye-only movement: without this a screen
                // reader user presses Continue and is told nothing until they
                // reach the bottom of a screen they did not know had moved.
                Padding(
                  padding: EdgeInsetsDirectional.only(bottom: spacing.md),
                  child: Text(
                    _finishing ? 'Finishing' : '',
                    style: type.labelSmall?.copyWith(
                      color: AppColors.of(context).onSurfaceMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How many steps there are, and where this one is.
///
/// Two channels, and neither of them is colour: the count of filled bars rises
/// with the step, and the step is spelled out in words on a live region. A
/// progress bar in one hue is a shape nobody has to decode.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        spacing.xl,
        spacing.xl,
        spacing.xl,
        spacing.md,
      ),
      child: Semantics(
        liveRegion: true,
        label: 'Step ${step + 1} of $total',
        child: ExcludeSemantics(
          child: Row(
            children: <Widget>[
              for (int index = 0; index < total; index++)
                Expanded(
                  child: Padding(
                    padding: index == total - 1
                        ? EdgeInsets.zero
                        : EdgeInsetsDirectional.only(end: spacing.sm),
                    child: Container(
                      height: spacing.sm,
                      decoration: BoxDecoration(
                        color: index <= step ? colors.accent : colors.outline,
                        borderRadius: AppShapes.of(context).chipRadius,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One step: a glyph, a heading, a paragraph.
class _InfoStep extends StatelessWidget {
  const _InfoStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: spacing.lg),
        Icon(
          icon,
          size: 64,
          color: colors.accent,
          // Decorative: the heading below says what this step is, in words.
          semanticLabel: '',
        ),
        SizedBox(height: spacing.xl),
        // The step's NAME, large and on the canvas — the same title treatment
        // every other screen opens with, so the walkthrough does not read as a
        // different app.
        ScreenTitle(title: title, padding: EdgeInsets.zero),
        SizedBox(height: spacing.md),
        Text(body, style: type.bodyLarge),
      ],
    );
  }
}

/// The import step: the walkthrough's one thing a person can act on.
class _InventoryStep extends StatelessWidget {
  const _InventoryStep({
    required this.busy,
    required this.message,
    required this.messageIsError,
    required this.onImport,
  });

  final bool busy;
  final String? message;
  final bool messageIsError;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _InfoStep(
          icon: Icons.inventory_2_outlined,
          title: 'Bring in your inventory',
          body:
              'Import an Excel workbook to get set up quickly, or skip this and '
              'add products one at a time. You can also connect a Google Sheet '
              'later in Settings.',
        ),
        SizedBox(height: spacing.lg),
        FilledButton.icon(
          onPressed: onImport,
          icon: const ExcludeSemantics(child: Icon(Icons.table_view_outlined)),
          label: Text(busy ? 'Importing' : 'Import Excel workbook'),
        ),
        if (busy) ...<Widget>[
          SizedBox(height: spacing.md),
          const _ImportProgress(),
        ],
        if (message != null) ...<Widget>[
          SizedBox(height: spacing.md),
          _ImportMessage(message: message!, isError: messageIsError),
        ],
      ],
    );
  }
}

/// The import running. Announced, because a disabled button is the only
/// evidence a sighted user gets that anything is happening at all.
class _ImportProgress extends StatelessWidget {
  const _ImportProgress();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Importing your inventory',
      child: ExcludeSemantics(
        child: const LinearProgressIndicator(),
      ),
    );
  }
}

/// What the import did, or why it did not.
///
/// Glyph plus sentence plus tone: three channels, so the difference between
/// "imported 40 products" and "the file could not be read" survives greyscale
/// and reaches a screen reader as a sentence rather than a hue.
class _ImportMessage extends StatelessWidget {
  const _ImportMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final Color tone = isError ? colors.danger : colors.success;

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: tone,
            // Decorative: the sentence beside it is the message.
            semanticLabel: '',
          ),
          SizedBox(width: AppSpacing.of(context).sm),
          Expanded(
            child: Text(message, style: type.bodyMedium?.copyWith(color: tone)),
          ),
        ],
      ),
    );
  }
}

/// Back or Skip, and the way onward.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.isFirst,
    required this.isLast,
    required this.locked,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final bool isFirst;
  final bool isLast;

  /// Disabled while an import or the finish is in flight.
  final bool locked;

  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        spacing.xl,
        0,
        spacing.xl,
        spacing.sm,
      ),
      child: Row(
        children: <Widget>[
          if (!isFirst)
            TextButton.icon(
              onPressed: locked ? null : onBack,
              // `arrow_back` is declared by Flutter with `matchTextDirection:
              // true`, so the glyph mirrors itself under an RTL locale — the
              // control points the way the reader does without the screen
              // having to choose a second icon.
              icon: ExcludeSemantics(child: Icon(Icons.arrow_back)),
              label: Text(l10n.actionBack),
            )
          else
            TextButton(
              onPressed: locked ? null : onSkip,
              child: Text(l10n.actionSkip),
            ),
          // Flexible, not a Spacer with a fixed button: at 200% text scale a
          // long label wraps instead of the row overflowing.
          SizedBox(width: spacing.md),
          Expanded(
            child: FilledButton(
              onPressed: locked ? null : onNext,
              child: Text(isLast ? 'Start selling' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The measure of the walkthrough column.
///
/// Prose, so the widest useful line is about seventy characters. Past this a
/// paragraph on a tablet is 140 characters of grey.
const double _kWalkthroughWidth = 680;
