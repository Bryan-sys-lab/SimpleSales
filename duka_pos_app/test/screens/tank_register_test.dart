// Tests for the Drinks tank data model and its register screen.
import 'package:duka_pos/screens/tank_register_screen.dart';
import 'package:duka_pos/services/analytics.dart';
import '../support/harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DrinkTankLevel', () {
    test('fill percent clamps at 100%', () {
      final tank = DrinkTankLevel(
        productId: 1,
        name: 'Tusker',
        litresRemaining: 70,
        tankCount: 100,
        capacityLitres: 60,
        costInvestedMinor: 1200000,
      );
      expect(tank.fillPercent, 1.0);
    });

    test('fill percent is zero when no capacity', () {
      final tank = DrinkTankLevel(
        productId: 1,
        name: 'Tusker',
        litresRemaining: 10,
        tankCount: 10,
        capacityLitres: 0,
        costInvestedMinor: 0,
      );
      expect(tank.fillPercent, 0);
    });

    test('costInvested converts minor units to Money', () {
      final tank = DrinkTankLevel(
        productId: 1,
        name: 'Tusker',
        litresRemaining: 10,
        tankCount: 10,
        capacityLitres: 60,
        costInvestedMinor: 1200000,
      );
      expect(tank.costInvested.minorUnits, 1200000);
    });
  });

  group('TankRegisterScreen pumps', () {
    testWidgets('compact phone shows all summary figures',
        (WidgetTester tester) async {
      await loadAppFonts();
      tester.useDevice(Device.compact);

      await tester.pumpApp(
        home: TankRegisterScreen(
          tanks: <DrinkTankLevel>[
            DrinkTankLevel(
              productId: 1,
              name: 'Tusker Lager',
              litresRemaining: 42,
              tankCount: 60,
              capacityLitres: 60,
              costInvestedMinor: 1200000,
            ),
          ],
          totalTankCount: 60,
          totalCapacityLitres: 60,
          totalInvestedMinor: 1200000,
          totalRemainingLitres: 42,
          tanksNeedingAttention: 0,
          onOpenTank: (DrinkTankLevel _) {},
          onAddTank: () {},
        ),
      );

      expect(find.text('Tank register'), findsOneWidget);
      expect(find.textContaining('L'),
          findsAtLeastNWidgets(2)); // capacity + remaining
      expect(find.textContaining('KSh'), findsAtLeastNWidgets(1)); // invested
      tester.expectNoOverflow('tank register');
    });

    testWidgets('tablet shows two-column layout', (WidgetTester tester) async {
      await loadAppFonts();
      tester.useDevice(Device.tablet);

      await tester.pumpApp(
        home: TankRegisterScreen(
          tanks: <DrinkTankLevel>[],
          totalTankCount: 0,
          totalCapacityLitres: 0,
          totalInvestedMinor: 0,
          totalRemainingLitres: 0,
          tanksNeedingAttention: 0,
          onOpenTank: (DrinkTankLevel _) {},
          onAddTank: () {},
        ),
      );

      expect(find.text('No tanks yet'), findsOneWidget);
      tester.expectNoOverflow('tank register tablet');
    });

    testWidgets('low attention strip shows amber warning',
        (WidgetTester tester) async {
      await loadAppFonts();
      tester.useDevice(Device.compact);

      await tester.pumpApp(
        home: TankRegisterScreen(
          tanks: <DrinkTankLevel>[
            DrinkTankLevel(
              productId: 1,
              name: 'Tusker Lager',
              litresRemaining: 3,
              tankCount: 60,
              capacityLitres: 60,
              costInvestedMinor: 1200000,
            ),
          ],
          totalTankCount: 60,
          totalCapacityLitres: 60,
          totalInvestedMinor: 1200000,
          totalRemainingLitres: 3,
          tanksNeedingAttention: 1,
          onOpenTank: (DrinkTankLevel _) {},
          onAddTank: () {},
        ),
      );

      expect(find.textContaining('tanks below safe level'), findsOneWidget);
      tester.expectNoOverflow('tank register low');
    });

    testWidgets('l10n keys exist in both locales', (WidgetTester tester) async {
      final en = await loadL10n(const Locale('en'));
      final sw = await loadL10n(const Locale('sw'));

      expect(en.tankRegisterTitle, 'Tank register');
      expect(en.tankActionReceive, 'Receive / replenish');
      expect(en.tankActionMeasure, 'Record measurement');
      expect(en.tankActionHistory, 'View history');
      expect(en.tankStatusHealthy, 'Healthy');
      expect(en.tankStatusLow, 'Low');
      expect(en.tankStatusCritical, 'Critical');

      expect(sw.tankRegisterTitle, isNotEmpty);
      expect(sw.tankActionReceive, isNotEmpty);
    });
  });
}
