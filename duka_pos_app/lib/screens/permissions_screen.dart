// The one step where the till asks for what it needs.
//
// ## WHY IT EXISTS
//
// A permission asked for at the moment it is needed is a permission prompt that
// arrives in the middle of a sale: the shopkeeper opens the scanner and gets a
// system dialog about the camera while a customer is standing at the counter.
//
// So the app asks ONCE, here, after the walkthrough — where the person is not
// in the middle of anything, and where they can read what each permission is
// FOR before answering.
//
// ## WHY IT CANNOT BLOCK
//
// Every permission on this screen is OPTIONAL, and so is the screen.
//
// A shop with a wedge scanner and no camera is a perfectly good shop. A shop
// that has not paired a printer is a perfectly good shop. A till that cannot
// sell because nobody granted a permission it does not need is a till that is
// broken, and the fix is never "make the permission mandatory".
//
// So: "Continue" is always there, and it is the same button whether the
// permissions were granted, refused, or never asked about.
//
// ## WHY IT IS ADMIN-ONLY, AND ONCE
//
// The same rule as the walkthrough it follows: the copy is addressed to
// whoever set the shop up, and a cashier is not that person.
//
// And it is asked ONCE per workspace, not on every launch. A permission the
// owner has already answered — granted or refused — is a decision, and a till
// that asks again every morning is a till people learn to dismiss without
// reading. The screen is still reachable from Settings, for a till that gains
// a printer later.
//
// ## WHAT IS NOT ON THIS SCREEN
//
// Notifications, location, storage. In-app notifications are counts-only and
// need no OS permission; the app never derives a place from a radio, and reads
// the gallery through the system photo picker, which needs no permission.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/screen_title.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';

/// The permissions the till can ask for, in the order they are asked.
const List<TillPermission> _asked = <TillPermission>[
  TillPermission.camera,
  TillPermission.bluetooth,
];

/// Asks the till's owner for the permissions the till can use.
///
/// [onComplete] is called when the owner moves on, whether the permissions
/// were granted or not. It is awaited, because the thing it does — recording
/// that the step has been seen and letting the router onward — is the whole
/// reason the screen can be dismissed.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({
    required this.permissions,
    this.onComplete,
    super.key,
  });

  /// How the app asks. Injected so the screen can be pumped in a test: the
  /// real one is a platform channel, and a screen whose only path to the
  /// system prompt is the platform is a screen nobody can test.
  final PermissionService permissions;

  /// Moving on, whether the permissions were granted or not.
  final Future<void> Function()? onComplete;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  /// Where each permission stands. Null until the first read answers.
  final Map<TillPermission, PermissionState> _states =
      <TillPermission, PermissionState>{};

  /// A prompt is up for this permission. A second tap while the system dialog
  /// is showing would stack a second dialog behind it.
  final Set<TillPermission> _asking = <TillPermission>{};

  /// The step is being closed.
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _readAll();
  }

  /// Reads where every permission stands.
  ///
  /// The states are read ONCE, into the screen's own map, rather than through
  /// a `FutureBuilder`: a builder is handed a new future on every build and
  /// starts over, so the read would repeat on every rebuild of the list.
  Future<void> _readAll() async {
    for (final TillPermission permission in _asked) {
      final PermissionState state = await widget.permissions.state(permission);
      if (!mounted) return;
      setState(() => _states[permission] = state);
    }
  }

  /// Asks for [permission] and records the answer.
  Future<void> _ask(TillPermission permission) async {
    if (_asking.contains(permission)) return;
    setState(() => _asking.add(permission));
    final bool granted = await widget.permissions.request(permission);
    if (!mounted) return;
    // The state after a refusal is not simply "refused": the system may have
    // said "don't ask again", and the two need different words. So the state
    // is READ rather than assumed — outside the setState, because a setState
    // closure cannot await.
    final PermissionState after = granted
        ? PermissionState.granted
        : await widget.permissions.state(permission);
    if (!mounted) return;
    setState(() {
      _asking.remove(permission);
      _states[permission] = after;
    });
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: EdgeInsetsDirectional.only(
                  start: spacing.lg,
                  end: spacing.lg,
                  bottom: spacing.lg,
                ),
                children: <Widget>[
                  ScreenTitle(
                    title: l10n.permissionsTitle,
                    subtitle: l10n.permissionsSubtitle,
                    padding: EdgeInsetsDirectional.only(
                      top: spacing.md,
                      bottom: spacing.lg,
                    ),
                  ),
                  for (final TillPermission permission in _asked)
                    Padding(
                      padding: EdgeInsets.only(bottom: spacing.md),
                      child: _PermissionCard(
                        permission: permission,
                        state: _states[permission],
                        busy: _asking.contains(permission),
                        onAsk: () => _ask(permission),
                      ),
                    ),
                  SizedBox(height: spacing.sm),
                  // The reassurance, in the app's own words: the point of this
                  // screen is that the owner can see they are not being
                  // blocked, and a screen of system prompts with no such
                  // sentence reads as one.
                  Text(
                    l10n.permissionsOptionalNote,
                    style: type.bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.lg,
                end: spacing.lg,
                bottom: spacing.lg,
              ),
              child: FilledButton(
                onPressed: _finishing ? null : _finish,
                child: Text(l10n.permissionsContinue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One permission: what it is for, where it stands, and a way to change it.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.permission,
    required this.state,
    required this.busy,
    required this.onAsk,
  });

  final TillPermission permission;

  /// Where the permission stands, or null while the first read answers.
  final PermissionState? state;

  /// A prompt is up.
  final bool busy;

  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    final PermissionState current = state ?? PermissionState.notAsked;
    final bool granted = current == PermissionState.granted;
    final bool permanent = current == PermissionState.permanentlyDenied;

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconBadge(
            icon: switch (permission) {
              TillPermission.camera => Icons.photo_camera_outlined,
              TillPermission.bluetooth => Icons.print_outlined,
            },
            // A granted permission is a quiet, successful thing; a refused one
            // is the only one that needs a colour.
            tone: granted ? StatusTone.success : StatusTone.neutral,
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  switch (permission) {
                    TillPermission.camera => l10n.permissionsCameraTitle,
                    TillPermission.bluetooth => l10n.permissionsBluetoothTitle,
                  },
                  style: type.titleMedium,
                ),
                const SizedBox(height: 2),
                // WHY, in the shop's language. A permission prompt with no
                // reason is a prompt people dismiss.
                Text(
                  switch (permission) {
                    TillPermission.camera => l10n.permissionsCameraWhy,
                    TillPermission.bluetooth => l10n.permissionsBluetoothWhy,
                  },
                  style: type.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                SizedBox(height: spacing.md),
                if (granted)
                  StatusChip(
                      tone: StatusTone.success, text: l10n.permissionsAllowed)
                else
                  // The button's LABEL says what it will do, and says the
                  // difference between asking again and sending somebody to
                  // the system Settings screen: a permanently denied
                  // permission cannot be asked for again, and pretending
                  // otherwise wastes the tap.
                  OutlinedButton(
                    onPressed: busy ? null : onAsk,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: shapes.controlRadius,
                      ),
                    ),
                    child: Text(
                      permanent
                          ? l10n.permissionsOpenSettings
                          : l10n.permissionsAllow,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
