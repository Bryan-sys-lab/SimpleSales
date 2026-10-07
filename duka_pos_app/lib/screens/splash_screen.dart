import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_brand.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';

/// The startup page.
///
/// Shown while the till reads its own state: opening the database, resolving
/// which workspace is active, finding out whether a shop exists. It exists so
/// that first launch is a deliberate moment showing the product's own identity
/// rather than a spinner on a blank background, and so the first frame the
/// merchant sees is branded.
///
/// It deliberately shows no shop name, no data and no controls: at this point
/// the app does not yet know who is signed in, and a splash that renders
/// something is a splash that can leak something.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The one dark surface in the app, and the only place the status bar's
      // icon brightness has to be stated by hand: the theme derives it from
      // `Theme.brightness`, which on the light theme means dark icons drawn on
      // an ink background. Every other screen sits on the canvas and inherits
      // the right answer; this one does not.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: kBrandInk,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(spacing.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: spacing.readableMaxWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // The mark, drawn rather than decoded, so it is correct on
                    // the first frame and cannot flash unstyled while a PNG
                    // loads. Its plate is the brand ink, the same ink as the
                    // page behind it, so the lockup reads as one mark rather
                    // than as an icon sitting on a background.
                    const Image(
                      image: AssetImage(
                        'assets/branding/stitch_simple_pos_launcher_icon/simple_pos_geometric_s_icon/screen.png',
                      ),
                      width: 76,
                      height: 76,
                      fit: BoxFit.contain,
                    ),
                    SizedBox(height: spacing.xl),
                    const SimplePosWordmark(color: kBrandPaper),
                    SizedBox(height: spacing.sm),
                    Text(
                      'Point of sale, built for the till it runs on',
                      textAlign: TextAlign.center,
                      style: type.bodyMedium?.copyWith(
                        color: kBrandPaper.withValues(alpha: 0.78),
                      ),
                    ),
                    SizedBox(height: spacing.xxl),
                    const _SplashProgress(),
                    SizedBox(height: spacing.xxl),
                    Text(
                      SimplePosBrand.poweredByTag,
                      textAlign: TextAlign.center,
                      style: type.labelSmall?.copyWith(
                        color: kBrandPaper.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "reading this till's own state" line.
///
/// A bar rather than a spinner. A spinner says "wait, I do not know how long";
/// a bar says "this is a process with a shape", which is the honest description
/// of opening a local database and resolving a workspace.
///
/// Under reduced motion it renders the SAME bar at a fixed value: an
/// indeterminate indicator is an animation with no stop condition, and
/// `disableAnimations` is a request to be shown no such thing. The end state is
/// the same either way, because the end state here is "the splash is gone".
class _SplashProgress extends StatelessWidget {
  const _SplashProgress();

  /// Where the static bar sits when motion is off. A third is a shape, not a
  /// claim about progress: nothing here knows how far along the boot is, and a
  /// bar that pretended to would be lying.
  static const double _restingFraction = 1 / 3;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final bool reduced = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      // A boot state is an eye-only change: a screen-reader user would
      // otherwise land on a static frame with nothing to tell them the app is
      // working and not hung.
      liveRegion: true,
      label: 'Opening this till',
      child: ExcludeSemantics(
        child: LinearProgressIndicator(
          value: reduced ? _restingFraction : null,
          color: colors.accent,
          backgroundColor: kBrandPaper.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}
