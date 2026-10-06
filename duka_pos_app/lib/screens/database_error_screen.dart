import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';

/// Shown when the local database cannot be opened at all.
///
/// This screen exists because the alternative is the one failure mode nobody
/// should have to explain to a shopkeeper at 8am: a blank frame, or an exception
/// rendered as text. It says three things and no more — what happened, that
/// nothing was deleted, and what to do next.
///
/// The technical detail goes to the crash reporter, never to this screen. A file
/// path in a customer's hands is not help.
class DatabaseErrorScreen extends StatelessWidget {
  const DatabaseErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                children: <Widget>[
                  const SimplePosMark(size: 48),
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
                      AppLocalizations.of(context).databaseErrorTitle,
                      textAlign: TextAlign.center,
                      style: type.headlineSmall,
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  Text(
                    AppLocalizations.of(context).databaseErrorBody,
                    textAlign: TextAlign.center,
                    style: type.bodyLarge,
                  ),
                  SizedBox(height: spacing.md),
                  Text(
                    AppLocalizations.of(context).databaseErrorAdvice,
                    textAlign: TextAlign.center,
                    style: type.bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
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
