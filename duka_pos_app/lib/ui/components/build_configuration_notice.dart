import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';
import 'surface.dart';

/// The notice that says what this build cannot do.
///
/// ## WHY THIS IS A CARD AND NOT A SCREEN
///
/// It used to be a whole screen, shown instead of the app: the release build
/// refused to open, and this screen was the reason. That was a dead end — the
/// person holding the phone could not sell anything, and the person who could
/// fix it was not there.
///
/// Now the build starts and this is a card, in the one screen that is about
/// the build: Diagnostics. The till keeps working, and the one fact that
/// matters — this build has no server, so no KRA receipt and no sync — is
/// stated once, in the owner's words, with the detail on the clipboard for
/// whoever builds the release.
///
/// ## WHAT IS NEVER HERE
///
/// The technical detail goes to the clipboard, not into the app's own state:
/// this is read by whoever builds the release, and a file path in a
/// customer's hands is not help.
class BuildConfigurationNotice extends StatefulWidget {
  const BuildConfigurationNotice({required this.problem, super.key});

  /// What is misconfigured, in words the person who built it will recognise.
  final String problem;

  @override
  State<BuildConfigurationNotice> createState() =>
      _BuildConfigurationNoticeState();
}

class _BuildConfigurationNoticeState extends State<BuildConfigurationNotice> {
  bool _copied = false;

  Future<void> _copyDetail() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: widget.problem));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.configurationErrorSharedMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.settings_suggest_outlined,
                size: 24,
                color: colors.warning,
                // Decorative: the headline below says the same thing in
                // words, and an unlabelled icon is silence to a screen
                // reader.
                semanticLabel: '',
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.configurationErrorTitle,
                    style: type.titleMedium,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(l10n.configurationNoticeBody, style: type.bodyMedium),
          SizedBox(height: spacing.xs),
          Text(
            l10n.configurationErrorAdvice,
            style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
          ),
          SizedBox(height: spacing.md),
          Text(
            l10n.configurationErrorDetail(widget.problem),
            style: type.bodySmall,
          ),
          SizedBox(height: spacing.sm),
          OutlinedButton.icon(
            onPressed: _copyDetail,
            icon: const Icon(Icons.copy_all_outlined),
            label: Text(l10n.configurationErrorShareAction),
          ),
          if (_copied) ...<Widget>[
            SizedBox(height: spacing.sm),
            Text(
              l10n.configurationErrorSharedMessage,
              style: type.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
