import 'package:material_ui/material_ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../profile/shop_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';
import '../ui/onboarding_style.dart';

/// A three-page product tour shown before anyone has an account.
///
/// It explains what SimpleSales is, what shop profiles exist, and how local
/// / offline behaviour works — then hands off to sign-in or account creation.
///
/// Never requests permissions, never touches the database, never reaches the
/// network.  All photographs are bundled assets.
class ProductOnboardingScreen extends StatefulWidget {
  const ProductOnboardingScreen({
    super.key,
    required this.onCreateAccount,
    required this.onSignIn,
    this.onSkip,
  });

  /// Invoked when the person finishes the tour and wants an account.
  final VoidCallback onCreateAccount;

  /// Invoked from the Sign-in button in the header on every page.
  final VoidCallback onSignIn;

  /// Invoked when the person skips the tour.  Marks the intro as seen through
  /// the existing [`WelcomeChooserScreen._finishIntro`] and returns to the
  /// chooser — it does not create a shop or navigate directly to setup.
  final VoidCallback? onSkip;

  @override
  State<ProductOnboardingScreen> createState() =>
      _ProductOnboardingScreenState();
}

class _ProductOnboardingScreenState extends State<ProductOnboardingScreen> {
  int _page = 0;

  /// The total number of pages — exactly three.
  static const int _pageCount = 3;

  void _next() {
    if (_page < _pageCount - 1) {
      setState(() => _page += 1);
    } else {
      widget.onCreateAccount();
    }
  }

