# Analytics Redesign Handover

Goal: redesign the analytics screen layout.

Tasks:
1. Move the range filter (Today/7 days/30 days/90 days/1 year) beside the title at the top, instead of a separate row.
2. Move payout next to credit/wallet in the top bar.
3. Put the sales card at the top as a large card.
4. Rearrange the remaining cards (KPIs, payments, stock, VAT) to fit the page properly.

Files:
- duka_pos_app/lib/screens/analytics_screen.dart (main layout, _AnalyticsScaffold, ScreenTitle)
- duka_pos_app/lib/screens/analytics_tables.dart
- duka_pos_app/lib/ui/components/screen_title.dart

Notes:
- Range state is `_range` (AnalyticsRange) with `_setRange`.
- `_RangeBar` widget was removed; re-add beside title if needed.
- Keep all 1689 tests passing.
