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
// phone has been trading — AND the one action that changes any of it.
//
// It used to be read-only, on the grounds that the address is what the
// emailed codes go to. That is true of the EMAIL and false of the rest: a
// shop owner whose name changed, or whose shop was renamed, had no way to
// correct it. The name and the shop name are edited directly; the email is
// edited too, and the app says plainly that a new address has to be verified
// before it can be used to recover the PIN. The PIN itself is NOT editable
// here — it has its own flow, with its own confirmation and its own lockout.
//
// ## Why the rows are cards and not a ruled table
//
// A rule-heavy table of label/value pairs is a spreadsheet, and a till is not a
// spreadsheet: the eye has to find the ONE fact it came for. Grouped into
// raised cards, each row led by a circular tonal badge, the facts scan as a
// short column of markers — and the badge carries the row's subject, so a
// glance says "email, photograph, shop" before a word is read.
//
// ## Why the photograph opens in a DIALOG
//
// The avatar is a 96dp circle in the corner of a card, and the photograph
// behind it is up to 512px. The owner who wants to SEE the photograph wants
// the whole of it at once, and wants to be back on the profile a moment later
// — so it opens over the screen in a dialog, not as a route with a back
// button. The app has one navigation system and it is go_router; a dialog is
// the one thing that opens without touching it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import 'package:go_router/go_router.dart';

import '../routing/routes.dart';
import '../db/database_helper.dart';
import '../services/app_state.dart';
import '../services/pin_reset_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/operation_result.dart';
import '../ui/components/product_photo.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/product_image_store.dart';
import '../widgets/profile_edit_sheet.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({this.picker, super.key});

  /// The picker the screen uses to choose a photograph.
  ///
  /// INJECTED so the screen can be pumped in a test: the real picker needs a
  /// camera roll and a platform channel, and a screen whose only path to a
  /// photograph is the platform is a screen nobody can test. Null means "ask
  /// the platform", which is what the app does.
  final ImagePicker? picker;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class ProfileScreenOpen extends ProfileScreen {
  const ProfileScreenOpen({super.key});
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// True while the account is being re-read from the shop's own database.
  bool _loading = false;

  /// True when the account could not be read at all.
  ///
  /// A separate flag from [_loading] because "the read has not answered" and
  /// "the read failed" are different facts, and a screen that collapses them
  /// shows a spinner forever on a database that is already broken.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Only when there is nothing to show. The session already holds the owner
    // by the time anybody can reach this screen, so the read below is the
    // RECOVERY path, not the normal one — and on a healthy session it never
    // runs, so nothing here changes what the screen shows.
    if (context.read<AppState>().owner == null) _load();
  }

  /// Re-reads the account from the shop's own database.
  ///
  /// The typed failure, never `toString()`: an owner reading "Garbage state
  /// detected in SplayTreeMap" learns nothing they can act on.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await context.read<AppState>().loadOwner();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
      ),
      body: Consumer<AppState>(
        builder: (BuildContext context, AppState state, __) {
          if (_failed) {
            return ErrorStateView(
              message: l10n.errorUnknown,
              onRetry: _load,
              retryLabel: l10n.actionRetry,
            );
          }

          final Owner? owner = state.owner;
          if (owner == null) {
            if (_loading) {
              return const SkeletonList(itemCount: 3, linesPerItem: 2);
            }
            // "No account" is not a failure: it is what a device looks like
            // before the shop admin has set it up, and it says what to do next.
            return EmptyStateView(
              title: l10n.profileNoAccountYet,
              message: l10n.chooserSetupHelp,
            );
          }

          return _ProfileBody(
            owner: owner,
            state: state,
            picker: widget.picker,
          );
        },
      ),
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody({
    required this.owner,
    required this.state,
    this.picker,
  });

  final Owner owner;
  final AppState state;

  /// The picker the body uses to choose a photograph. See [ProfileScreen.picker].
  final ImagePicker? picker;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  /// Bumped when a new photograph is saved, so the avatar re-reads the file.
  ///
  /// A counter rather than a `setState` on the parent alone: the avatar holds
  /// its resolved path, and a rebuild that does not change the path would
  /// leave the OLD photograph on screen — a picture of the person as they were
  /// before they picked a new one.
  int _avatarRevision = 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final owner = widget.owner;

    return ListView(
      padding: EdgeInsets.all(spacing.lg),
      children: <Widget>[
        // The identity, and the photograph that goes with it.
        SurfaceCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _AvatarRing(
                size: 96,
                name: owner.name,
                revision: _avatarRevision,
              ),
              SizedBox(width: spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      owner.name,
                      style: AppTypography.of(context).titleLarge,
                    ),
                    SizedBox(height: spacing.xs),
                    // The shop, not a second name: an owner may run several and
                    // this is the one that is signed in.
                    Text(
                      owner.shopName,
                      style: AppTypography.of(context).bodyMedium?.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                    ),
                    SizedBox(height: spacing.sm),
                    // The one action on this screen that CHANGES something.
                    //
                    // A profile that cannot be edited is a photograph of the
                    // past: an owner whose name changed, or whose shop was
                    // renamed, had no way to correct it. The PIN is not here —
                    // it has its own flow, with its own confirmation.
                    OutlinedButton.icon(
                      onPressed: _edit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(l10n.profileEditAction),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),

        // The facts, grouped, each led by its own marker.
        SurfaceCard(
          padding: EdgeInsets.zero,
          clipContent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ProfileRow(
                icon: Icons.photo_camera_outlined,
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
                icon: Icons.alternate_email,
                label: l10n.profileEmailLabel,
                // MASKED, like every other place the address appears.
                value: PinResetService.maskEmail(owner.email),
              ),
              const Divider(height: 1),
              _ProfileRow(
                icon: Icons.verified_outlined,
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
                icon: Icons.event_outlined,
                label: l10n.profileSinceLabel,
                // Stored as a string, because an ISO timestamp is the only
                // thing that survives a locale change. Formatted at render,
                // here, rather than parsed everywhere else.
                value: _formatSince(owner.createdAt, context),
              ),
              const Divider(height: 1),
              _ProfileRow(
                icon: Icons.storefront_outlined,
                label: l10n.profileShopLabel,
                value: owner.shopName,
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.xl),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.settings),
          icon: const Icon(Icons.settings_outlined),
          label: Text(l10n.profileBackToSettings),
        ),
      ],
    );
  }

  /// Asks the owner for their details and saves what they change.
  ///
  /// The sheet is dismissed with the new values, and the save happens HERE —
  /// so a cancelled sheet changes nothing, and a failed save leaves the
  /// profile as it was rather than half-edited.
  Future<void> _edit() async {
    final l10n = AppLocalizations.of(context);
    final owner = widget.owner;

    final edit = await showModalBottomSheet<ProfileEdit>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => ProfileEditSheet(
        name: owner.name,
        shopName: owner.shopName,
        email: owner.email,
      ),
    );
    if (edit == null || !mounted) return;

    final String email = edit.email.trim();
    final bool emailChanged = email.toLowerCase() != owner.email.trim().toLowerCase();

    try {
      await DatabaseHelper.instance.updateOwnerProfile(
        name: edit.name,
        shopName: edit.shopName,
        email: email,
      );
    } on Object {
      if (!mounted) return;
      await showOperationFailure(
        context,
        title: l10n.profileEditFailedTitle,
        message: l10n.profileEditFailed,
      );
      return;
    }
    if (!mounted) return;

    // The owner row has changed, so the session has to re-read it: the shell's
    // bar, the dashboard's welcome and the receipt header all read from it.
    await widget.state.loadOwner();

    // A NEW ADDRESS IS NOT A VERIFIED ADDRESS.
    //
    // The verification flag is about "this address can receive mail", and a
    // typed-in address has not been proven. So changing it clears the flag
    // until the backend verifies the new one. A shop that changed nothing
    // keeps the flag it had.
    if (emailChanged) {
      await widget.state.clearIdentityVerified();
    }
    if (!mounted) return;

    // The save, confirmed, on a screen.
    //
    // A profile edit is not a tap the owner makes fifty times a day, and the
    // one thing they need to know is that the till now knows their name.
    await showOperationSuccess(
      context,
      title: l10n.profileEditSavedTitle,
      message: edit.name,
      detailIcon: Icons.person_outline,
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

    final XFile? picked = await (widget.picker ?? ImagePicker())
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
    setState(() => _avatarRevision++);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.profilePhotoSaved)),
    );
  }
}

