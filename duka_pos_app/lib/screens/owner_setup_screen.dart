import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../profile/shop_profile.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/workspace_service.dart';
import '../routing/app_stage_controller.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/onboarding_style.dart';
import '../utils/pin_rules.dart';

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
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  ShopProfile _shopProfile = ShopProfile.duka;

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

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// The owner's PIN is an ADMIN PIN, and an admin PIN is six digits.
  static final RegExp _pinPattern = PinRules.adminPattern;

  String? _required(String? value, String label) =>
      (value == null || value.trim().isEmpty)
          ? AppLocalizations.of(context).ownerLabelRequired(label)
          : null;

  String? _validateShop(String? value) =>
      _required(value, AppLocalizations.of(context).settingsShopNameLabel);

  String? _validateName(String? value) =>
      _required(value, AppLocalizations.of(context).ownerSetupNameLabel);

  String? _validateEmail(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) {
      return l10n.ownerSetupEmailLabel;
    }
    return _emailPattern.hasMatch(value.trim().toLowerCase())
        ? null
        : l10n.ownerSetupInvalidEmail;
  }

  String? _validatePin(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) return l10n.validationPinRequired;
    return _pinPattern.hasMatch(value) ? null : l10n.validationPinNotSixDigits;
  }

  String? _validatePinConfirm(String? value) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) {
      return l10n.validationPinConfirmRequired;
    }
    return value == _pin.text ? null : l10n.validationPinMismatch;
  }

  Future<void> _openAssetPdf(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final file = File('${(await getTemporaryDirectory()).path}/${asset.split('/').last}');
      await file.writeAsBytes(data.buffer.asUint8List());
      await launchUrl(Uri.file(file.path));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open document')),
        );
      }
    }
  }

  Future<void> _create() async {
    if (_saving) return;
    if (!_acceptedTerms || !_acceptedPrivacy) {
      setState(() => _error = 'Accept the Terms of Service and Privacy Policy.');
      return;
    }

    final String email = _email.text.trim().toLowerCase();
    if (_name.text.trim().isEmpty ||
        _shop.text.trim().isEmpty ||
        email.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).ownerSetupMissingDetails,
      );
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      setState(
        () => _error = AppLocalizations.of(context).ownerSetupInvalidEmail,
      );
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }
    if (!_pinPattern.hasMatch(_pin.text)) {
      setState(() =>
          _error = AppLocalizations.of(context).validationPinNotSixDigits);
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }
    if (_pin.text != _pin2.text) {
      setState(
          () => _error = AppLocalizations.of(context).validationPinMismatch);
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }
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
        pinHash: await AuthService.hashPin(_pin.text),
        email: email,
        shopName: _shop.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );
      await DatabaseHelper.instance.createOwner(owner);
      await DatabaseHelper.instance.setShopProfile(_shopProfile);
      await WorkspaceService.register(
        workspaceKey: await WorkspaceService.activeWorkspaceKey(),
        shopName: owner.shopName,
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'onboarding_completed_${await WorkspaceService.activeWorkspaceKey()}',
        true,
      );
      unawaited(BackendService.linkShopToBackend(
        shopName: owner.shopName,
        ownerName: owner.name,
        email: owner.email,
        businessProfile: _shopProfile,
      ).catchError((_) {}));
      if (!mounted) return;
      await context.read<AppState>().loadOwner();
      if (!mounted) return;
      await context.read<AppStageController>().completeOnboarding();
      if (!mounted) return;
      context.read<AppState>().signInAsOwner();
      if (!mounted) return;
      setState(() => _saving = false);
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
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        widget.onCancel?.call();
      },
      child: Scaffold(
        backgroundColor: colors.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kFormWidth),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(spacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                    // Header
                    Row(
                      children: <Widget>[
                        if (widget.onCancel != null)
                          IconButton(
                            onPressed: widget.onCancel,
                            icon: const Icon(Icons.arrow_back),
                          ),
                        const SimplePosMark(size: 36),
                      ],
                    ),
                    SizedBox(height: spacing.sm),
                    // Media window style header
                    OnboardStyle.window(
                      context: context,
                      image: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Color(0xFF0B0F14),
                              Color(0xFF11161D),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(Icons.storefront_outlined, size: 56, color: Color(0xFF4ADE7E)),
                        ),
                      ),
                      badgeIcon: Icons.storefront_outlined,
                      label: widget.isAdditionalShop ? 'ADD SHOP' : 'SET UP',
                      title: widget.isAdditionalShop
                          ? 'Add another shop'
                          : 'Set up your shop',
                      body: widget.isAdditionalShop
                          ? 'This shop gets its own admin PIN, so a PIN that opens one shop on this phone does not open another. Give the new shop its name and you will go straight into it.'
                          : 'Create the shop admin account. The admin can create managers and cashiers, manage stock, and connect optional services.',
                      type: type,
                      colors: colors,
                      spacing: spacing,
                    ),
                    SizedBox(height: spacing.sm),
                    // Profile picker
                    _ProfilePicker(
                      value: _shopProfile,
                      onChanged: (value) {
                        if (value != null) setState(() => _shopProfile = value);
                      },
                    ),
                    SizedBox(height: spacing.sm),
                    // Form
                    _SetupFields(
                      formKey: _formKey,
                      shop: _shop,
                      name: _name,
                      email: _email,
                      pin: _pin,
                      pin2: _pin2,
                      validateShop: _validateShop,
                      validateName: _validateName,
                      validateEmail: _validateEmail,
                      validatePin: _validatePin,
                      validatePinConfirm: _validatePinConfirm,
                      onSubmit: _create,
                    ),
                    SizedBox(height: spacing.md),
                    Row(
                      children: [
                        Checkbox(
                          value: _acceptedTerms,
                          onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _openAssetPdf(
                                'assets/SimpleSales_Terms_of_Service.pdf'),
                            child: Text('I agree to the Terms of Service',
                                style: TextStyle(
                                    decoration: TextDecoration.underline,
                                    color: Theme.of(context).colorScheme.primary)),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _acceptedPrivacy,
                          onChanged: (v) => setState(() => _acceptedPrivacy = v ?? false),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _openAssetPdf(
                                'assets/SimpleSales_Privacy_Policy.pdf'),
                            child: Text('I agree to the Privacy Policy',
                                style: TextStyle(
                                    decoration: TextDecoration.underline,
                                    color: Theme.of(context).colorScheme.primary)),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...<Widget>[
                      SizedBox(height: spacing.md),
                      PersistentBanner(
                        message: _error!,
                        icon: Icons.error_outline,
                        tone: StatusTone.danger,
                      ),
                    ],
                  ],
                ),
              ),
            ),
                  Padding(
                    padding: EdgeInsets.all(spacing.xl),
                    child: OnboardStyle.primaryButton(
                      context: context,
                      onPressed: _saving ? null : _create,
                      label: _saving ? 'Creating the shop' : 'Create shop admin account',
                      colors: colors,
                      spacing: spacing,
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

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({required this.value, required this.onChanged});

  final ShopProfile value;
  final ValueChanged<ShopProfile?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<ShopProfile>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: l10n.shopProfileLabel,
        helperText: l10n.shopProfileHelp,
      ),
      items: ShopProfile.values
          .map((profile) => DropdownMenuItem<ShopProfile>(
                value: profile,
                child: Text(profile.displayName),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _SetupFields extends StatelessWidget {
  const _SetupFields({
    required this.formKey,
    required this.shop,
    required this.name,
    required this.email,
    required this.pin,
    required this.pin2,
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
            label: AppLocalizations.of(context).ownerSetupNameLabel,
            autofillHints: const <String>[AutofillHints.name],
            validator: validateName,
          ),
          SizedBox(height: spacing.md),
          _SetupField(
            controller: email,
            label: AppLocalizations.of(context).ownerSetupEmailLabel,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const <String>[AutofillHints.email],
            validator: validateEmail,
          ),
          SizedBox(height: spacing.md),
          _SetupField(
            controller: pin,
            label: AppLocalizations.of(context).ownerSetupPinLabel,
            keyboardType: TextInputType.number,
            obscure: true,
            maxLength: PinRules.adminLength,
            autofillHints: const <String>[AutofillHints.newPassword],
            validator: validatePin,
          ),
          SizedBox(height: spacing.md),
          _SetupField(
            controller: pin2,
            label: AppLocalizations.of(context).ownerSetupPinConfirmLabel,
            keyboardType: TextInputType.number,
            obscure: true,
            maxLength: PinRules.adminLength,
            isLast: true,
            onSubmitted: onSubmit,
            autofillHints: const <String>[AutofillHints.newPassword],
            validator: validatePinConfirm,
          ),
        ],
      ),
    );
  }
}

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

const double _kFormWidth = 460;
