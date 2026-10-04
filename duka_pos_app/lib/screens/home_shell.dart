import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/sign_out_sheet.dart';
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

  /// Bumped whenever the catalogue changes — a product added, a variant
  /// configured, a shot cup saved.
  ///
  /// The shell keeps its tabs alive in an `IndexedStack`, so the sell screen is
  /// not rebuilt when the owner switches tabs and it would otherwise keep
  /// selling yesterday's catalogue until the app restarted. Anything that writes
  /// to the catalogue bumps this, and the sell screen reloads.
  int _catalogueGeneration = 0;

  int get catalogueGeneration => _catalogueGeneration;

  HomeTab get current => _current;

  void goTo(HomeTab tab) {
    if (_current == tab) return;
    _current = tab;
    notifyListeners();
  }

  /// Says the catalogue changed. Separate from [goTo] because saving a product
  /// does not necessarily move the user anywhere, and a reload should happen
  /// whether or not they navigate afterwards.
  void markCatalogueChanged() {
    _catalogueGeneration++;
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

  /// Survives the session, so a sign-out warned about a cart the sell screen
  /// built and then left is still warned about it.
  final CartLineCount _cartCount = CartLineCount();
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
      if (!mounted) return;
      // An idle sign-out is the same event as a deliberate one — same session
      // ended, same tokens to clear — so it goes through `signOut` rather than
      // a shortcut that would leave the online identity alive on the device.
      // No sheet: asking someone to confirm a timeout would defeat it, and the
      // till is secure again either way. The shift they left open is stated
      // next time they sign in, on the dashboard.
      context.read<AppState>().signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Provided here rather than in `main.dart` so the notifier is created and
    // disposed with the shell it drives.
    return ChangeNotifierProvider<HomeShellTabs>.value(
      value: _tabs,
      // Above the tabs, not inside the sell screen: the sign-out sheet is shown
      // by the shell's own app bar, and it has to read the cart count from a
      // screen that may not be built — on the dashboard, with the sell tab
      // never opened this session.
      child: Provider<CartLineCount>.value(
        value: _cartCount,
        child: Listener(
          onPointerDown: (_) => _resetIdleTimer(),
          behavior: HitTestBehavior.translucent,
          child: Consumer<HomeShellTabs>(
            builder: (context, tabController, _) =>
                _scaffold(context, tabController),
          ),
        ),
      ),
    );
  }

  /// Ends the session, after saying what is still open.
  ///
  /// Confirmation lives here rather than in the sheet's caller so the deliberate
  /// and the accidental paths cannot diverge.
  Future<void> _signOut() async {
    final confirmed = await confirmSignOut(context);
    if (!confirmed || !mounted) return;
    // `signOut` clears the local session first and tears the online one down in
    // the background, so the PIN pad appears without waiting on the network.
    context.read<AppState>().signOut();
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
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Sign out',
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: TextButton.icon(
                // Tapping the name opens the same sheet rather than signing out
                // straight away: the name is the easiest thing on the bar to hit
                // by accident, and an accidental sign-out on a busy till is a
                // customer waiting.
                onPressed: _signOut,
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
