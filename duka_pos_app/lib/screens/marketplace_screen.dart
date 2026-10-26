import 'package:flutter/material.dart';

import '../services/plugin_registry.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';

class MarketplaceScreen extends StatelessWidget {
  const MarketplaceScreen({super.key, this.plugins = PluginRegistry.catalog});

  /// The router uses the built-in catalogue today. A future authenticated
  /// marketplace response can pass [PluginRegistry.mergeRemote] here without
  /// changing the screen or the offline checkout path.
  final List<BusinessPlugin> plugins;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme text = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.marketplaceTitle)),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: EdgeInsets.all(spacing.lg),
            children: <Widget>[
              Text(l10n.marketplaceIntro, style: text.headlineSmall),
              SizedBox(height: spacing.xs),
              Text(
                l10n.marketplaceDescription,
                style: text.bodyLarge?.copyWith(color: colors.onSurfaceMuted),
              ),
              SizedBox(height: spacing.lg),
              for (final BusinessPlugin plugin in plugins)
                Padding(
                  padding: EdgeInsets.only(bottom: spacing.md),
                  child: Card(
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: spacing.md,
                        vertical: spacing.xs,
                      ),
                      leading:
                          Icon(_iconFor(plugin.category), color: colors.accent),
                      title: Text(plugin.name),
                      subtitle: Text(plugin.description),
                      trailing: OutlinedButton(
                        onPressed: null,
                        child: Text(l10n.marketplaceComingSoon),
                      ),
                    ),
                  ),
                ),
              SizedBox(height: spacing.xl),
            ],
          ),
          IgnorePointer(
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: Transform.rotate(
                angle: -0.22,
                child: Container(
                  margin: EdgeInsetsDirectional.only(
                      top: spacing.xl, end: spacing.lg),
                  padding: EdgeInsets.symmetric(
                      horizontal: spacing.md, vertical: spacing.xs),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.danger, width: 2),
                    color: colors.canvas.withValues(alpha: 0.92),
                  ),
                  child: Text(
                    l10n.marketplaceStamp,
                    style: text.labelLarge?.copyWith(
                      color: colors.danger,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(PluginCategory category) => switch (category) {
        PluginCategory.ai => Icons.auto_awesome_outlined,
        PluginCategory.analytics => Icons.insights_outlined,
        PluginCategory.reporting => Icons.assessment_outlined,
        PluginCategory.hrPayroll => Icons.badge_outlined,
        PluginCategory.legal => Icons.gavel_outlined,
        PluginCategory.insuranceLoans => Icons.account_balance_outlined,
        PluginCategory.social => Icons.share_outlined,
      };
}
