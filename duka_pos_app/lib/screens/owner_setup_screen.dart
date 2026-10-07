import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';

/// Creates the shop and its admin account, or adds a second shop to a device
/// that already runs one.
///
/// Self-contained by construction: no app bar and no navigation affordance of
/// its own. The only way out is [onCancel], and it is offered only when there is
/// somewhere to cancel to, which is why the router passes null for a device's
/// first shop.
class OwnerSetupScreen extends StatefulWidget {
  /// Shown as a back affordance when this screen was entered from another one.
  /// Null when it is the app's only entry point and there is nowhere to go back
  /// to.
  final VoidCallback? onCancel;

  /// True when this device already runs a shop and this is a *second* one.
  ///
  /// Changes the copy and, more importantly, the defaults: the new shop's admin
  /// is pre-filled from the existing owner and keeps the same PIN, because it
  /// is the same person. Asking a shop owner to invent a new PIN and a new email
  /// for the branch they work in every day is what made "add another shop" feel
  /// like registering from scratch.
  final bool isAdditionalShop;

  /// The owner to carry across. Null when this is the first shop.
  final Owner? carryOverFrom;

  /// Called after a successful create, with the new shop's name.
  final ValueChanged<String>? onCreated;

  const OwnerSetupScreen({
    super.key,
    this.onCancel,
    this.isAdditionalShop = false,
    this.carryOverFrom,
    this.onCreated,
  });

  @override
  State<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends State<OwnerSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _shop = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _pin2 = TextEditingController();

  /// Submit-level failures only. A field that is simply wrong is reported by the
  /// field, next to the field, where a person can see which one it was.
  String? _error;

  /// True while the create is in flight. Two owners written for one shop is a
  /// support call, so the button stops accepting taps rather than relying on
  /// the person not pressing it twice.
  bool _saving = false;

  /// True when the PIN fields are hidden because the existing admin's hash is
  /// being reused.
  ///
  /// The plaintext is never needed and never held: the new owner's row is given
  /// the *existing hash*, so the same four digits the owner already uses keep
  /// working on the new shop. Asking them to retype it would make adding a
  /// branch feel like registering from scratch, which is the thing they were
  /// avoiding.
  bool get _reusingPin =>
      widget.isAdditionalShop && widget.carryOverFrom != null;

  @override
  void initState() {
    super.initState();
    final Owner? previous = widget.carryOverFrom;
    if (!widget.isAdditionalShop || previous == null) return;
    // Pre-filled and editable: two admins at the same business may share a
    // device legitimately, and forcing the name they type to match the old
    // owner would be a strange constraint.
    _name.text = previous.name;
    _email.text = previous.email;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _shop.dispose();
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- validation
  //
  // Every rule and every message below is the one this screen already enforced
  // at submit time. They are duplicated onto the fields rather than moved, so a
  // person is told what is wrong WHILE they type, and the submit-time guard is
  // still there for fields an autofill filled in without ever being focused.

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _pinPattern = RegExp(r'^\d{4}$');

  String? _required(String? value, String label) =>
      (value == null || value.trim().isEmpty)
          ? AppLocalizations.of(context).ownerLabelRequired(label)
          : null;

  String? _validateShop(String? value) =>
      _required(value, AppLocalizations.of(context).settingsShopNameLabel);

  String? _validateName(String? value) => _required(value, 'Your name');

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Owner email is required';
    return _emailPattern.hasMatch(value.trim().toLowerCase())
        ? null
        : 'Enter a valid email address';
  }

  String? _validatePin(String? value) {
    if (value == null || value.isEmpty) return 'PIN is required';
    return _pinPattern.hasMatch(value) ? null : 'PIN must be exactly 4 digits';
  }

