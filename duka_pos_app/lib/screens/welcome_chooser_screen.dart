import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../routing/app_stage_controller.dart';
import '../routing/routes.dart';
import '../services/app_stage.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../ui/brand/nerva_wordmark.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';

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
class WelcomeChooserScreen extends StatelessWidget {
  const WelcomeChooserScreen({
    super.key,
    required this.shopName,
    required this.hasShop,
    this.intent,
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

  /// The intent the setup action sends.
  AppChooserIntent get _setupIntent =>
      intent ?? (hasShop ? AppChooserIntent.addShop : AppChooserIntent.setUp);

  void _choose(BuildContext context, AppChooserIntent choice) {
    HapticTheme.of(context).fire(HapticEvent.select);
    // Both halves are needed. `choose` records WHY, which the setup screen
    // reads to change its own copy. `go` asks the router where that lands.
    // Recording alone would be a no-op whenever the intent was already current
    // (and "sign in" is the intent a chooser starts on), so the one choice a
    // returning user makes every single day would do nothing at all.
    context.read<AppStageController>().choose(choice);
    context.go(choice == AppChooserIntent.signIn ? Routes.login : Routes.setup);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final bool addingAnother = _setupIntent == AppChooserIntent.addShop;
    final bool showShop = hasShop && shopName.trim().isNotEmpty;

    return Scaffold(
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
                  // The VECTOR mark, not the PNG. Three other screens still
                  // load `screen.png` for the same lockup, and a raster image
                  // of a mark that is drawn as paths in the app is the one
                  // place the brand can land fuzzy: this is on the very first
                  // screen a shop owner sees, at whatever density the device
                  // ships with. It is also the same mark the launcher icon is
                  // built from, so the icon and the app finally agree.
                  const Center(
                    child: SimplePosMark(size: 72),
                  ),
                  SizedBox(height: spacing.lg),
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
                          ? AppLocalizations.of(context)
                              .chooserSignedInShop(shopName)
                          : AppLocalizations.of(context).chooserHeading,
                      textAlign: TextAlign.center,
                      style: showShop ? type.bodyMedium : type.titleMedium,
                    ),
                  ),

                  if (addingAnother) ...<Widget>[
                    SizedBox(height: spacing.sm),
                    Text(
                      AppLocalizations.of(context).chooserHasShopWarning,
                      textAlign: TextAlign.center,
                      style: type.bodySmall?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],

                  SizedBox(height: spacing.xxl),

                  // HIERARCHY, which this screen did not have.
                  //
                  // It used to be three buttons of equal weight: two
                  // `OutlinedButton`s and one `FilledButton`, all the same size,
                  // all with the same icon-first treatment. A shop owner's daily
                  // choice — sign in — competed for attention with the one thing
                  // they do once in the app's life.
                  //
                  // Now the two sign-in paths sit together as the primary
                  // group, each sized for a thumb, and setting up a shop is
                  // demoted to a quiet text button at the bottom, where it is
                  // still reachable in one tap but stops reading as the main
                  // event. The pair is ordered by how often it is used: owner
                  // every day, staff on a shift start.
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: () => _choose(context, AppChooserIntent.signIn),
                    icon:
                        const ExcludeSemantics(child: Icon(Icons.pin_outlined)),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: spacing.lg),
                      child: Text(
                          AppLocalizations.of(context).chooserSignInAction),
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  FilledButton.tonalIcon(
                    onPressed: () => context.go(Routes.staffLogin),
                    icon: const ExcludeSemantics(
                        child: Icon(Icons.person_outline)),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: spacing.lg),
                      child: Text(
                        AppLocalizations.of(context).chooserSignInAsStaffAction,
                      ),
                    ),
                  ),

                  SizedBox(height: spacing.xl),
                  Divider(color: colors.outline),
                  SizedBox(height: spacing.md),

                  // Setup is the LAST choice, and it is deliberately the quietest
                  // thing on the screen: someone who has never set a shop up
                  // will read the two buttons above and reach this, and someone
                  // who has done it once will scroll past it for years.
                  TextButton.icon(
                    onPressed: () => _choose(context, _setupIntent),
                    icon: ExcludeSemantics(
                      child: Icon(
                        addingAnother
                            ? Icons.add_business_outlined
                            : Icons.storefront_outlined,
                      ),
                    ),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: spacing.lg),
                      child: Text(
                        addingAnother
                            ? AppLocalizations.of(context).chooserSetupAnother
                            : AppLocalizations.of(context).chooserSetupFirst,
                      ),
                    ),
                  ),

                  Text(
                    hasShop
                        ? AppLocalizations.of(context).chooserSignInHelp
                        : AppLocalizations.of(context).chooserSetupHelp,
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