  /// The page content: hero + title + body, or profile overview on page 2.
  Widget _pageContent(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    switch (_page) {
      case 0:
        return _heroPanel(
          image: Image.asset(
            'assets/onboarding/hero_kenyan_shop_photo.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: _mediaHeight(context),
          ),
          badgeIcon: Icons.storefront_outlined,
          label: l10nOf(context).productOnboardingPage1Label,
          title: l10nOf(context).productOnboardingPage1Title,
          body: l10nOf(context).productOnboardingPage1Body,
          colors: colors,
          spacing: spacing,
        );
      case 1:
        return _profileOverview(context);
      case 2:
        return _heroPanel(
          image: Image.asset(
            'assets/onboarding/hero_kenyan_shop_photo.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: _mediaHeight(context),
          ),
          badgeIcon: Icons.cloud_off_outlined,
          label: l10nOf(context).productOnboardingPage3Label,
          title: l10nOf(context).productOnboardingPage3Title,
          body: l10nOf(context).productOnboardingPage3Body,
          colors: colors,
          spacing: spacing,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  AppLocalizations l10nOf(BuildContext context) => AppLocalizations.of(context);
  AppShapes get shapes => AppShapes.of(context);

  double _mediaHeight(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    if (width < 400) return 240;
    if (width < 600) return 280;
    return 320;
  }

  /// The page title, body and hero image in one scrolling panel.
  Widget _heroPanel({
    required Widget image,
    required IconData badgeIcon,
    required String label,
    required String title,
    required String body,
    required AppColors colors,
    required AppSpacing spacing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: _mediaHeight(context),
          width: double.infinity,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: image),
              Positioned(
                left: -spacing.md,
                bottom: -spacing.md,
                child: Container(
                  width: _mediaHeight(context) * 0.85,
                  height: _mediaHeight(context) * 0.85,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        colors.accent.withValues(alpha: 0.45),
                        colors.accent.withValues(alpha: 0.0),
                      ],
                      center: Alignment.bottomLeft,
                      radius: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: spacing.sm,
                bottom: spacing.sm,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    badgeIcon,
                    color: colors.accent,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.accentContainer.withValues(alpha: 0.15),
                  borderRadius: shapes.cardRadius,
                ),
                child: Text(
                  label,
                  style: AppTypography.of(context).labelLarge?.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              SizedBox(height: spacing.sm),
              Text(
                title,
                style: AppTypography.of(context).headlineSmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              SizedBox(height: spacing.sm),
              Text(
                body,
                style: AppTypography.of(context).bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Page two: four informational profile cards, not selectable here.
  Widget _profileOverview(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.accentContainer.withValues(alpha: 0.15),
                  borderRadius: shapes.cardRadius,
                ),
                child: Text(
                  l10n.productOnboardingPage2Label,
                  style: type.labelLarge?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: spacing.sm),
              Text(
                l10n.productOnboardingPage2Title,
                style: type.headlineSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: spacing.sm),
              Text(
                l10n.productOnboardingPage2Body,
                style: type.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.md),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: spacing.md),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.95,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: ShopProfile.values.length,
          itemBuilder: (BuildContext context, int index) {
            final ShopProfile profile = ShopProfile.values[index];
            return _InfoCard(
              profile: profile,
              l10n: l10n,
              colors: colors,
              spacing: spacing,
              type: type,
            );
          },
        ),
        SizedBox(height: spacing.md),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Header: sign-in on every page, page progress.
            Padding(
              padding: EdgeInsets.all(spacing.md),
              child: Row(
                children: <Widget>[
                  const SimplePosMark(size: 32),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          l10n.productOnboardingHeader,
                          style: type.titleMedium?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: spacing.xs),
                        Text(
                          '${_page + 1} of $_pageCount',
                          style: type.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          semanticsLabel:
                              '${l10n.productOnboardingPageProgress} ${_page + 1} of $_pageCount',
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: widget.onSignIn,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.accent,
                      side: BorderSide(color: colors.accent),
                      shape: RoundedRectangleBorder(
                        borderRadius: shapes.controlRadius,
                      ),
                    ),
                    child: Text(l10n.actionSignIn),
                  ),
                ],
              ),
            ),

            // Scrollable content: hero + page body.
            Expanded(
              child: SingleChildScrollView(
                child: _pageContent(context),
              ),
            ),

            // Footer: Skip / Continue.
            Padding(
              padding: EdgeInsets.all(spacing.md),
              child: Row(
                children: <Widget>[
                  if (widget.onSkip != null)
                    OnboardStyle.link(
                      context: context,
                      onPressed: widget.onSkip,
                      label: l10n.actionSkip,
                      colors: colors,
                    )
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  Expanded(
                    child: OnboardStyle.primaryButton(
                      context: context,
                      onPressed: _next,
                      label: _page == _pageCount - 1
                          ? l10n.actionCreateAccount
                          : l10n.actionContinue,
                      colors: colors,
                      spacing: spacing,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One informational profile card on page two — not selectable, just explains.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.profile,
    required this.l10n,
    required this.colors,
    required this.spacing,
    required this.type,
  });

  final ShopProfile profile;
  final AppLocalizations l10n;
  final AppColors colors;
  final AppSpacing spacing;
  final TextTheme type;

  IconData get _icon {
    switch (profile) {
      case ShopProfile.duka:
        return Icons.storefront_outlined;
      case ShopProfile.drinks:
        return Icons.local_bar_outlined;
      case ShopProfile.fashion:
        return Icons.checkroom_outlined;
      case ShopProfile.open:
        return Icons.work_outline;
    }
  }

  String get _subtitle {
    switch (profile) {
      case ShopProfile.duka:
        return l10n.productOnboardingDukaSubtitle;
      case ShopProfile.drinks:
        return l10n.productOnboardingDrinksSubtitle;
      case ShopProfile.fashion:
        return l10n.productOnboardingFashionSubtitle;
      case ShopProfile.open:
        return l10n.productOnboardingOpenSubtitle;
    }
  }

  String get _imageAsset => 'assets/onboarding/${profile.name}_shop_photo.jpg';

  String get _title {
    switch (profile) {
      case ShopProfile.duka:
        return l10n.productOnboardingDukaTitle;
      case ShopProfile.drinks:
        return l10n.productOnboardingDrinksTitle;
      case ShopProfile.fashion:
        return l10n.productOnboardingFashionTitle;
      case ShopProfile.open:
        return l10n.productOnboardingOpenTitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceSunken,
      borderRadius: AppShapes.of(context).cardRadius,
      child: InkWell(
        borderRadius: AppShapes.of(context).cardRadius,
        onTap: () {}, // Decorative: not selectable on the tour.
        child: Padding(
          padding: EdgeInsets.all(spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ClipRRect(
                borderRadius: AppShapes.of(context).controlRadius,
                child: Image.asset(
                  _imageAsset,
                  height: 76,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => Container(
                    height: 76,
                    color: colors.surfaceRaised,
                    child: Icon(
                      _icon,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.xxs),
              Text(
                _title,
                style: type.titleSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: spacing.xxs),
              Text(
                _subtitle,
                style: type.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
