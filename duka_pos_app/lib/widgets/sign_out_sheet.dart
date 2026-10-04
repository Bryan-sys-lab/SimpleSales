// Ending a session on a shared till.
//
// Signing out is not a formality. Three things can be true at once and each of
// them needs saying out loud before the session ends:
//
//   * Cash is in the drawer with nobody holding a shift against it. Closing a
//     shift needs a session; a shift abandoned mid-day has a float and no
//     reconciliation, which is the one state a till must not be left in.
//   * A cart may be part-built. Its contents are unsold and unsaved, so signing
//     out of the middle of a sale discards them.
//   * An online identity may be signed in, and its tokens are on this device.
//
// So this is a sheet with an explicit confirm, not a bare sign-out call, and the
// open-shift case is a warning the person can dismiss — deliberately, because
// there are legitimate reasons to step away from an open till (a delivery, a
// break) and the app should not refuse to let them.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';

/// Shows the sign-out confirmation and returns true if the session should end.
///
/// A null result means the sheet was dismissed, which is never a sign-out.
Future<bool> confirmSignOut(BuildContext context) async {
  final state = context.read<AppState>();
  final name = state.currentStaffName;

  // Read the open shift *before* anything changes, so the warning is built from
  // the state the person is actually in.
  Shift? openShift;
  try {
    openShift = await state.openShiftId();
  } catch (_) {
    // A failed read must not block a sign-out. Someone locked out of the app
    // because a query failed is a worse outcome than a shift they will see is
    // still open next time they sign in.
    openShift = null;
  }
  if (!context.mounted) return false;

  final cartCount = context.read<CartLineCount>().count;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              name == null ? 'Sign out' : 'Sign out $name',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'The PIN pad comes back for the next person.',
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
          ),
          if (cartCount > 0)
            _Warning(
              icon: Icons.shopping_cart_outlined,
              title:
                  'You have ${cartCount == 1 ? 'an item' : '$cartCount items'} in the cart',
              detail:
                  'Nothing has been charged, and signing out clears the cart.',
            ),
          if (openShift != null)
            _Warning(
              icon: Icons.point_of_sale_outlined,
              title: 'Your shift is still open',
              detail:
                  'The cash you started with is still counted against your shift. '
                  'You can sign out and reconcile later, but the shift stays open '
                  'until someone closes it.',
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('Stay signed in'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

/// One thing the person should know before they sign out.
///
/// The title and detail carry the state; the icon only reinforces it. Colour
/// alone would say none of this to a screen reader.
class _Warning extends StatelessWidget {
  const _Warning({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Semantics(
        label: '$title. $detail',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How many lines the sell screen's cart holds.
///
/// Read by the sign-out sheet so it can warn about unsold items without the
/// sheet reaching into another screen's private state. Provided by `SellScreen`
/// and reads zero everywhere else, which is the right default for a screen with
/// no cart.
///
/// Deliberately **not** a [ChangeNotifier]: the sheet is built fresh each time
/// it is opened, so it needs the current number and nothing else. Being a
/// notifier would mean the number has to be published after each of the cart's
/// several mutation sites, and a missed one under-reports a cart the sheet is
/// warning about. Read once, at open, it cannot drift.
class CartLineCount {
  int _count = 0;

  int get count => _count;

  void set(int value) => _count = value;
}
