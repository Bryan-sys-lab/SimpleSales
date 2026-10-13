import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_keys.dart';
import '../services/app_state.dart';
import '../theme/app_spacing.dart';
import '../ui/layout/window_size_class.dart';
import '../widgets/sign_out_sheet.dart';
import 'idle_guard.dart';
import 'routes.dart';

/// The destinations this session may see.
///
/// Role-filtered ONCE, here, rather than by each affordance. A tab bar and a
/// drawer that disagree about who is an admin is how a cashier ends up with a
/// Settings tile that opens a dashboard.
List<AppDestination> visibleDestinations(AppState state) {
  return <AppDestination>[
    AppDestination.dashboard,
    AppDestination.sell,
    // Inventory, Analytics and Reports report the whole shop. A cashier's
    // business is this counter, not the month.
    if (state.canManageStock) AppDestination.inventory,
    if (state.canManageStock) AppDestination.analytics,
    if (state.isAdmin) AppDestination.settings,
  ];
}

/// Lets a screen inside the shell move the shell to another destination.
///
/// The shell owns the selected branch, so a dashboard tile reading "12 items low"
/// has no other way to put the user in front of the list it is counting.
///
/// [goTo] resolves through the router's own branch index, which is the ENUM index
/// and not the index in the role-filtered list — those are different numbers the
/// moment a role hides a destination, and conflating them is how a low-stock link
/// opens Settings.
///
/// ## Why [attach] exists
///
/// go_router builds a NEW [StatefulNavigationShell] widget on every navigation,
/// and `currentIndex` is a `final` field of that widget: the shell's
/// `IndexedStack` shows `widget.currentIndex` and nothing else. An earlier
/// version of this class captured the FIRST shell widget in its constructor and
/// the scaffold rendered `tabs.shell` — so `goBranch` ran, the URL and the
/// highlighted tab changed, and the body kept painting the stale widget whose
/// index was still 0: the dashboard, forever. [HomeShell] now hands every fresh
/// shell to [attach], and nothing in this class mirrors the index: the router is
/// the only source of truth for which tab is showing.
class HomeShellTabs extends ChangeNotifier {
  HomeShellTabs(this._shell, this._state) {
    _state.addListener(_onAppStateChanged);
  }

  StatefulNavigationShell _shell;
  final AppState _state;
  bool _disposed = false;

  /// Points this at the shell widget go_router most recently built.
  ///
  /// Deliberately silent: it runs inside a build, and the widgets that care
  /// about the index are rebuilt by the same pass that delivered the new shell.
  void attach(StatefulNavigationShell shell) => _shell = shell;

  StatefulNavigationShell get shell => _shell;

  /// The destination the router is showing, whether or not this role may see it.
  AppDestination get current => AppDestination.values[_shell.currentIndex];