  String? _validatePinConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Enter the PIN again';
    return value == _pin.text ? null : 'PINs do not match';
  }

  Future<void> _create() async {
    if (_saving) return;

    final String email = _email.text.trim().toLowerCase();
    // The original submit gate, unchanged and in the original order: one
    // message for the three required fields, because that is what this screen
    // has always said.
    if (_name.text.trim().isEmpty ||
        _shop.text.trim().isEmpty ||
        email.isEmpty) {
      setState(() => _error = 'Enter your name, email, and shop name');
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }
    // The PIN is only asked for when there is nothing to inherit. Re-asking for
    // it on a second shop is what made this flow feel like signing up again.
    if (!_reusingPin) {
      if (!_pinPattern.hasMatch(_pin.text)) {
        setState(() => _error = 'PIN must be exactly 4 digits');
        HapticTheme.of(context).fire(HapticEvent.reject);
        return;
      }
      if (_pin.text != _pin2.text) {
        setState(() => _error = 'PINs do not match');
        HapticTheme.of(context).fire(HapticEvent.reject);
        return;
      }
    }
    // Then the same rules again, per field, for anything the gate above let
    // through but the field has not seen.
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final Owner owner = Owner(
        id: 1,
        name: _name.text.trim(),
        pinHash: _reusingPin
            ? widget.carryOverFrom!.pinHash
            : await AuthService.hashPin(_pin.text),
        email: email,
        shopName: _shop.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );
      await DatabaseHelper.instance.createOwner(owner);
      await WorkspaceService.register(
        workspaceKey: await WorkspaceService.activeWorkspaceKey(),
        shopName: owner.shopName,
      );
      unawaited(BackendService.linkShopToBackend(
        shopName: owner.shopName,
        ownerName: owner.name,
        email: owner.email,
      ).catchError((_) {}));
      if (!mounted) return;
      // Land the person straight into the new shop. Choosing from a shop list
      // used to happen here, and it dumped them on a landing page asking to
      // create an admin they had already created.
      await context.read<AppState>().loadOwner();
      if (!mounted) return;
      await context.read<AppState>().signInAsOwner();
      widget.onCreated?.call(owner.shopName);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. Check the phone has storage space free, '
            'then try again.';
      });
      HapticTheme.of(context).fire(HapticEvent.reject);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(spacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kFormWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (widget.onCancel != null)
                    _BackRow(onBack: widget.onCancel!),
                  const _SetupLockup(),
                  SizedBox(height: spacing.lg),
                  _SetupHeading(
                    isAdditionalShop: widget.isAdditionalShop,
                    reusingPin: _reusingPin,
                  ),
                  SizedBox(height: spacing.md),
                  if (_reusingPin) ...<Widget>[
                    const _CarriedPinNote(),
                    SizedBox(height: spacing.md),
                  ],
                  _SetupFields(
                    formKey: _formKey,
                    shop: _shop,
                    name: _name,
                    email: _email,
                    pin: _pin,
                    pin2: _pin2,
                    reusingPin: _reusingPin,
                    validateShop: _validateShop,
                    validateName: _validateName,
                    validateEmail: _validateEmail,
                    validatePin: _validatePin,
                    validatePinConfirm: _validatePinConfirm,
                    onSubmit: _create,
                  ),
                  if (_error != null) ...<Widget>[
                    SizedBox(height: spacing.md),
                    PersistentBanner(
                      message: _error!,
                      icon: Icons.error_outline,
                      tone: StatusTone.danger,
                    ),
                  ],
                  SizedBox(height: spacing.xl),
                  FilledButton(
                    onPressed: _saving ? null : _create,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: spacing.md),
                      child: Text(
                        _saving
                            ? 'Creating the shop'
                            : 'Create shop admin account',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark and the logotype, above the form.
///
/// The wordmark is the product's own name, so the mark beside it is decorative:
/// two nodes announcing "Simple POS" is a screen reader stuttering.
class _SetupLockup extends StatelessWidget {
  const _SetupLockup();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    // A `Wrap`, not a `Row`.
    //
    // The mark is a fixed 36px and the wordmark scales with the user's text
    // setting, so at 200% on a 320dp phone the pair is ~334px wide against288
    // available — a 1.4px overflow, which the overflow matrix catches and a
    // design review never would.
    //
    // `Wrap` is the fix rather than a smaller wordmark or a `FittedBox`: the
    // logotype drops onto its own line at accessibility text sizes instead of the
    // layout giving up something. Clamping the scale or shrinking the type would
    // defeat the very setting that caused the problem.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: spacing.md,
      children: const <Widget>[
        Image(
          image: AssetImage(
            'assets/branding/stitch_simple_pos_launcher_icon/simple_pos_geometric_s_icon/screen.png',
          ),
          width: 36,
          height: 36,
          fit: BoxFit.contain,
        ),
        SimplePosWordmark(),
      ],
    );
  }
}

/// The heading and what this screen is for.
class _SetupHeading extends StatelessWidget {
  const _SetupHeading({
    required this.isAdditionalShop,
    required this.reusingPin,
  });

  final bool isAdditionalShop;

  /// Branches on the PIN being carried rather than on the intent alone: an
  /// "additional shop" with nothing to carry is still a first-time setup.
  final bool reusingPin;

