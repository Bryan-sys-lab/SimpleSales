import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/animated_startup_brand.dart';
import '../ui/brand/nerva_wordmark.dart';

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
    final AppColors colors = AppColors.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Stated by hand because the splash paints the CANVAS, and the canvas is
      // near-black at night and near-white by day: the icon brightness has to
      // follow the theme rather than be pinned to one.
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        // The THEME's canvas, not a brand ink constant. The splash is the first
        // frame of the app and it has to be the same surface every other screen
        // sits on — a splash in a different colour from the app it introduces
        // reads as two products.
        backgroundColor: colors.canvas,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.mobilePageGutter,
                vertical: spacing.xl,
              ),
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
                    const AnimatedStartupBrand(),
                    SizedBox(height: spacing.lg),
                    // The ATTRIBUTION first, the app's own name after it.
                    //
                    // It used to be the other way round — the shop's app in
                    // large type, then a small "Powered by Nerva" trailing
                    // underneath like a footnote. Read in that order the
                    // footer looked like it belonged to the line above it, and
                    // the lockup said the app was made by whoever the line
                    // named. The vendor comes first, the product second.
                    //
                    // The VENDOR'S MARK, not the vendor's name in the app's
                    // typeface: a brand set in the wrong face is a line of
                    // somebody else's copy.
                    Center(
                      child: PoweredByNerva(
                        style: type.labelSmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.md),
                    Text(
                      'Point of sale, built for the till it runs on',
                      textAlign: TextAlign.center,
                      style: type.bodyMedium?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.78),
                      ),
                    ),
                    SizedBox(height: spacing.xxl),
                    const _SplashProgress(),
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
          backgroundColor: colors.onSurface.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}
