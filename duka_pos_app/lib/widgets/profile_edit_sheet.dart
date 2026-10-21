// Editing the owner's own details.
//
// ## WHY THIS EXISTS
//
// The profile screen used to say, in its own header, that it "deliberately does
// NOT offer editing the identity — the address is what the emailed codes go
// to, and changing it is a verification flow rather than a text field".
//
// The first half of that was right about the EMAIL and wrong about the rest.
// A shop owner whose name changed, whose shop was renamed, or whose phone
// number moved on, had no way to correct any of it: the profile was a
// photograph of the past.
//
// So the NAME and the SHOP NAME are edited here, directly. They are local
// facts about this till, and nothing about them reaches a server.
//
// ## AND THE EMAIL
//
// The email is the one that is different, and the difference is not a detail.
//
// The address is where the PIN-recovery codes and the verification codes are
// SENT. Typing a new one into a text field does not move them: the old
// address keeps receiving them until the backend is told, and the backend
// only hears about a new address from the owner proving they can receive mail
// there.
//
// So the email is edited here TOO, and the app says plainly what has to
// happen next: the new address is unverified until a code is sent to it, and
// the old one stops working for recovery the moment the backend accepts the
// change. An owner who has never linked a shop to the backend has no codes to
// send, and for them the address is simply the one they type.
//
// What is NOT offered here is the PIN. It has its own flow, with its own
// confirmation and its own lockout, and a profile edit is not a way around it.

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';

/// What the owner changed.
class ProfileEdit {
  const ProfileEdit({
    required this.name,
    required this.shopName,
    required this.email,
  });

  final String name;
  final String shopName;
  final String email;
}

/// Asks the owner for their details.
///
/// Returns null when the sheet is dismissed, so a cancelled edit changes
/// nothing. The save button is disabled until the form is valid, and the
/// reason is on the field rather than in a dialog.
class ProfileEditSheet extends StatefulWidget {
  const ProfileEditSheet({
    required this.name,
    required this.shopName,
    required this.email,
    super.key,
  });

  final String name;
  final String shopName;
  final String email;

  @override
  State<ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<ProfileEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _shopName =
      TextEditingController(text: widget.shopName);
  late final TextEditingController _email =
      TextEditingController(text: widget.email);

  @override
  void dispose() {
    _name.dispose();
    _shopName.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Whether the form can be saved.
  ///
  /// A name and a shop name are required — a till that says nothing about who
  /// it belongs to is a till nobody can claim. The email is optional: a shop
  /// that has never been linked to the backend has no codes to receive, and
  /// requiring an address would be requiring a thing it does not need.
  bool get _valid =>
      _name.text.trim().isNotEmpty && _shopName.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.lg,
            end: spacing.lg,
            top: spacing.lg,
            bottom: spacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(l10n.profileEditTitle, style: type.headlineSmall),
              SizedBox(height: spacing.lg),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.profileEditNameLabel,
                  helperText: l10n.profileEditNameHelp,
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: spacing.md),
              TextField(
                controller: _shopName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.profileEditShopNameLabel,
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: spacing.md),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.profileEditEmailLabel,
                  helperText: l10n.profileEditEmailHelp,
                  helperMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: spacing.lg),
              // The consequence, said before the button rather than after it.
              Text(
                l10n.profileEditEmailWarning,
                style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
              ),
              SizedBox(height: spacing.lg),
              FilledButton(
                onPressed: _valid
                    ? () => Navigator.pop(
                          context,
                          ProfileEdit(
                            name: _name.text.trim(),
                            shopName: _shopName.text.trim(),
                            email: _email.text.trim(),
                          ),
                        )
                    : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: shapes.controlRadius,
                  ),
                ),
                child: Text(l10n.profileEditSave),
              ),
              SizedBox(height: spacing.sm),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.actionCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