  @override
  Widget build(BuildContext context) {
    final TextTheme type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            isAdditionalShop
                ? AppLocalizations.of(context).settingsAddShopTitle
                : 'Set up your shop',
            style: type.headlineSmall,
          ),
        ),
        SizedBox(height: AppSpacing.of(context).sm),
        Text(
          reusingPin
              ? 'This shop reuses the admin account and PIN you already use. '
                  'Give the new shop its own name and you will go straight into '
                  'it.'
              : 'Create the shop admin account. The admin can create managers '
                  'and cashiers, manage stock, and connect optional services.',
          style: type.bodyMedium,
        ),
      ],
    );
  }
}

/// The one thing a person cannot see on this screen, said out loud.
class _CarriedPinNote extends StatelessWidget {
  const _CarriedPinNote();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.accentContainer,
        borderRadius: AppShapes.of(context).controlRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.lock_outline,
            size: 18,
            color: colors.onAccentContainer,
            // Decorative: the sentence beside it carries the meaning.
            semanticLabel: '',
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              'The PIN already set on this device stays the same on this shop. '
              'You will not be asked for it again.',
              style: type.bodySmall?.copyWith(color: colors.onAccentContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// The way out, when there is one.
class _BackRow extends StatelessWidget {
  const _BackRow({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onBack,
        // Adaptive: the same control points the way the reader does, and a
        // hard-coded arrow is a screen that is wrong in half the world's
        // languages. Not const: the adaptive set resolves per platform at
        // build time.
        icon: ExcludeSemantics(child: Icon(Icons.arrow_back)),
        label: const Text('Back'),
      ),
    );
  }
}

/// The five fields, in the order a person fills them.
///
/// One widget so the screen's own build stays a list of what it is rather than
/// a transcription of five sets of decoration.
class _SetupFields extends StatelessWidget {
  const _SetupFields({
    required this.formKey,
    required this.shop,
    required this.name,
    required this.email,
    required this.pin,
    required this.pin2,
    required this.reusingPin,
    required this.validateShop,
    required this.validateName,
    required this.validateEmail,
    required this.validatePin,
    required this.validatePinConfirm,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController shop;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController pin;
  final TextEditingController pin2;
  final bool reusingPin;
  final String? Function(String?) validateShop;
  final String? Function(String?) validateName;
  final String? Function(String?) validateEmail;
  final String? Function(String?) validatePin;
  final String? Function(String?) validatePinConfirm;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Form(
      key: formKey,
      // Validated as a person leaves a field, not on submit and not while they
      // are still typing the first character of their email address.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SetupField(
            controller: shop,
            label: AppLocalizations.of(context).settingsShopNameLabel,
            autofillHints: const <String>[AutofillHints.organizationName],
            validator: validateShop,
          ),
          SizedBox(height: spacing.md),
          _SetupField(
            controller: name,
            label: 'Your name (shop admin)',
            autofillHints: const <String>[AutofillHints.name],
            validator: validateName,
          ),
          SizedBox(height: spacing.md),
          _SetupField(
            controller: email,
            label: 'Owner email',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const <String>[AutofillHints.email],
            validator: validateEmail,
          ),
          if (!reusingPin) ...<Widget>[
            SizedBox(height: spacing.md),
            _SetupField(
              controller: pin,
              label: 'Set a 4-digit PIN',
              keyboardType: TextInputType.number,
              obscure: true,
              maxLength: 4,
              autofillHints: const <String>[AutofillHints.newPassword],
              validator: validatePin,
            ),
            SizedBox(height: spacing.md),
            _SetupField(
              controller: pin2,
              label: 'Confirm PIN',
              keyboardType: TextInputType.number,
              obscure: true,
              maxLength: 4,
              isLast: true,
              onSubmitted: onSubmit,
              autofillHints: const <String>[AutofillHints.newPassword],
              validator: validatePinConfirm,
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled field.
///
/// Focus traversal is by `TextInputAction`: `next` moves to the next field and
/// the last field submits. That is the platform's own traversal, and threading
/// five `FocusNode`s through this screen to reproduce it by hand would be one
/// more thing to dispose.
class _SetupField extends StatelessWidget {
  const _SetupField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscure = false,
    this.maxLength,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
    this.isLast = false,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscure;
  final int? maxLength;
  final List<String>? autofillHints;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;

  /// The last field in the form: Enter finishes it rather than moving on.
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscure,
      maxLength: maxLength,
      autofillHints: autofillHints,
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: isLast ? (_) => onSubmitted?.call() : null,
      decoration: InputDecoration(labelText: label),
    );
  }
}

/// The measure of the form.
///
/// A form, not prose: five fields and a button, which stay legible and reachable
/// far wider than this but start to look like a settings table past it.
const double _kFormWidth = 460;
