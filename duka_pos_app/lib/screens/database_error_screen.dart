import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/app_stage_controller.dart';
import '../services/failure_recorder.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';

/// The last screen, when the app cannot open its own data.
///
/// A dead end is not a design decision, it is a missing feature. The owner
/// reading this cannot fix the phone, cannot call anyone, and cannot find out
/// whether the problem has gone away — so this screen does three things
/// instead of one:
///
/// * It SAYS what happened, in the owner's terms, and what to do about it.
/// * It LETS THEM TRY AGAIN. The condition is often temporary — a full disk
///   freed, a restored backup, a working directory that changed under an
///   update — and a screen that can only report a failure has given up on
///   the one thing it could still have done.
/// * It LETS THEM SEND THE DIAGNOSTICS. The crash report carries the trail
///   that led here, and it is on the phone; without a way to get it out, the
///   support call starts with "what did it do?".
///
/// The technical detail goes to the crash reporter, never to this screen. A
/// file path in a customer's hands is not help.
class DatabaseErrorScreen extends StatefulWidget {
  const DatabaseErrorScreen({super.key});

  @override
  State<DatabaseErrorScreen> createState() => _DatabaseErrorScreenState();
}

class _DatabaseErrorScreenState extends State<DatabaseErrorScreen> {
  bool _retrying = false;
  bool _copied = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _copied = false;
    });

    final bool worked = await context.read<AppStageController>().retry();
    if (!mounted) return;

    setState(() {
      _retrying = false;
      _copied = false;
    });

    // A failed retry says so, out loud, rather than leaving the owner to
    // wonder whether the button did anything at all.
    if (!worked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).databaseErrorRetryFailed,
          ),
        ),
      );
    }
  }

  Future<void> _copyDiagnostics() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FailureRecorder recorder = failureRecorder;

    final StringBuffer report = StringBuffer()
      ..writeln('SimpleSales failure report');
    for (final MapEntry<String, String> field in recorder.environment().entries) {
      report.writeln('${field.key}: ${field.value}');
    }
    report.writeln('trail: ${recorder.trail.crumbs.join(' > ')}');

    await Clipboard.setData(ClipboardData(text: report.toString()));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.databaseErrorSharedMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(spacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: spacing.readableMaxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Image(
                    image: AssetImage(
                      'assets/branding/stitch_simple_pos_launcher_icon/simple_pos_geometric_s_icon/screen.png',
                    ),
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: spacing.xl),
                  Icon(
                    Icons.storage_outlined,
                    size: 40,
                    color: colors.danger,
                    // Decorative: the headline below says the same thing in
                    // words, and an unlabelled icon is silence to a screen reader.
                    semanticLabel: '',
                  ),
                  SizedBox(height: spacing.md),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.databaseErrorTitle,
                      textAlign: TextAlign.center,
                      style: type.headlineSmall,
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  Text(
                    l10n.databaseErrorBody,
                    textAlign: TextAlign.center,
                    style: type.bodyLarge,
                  ),
                  SizedBox(height: spacing.md),
                  Text(
                    l10n.databaseErrorAdvice,
                    textAlign: TextAlign.center,
                    style: type.bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: _retrying ? null : _retry,
                          icon: _retrying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(l10n.databaseErrorRetryAction),
                        ),
                        SizedBox(height: spacing.sm),
                        OutlinedButton.icon(
                          onPressed: _copyDiagnostics,
                          icon: const Icon(Icons.copy_all_outlined),
                          label: Text(l10n.databaseErrorShareAction),
                        ),
                        if (_copied) ...<Widget>[
                          SizedBox(height: spacing.sm),
                          StatusChip(
                            tone: StatusTone.success,
                            text: l10n.databaseErrorSharedMessage,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
