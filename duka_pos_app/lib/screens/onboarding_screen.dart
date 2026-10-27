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
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/onboarding_style.dart';

/// First-run walkthrough. Shown once per shop workspace, after local account
/// creation and before the shell.
///
/// Redesigned to match the brand onboarding artwork: each step opens with a
/// large media "window" at the top (photo over a green curve), an icon badge,
/// a profile chip, a title, a short body, check-marked features, a page
/// indicator, and a primary action. Google Sheets import is intentionally NOT
/// offered here because it requires a Google account connection that is set up
/// later in Settings; offering it on a fresh install would always fail.
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
    final AppColors colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _kWalkthroughWidth),
            child: Column(
              children: <Widget>[
                // One page per step: a media window at top, then the card.
                Expanded(
                  child: PageView(
                    physics: const NeverScrollableScrollPhysics(),
                    controller: PageController(initialPage: _step),
                    onPageChanged: (index) {
                      if (mounted) setState(() => _step = index);
                    },
        children: <Widget>[
          _InfoPage(
            media: const _OnboardMedia(
              icon: Icons.storefront_outlined,
              label: 'WELCOME',
              title: 'Your till, your rules',
              body:
                  'This till keeps selling when the internet does '
                  'not. Sales, stock, staff, and reports are stored '
                  'on this phone first, so the shop keeps working '
                  'with no signal.',
            ),
          ),
                      _InfoPage(
                        media: const _OnboardMedia(
                          icon: Icons.verified_user_outlined,
                          label: 'Account',
                          title: 'Your account and your shop',
                          body:
                              'The email you entered identifies this shop to the '
                              'online services. Your 6-digit PIN is what '
                              'unlocks the till on this device, and it never '
                              'leaves the phone.\n\nM-Pesa and analytics need an '
                              'internet connection the first time. Until then, '
                              'cash sales work exactly the same, and you can '
                              'connect later from Settings.',
                        ),
                      ),
                      _InventoryPage(
                        busy: _busy,
                        message: _message,
                        messageIsError: _messageIsError,
                        onImport: _busy ? null : _importExcel,
                      ),
                      _InfoPage(
                        media: const _OnboardMedia(
                          icon: Icons.check_circle_outline,
                          label: 'Ready',
                          title: 'You are ready',
                          body:
                              'Start selling straight away. You can import more '
                              'inventory, add managers and cashiers, and connect '
                              'optional online services from Settings at any '
                              'time.',
                        ),
                      ),
                    ],
                  ),
                ),
                _ProgressDots(step: _step, total: _lastStep + 1, colors: colors),
                SizedBox(height: spacing.section),
                _Footer(
                  isFirst: _isFirst,
                  isLast: _isLast,
                  locked: _locked,
                  onBack: _back,
                  onNext: _next,
                  onSkip: _finish,
                  colors: colors,
                  spacing: spacing,
                ),
                SizedBox(height: spacing.xs),
                // A step change is eye-only movement: without this a screen
                // reader user presses Continue and is told nothing until they
                // reach the bottom of a screen they did not know had moved.
                Padding(
                  padding: EdgeInsetsDirectional.only(bottom: spacing.md),
                  child: Text(
                    _finishing ? 'Finishing' : '',
                    style: type.labelSmall?.copyWith(
                      color: colors.onSurfaceMuted,
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

/// One page: media window at top, then a card with label, title, body, and
/// check-marked features.
class _InfoPage extends StatelessWidget {
  const _InfoPage({required this.media});

  final _OnboardMedia media;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          media,
          SizedBox(height: spacing.lg),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              spacing.xl, 0, spacing.xl, spacing.xl,
            ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(media.title, style: OnboardStyle.typeFor(context).headlineSmall?.copyWith(color: colors.accent, fontWeight: FontWeight.w700)),
              SizedBox(height: spacing.md),
              Text(media.body, style: type.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The import step: the walkthrough's one thing a person can act on.
class _InventoryPage extends StatelessWidget {
  const _InventoryPage({
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
    final TextTheme type = AppTypography.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _OnboardMedia(
            icon: Icons.inventory_2_outlined,
            label: 'Inventory',
            title: 'Bring in your inventory',
            body:
                'Import an Excel workbook to get set up quickly, or skip this '
                'and add products one at a time. You can also connect a Google '
                'Sheet later in Settings.',
          ),
          SizedBox(height: spacing.lg),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              spacing.xl, 0, spacing.xl, spacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const ExcludeSemantics(
                    child: Icon(Icons.table_view_outlined),
                  ),
                  label: Text(busy ? 'Importing' : 'Import Excel workbook'),
                ),
                if (busy) ...<Widget>[
                  SizedBox(height: spacing.md),
                  const _ImportProgress(),
                ],
                if (message != null) ...<Widget>[
                  SizedBox(height: spacing.md),
                  _ImportMessage(
                    message: message!,
                    isError: messageIsError,
                    type: type,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
  const _ImportMessage({
    required this.message,
    required this.isError,
    required this.type,
  });

  final String message;
  final bool isError;
  final TextTheme type;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
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
            semanticLabel: '',
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              message,
              style: type.bodyMedium?.copyWith(color: tone),
            ),
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
    required this.colors,
    required this.spacing,
  });

  final bool isFirst;
  final bool isLast;
  final bool locked;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final AppColors colors;
  final AppSpacing spacing;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        spacing.xl, 0, spacing.xl, spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (!isFirst)
                TextButton.icon(
                  onPressed: locked ? null : onBack,
                  icon: ExcludeSemantics(child: Icon(Icons.arrow_back)),
                  label: Text(l10n.actionBack),
                )
              else
              TextButton(
                onPressed: locked ? null : () {},
                child: Text(l10n.actionBack),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: locked ? null : onNext,
                  child: Text(isLast ? 'Start selling' : 'Continue'),
                ),
              ),
            ],
          ),
          if (isLast) ...<Widget>[
            SizedBox(height: spacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: locked ? null : () {},
                child: Text(l10n.actionBack),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Page dots: filled count rises with the step, the active step is spelled out
/// in words for screen readers — two channels, neither is colour.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    required this.step,
    required this.total,
    required this.colors,
  });

  final int step;
  final int total;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Semantics(
      liveRegion: true,
      label: 'Step ${step + 1} of $total',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int index = 0; index < total; index++)
              Padding(
                padding: index == total - 1
                    ? EdgeInsets.zero
                    : EdgeInsetsDirectional.only(end: spacing.sm),
                child: Container(
                  width: 24,
                  height: 6,
                  decoration: BoxDecoration(
                    color: index <= step ? colors.accent : colors.outline,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The media "window" at the top of every onboarding page: a brand-coloured
/// block with the green curve swept across the bottom-left corner and an icon
/// badge anchored to it. Swap [image] in for the real profile photos when they
/// are bundled.
class _OnboardMedia extends StatelessWidget {
  const _OnboardMedia({
    required this.icon,
    required this.label,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String label;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final double mediaHeight = 260;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipPath(
          clipper: _OnboardMediaCurve(),
          child: Container(
            height: mediaHeight,
            width: double.infinity,
            color: colors.accent,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          colors.accent.withValues(alpha: 0.35),
                          colors.accent.withValues(alpha: 0.15),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                // Icon badge anchored to the media block.
                Positioned(
                  left: spacing.lg,
                  bottom: spacing.lg,
                  child: Container(
                    width: 56,
                    height: 56,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                    child: Icon(
                      icon,
                      size: 28,
                      color: colors.accent,
                    ),
                  ),
                ),
                // Profile-style chip floating just below the curve.
                Positioned(
                  left: spacing.lg,
                  bottom: -14,
                  child: Container(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      spacing.md, spacing.xs, spacing.md, spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.canvas,
                    borderRadius: BorderRadius.circular(6),
                  ),
                    child: Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Sweeps the bottom-left corner of the media block up into a curve, mirroring
/// the brand onboarding artwork.
class _OnboardMediaCurve extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final Path path = Path()
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.55,
        size.height,
        0,
        size.height * 0.62,
      )
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _OnboardMediaCurve old) => false;
}

/// The measure of the walkthrough column.
///
/// Prose, so the widest useful line is about seventy characters. Past this a
/// paragraph on a tablet is 140 characters of grey.
const double _kWalkthroughWidth = 680;
