import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';

/// Shared visual language for the onboarding + sign-in surfaces.
///
/// Colours come from the theme (dark canvas, emerald accent) so this one file
/// is the single place the inspiration's look is authored. Every screen below
/// assembles these primitives; none invents a hex or a radius.
abstract class OnboardStyle {
  /// The heading over one role's accounts, localised.
  static const double _markSize = 36;
  static const double _mediaHeight = 256;
  static const double _badgeSize = 56;
  static const double _chipRadius = 20;

  /// The media "window" at the top of an onboarding page: a brand photograph
  /// with the green curve swept across the bottom-left corner and an icon badge
  /// anchored to it, then a label chip + title + body beneath on the canvas.
  static Widget window({
    required BuildContext context,
    required Widget image,
    required IconData badgeIcon,
    required String label,
    required String title,
    required String body,
    required TextTheme type,
    required AppColors colors,
    required AppSpacing spacing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: _mediaHeight,
          width: double.infinity,
          child: Stack(
            children: <Widget>[
              // Brand photograph filling the window.
              Positioned.fill(child: image),
              // Green glow in the bottom-left corner of the window.
              Positioned(
                left: -spacing.md,
                bottom: -spacing.md,
                child: Container(
                  width: _mediaHeight * 0.85,
                  height: _mediaHeight * 0.85,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        colors.accent.withValues(alpha: 0.45),
                        colors.accent.withValues(alpha: 0.0),
                      ],
                      center: Alignment.bottomLeft,
                      radius: 1,
                    ),
                  ),
                ),
              ),
              // Icon badge anchored to the window.
              Positioned(
                left: spacing.lg,
                bottom: spacing.lg,
                child: Container(
                  width: _badgeSize,
                  height: _badgeSize,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: AppShapes.of(context).controlRadius,
                  ),
                  child: Icon(badgeIcon, size: 28, color: colors.onAccent),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(spacing.xl, 0, spacing.xl, spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Label chip: uppercase, green.
              Container(
                padding: EdgeInsetsDirectional.fromSTEB(spacing.md, spacing.xs, spacing.md, spacing.xs),
                decoration: BoxDecoration(
                  color: colors.accentContainer,
                  borderRadius: BorderRadius.circular(_chipRadius),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: colors.onAccentContainer,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(height: spacing.md),
              // Title: emerald accent.
              Text(
                title,
                style: type.headlineSmall?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: spacing.sm),
              // Body: centered, high-contrast.
              Text(
                body,
                textAlign: TextAlign.center,
                style: type.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The page dots indicator: filled count rises with the step; active step
  /// spelled out for screen readers.
  static Widget dots({
    required int step,
    required int total,
    required AppColors colors,
    required AppSpacing spacing,
  }) {
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

  /// The primary action: full width, emerald fill, white ink, with an arrow.
  static Widget primaryButton({
    required BuildContext context,
    required VoidCallback? onPressed,
    required String label,
    required AppColors colors,
    required AppSpacing spacing,
  }) {
    final TextTheme type = AppTypography.of(context);
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.of(context).controlRadius,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: colors.onAccent)),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_rounded, size: 20, color: colors.onAccent),
        ],
      ),
    );
  }

  /// A small link-style action in accent green.
  static Widget link({
    required BuildContext context,
    required VoidCallback? onPressed,
    required String label,
    required AppColors colors,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: typeFor(context).labelLarge?.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  /// The top-of-screen lockup: SimpleSales mark left, sign-in link right.
  static Widget header({
    required BuildContext context,
    required VoidCallback? onSignIn,
    required AppColors colors,
    required AppSpacing spacing,
    required TextTheme type,
  }) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(spacing.xl, spacing.xs, spacing.xl, spacing.xs),
      child: Row(
        children: <Widget>[
          const SimplePosMark(size: _markSize, variant: SimplePosMarkVariant.full),
          const Spacer(),
          TextButton(
            onPressed: onSignIn,
            style: TextButton.styleFrom(
              foregroundColor: colors.accent,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('I have an account', style: type.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  static TextTheme typeFor(BuildContext context) => AppTypography.of(context);
}

/// A feature line: green check glyph + sentence.
class OnboardFeature extends StatelessWidget {
  const OnboardFeature({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = OnboardStyle.typeFor(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.check_circle, size: 20, color: colors.accent),
          SizedBox(width: spacing.sm),
          Expanded(child: Text(text, style: type.bodyMedium)),
        ],
      ),
    );
  }
}

/// Import button with optional busy indicator + message.
class OnboardImportBox extends StatelessWidget {
  const OnboardImportBox({
    required this.busy,
    required this.message,
    required this.messageIsError,
    required this.onImport,
    super.key,
  });

  final bool busy;
  final String? message;
  final bool messageIsError;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = OnboardStyle.typeFor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
          OnboardImportMessage(message: message!, isError: messageIsError, type: type),
        ],
      ],
    );
  }
}

class _ImportProgress extends StatelessWidget {
  const _ImportProgress();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Importing your inventory',
      child: ExcludeSemantics(child: const LinearProgressIndicator()),
    );
  }
}

class OnboardImportMessage extends StatelessWidget {
  const OnboardImportMessage({
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
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, size: 18, color: tone, semanticLabel: ''),
          SizedBox(width: spacing.sm),
          Expanded(child: Text(message, style: type.bodyMedium?.copyWith(color: tone))),
        ],
      ),
    );
  }
}

/// A profile choice card: icon + label + subtitle.
class OnboardProfileCard extends StatelessWidget {
  const OnboardProfileCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = OnboardStyle.typeFor(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: spacing.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: spacing.minTapTarget),
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
            color: selected ? colors.accentContainer : colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: shapes.controlRadius,
              side: BorderSide(color: selected ? colors.accent : colors.outline, width: selected ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(horizontal: spacing.md, vertical: spacing.sm),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected ? colors.accent : colors.surfaceSunken,
                        borderRadius: shapes.controlRadius,
                      ),
                      child: Icon(icon, size: 22, color: selected ? colors.onAccent : colors.onSurfaceVariant),
                    ),
                    SizedBox(width: spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(label,
                              style: selected
                                  ? type.titleMedium?.copyWith(color: colors.onAccentContainer, fontWeight: FontWeight.w700)
                                  : type.bodyLarge?.copyWith(color: colors.onSurface)),
                          SizedBox(height: spacing.xxs),
                          Text(subtitle,
                              style: type.labelMedium?.copyWith(
                                color: selected ? colors.onAccentContainer : colors.onSurfaceMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
