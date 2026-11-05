import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/layout/page.dart';

/// Create or edit a job for the Open profile.
class OpenJobFormScreen extends StatefulWidget {
  const OpenJobFormScreen({super.key});

  @override
  State<OpenJobFormScreen> createState() => _OpenJobFormScreenState();
}

class _OpenJobFormScreenState extends State<OpenJobFormScreen> {
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
            l10n.openJobFormTitle,
            style: AppTypography.of(context).headlineSmall,
          ),
        ],
      ),
    );
  }
}