/// The avatar, drawn from the file this account's photograph is stored at.
///
/// The future is held HERE and answered once, rather than handed to a
/// `FutureBuilder` on every build: a builder that is given a new future starts
/// over, so the picture would blink in and out on every rebuild of the screen
/// — and a screen that rebuilds whenever the session notifies is a screen that
/// rebuilds often.
class _AvatarRing extends StatefulWidget {
  const _AvatarRing({
    required this.size,
    required this.name,
    required this.revision,
  });

  final double size;

  /// The owner's name, for the initials shown when there is no photograph.
  final String name;

  /// Bumped when the file behind the avatar changes.
  final int revision;

  @override
  State<_AvatarRing> createState() => _AvatarRingState();
}

class _AvatarRingState extends State<_AvatarRing> {
  /// The resolved absolute path, once.
  late Future<String?> _resolved;

  /// What the future resolved to. Null until it does, and null forever for an
  /// account with no photograph.
  String? _path;

  /// Bumped every time the photograph is read.
  ///
  /// It is part of the photograph's key, so the framework asks for it afresh
  /// instead of keeping the frame it drew last time — and the decoded entry
  /// for the path is forgotten, so "afresh" means the file as it is NOW.
  int _version = 0;

  /// The decode width the last build used.
  ///
  /// The codec's cache is keyed by the path AND the decode width, so the
  /// entry to forget is the one that was written. Null until the first build
  /// — before it, nothing has been decoded and nothing can be stale.
  int? _cacheWidth;

