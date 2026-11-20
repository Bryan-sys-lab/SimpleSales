import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../profile/shop_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';

/// A visual profile selector for the account-setup form.
///
/// Renders each shop profile as a card with an icon, name, and short
/// description in a horizontal rail, so the choices remain browsable on a
/// narrow phone without shrinking into a cramped grid.
///
/// Duka is the default — callers set [`ShopProfilePicker.value`] to change it.
class ShopProfilePicker extends StatelessWidget {
  const ShopProfilePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The currently selected profile.
  final ShopProfile value;

  /// Called when the person taps a different profile card.
  final ValueChanged<ShopProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.6).toDouble();
    final double cardWidth = 150 * textScale;
    final double railHeight = 140 + (textScale - 1) * 34;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.md),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.shopProfileLabel,
                  style: type.titleMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.xs),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.md),
          child: Text(
            l10n.shopProfileHelp,
            style: type.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(height: spacing.md),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: ShopProfile.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final ShopProfile profile = ShopProfile.values[index];
              return SizedBox(
                width: cardWidth,
                child: _ProfileCard(
                  profile: profile,
                  selected: profile == value,
                  onSelected: onChanged,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One shop-profile choice: icon, name, one-line description, selected state.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.selected,
    required this.onSelected,
  });

  final ShopProfile profile;
  final bool selected;
  final ValueChanged<ShopProfile> onSelected;

  /// One line describing what this profile is for.
  String get _subtitle {
    switch (profile) {
      case ShopProfile.duka:
        return 'General shop · products, stock, POS';
      case ShopProfile.drinks:
        return 'Bar and drinks · tanks, pours, stock';
      case ShopProfile.fashion:
        return 'Fashion boutique · styles, sizes, colours';
      case ShopProfile.open:
        return 'Open business · inventory, costs, sales';
    }
  }

  /// The name of this profile.
  String get _title {
    switch (profile) {
      case ShopProfile.duka:
        return 'Duka';
      case ShopProfile.drinks:
        return 'Drinks';
      case ShopProfile.fashion:
        return 'Fashion';
      case ShopProfile.open:
        return 'Open';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '$_title. $_subtitle',
      child: Material(
      color: selected
          ? colors.accentContainer.withValues(alpha: 0.15)
          : colors.surface,
      borderRadius: shapes.cardRadius,
      child: InkWell(
        borderRadius: shapes.cardRadius,
        onTap: () => onSelected(profile),
        child: Padding(
          padding: EdgeInsets.all(spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.accent
                          : colors.surfaceSunken,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      profile == ShopProfile.duka
                          ? Icons.storefront_outlined
                          : profile == ShopProfile.drinks
                              ? Icons.local_bar_outlined
                              : profile == ShopProfile.fashion
                                  ? Icons.checkroom_outlined
                                  : Icons.work_outline,
                      color: selected
                          ? colors.onAccentContainer
                          : colors.onSurfaceVariant,
                      size: 16,
                    ),
                  ),
                  const Spacer(),
                  if (selected)
                    Icon(
                      Icons.check_circle,
                      color: colors.accent,
                      size: 16,
                    ),
                ],
              ),
              SizedBox(height: spacing.xxs),
              Text(
                _title,
                style: type.titleSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2),
              Text(
                _subtitle,
                style: type.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
