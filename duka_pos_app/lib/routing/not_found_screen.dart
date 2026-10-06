import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import 'routes.dart';

/// The designed 404.
///
/// `GoRouter.errorBuilder` means an unmatched deep link lands HERE rather than on
/// a red error box in debug or a grey page in release. That matters more than it
/// sounds: a printed QR code or a bookmarked URL from an old release will hit
/// this, and "this link is out of date, here's where to go" is a support answer
/// that costs nothing.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({required this.location, super.key});

  /// The path that did not match. Shown verbatim — it is the single most useful
  /// thing on the screen for whoever filed the bug.
  final String location;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).notFoundTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(spacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: spacing.readableMaxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.link_off_outlined,
                    size: 40,
                    color: colors.onSurfaceMuted,
                    semanticLabel: '',
                  ),
                  SizedBox(height: spacing.md),
                  Semantics(
                    header: true,
                    child: Text(
                      AppLocalizations.of(context).notFoundHeading,
                      textAlign: TextAlign.center,
                      style: type.titleLarge,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    AppLocalizations.of(context).notFoundBody,
                    textAlign: TextAlign.center,
                    style: type.bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  // Pinned LTR: a technical path is a strong-LTR run, and under
                  // an RTL locale it would otherwise reorder into nonsense.
                  Semantics(
                    label: AppLocalizations.of(context)
                        .notFoundPathLabel(location),
                    child: ExcludeSemantics(
                      child: Container(
                        padding: EdgeInsets.all(spacing.md),
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: AppShapes.of(context).controlRadius,
                        ),
                        child: Text(
                          location,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: type.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.xl),
                  FilledButton(
                    onPressed: () => context.go(Routes.dashboard),
                    child: Text(AppLocalizations.of(context).notFoundAction),
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
