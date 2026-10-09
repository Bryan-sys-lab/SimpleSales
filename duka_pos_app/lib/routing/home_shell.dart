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
import 'routes.dart';

/// A shared till left signed in on the counter is a real risk — anyone walking
/// past can sell, adjust stock, or (in an owner session) open Settings. The
/// shell wraps the whole signed-in app in an idle timer, the way a POS terminal
/// would. Any tap or scroll anywhere resets the clock.
const Duration _idleTimeout = Duration(minutes: 4);

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
class HomeShellTabs extends ChangeNotifier {
  HomeShellTabs(this._shell, this._state) : _shellIndex = _shell.currentIndex {
    _state.addListener(_onAppStateChanged);
  }

  final StatefulNavigationShell _shell;
  final AppState _state;

  late int _shellIndex;

  /// Call this from [HomeShell.build] to keep the shell index in sync.
  void updateShellIndex(int index) {
    if (_shellIndex == index) return;
    _shellIndex = index;
    notifyListeners();
  }

  void _onAppStateChanged() {
    final List<AppDestination> visible = visibleDestinations(_state).toList();
    // If the current branch is no longer visible (role change), go to first visible.
    final AppDestination? currentDest = visible.isNotEmpty
        ? visible.firstWhere(
            (d) => d.index == _shellIndex,
            orElse: () => visible.first,
          )
        : null;
    if (currentDest == null) return;
    if (!visible.contains(currentDest)) {
      _shell.goBranch(visible.first.index, initialLocation: false);
    }
  }

  @override
  void dispose() {
    _state.removeListener(_onAppStateChanged);
    super.dispose();
  }

  int _catalogueGeneration = 0;

  int get catalogueGeneration => _catalogueGeneration;

  StatefulNavigationShell get shell => _shell;

  AppDestination get current {
    final List<AppDestination> visible = visibleDestinations(_state).toList();
    // Find visible destination whose shell branch index (enum index) matches _shellIndex.
    return visible.isNotEmpty
        ? visible.firstWhere(
            (d) => d.index == _shellIndex,
            orElse: () => visible.first,
          )
        : AppDestination.dashboard;
  }

  void goTo(AppDestination destination) {
    final List<AppDestination> visible = visibleDestinations(_state).toList();
    if (!visible.contains(destination)) {
      if (visible.isNotEmpty && _shellIndex != visible.first.index) {
        _shell.goBranch(visible.first.index, initialLocation: true);
      }
      return;
    }
    _shell.goBranch(
      destination.index,
      initialLocation: destination != current,
    );
    // Update local index immediately for instant UI feedback; the shell rebuild
    // will call updateShellIndex again with the confirmed value.
    _shellIndex = destination.index;
    notifyListeners();
  }

  void markCatalogueChanged() {
    _catalogueGeneration++;
    notifyListeners();
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
class HomeShell extends StatelessWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return ChangeNotifierProvider<HomeShellTabs>(
      create: (_) => HomeShellTabs(navigationShell, state),
      // Update the shell index on every build so navigation affordances stay in
      // sync when the branch changes via user interaction (not just goTo).
      builder: (BuildContext context, Widget? child) {
        context.read<HomeShellTabs>().updateShellIndex(navigationShell.currentIndex);
        return child!;
      },
      // Above the branches, not inside the sell screen: the sign-out sheet is
      // shown by the shell's own app bar and must read the cart count from a
      // screen that may never have been opened this session.
      child: Provider<CartLineCount>(
        create: (_) => CartLineCount(),
        child: const _IdleGuard(child: _ShellScaffold()),
      ),
    );
  }
}

/// Resets the idle clock on any pointer interaction.
///
/// `Listener` with `HitTestBehavior.translucent` rather than a gesture
/// recogniser: this must not compete for the gesture arena, and a scroll has to
/// count as activity too.
class _IdleGuard extends StatefulWidget {
  const _IdleGuard({required this.child});

  final Widget child;

  @override
  State<_IdleGuard> createState() => _IdleGuardState();
}

class _IdleGuardState extends State<_IdleGuard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reset() {
    _timer?.cancel();
    _timer = Timer(_idleTimeout, () {
      if (!mounted) return;
      // An idle sign-out is the same event as a deliberate one — same session
      // ended, same tokens to clear — so it goes through `signOut` rather than a
      // shortcut that would leave the online identity alive on the device. No
      // confirmation sheet: asking someone to confirm a timeout would defeat it,
      // and the till is secure again either way.
      context.read<AppState>().signOut();
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _reset(),
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      );
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold();

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final HomeShellTabs tabs = context.watch<HomeShellTabs>();
    final List<AppDestination> destinations =
        visibleDestinations(state).toList(growable: false);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final WindowSizeClass sizeClass =
            windowSizeClassFor(constraints.maxWidth);
        final Widget body = tabs.shell;

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
                    selected: tabs.current,
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
                    selected: tabs.current,
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
                  selected: tabs.current,
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
        label: l10n.shellSignedInAs(title, role),
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
                onTap: () {
                  onSelect(destination);
                  Navigator.of(context).maybePop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