  /// Role changed under a live session (an owner demoting a manager, say): if the
  /// branch on screen is no longer offered, move to the first one that is.
  ///
  /// The router's redirect also guards the URL; this keeps the shell's own
  /// chrome from sitting on a tab it no longer lists. Deferred to after the
  /// frame because this listener can fire in the middle of a build.
  void _onAppStateChanged() {
    if (_disposed || !_state.isSignedIn) return;
    if (visibleDestinations(_state).contains(current)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final List<AppDestination> visible = visibleDestinations(_state);
      if (visible.isEmpty || visible.contains(current)) return;
      _shell.goBranch(visible.first.index);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  int _catalogueGeneration = 0;

  int get catalogueGeneration => _catalogueGeneration;

  /// Moves the shell to [destination].
  ///
  /// A no-op for a destination this role does not have: a cashier tapping a
  /// stock tile should not be thrown somewhere else.
  ///
  /// Switching to another tab RESUMES that tab's own stack (each branch keeps its
  /// scroll position and any pushed detail); re-selecting the tab already showing
  /// pops it back to its root. Passing `initialLocation: true` on a switch would
  /// throw away the stack the router keeps alive for exactly this reason.
  void goTo(AppDestination destination) {
    if (!visibleDestinations(_state).contains(destination)) return;
    _shell.goBranch(
      destination.index,
      initialLocation: destination.index == _shell.currentIndex,
    );
  }

  void markCatalogueChanged() {
    _catalogueGeneration++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _state.removeListener(_onAppStateChanged);
    super.dispose();
  }
}

/// The chrome around the five branches.
///
/// One widget decides the navigation affordance for the whole app, from the
/// window's width and nothing else. Deciding it per screen is how an app ends up
/// with a bottom bar on a tablet and a rail on a phone depending on which screen
/// you opened first.
///
/// Width, never the device: a resized desktop window, a split-screen tablet and
/// a foldable's outer display all report their real constraints, and none of
/// them is `Platform.isTablet`.
///
/// Stateful so the [HomeShellTabs] it owns outlives the many [StatefulNavigationShell]
/// widgets go_router will hand it — see [HomeShellTabs.attach].
class HomeShell extends StatefulWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final HomeShellTabs _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = HomeShellTabs(widget.navigationShell, context.read<AppState>());
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tabs.attach(widget.navigationShell);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HomeShellTabs>.value(
      value: _tabs,
      // Above the branches, not inside the sell screen: the sign-out sheet is
      // shown by the shell's own app bar and must read the cart count from a
      // screen that may never have been opened this session.
      child: Provider<CartLineCount>(
        create: (_) => CartLineCount(),
        // The CURRENT shell widget travels down as a constructor argument, so
        // the scaffold can never paint a stale one.
        child: IdleGuard(
          child: _ShellScaffold(navigationShell: widget.navigationShell),
        ),
      ),
    );
  }
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final HomeShellTabs tabs = context.read<HomeShellTabs>();
    final List<AppDestination> destinations =
        visibleDestinations(state).toList(growable: false);

    // Read straight from the router's widget, on every build. If a role change
    // has just hidden the branch on screen, highlight the first tab that is
    // offered rather than handing the bar an index of -1.
    final AppDestination active =
        AppDestination.values[navigationShell.currentIndex];
    final AppDestination selected =
        destinations.contains(active) ? active : destinations.first;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final WindowSizeClass sizeClass =
            windowSizeClassFor(constraints.maxWidth);
        final Widget body = navigationShell;

        return Scaffold(
          appBar: _ShellAppBar(
            title: state.owner?.shopName ?? SimplePosBrand.appName,
            isOwner: state.isAdmin,
            staffName: state.currentStaffName ?? '',
            onSignOut: () => _signOut(context),
          ),
          body: switch (sizeClass) {
            WindowSizeClass.compact => body,
            WindowSizeClass.extraLarge => Row(
                children: <Widget>[
                  _ShellDrawer(
                    destinations: destinations,
                    selected: selected,
                    onSelect: tabs.goTo,
                  ),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(child: body),
                ],
              ),
            _ => Row(
                children: <Widget>[
                  _ShellRail(
                    destinations: destinations,
                    selected: selected,
                    extended: sizeClass != WindowSizeClass.medium,
                    onSelect: tabs.goTo,
                  ),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(child: body),
                ],
              ),
          },
          bottomNavigationBar: sizeClass == WindowSizeClass.compact
              ? _ShellNavigationBar(
                  destinations: destinations,
                  selected: selected,
                  onSelect: tabs.goTo,
                )
              : null,
        );
      },
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final bool confirmed = await confirmSignOut(context);
    if (!confirmed || !context.mounted) return;
    // `signOut` clears the local session first and tears the online one down in
    // the background, so the PIN pad appears without waiting on the network.
    context.read<AppState>().signOut();
  }
}

