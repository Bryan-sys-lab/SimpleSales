import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_keys.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../profile/profile_navigation.dart';
import '../profile/shop_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/brand_header.dart';
import '../ui/components/status_bar.dart';
import '../ui/components/notification_sheet.dart';
import '../ui/layout/window_size_class.dart';
import '../widgets/sign_out_sheet.dart';
import 'idle_guard.dart';
import 'routes.dart';
import 'shell_nav_bar.dart';

/// The destinations this session may see.
///
/// Role-filtered ONCE, here, rather than by each affordance. A tab bar and a
/// drawer that disagree about who is an admin is how a cashier ends up with a
/// Settings tile that opens a dashboard.
List<AppDestination> visibleDestinations(AppState state) {
  // The order is the ORDER THE BAR SHOWS THEM IN, and the sell button sits in
  // the middle of it.
  //
  // So the destinations divide around it: the ones before sell on the left
  // shoulder, the ones after on the right. The order is chosen so that the
  // split is as even as each role can make it — a cashier gets one on each
  // side, a manager two and two, an owner two and three — and so the
  // everyday destinations are the ones nearest the ball.
  
  // Open profile primary navigation: Jobs/Pots/Business Record instead of inventory
  if (state.shopProfile == ShopProfile.open) {
    return <AppDestination>[
      AppDestination.dashboard,
      AppDestination.openBusiness,
      AppDestination.sell,
      AppDestination.analytics,
      AppDestination.more,
      AppDestination.support,
    ];
  }
  
  return <AppDestination>[
    AppDestination.dashboard,
    // Inventory and Reports report the whole shop. A cashier's business is
    // this counter, not the month.
    if (state.canManageStock && state.shopProfile.navigation.showInventory)
      AppDestination.inventory,
    AppDestination.sell,
    // Analytics is open to everybody, and it shows each person their OWN
    // takings. A cashier may read how their counter is doing without being
    // shown what the shop is doing — so the figures are scoped to the rows
    // they sold, and the manager's whole-shop view is the same screen with
    // the scope opened up.
    AppDestination.analytics,
    AppDestination.more,
    AppDestination.support,
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
  HomeShellTabs(this._shell, this._state, {VoidCallback? onMore})
      : _onMore = onMore ?? (() {}) {
    _state.addListener(_onAppStateChanged);
    _catalogueListeners.add(_onCatalogueChange);
    _catalogueGeneration = catalogueGeneration;
  }

  StatefulNavigationShell _shell;
  final AppState _state;
  final VoidCallback _onMore;
  bool _disposed = false;

  /// Points this at the shell widget go_router most recently built.
  ///
  /// Deliberately silent: it runs inside a build, and the widgets that care
  /// about the index are rebuilt by the same pass that delivered the new shell.
  void attach(StatefulNavigationShell shell) => _shell = shell;

  StatefulNavigationShell get shell => _shell;

  /// The destination the router is showing, whether or not this role may see it.
  AppDestination get current => AppDestination.branchAt(_shell.currentIndex);

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

  /// The catalogue's generation as this shell last saw it.
  ///
  /// Backed by the module-level [catalogueGeneration], which is the authority: a
  /// screen pushed above the shell announces there and this follows it. There is
  /// deliberately no `markCatalogueChanged` member on this class — a member of
  /// that name shadows the module-level function inside the class and recurses
  /// forever, which is an easy mistake to make.
  int get catalogueGenerationSeen => _catalogueGeneration;

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
    if (destination == AppDestination.more) {
      _onMore();
      return;
    }
    _shell.goBranch(
      destination.branchIndex,
      initialLocation: destination.branchIndex == _shell.currentIndex,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _catalogueListeners.remove(_onCatalogueChange);
    _state.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onCatalogueChange() {
    _catalogueGeneration = catalogueGeneration;
    notifyListeners();
  }
}

/// A catalogue change that happened ABOVE the shell.
///
/// Product detail, shot cups and the imports answer are pushed on the ROOT
/// navigator, so they cover the whole shell — which means they sit OUTSIDE the
/// subtree `ChangeNotifierProvider<HomeShellTabs>` is in, and
/// `context.read<HomeShellTabs>()` throws `ProviderNotFoundException` where
/// they stand. That is exactly what shot cups did: the cup was written, the
/// notification threw, and neither the list nor the till ever saw it — "I
/// created a cup and nothing happened".
///
/// So the generation count and its listeners live at module level, the shell
/// subscribes to them, and any screen anywhere can announce. Same shape as
/// [systemBackHandler]: state that has to outlive one subtree lives in one
/// module-level place with a seam a test can reach.
final Set<VoidCallback> _catalogueListeners = <VoidCallback>{};

/// The module-level listeners, exposed for a test only.
///
/// Nothing in the app needs them: a screen that wants to announce calls
/// [markCatalogueChanged] and a screen that wants to hear holds the provider.
/// A test needs to prove an announcement travels from a screen ABOVE the shell
/// to a listener inside it, and building a whole shell to do that is a lot of
/// scaffolding for one fact.
@visibleForTesting
Set<VoidCallback> get catalogueListenersForTesting => _catalogueListeners;

/// Puts the generation back to zero, for a test only.
///
/// The counter is module level on purpose — it has to outlive one subtree — so a
/// test file that only reads it must be able to say which number it expects.
@visibleForTesting
void resetCatalogueGenerationForTesting() => catalogueGeneration = 0;

/// The catalogue's generation: incremented on every change, for a listener that
/// cannot use a callback — a late `addPostFrameCallback` that needs to know
/// whether what it is about to read is still what it saw.
int catalogueGeneration = 0;

/// Announces that the catalogue changed, everywhere.
///
/// Safe to call from any screen, at any time, including before the shell has
/// ever been built: with no shell there is nothing to notify, and the next
/// screen to read the catalogue reads the database anyway.
void markCatalogueChanged() {
  catalogueGeneration++;
  for (final VoidCallback listener in _catalogueListeners.toList()) {
    listener();
  }
}

/// The chrome around the six branches.
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
    _tabs = HomeShellTabs(
      widget.navigationShell,
      context.read<AppState>(),
      onMore: () => _openMore(context),
    );
  }

  Future<void> _openMore(BuildContext context) async {
    final state = context.read<AppState>();
    final action = await showModalBottomSheet<_MoreAction>(
      context: context,
      useSafeArea: true,
      builder: (_) => _MoreSheet(
        showLayby: state.shopProfile.navigation.showLayby,
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _MoreAction.settings:
        context.push(Routes.settings);
      case _MoreAction.support:
        _tabs.goTo(AppDestination.support);
      case _MoreAction.marketplace:
        context.push(Routes.marketplace);
      case _MoreAction.notifications:
        final destination = await showNotificationSheet(
          context,
          staffId: state.currentStaffId ?? 1,
          role: state.role.wire,
        );
        if (destination != null && context.mounted) context.push(destination);
      case _MoreAction.laybys:
        context.push(Routes.laybys);
      case _MoreAction.openBusiness:
        context.push(Routes.openBusiness);
    }
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
        AppDestination.branchAt(navigationShell.currentIndex);
    final AppDestination selected =
        destinations.contains(active) ? active : destinations.first;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final WindowSizeClass sizeClass =
            windowSizeClassFor(constraints.maxWidth);
        final Widget body = navigationShell;

        // The SUPPORT leaves the bottom bar and becomes a floating bubble.
        //
        // The bar's shape is a horseshoe with the sell button in the middle,
        // and the destinations divide evenly around it — which the support
        // item broke every time: one more on one shoulder than the other, in
        // every role. As a bubble it is also where a person who needs help
        // expects it: not a tab they have to find, but a corner they can reach
        // from wherever they are.
        //
        // The rail and the drawer KEEP it: they have room, and they are the
        // wider screens' affordance.
        final List<AppDestination> barDestinations = <AppDestination>[
          for (final AppDestination destination in destinations)
            if (destination != AppDestination.support) destination,
        ];

        return Scaffold(
          appBar: _ShellAppBar(
            title: state.owner?.shopName ?? SimplePosBrand.appName,
            roleLabel: _roleLabel(context, state),
            sessionName: state.currentStaffName ?? _roleLabel(context, state),
            onSignOut: () => _signOut(context),
            onOpenProfile: () => context.push(Routes.profile),
            onOpenCredit: () => context.push(Routes.customers),
            showCredit: state.isOwnerSession || state.role == ShopRole.manager,
          ),
          // The body.
          //
          // The support bubble used to FLOAT over the bottom-right corner of
          // the body. It was a `PositionedDirectional` in a Stack, so when the
          // keyboard opened the Scaffold shrank the body and the bubble rode
          // up with it — landing on top of the buttons at the far end of the
          // screen, exactly where a cashier's thumb was reaching. It lives in
          // the app bar now, where it cannot move and cannot cover anything.
          body: Column(
            children: <Widget>[
              // The status strip, ABOVE the content and BELOW the bar.
              //
              // A column, so the strip is the first thing the content sits
              // under and the content never overlaps it. And it is here rather
              // than on the dashboard because a cashier is rarely on the
              // dashboard, and a till that cannot reach the server is exactly
              // where the owner needs to know.
              const TillStatusBar(),
              Expanded(
                // The branch, once.
                //
                // ONE `body` in the tree: the strip is a COLUMN above it,
                // so the branch is the column's only child. Putting the
                // branch in the column AND in the size switch built it
                // twice, and a `StatefulNavigationShell` carries a
                // GlobalKey — so the tree had the same key twice and the
                // whole shell failed to mount.
                child: switch (sizeClass) {
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
              ),
            ],
          ),
          bottomNavigationBar: sizeClass == WindowSizeClass.compact
              ? ShellNavBar(
                  destinations: barDestinations,
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

enum _MoreAction {
  settings,
  support,
  marketplace,
  notifications,
  laybys,
  openBusiness
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.showLayby});

  final bool showLayby;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        if (showLayby)
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: const Text('Fashion lay-bys'),
            onTap: () => Navigator.pop(context, _MoreAction.laybys),
          ),
        // Open business record is now primary navigation for Open profile
        // so it's not in the more sheet for that profile
        if (context.read<AppState>().shopProfile.navigation.showJobs && 
            context.read<AppState>().shopProfile != ShopProfile.open)
          ListTile(
            leading: const Icon(Icons.work_outline),
            title: const Text('Open business record'),
            subtitle: const Text('Pots, jobs and owner money'),
            onTap: () => Navigator.pop(context, _MoreAction.openBusiness),
          ),
        if (context.read<AppState>().isAdmin)
          ListTile(
            leading: const Icon(Icons.tune_outlined),
            title: Text(l10n.navSettings),
            onTap: () => Navigator.pop(context, _MoreAction.settings),
          ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(l10n.navSupport),
          onTap: () => Navigator.pop(context, _MoreAction.support),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_none),
          title: Text(l10n.notifications),
          onTap: () => Navigator.pop(context, _MoreAction.notifications),
        ),
        ListTile(
          leading: const Icon(Icons.extension_outlined),
          title: Text(l10n.businessToolsMarketplace),
          onTap: () => Navigator.pop(context, _MoreAction.marketplace),
        ),
      ],
    );
  }
}

