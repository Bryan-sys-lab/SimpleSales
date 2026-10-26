import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/blackbee_seed_service.dart';
import '../services/import_review_service.dart';
import '../theme/app_spacing.dart';
import '../ui/components/surface.dart';
import 'imports_screen.dart';

class BlackbeeSeedScreen extends StatefulWidget {
  const BlackbeeSeedScreen({super.key});

  @override
  State<BlackbeeSeedScreen> createState() => _BlackbeeSeedScreenState();
}

class _BlackbeeSeedScreenState extends State<BlackbeeSeedScreen> {
  Set<String> _existing = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final products = await DatabaseHelper.instance.getProducts(activeOnly: true);
    if (!mounted) return;
    setState(() => _existing = products.map((p) => p.name.toLowerCase()).toSet());
  }

  Future<void> _price(String name) async {
    await showImportCompletionSheet(
      context,
      draft: ImportDraft(
        name: name,
        costMinor: null,
        sellMinor: null,
        stockQty: 0,
        category: '',
        reorderLevel: 0,
        missing: const <String>['cost', 'sell'],
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
        appBar: AppBar(title: Text(l10n.blackbeeSeedTitle)),
        body: ListView.separated(
          padding: EdgeInsetsDirectional.all(AppSpacing.of(context).md),
          itemCount: BlackbeeSeedService.productNames.length,
          separatorBuilder: (_, __) => SizedBox(height: AppSpacing.of(context).xs),
          itemBuilder: (_, index) {
            final name = BlackbeeSeedService.productNames[index];
            final added = _existing.contains(name.toLowerCase());
            return SurfaceCard(
              child: ListTile(
                title: Text(name),
                subtitle: Text(added
                    ? l10n.blackbeeSeedAdded
                    : l10n.blackbeeSeedPriceRequired),
                trailing: added
                    ? const Icon(Icons.check_circle_outline)
                    : const Icon(Icons.edit_outlined),
                onTap: added ? null : () => _price(name),
              ),
            );
          },
        ),
        );
  }
}
