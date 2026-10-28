import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../profile/profile_navigation.dart';
import '../services/app_state.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppState>().shopProfile.navigation;
    final features = <_Feature>[
      _Feature('Sell', 'Tap a product to add it to the cart, then charge.',
          Icons.point_of_sale_outlined),
      _Feature('Inventory', 'Add products, receive stock, and check low stock.',
          Icons.inventory_2_outlined),
    ];
    if (nav.showDrinkService) {
      features.add(_Feature('Tanks', 'Set up tanks, record dips and shrinkage.',
          Icons.propane_tank_outlined));
      features.add(_Feature('Shots', 'Sell by shot cup from a bottle.',
          Icons.local_drink_outlined));
    }
    if (nav.showLayby) {
      features.add(_Feature(
          'Lay-bys', 'Take a deposit and collect the balance later.',
          Icons.bookmark_border));
    }
    if (nav.showJobs) {
      features.add(_Feature('Jobs', 'Create a job, take payments, mark complete.',
          Icons.work_outline));
      features.add(_Feature('Cost groups', 'Record what you paid and recover it on sales.',
          Icons.account_balance_wallet_outlined));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: features.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final f = features[index];
          return _FeatureStrip(feature: f);
        },
      ),
    );
  }
}

class _Feature {
  final String title;
  final String body;
  final IconData icon;
  const _Feature(this.title, this.body, this.icon);
}

class _FeatureStrip extends StatelessWidget {
  const _FeatureStrip({required this.feature});

  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCard(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(feature.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(feature.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  void _openCard(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(feature.title,
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(feature.body),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
