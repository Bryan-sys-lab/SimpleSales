// The shop's own account, and the photograph that goes with it.
//
// ## Why the avatar is a FILE and not a column
//
// A photograph is large and it is personal, and both of those point the same
// way: the bytes belong on the filesystem under the app's documents directory,
// with a path in the row. Storing them in SQLite would put them into every
// encrypted backup the shop takes and into every audit-log export, and it would
// make `getOwner()` a query that reads megabytes.
//
// ## Why the photo is re-encoded on the way in
//
// A phone camera produces a four-kilopixel JPEG. The largest slot this app draws
// one into is a 96 logical-pixel circle, so decoding the original to fill it is
// wasted memory and wasted decode on the phones this till targets. Import
// re-encodes to the longest edge the app needs, which also strips the EXIF
// orientation block — so a photograph taken in portrait does not arrive
// sideways, and a GPS coordinate the shop never chose is not carried along.
//
// ## What this screen is for
//
// Everything an owner needs to know about the account that is signed in, in one
// place: who it is, whether the address has been verified, and how long this
// phone has been trading. It deliberately does NOT offer editing the identity —
// the address is what the emailed codes go to, and changing it is a verification
// flow rather than a text field.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import 'package:go_router/go_router.dart';

import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/pin_reset_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/product_image_store.dart';

/// The account, as one screen an owner can read.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).profileTitle),
      ),
      body: Consumer<AppState>(
        builder: (BuildContext context, AppState state, __) {
          final Owner? owner = state.owner;
          if (owner == null) {
            return Center(
              child: Text(AppLocalizations.of(context).profileNoAccountYet),
            );
          }
          return _ProfileBody(owner: owner, state: state);
        },
      ),
    );
  }
}

/// Opens the account with the real data wired in.
class ProfileScreenOpen extends ProfileScreen {
  const ProfileScreenOpen({super.key});
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody({required this.owner, required this.state});

  final Owner owner;
  final AppState state;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final owner = widget.owner;

    return ListView(
      padding: EdgeInsets.all(AppSpacing.of(context).lg),
      children: <Widget>[
        // The avatar, and the name it belongs to.
        Center(
          child: Column(
            children: <Widget>[
              const _AvatarRing(size: 96),
              SizedBox(height: AppSpacing.of(context).md),
              Text(
                owner.name,
                style: AppTypography.of(context).headlineSmall,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.of(context).xs),
              // The shop, not a second name: an owner may run several and this
              // is the one that is signed in.
              Text(
                owner.shopName,
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: AppColors.of(context).onSurfaceMuted,
                    ),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.of(context).xl),

        _ProfileRow(
          label: l10n.profilePhotoLabel,
          value: l10n.profilePhotoHelp,
          trailing: TextButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(l10n.profilePhotoChange),
          ),
        ),
        const Divider(height: 1),

        _ProfileRow(
          label: l10n.profileEmailLabel,
          // MASKED, like every other place the address appears.
          value: PinResetService.maskEmail(owner.email),
        ),
        const Divider(height: 1),

        _ProfileRow(
          label: l10n.profileVerifiedLabel,
          value: widget.state.identityVerified
              ? l10n.profileVerifiedYes
              : l10n.profileVerifiedNo,
          trailing: StatusChip(
            tone: widget.state.identityVerified
                ? StatusTone.success
                : StatusTone.warning,
            text: widget.state.identityVerified
                ? l10n.profileVerifiedYes
                : l10n.profileVerifiedNo,
            dense: true,
          ),
        ),
        const Divider(height: 1),

        _ProfileRow(
          label: l10n.profileSinceLabel,
          // Stored as a string, because an ISO timestamp is the only thing that
          // survives a locale change. Formatted at render, here, rather than
          // parsed everywhere else.
          value: _formatSince(owner.createdAt, context),
        ),
        const Divider(height: 1),

        _ProfileRow(
          label: l10n.profileShopLabel,
          value: owner.shopName,
        ),

        SizedBox(height: AppSpacing.of(context).xl),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.settings),
          icon: const Icon(Icons.settings_outlined),
          label: Text(l10n.profileBackToSettings),
        ),
      ],
    );
  }

  String _formatSince(String createdAt, BuildContext context) {
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return createdAt;
    // Local, not UTC: an owner reading "since March" means the month they
    // remember, not the server's.
    return MaterialLocalizations.of(context).formatFullDate(parsed.toLocal());
  }

  /// What to say when a photograph cannot be stored.
  ///
  /// Both causes an owner can act on resolve to the same sentence — free up
  /// space, or pick a file that is an image — so they are not distinguished.
  String _photoMessage(AppLocalizations l10n, ProductImageFailure failure) =>
      l10n.inventoryPhotoAddFailed;

  Future<void> _pickPhoto() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.inventoryPhotoFromGallery),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.inventoryPhotoFromCamera),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 512, imageQuality: 88);
    if (picked == null) return;

    // Imported through the same store the product photographs use, so there is
    // one re-encode rule and one place that knows where files live. The path is
    // returned but not kept on the owner row: the avatar is per-device, so
    // where it lives is a property of the device rather than of the account.
    try {
      await ProductImageStore.saveAvatar(File(picked.path));
    } on ProductImageException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_photoMessage(l10n, error.failure))),
      );
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.profilePhotoSaved)),
    );
  }
}

/// The avatar, drawn from the file this account's photograph is stored at.
///
/// Falls back to the owner's initials rather than to a generic silhouette:
/// an account with no photograph still reads as a person.
class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Watched, not read: picking a photograph re-renders this ring.
    final AppState state = context.watch<AppState>();
    final name = state.owner?.name ?? '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceSunken,
        border: Border.all(color: colors.outline, width: 2),
      ),
      alignment: Alignment.center,
      child: FutureBuilder<String?>(
        future: ProductImageStore.resolve(ProductImageStore.avatarRelativePath),
        builder: (BuildContext context, AsyncSnapshot<String?> snap) {
          final path = snap.data;
          if (path != null) {
            // Sized at 2x the drawn edge so the codec decodes only what the
            // screen shows. The photo is decorative beside the name below it,
            // so it is excluded from semantics rather than announced twice.
            return ExcludeSemantics(
              child: ClipOval(
                child: Image.file(
                  File(path),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 2).round(),
                  // A photograph that has moved or been deleted reads the same
                  // as never having had one, rather than as a broken image.
                  errorBuilder: (_, __, ___) =>
                      _Initials(name: name, size: size),
                ),
              ),
            );
          }
          return _Initials(name: name, size: size);
        },
      ),
    );
  }
}

/// An account's initials, for one with no photograph yet.
///
/// Better than a generic silhouette: a shop owner looking at their own account
/// reads their own name, and two accounts on one device are told apart at a
/// glance rather than by size alone.
class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    if (name.trim().isEmpty) {
      return Icon(Icons.person_outline,
          size: size * 0.45, color: colors.onSurfaceMuted);
    }
    final String initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    return Text(
      initials,
      style: theme.textTheme.headlineMedium?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// One label/value line of the account.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final type = AppTypography.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.of(context).md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: type.labelMedium),
                SizedBox(height: 2),
                Text(value, style: type.bodyLarge),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            SizedBox(width: AppSpacing.of(context).sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