/// The shell's own app bar: which shop this is, and the way out of it.
class _ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ShellAppBar({
    required this.title,
    required this.isOwner,
    required this.staffName,
    required this.onSignOut,
  });

  final String title;
  final bool isOwner;
  final String staffName;
  final VoidCallback onSignOut;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String role = isOwner ? l10n.shellRoleOwner : staffName;

    return AppBar(
      title: Semantics(
        header: true,
        // The header a screen reader announces is the shop AND the session, not
        // just the shop: on a till with four staff, "which shop am I in and as
        // whom" is the first question after every sign-in.
        // gen-l10n sorts the parameters ALPHABETICALLY — role, title — which is
        // the reverse of the sentence "{title}, signed in as {role}".
        label: l10n.shellSignedInAs(role, title),
        child: ExcludeSemantics(
          child: Text(title, overflow: TextOverflow.ellipsis),
        ),
      ),
      actions: <Widget>[
        // Tapping the name opens the sign-out sheet rather than signing out
        // straight away: the name is the easiest thing on the bar to hit by
        // accident, and an accidental sign-out on a busy till is a customer
        // waiting.
        Semantics(
          button: true,
          label: l10n.shellAccountMenuLabel,
          child: TextButton.icon(
            onPressed: onSignOut,
            icon: Icon(
              isOwner ? Icons.workspace_premium_outlined : Icons.person_outline,
              size: 18,
            ),
            label: Text(role, overflow: TextOverflow.ellipsis),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.shellSignOutTooltip,
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
        ),
        SizedBox(width: spacing.xs),
      ],
    );
  }
}

/// Compact: a bottom bar.
class _ShellNavigationBar extends StatelessWidget {
  const _ShellNavigationBar({
    required this.destinations,
    required this.selected,
    required this.onSelect,
  });

  final List<AppDestination> destinations;
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: destinations.indexOf(selected),
        onDestinationSelected: (int i) => onSelect(destinations[i]),
        destinations: <Widget>[
          for (final AppDestination destination in destinations)
            NavigationDestination(
              icon: destination.imageAsset != null
                  ? Image.asset(
                      destination.imageAsset!,
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                    )
                  : Icon(destination.icon),
              label: destination.label(l10n),
              tooltip: destination.label(l10n),
            ),
        ],
      ),
    );
  }
}

/// Medium and expanded: a rail. Extended from `expanded` up, where there is room
/// for the full word rather than an initial.
class _ShellRail extends StatelessWidget {
  const _ShellRail({
    required this.destinations,
    required this.selected,
    required this.extended,
    required this.onSelect,
  });

  final List<AppDestination> destinations;
  final AppDestination selected;
  final bool extended;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return NavigationRail(
      selectedIndex: destinations.indexOf(selected),
      onDestinationSelected: (int i) => onSelect(destinations[i]),
      extended: extended,
      minExtendedWidth: 176,
      labelType: extended ? null : NavigationRailLabelType.all,
      destinations: <NavigationRailDestination>[
        for (final AppDestination destination in destinations)
          NavigationRailDestination(
            icon: destination.imageAsset != null
                ? Image.asset(
                    destination.imageAsset!,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                  )
                : Icon(destination.icon),
            // `extended` renders its own label beside the icon; supplying one
            // here too would double it.
            label: Text(
              extended ? destination.label(l10n) : destination.shortLabel(l10n),
            ),
          ),
      ],
    );
  }
}

/// Extra-large: a drawer, with the session detail a rail has no room for.
class _ShellDrawer extends StatelessWidget {
  const _ShellDrawer({
    required this.destinations,
    required this.selected,
    required this.onSelect,
  });

  final List<AppDestination> destinations;
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(state.owner?.shopName ?? SimplePosBrand.appName),
              subtitle: Text(
                l10n.roleLabel(state.isAdmin),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            for (final AppDestination destination in destinations)
              ListTile(
                selected: destination == selected,
                selectedTileColor:
                    Theme.of(context).colorScheme.primaryContainer,
                leading: Icon(destination.icon),
                title: Text(destination.label(l10n)),
                // No `Navigator.maybePop()` here: this is a permanent pane, not a
                // modal drawer, so there is nothing to close. The call used to
                // reach the root navigator, where the app's `PopScope` turned
                // every tap into a "Press back again to exit" snackbar.
                onTap: () => onSelect(destination),
              ),
          ],
        ),
      ),
    );
  }
}
