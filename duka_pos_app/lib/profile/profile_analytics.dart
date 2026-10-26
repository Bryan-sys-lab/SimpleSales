import 'shop_profile.dart';

/// Stable identifiers for profile-specific dashboard emphasis.
///
/// The underlying analytics engine remains shared. These identifiers select
/// prominent cards; they are not alternate formulas or data writers.
enum ProfileKpi {
  revenue,
  grossProfit,
  netProfit,
  cashFlow,
  cashPosition,
  litresSold,
  pourVariance,
  stockValue,
  lowStock,
  topCategory,
  variantSales,
  laybyBalance,
  pooledCost,
  jobsCompleted,
  receivables,
}

class ProfileAnalytics {
  const ProfileAnalytics({required this.emphasis});

  final List<ProfileKpi> emphasis;

  static ProfileAnalytics forProfile(ShopProfile profile) => switch (profile) {
        ShopProfile.drinks => const ProfileAnalytics(
            emphasis: <ProfileKpi>[
              ProfileKpi.revenue,
              ProfileKpi.grossProfit,
              ProfileKpi.litresSold,
              ProfileKpi.pourVariance,
              ProfileKpi.stockValue,
            ],
          ),
        ShopProfile.duka => const ProfileAnalytics(
            emphasis: <ProfileKpi>[
              ProfileKpi.revenue,
              ProfileKpi.grossProfit,
              ProfileKpi.stockValue,
              ProfileKpi.lowStock,
              ProfileKpi.topCategory,
            ],
          ),
        ShopProfile.fashion => const ProfileAnalytics(
            emphasis: <ProfileKpi>[
              ProfileKpi.revenue,
              ProfileKpi.grossProfit,
              ProfileKpi.variantSales,
              ProfileKpi.laybyBalance,
              ProfileKpi.topCategory,
            ],
          ),
        ShopProfile.open => const ProfileAnalytics(
            emphasis: <ProfileKpi>[
              ProfileKpi.revenue,
              ProfileKpi.netProfit,
              ProfileKpi.cashPosition,
              ProfileKpi.pooledCost,
              ProfileKpi.jobsCompleted,
              ProfileKpi.receivables,
            ],
          ),
      };
}

extension ShopProfileAnalytics on ShopProfile {
  ProfileAnalytics get analytics => ProfileAnalytics.forProfile(this);
}
