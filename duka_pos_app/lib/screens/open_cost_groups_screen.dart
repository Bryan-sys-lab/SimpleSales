import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/layout/page.dart';

/// Cost groups list for the Open profile.
class OpenCostGroupsScreen extends StatelessWidget {
  const OpenCostGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);

    return AdaptivePage(
      scrollable: true,
      padding: PageGutter.of(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: spacing.section),
          Text(
            l10n.openCostGroupsTitle,
            style: AppTypography.of(context).headlineSmall,
          ),
        ],
      ),
    );
  }
}
