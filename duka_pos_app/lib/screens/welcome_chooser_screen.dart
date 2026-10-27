import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routing/app_stage_controller.dart';
import '../routing/routes.dart';
import '../services/app_stage.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/nerva_wordmark.dart';
import '../ui/brand/simple_pos_mark.dart';
import '../ui/onboarding_style.dart';
import 'product_onboarding_screen.dart';

/// The first screen a person sees when there is no signed-in session.
///
/// Two choices, always, for everyone: **sign in** or **set up**. This replaces a
/// flow that branched silently on whether a shop happened to exist, so a
/// cashier handed a brand-new till landed on a form addressed to whoever
/// installs the app, with no sign-in anywhere in the sightline. Nothing about
/// who is holding the phone should decide whether they are offered a way to
/// sign in.
///
/// The shop name is shown so somebody signing in knows *which* shop this device
/// is pointed at before they type a PIN. A shop name is not sensitive: it is
/// printed on every receipt this till issues, and without it a person holding a
/// till set up for someone else has no way to tell they are in the wrong place.
///
/// Where a choice LEADS is the router's decision, not this screen's. Pressing a
/// button records the intent with [AppStageController] and asks the router to
/// resolve it; there is no `Navigator` call on this screen at all, and that is
/// deliberate. A chooser that pushed its own screens is how a signed-out till
/// ends up with two stacks and two sets of answers to "where am I".
class WelcomeChooserScreen extends StatefulWidget {
  const WelcomeChooserScreen({
    super.key,
    required this.shopName,
    required this.hasShop,
    this.intent,
    this.showProductIntro = false,
  });

  /// The active shop's name, or empty when there is no shop yet.
  final String shopName;

  final bool hasShop;

  /// Overrides where the setup action sends the chooser.
  ///
  /// Null, which is how the router builds this screen, means "derive it": on a
  /// device that already runs a shop, setting up again IS adding a second one,
  /// and the setup screen changes its heading and reuses the existing PIN
  /// because of that flag alone.
  final AppChooserIntent? intent;

  /// The router enables this for the first signed-out visit. Tests and callers
  /// that need the chooser directly can keep the established chooser surface.
  final bool showProductIntro;

  @override
  State<WelcomeChooserScreen> createState() => _WelcomeChooserScreenState();
}

class _WelcomeChooserScreenState extends State<WelcomeChooserScreen> {
  bool _introVisible = false;
  bool _introLoading = false;

  @override
  void initState() {
    super.initState();
    _introVisible = widget.showProductIntro;
    if (widget.showProductIntro) _readIntroPreference();
  }

  Future<void> _readIntroPreference() async {
    setState(() => _introLoading = true);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _introLoading = false;
      _introVisible = !(prefs.getBool('product_onboarding_seen') ?? false);
    });
  }

  Future<void> _finishIntro(VoidCallback next) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('product_onboarding_seen', true);
    if (!mounted) return;
    setState(() => _introVisible = false);
    next();
  }

  /// The intent the setup action sends.
  AppChooserIntent get _setupIntent =>
      widget.intent ??
      (widget.hasShop ? AppChooserIntent.addShop : AppChooserIntent.setUp);

  void _choose(BuildContext context, AppChooserIntent choice) {
    HapticTheme.of(context).fire(HapticEvent.select);
    context.read<AppStageController>().choose(choice);
    context.go(choice == AppChooserIntent.signIn ? Routes.login : Routes.setup);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    if (_introLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_introVisible) {
      return ProductOnboardingScreen(
        onCreateAccount: () =>
            _finishIntro(() => _choose(context, _setupIntent)),
        onSignIn: () =>
            _finishIntro(() => _choose(context, AppChooserIntent.signIn)),
      );
    }

    final bool addingAnother = _setupIntent == AppChooserIntent.addShop;
    final bool showShop = widget.hasShop && widget.shopName.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(spacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kChooserWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Header: mark left, sign-in link right.
                  OnboardStyle.header(
                    context: context,
                    onSignIn: () => _choose(context, AppChooserIntent.signIn),
                    colors: colors,
                    spacing: spacing,
                    type: type,
                  ),
                  SizedBox(height: spacing.lg),

                const Center(child: SimplePosMark(size: 64)),
                  SizedBox(height: spacing.md),
                  const Center(child: SimplePosWordmark()),
                  SizedBox(height: spacing.lg),

                  // Either the shop this device is pointed at, or the one thing
                  // a person has to do next. Both are states a screen reader
                  // should announce on arrival: the first is what proves this
                  // is the right till, the second is the screen's own job.
                  Semantics(
                    liveRegion: true,
                    header: true,
                    child: Text(
                      showShop
                          ? l10n.chooserSignedInShop(widget.shopName)
                          : l10n.chooserHeading,
                      textAlign: TextAlign.center,
                      style: showShop ? type.bodyMedium : type.titleMedium,
                    ),
                  ),

                  if (addingAnother) ...<Widget>[
                    SizedBox(height: spacing.sm),
                    Text(
                      l10n.chooserHasShopWarning,
                      textAlign: TextAlign.center,
                      style: type.bodySmall?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],

                  SizedBox(height: spacing.xxl),

                  // Sign-in paths grouped as the primary choice, ordered by how
                  // often they are used: owner every day, staff at shift start.
                  OnboardStyle.primaryButton(
                    context: context,
                    onPressed: () => _choose(context, AppChooserIntent.signIn),
                    label: l10n.chooserSignInAction,
                    colors: colors,
                    spacing: spacing,
                  ),
                  SizedBox(height: spacing.md),
                  OnboardStyle.primaryButton(
                    context: context,
                    onPressed: () => context.go(Routes.staffLogin),
                    label: l10n.chooserSignInAsStaffAction,
                    colors: colors,
                    spacing: spacing,
                  ),

                  SizedBox(height: spacing.xl),
                  Divider(color: colors.outline),
                  SizedBox(height: spacing.md),

                  // Setup is the LAST choice, deliberately the quietest thing on
                  // the screen: someone who has never set a shop up will read the
                  // two buttons above and reach this, and someone who has done it
                  // once will scroll past it for years.
                  OnboardStyle.primaryButton(
                    context: context,
                    onPressed: () => _choose(context, _setupIntent),
                    label: addingAnother
                        ? l10n.chooserSetupAnother
                        : l10n.chooserSetupFirst,
                    colors: colors,
                    spacing: spacing,
                  ),

                  Text(
                    widget.hasShop
                        ? l10n.chooserSignInHelp
                        : l10n.chooserSetupHelp,
                    textAlign: TextAlign.center,
                    style:
                        type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                  ),
                  SizedBox(height: spacing.lg),
                  Center(
                    child: PoweredByNerva(
                      style: type.labelSmall?.copyWith(
                        color: colors.onSurfaceMuted,
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

/// The measure of the chooser column.
///
/// Not a token: this is not prose but two buttons and a lockup, and past this
/// width a two-choice screen stops reading as a decision and starts reading as
/// a form. The brief's readable cap exists for paragraphs; this is not one.
const double _kChooserWidth = 460;