/// The role of whoever is signed in, in the app's own words.
///
/// "Owner", "Manager" or "Cashier" — the ROLE, not the name. The name is in
/// the dashboard's welcome, where a person is greeted by it, and the role is a
/// fact about this session, which is what belongs beside the way out of it.
String _roleLabel(BuildContext context, AppState state) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return switch (state.role) {
    ShopRole.admin => l10n.shellRoleOwner,
    ShopRole.manager => l10n.settingsRoleManager,
    ShopRole.cashier => l10n.settingsRoleCashier,
  };
}

/// The shell's own bar: the session, and the way out of it.
///
/// NOT a coloured band. It is the canvas, with the brand mark at the leading
/// edge and the session at the trailing edge — the app-level furniture, kept
/// quiet so that the screen's own large title stays the biggest thing on it.
///
/// The screen's NAME belongs to the screen: every branch opens with a
/// [ScreenTitle] on the canvas below this bar, which is why the shop name is
/// not repeated up here.
class _ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ShellAppBar({
    required this.title,
    required this.roleLabel,
    required this.sessionName,
    required this.onSignOut,
    required this.onOpenProfile,
    required this.onOpenCredit,
    required this.showCredit,
  });

  final String title;

  /// Who is signed in: "Owner", "Manager" or "Cashier".
  ///
  /// The ROLE, not the name. The name is in the dashboard's welcome, where a
  /// person is greeted by it, and the role is a fact about this session —
  /// which is what belongs beside the way out of the session.
  final String roleLabel;
  final String sessionName;

  final VoidCallback onSignOut;

  /// Opens the person's own account.
  ///
  /// A VIEWER, not an editor and not a way out: the account icon is the
  /// person icon, and a person icon that signs you out is a trap. Editing
  /// lives on the profile screen itself, where there is room to say what
  /// editing does.
  final VoidCallback onOpenProfile;

  final VoidCallback onOpenCredit;
  final bool showCredit;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String role = roleLabel;
    final bool compact = MediaQuery.sizeOf(context).width < 400;
    final bool showRoleText = !compact;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: compact ? 0 : spacing.lg,
      title:
          compact ? const SizedBox.shrink() : BrandHeader(markSize: spacing.xl),
      actions: <Widget>[
        // Non-identity actions live in More. Only identity and sign-out stay
        // on the app bar, with credit restored as the one operational shortcut
        // owners and managers need at a glance.
        if (showCredit)
          Semantics(
            button: true,
            label: l10n.shellCreditMenuLabel,
            child: IconButton(
              tooltip: l10n.shellCreditMenuLabel,
              onPressed: onOpenCredit,
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
        // Who is signed in, quietly, RIGHT BESIDE the account icon. The full
        // name is on the dashboard's title block and in Settings, so this is a
        // reminder that travels with the avatar rather than a label of its own.
        if (showRoleText)
          ConstrainedBox(
            // Keep the app-level actions usable on a compact till after the
            // credit shortcut is added. The full identity remains available
            // in Profile; this label only needs to identify the role at a
            // glance.
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(
              sessionName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.of(context)
                  .labelMedium
                  ?.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
        // The account: a VIEWER of who is signed in.
        //
        // It used to open the sign-out sheet, which is a trap: the person
        // icon means "this is me", and a person icon that ends the session is
        // the easiest button on the bar to hit by accident. On a busy till an
        // accidental sign-out is a customer waiting.
        Semantics(
          button: true,
          // The header a screen reader announces is the shop AND the session,
          // not just the shop: on a till with four staff, "which shop am I in
          // and as whom" is the first question after every sign-in.
          //
          // gen-l10n sorts the parameters ALPHABETICALLY — role, title — which
          // is the reverse of the sentence "{title}, signed in as {role}".
          label: l10n.shellSignedInAs(role, title),
          child: IconButton(
            tooltip: l10n.shellAccountMenuLabel,
            onPressed: onOpenProfile,
            icon: const Icon(Icons.person_outline),
          ),
        ),
        IconButton(
          tooltip: l10n.shellSignOutTooltip,
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
        ),
        if (!compact) SizedBox(width: spacing.xs),
      ],
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
            icon: Icon(destination.icon),
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