  @override
  void initState() {
    super.initState();
    _resolved = _resolve();
    _resolved.then(_onResolved);
  }

  @override
  void didUpdateWidget(covariant _AvatarRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new photograph is a new answer. The SIZE is not: the path does not
    // depend on it.
    if (oldWidget.revision != widget.revision) {
      _resolved = _resolve();
      _resolved.then(_onResolved);
    }
  }

  /// The future's answer, applied once.
  ///
  /// `mounted` first: an avatar scrolled out of the tree mid-resolve must not
  /// set state on a widget the framework has already thrown away.
  void _onResolved(String? path) {
    if (!mounted) return;
    setState(() {
      _path = path;
      _version++;
    });
  }

  Future<String?> _resolve() async {
    final String? path =
        await ProductImageStore.resolve(ProductImageStore.avatarRelativePath);
    final int? width = _cacheWidth;
    if (path != null && width != null) {
      // The photograph is written OVER the file at the same path, so the entry
      // the codec is holding is the PREVIOUS photograph. Forget it before the
      // photograph is asked for again, or the owner picks a new picture and
      // the avatar goes on showing the old one.
      await forgetDecodedPhoto(path, cacheWidth: width);
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final String? path = _path;
    final Widget picture = path == null
        ? _Initials(name: widget.name, size: widget.size)
        : _photograph(context, path);

    // Tappable ONLY when there is a photograph behind it. With initials there
    // is nothing to open, and a button that opens nothing is worse than no
    // button at all.
    if (path == null) return _ring(context, picture);

    return Semantics(
      button: true,
      label: AppLocalizations.of(context).profilePhotoLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _openFullSize(context, path),
        // Circular, because the thing it is on is circular: a rectangular
        // splash on a round avatar is a splash on the wrong shape.
        customBorder: const CircleBorder(),
        child: _ring(context, picture),
      ),
    );
  }

  /// Opens the photograph, whole, over the screen.
  void _openFullSize(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _FullSizePhotoDialog(path: path, name: widget.name),
    );
  }

  /// The circle itself.
  Widget _ring(BuildContext context, Widget picture) {
    final AppColors colors = AppColors.of(context);
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceSunken,
        border: Border.all(color: colors.outline, width: 2),
      ),
      alignment: Alignment.center,
      child: picture,
    );
  }

  /// The photograph itself.
  Widget _photograph(BuildContext context, String path) {
    final int cacheWidth = (widget.size * 2).round();
    _cacheWidth = cacheWidth;

    // The photo is decorative beside the name below it, so it is excluded from
    // semantics rather than announced twice.
    return ExcludeSemantics(
      child: ClipOval(
        child: PhotoImage(
          path: path,
          size: widget.size,
          version: _version,
          // Sized at 2x the drawn edge so the codec decodes only what the
          // screen shows.
          cacheWidth: cacheWidth,
          // A photograph that has moved or been deleted reads the same as never
          // having had one, rather than as a broken image.
          errorBuilder: (_, __, ___) =>
              _Initials(name: widget.name, size: widget.size),
        ),
      ),
    );
  }
}

/// The account's photograph, whole, over the screen.
///
/// The photograph is up to 512px and the avatar is a 96dp circle: an owner
/// who wants to see the photograph wants all of it at once, and wants to be
/// back on the profile a moment later.
class _FullSizePhotoDialog extends StatelessWidget {
  const _FullSizePhotoDialog({required this.path, required this.name});

  /// The absolute path of the photograph.
  final String path;

  /// The owner's name, for the initials shown if the file has gone.
  final String name;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Size screen = MediaQuery.sizeOf(context);

    return AlertDialog(
      title: Text(l10n.profilePhotoLabel),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screen.width * 0.8,
          maxHeight: screen.height * 0.6,
        ),
        child: ClipRRect(
          borderRadius: AppShapes.of(context).controlRadius,
          child: PhotoImage(
            path: path,
            size: screen.width * 0.8,
            fit: BoxFit.contain,
            // The whole photograph, not a crop of it: this is the one place
            // in the app where the picture is the subject.
            errorBuilder: (_, __, ___) => _Initials(name: name, size: 96),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionDone),
        ),
      ],
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
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
      style: AppTypography.of(context).headlineMedium?.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// One fact about the account: a marker, the label, and the value.
///
/// The value sits UNDER the label rather than beside it, so a long value — an
/// address, a shop name, a help line — WRAPS instead of being cut off. A
/// truncated value is a value the owner cannot read, and the whole point of
/// this screen is that they can.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return ConstrainedBox(
      // The floor is on the row, not on the label: the target stays legal when
      // the value wraps to three lines at 200% text.
      constraints: BoxConstraints(minHeight: spacing.minTapTarget),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: spacing.lg,
          end: spacing.lg,
          top: spacing.md,
          bottom: spacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IconBadge(icon: icon),
            SizedBox(width: spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: type.labelMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(value, style: type.bodyLarge),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              SizedBox(width: spacing.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
