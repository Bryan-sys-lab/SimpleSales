import 'package:flutter/material.dart';

import '../profile/shop_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';
import '../ui/onboarding_style.dart';

/// The product tour shown before a first account is created.
///
/// Redesigned to match the inspiration: dark canvas, emerald accent,
/// large image window with green curve, icon badge, label chip, title,
/// body, checkmarks, page dots, and a green primary action.
class ProductOnboardingScreen extends StatefulWidget {
  const ProductOnboardingScreen({
    super.key,
    required this.onCreateAccount,
    required this.onSignIn,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  @override
  State<ProductOnboardingScreen> createState() =>
      _ProductOnboardingScreenState();
}

class _ProductOnboardingScreenState extends State<ProductOnboardingScreen> {
  final PageController _pages = PageController();
  int _page = 0;

  static const List<_TourPage> _tour = <_TourPage>[
    _TourPage(
      title: 'Your business, simplified',
      body:
          'Sell faster, keep track of stock and understand your numbers — even when the signal drops.',
      image: 'assets/onboarding/hero_kenyan_shop_photo.jpg',
      badgeIcon: Icons.storefront_outlined,
      label: 'SIMPLESALES',
    ),
    _TourPage(
      title: 'One app. Four ways to work.',
      body:
          'Choose the profile that matches your business today. You can keep your workflow focused without losing the tools you need to grow.',
      image: 'assets/onboarding/hero_kenyan_shop_photo.jpg',
      badgeIcon: Icons.grid_view_rounded,
      label: 'PROFILES',
    ),
    _TourPage(
      profile: ShopProfile.drinks,
      title: 'Drinks profile',
      body: 'For bottle stores, bars, kiosks and beverage retailers.',
      image: 'assets/onboarding/drinks_shop_photo.jpg',
      badgeIcon: Icons.local_bar_outlined,
      label: 'DRINKS',
      bullets: <String>[
        'Ring up drinks quickly',
        'Track bottles, crates and stock levels',
        'See best sellers and profit clearly',
      ],
    ),
    _TourPage(
      profile: ShopProfile.duka,
      title: 'Duka profile',
      body: 'For dukas, mini-markets and everyday general shops.',
      image: 'assets/onboarding/duka_shop_photo.jpg',
      badgeIcon: Icons.storefront_outlined,
      label: 'DUKA',
      bullets: <String>[
        'Search or scan products easily',
        'Manage categories and low-stock alerts',
        'Track daily sales and expenses',
      ],
    ),
    _TourPage(
      profile: ShopProfile.fashion,
      title: 'Fashion profile',
      body: 'For clothing, shoes, boutiques and style retailers.',
      image: 'assets/onboarding/fashion_shop_photo.jpg',
      badgeIcon: Icons.checkroom_outlined,
      label: 'FASHION',
      bullets: <String>[
        'Manage sizes, colours and variants',
        'Track collections and inventory',
        'Handle returns and exchanges with confidence',
      ],
    ),
    _TourPage(
      profile: ShopProfile.open,
      title: 'Open profile',
      body: 'For businesses that need a flexible catalogue and workflow.',
      image: 'assets/onboarding/open_shop_photo.jpg',
      badgeIcon: Icons.grid_view_rounded,
      label: 'OPEN',
      bullets: <String>[
        'Create categories that fit your business',
        'Track sales, expenses and profit',
        'Grow into richer reports when you are ready',
      ],
    ),
  ];

  bool get _last => _page == _tour.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      widget.onCreateAccount();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Header
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(spacing.xl, spacing.xs, spacing.xl, spacing.xs),
              child: Row(
                children: <Widget>[
                  const SimplePosMark(size: 36),
                  const Spacer(),
                  Expanded(
                    child: TextButton(
                      onPressed: widget.onSignIn,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.accent,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 44),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      child: Text(
                        'I have an account',
                        style: type.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                        softWrap: true,
                        maxLines: 2,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _tour.length,
                onPageChanged: (int value) => setState(() => _page = value),
                itemBuilder: (BuildContext context, int index) {
                  final _TourPage page = _tour[index];
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        OnboardStyle.window(
                          context: context,
                          image: Image.asset(page.image, fit: BoxFit.cover, alignment: Alignment.topCenter, semanticLabel: 'Kenyan shop business'),
                          badgeIcon: page.badgeIcon,
                          label: page.label,
                          title: page.title,
                          body: page.body,
                          type: type,
                          colors: colors,
                          spacing: spacing,
                        ),
                        if (page.bullets.isNotEmpty) ...<Widget>[
                          Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(spacing.xl, 0, spacing.xl, spacing.xl),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                for (final String bullet in page.bullets)
                                  OnboardFeature(text: bullet),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(spacing.xl, spacing.sm, spacing.xl, spacing.md),
              child: Column(
                children: <Widget>[
                  OnboardStyle.dots(step: _page, total: _tour.length, colors: colors, spacing: spacing),
                  SizedBox(height: spacing.lg),
                  OnboardStyle.primaryButton(
                    context: context,
                    onPressed: _next,
                    label: _last ? 'Create your account' : 'Continue',
                    colors: colors,
                    spacing: spacing,
                  ),
                  if (_last) ...<Widget>[
                    SizedBox(height: spacing.md),
                    OnboardStyle.link(context: context, onPressed: widget.onSignIn, label: 'Already have an account? Sign in', colors: colors),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourPage {
  const _TourPage({
    required this.title,
    required this.body,
    required this.image,
    required this.badgeIcon,
    required this.label,
    this.profile,
    this.bullets = const <String>[],
  });

  final ShopProfile? profile;
  final String title;
  final String body;
  final String image;
  final IconData badgeIcon;
  final String label;
  final List<String> bullets;
}
