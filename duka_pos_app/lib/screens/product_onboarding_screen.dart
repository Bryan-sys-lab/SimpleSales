import 'package:flutter/material.dart';

import '../profile/shop_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';

/// The product tour shown before a first account is created.
///
/// This is deliberately separate from the post-account permission flow. It
/// explains the four business profiles in the language of a Kenyan shop owner,
/// then hands the person to the real sign-in/setup choices.
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
    ),
    _TourPage(
      title: 'One app. Four ways to work.',
      body:
          'Choose the profile that matches your business today. You can keep your workflow focused without losing the tools you need to grow.',
      image: null,
    ),
    _TourPage(
      profile: ShopProfile.drinks,
      title: 'Drinks profile',
      body: 'For bottle stores, bars, kiosks and beverage retailers.',
      image: 'assets/onboarding/drinks_shop_photo.jpg',
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
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                  spacing.md, spacing.md, spacing.md, spacing.xs),
              child: Row(
                children: <Widget>[
                  const SimplePosMark(size: 34),
                  SizedBox(width: spacing.sm),
                  if (MediaQuery.textScalerOf(context).scale(1) <= 1.3)
                    Text('SimpleSales', style: type.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onSignIn,
                    child: Text(
                      MediaQuery.textScalerOf(context).scale(1) > 1.3
                          ? 'Sign in'
                          : 'I have an account',
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
                  return _TourPageView(page: _tour[index]);
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  spacing.lg, spacing.xs, spacing.lg, spacing.md),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int i = 0; i < _tour.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == _page ? 22 : 8,
                          height: 8,
                          margin: EdgeInsets.symmetric(horizontal: spacing.xxs),
                          decoration: BoxDecoration(
                            color: i == _page
                                ? colors.accent
                                : colors.outlineStrong,
                            borderRadius: AppShapes.of(context).chipRadius,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _next,
                      icon: Icon(_last
                          ? Icons.arrow_forward_rounded
                          : Icons.chevron_right_rounded),
                      label: Text(_last ? 'Create your account' : 'Continue'),
                    ),
                  ),
                  if (_last) ...<Widget>[
                    SizedBox(height: spacing.xs),
                    TextButton(
                      onPressed: widget.onSignIn,
                      child: const Text('Already have an account? Sign in'),
                    ),
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
    this.profile,
    this.bullets = const <String>[],
  });

  final ShopProfile? profile;
  final String title;
  final String body;
  final String? image;
  final List<String> bullets;
}

class _TourPageView extends StatelessWidget {
  const _TourPageView({required this.page});

  final _TourPage page;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return SingleChildScrollView(
      padding:
          EdgeInsets.fromLTRB(spacing.lg, spacing.md, spacing.lg, spacing.lg),
      child: page.image != null
          ? _PhotoTourCard(page: page, colors: colors, type: type)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ProfileOverview(colors: colors),
                SizedBox(height: spacing.lg),
                _TourCopy(page: page, colors: colors, type: type),
              ],
            ),
    );
  }

  static IconData _profileIcon(ShopProfile profile) => switch (profile) {
        ShopProfile.drinks => Icons.local_bar_outlined,
        ShopProfile.duka => Icons.storefront_outlined,
        ShopProfile.fashion => Icons.checkroom_outlined,
        ShopProfile.open => Icons.grid_view_rounded,
      };
}

class _PhotoTourCard extends StatelessWidget {
  const _PhotoTourCard({
    required this.page,
    required this.colors,
    required this.type,
  });

  final _TourPage page;
  final AppColors colors;
  final TextTheme type;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final bool hero = page.profile == null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppShapes.of(context).cardRadius,
        border: Border.all(color: colors.outline),
      ),
      child: ClipRRect(
        borderRadius: AppShapes.of(context).cardRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: hero ? 1.22 : 1.72,
              child: Semantics(
                image: true,
                label:
                    'Kenyan ${hero ? 'shop' : page.profile!.displayName} business',
                child: Image.asset(
                  page.image!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(hero ? spacing.lg : spacing.md),
              child: _TourCopy(page: page, colors: colors, type: type),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourCopy extends StatelessWidget {
  const _TourCopy({
    required this.page,
    required this.colors,
    required this.type,
  });

  final _TourPage page;
  final AppColors colors;
  final TextTheme type;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (page.profile != null)
          Row(
            children: <Widget>[
              Icon(_TourPageView._profileIcon(page.profile!),
                  color: colors.accent),
              SizedBox(width: spacing.xs),
              Text(page.profile!.displayName.toUpperCase(),
                  style: type.labelLarge?.copyWith(color: colors.accent)),
            ],
          ),
        if (page.profile != null) SizedBox(height: spacing.xs),
        Text(page.title, style: type.headlineSmall),
        SizedBox(height: spacing.sm),
        Text(page.body, style: type.bodyLarge),
        if (page.bullets.isNotEmpty) ...<Widget>[
          SizedBox(height: spacing.lg),
          for (final String bullet in page.bullets)
            Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.check_circle, size: 20, color: colors.accent),
                  SizedBox(width: spacing.sm),
                  Expanded(child: Text(bullet, style: type.bodyMedium)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _ProfileOverview extends StatelessWidget {
  const _ProfileOverview({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: spacing.sm,
      mainAxisSpacing: spacing.sm,
      childAspectRatio: 1.22,
      children: <Widget>[
        for (final ({String label, IconData icon}) item
            in <({String label, IconData icon})>[
          (label: 'Drinks', icon: Icons.local_bar_outlined),
          (label: 'Duka', icon: Icons.storefront_outlined),
          (label: 'Fashion', icon: Icons.checkroom_outlined),
          (label: 'Open', icon: Icons.grid_view_rounded),
        ])
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accentContainer,
              borderRadius: AppShapes.of(context).controlRadius,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(item.icon, color: colors.onAccentContainer, size: 30),
                SizedBox(height: spacing.xs),
                Text(item.label,
                    style: type.titleSmall
                        ?.copyWith(color: colors.onAccentContainer)),
              ],
            ),
          ),
      ],
    );
  }
}
