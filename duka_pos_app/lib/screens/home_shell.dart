import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'dashboard_screen.dart';
import 'sell_screen.dart';
import 'inventory_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

/// A shared shop till left signed in on the counter is a real risk — anyone
/// walking past can sell, adjust stock, or (if it was an owner session) open
/// Settings. This wraps the whole signed-in app in an idle timer that signs
/// out automatically after a few minutes of no touches, the same way a real
/// POS terminal would. Any tap/scroll anywhere resets the clock.
const _idleTimeout = Duration(minutes: 4);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      if (mounted) context.read<AppState>().signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isOwner = state.isAdmin;

    final tabs = <_Tab>[
      _Tab('Dashboard', Icons.dashboard_outlined, const DashboardScreen()),
      _Tab('Sell', Icons.point_of_sale_outlined, const SellScreen()),
      if (state.canManageStock)
        _Tab('Inventory', Icons.inventory_2_outlined, const InventoryScreen()),
      if (state.canManageStock)
        _Tab('Reports', Icons.bar_chart_outlined, const ReportsScreen()),
      if (isOwner)
        _Tab('Settings', Icons.settings_outlined, const SettingsScreen()),
    ];
    final index = _tab < tabs.length ? _tab : 0;

    return Listener(
      onPointerDown: (_) => _resetIdleTimer(),
      behavior: HitTestBehavior.translucent,
      child: _scaffold(context, state, isOwner, tabs, index),
    );
  }

  Widget _scaffold(BuildContext context, AppState state, bool isOwner,
      List<_Tab> tabs, int index) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(state.owner?.shopName ?? 'Duka POS'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: TextButton.icon(
                onPressed: () => state.signOut(),
                icon: Icon(isOwner
                    ? Icons.workspace_premium_outlined
                    : Icons.person_outline),
                label: Text(state.currentStaffName ?? ''),
              ),
            ),
          ),
        ],
      ),
      body: tabs[index].screen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: tabs
            .map((t) =>
                NavigationDestination(icon: Icon(t.icon), label: t.label))
            .toList(),
      ),
    );
  }
}
// (end of _HomeShellState)

class _Tab {
  final String label;
  final IconData icon;
  final Widget screen;
  _Tab(this.label, this.icon, this.screen);
}
