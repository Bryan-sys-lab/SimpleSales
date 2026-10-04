import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'analytics_screen.dart';
import 'dashboard_screen.dart';
import 'sell_screen.dart';
import 'inventory_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

/// A shared shop till left signed in on the counter is a real risk — anyone
/// walking past can sell, adjust stock, or (if it was an owner session) open
/// Settings. This wraps the whole signed-in app in an idle timer that signs
/// out automatically after a few minutes of no touches, the same way a
/// POS terminal would. Any tap/scroll anywhere resets the clock.
const _idleTimeout = Duration(minutes: 4);

/// The destinations the shell can show, named rather than counted.
///
/// The list is role-dependent — a cashier has no Inventory, Analytics or
/// Settings destination — so a screen that wants to send the user somewhere has
/// to name the place, not hold an index. An index into a list that changes
/// shape with the role is how a "jump to stock" link ends up opening Settings.
enum HomeTab { dashboard, sell, inventory, analytics, reports, settings }

/// Lets a screen inside the shell move the shell to another tab.
///
/// The shell owns the selected tab, so a dashboard tile reading "12 items low"
/// has no other way to put the user in front of the list it is counting.
/// [goTo] is a no-op for a tab the current role does not have, which is the
/// right behaviour: there is nowhere to go, and silently opening something else
/// would be worse than doing nothing.
class HomeShellTabs extends ChangeNotifier {
  HomeTab _current = HomeTab.dashboard;

  HomeTab get current => _current;

  void goTo(HomeTab tab) {
    if (_current == tab) return;
    _current = tab;
    notifyListeners();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final HomeShellTabs _tabs = HomeShellTabs();
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
    // Provided here rather than in `main.dart` so the notifier is created and
    // disposed with the shell it drives.
    return ChangeNotifierProvider<HomeShellTabs>.value(
      value: _tabs,
      child: Listener(
        onPointerDown: (_) => _resetIdleTimer(),
        behavior: HitTestBehavior.translucent,
        child: Consumer<HomeShellTabs>(
          builder: (context, tabController, _) =>
              _scaffold(context, tabController),
        ),
      ),
    );
  }

  Widget _scaffold(BuildContext context, HomeShellTabs tabController) {
    final state = context.watch<AppState>();
    final isOwner = state.isAdmin;

    final tabs = <_Tab>[
      _Tab(HomeTab.dashboard, 'Dashboard', Icons.dashboard_outlined,
          const DashboardScreen()),
      _Tab(HomeTab.sell, 'Sell', Icons.point_of_sale_outlined,
          const SellScreen()),
      if (state.canManageStock)
        _Tab(HomeTab.inventory, 'Inventory', Icons.inventory_2_outlined,
            const InventoryScreen()),
      // Analytics is a manager-and-above screen: it reports the whole shop,
      // which is not a cashier's business to see.
      if (state.canManageStock)
        _Tab(HomeTab.analytics, 'Analytics', Icons.insights_outlined,
            const AnalyticsScreen()),
      if (state.canManageStock)
        _Tab(HomeTab.reports, 'Reports', Icons.bar_chart_outlined,
            const ReportsScreen()),
      if (isOwner)
        _Tab(HomeTab.settings, 'Settings', Icons.settings_outlined,
            const SettingsScreen()),
    ];
    // Resolved by identity, so a role change that removes a tab falls back to
    // the dashboard instead of leaving a stale index pointing at whatever
    // shifted into that position.
    final requested = tabs.indexWhere((t) => t.id == tabController.current);
    final index = requested < 0 ? 0 : requested;

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
        onDestinationSelected: (i) => tabController.goTo(tabs[i].id),
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
  final HomeTab id;
  final String label;
  final IconData icon;
  final Widget screen;
  _Tab(this.id, this.label, this.icon, this.screen);
}
