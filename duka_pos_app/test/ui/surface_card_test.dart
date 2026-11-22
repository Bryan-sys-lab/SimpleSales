import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/theme/app_colors.dart';
import 'package:duka_pos/theme/app_gradients.dart';
import 'package:duka_pos/ui/components/surface.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a feature card gets a quiet accent outline, not a tinted fill',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const SurfaceCard(
        accentEdge: true,
        child: Text('Revenue overview'),
      ),
    );

    final BoxDecoration decoration = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((DecoratedBox box) => box.decoration)
        .whereType<BoxDecoration>()
        .single;
    final Border border = decoration.border! as Border;
    final AppColors colors =
        AppColors.of(tester.element(find.byType(SurfaceCard)));

    expect(decoration.gradient, isNull);
    expect(decoration.color, colors.surface);
    expect(border.top.width, 2);
    expect(border.top.color, colors.accentContainer);
  });

  testWidgets('a tappable surface card keeps its gradient and tap behavior',
      (tester) async {
    tester.useDevice(Device.compact);
    var taps = 0;
    await tester.pumpApp(
      home: Column(
        children: <Widget>[
          SurfaceCard(
            gradient: AppGradients.primary,
            child: const Text('Featured report'),
          ),
          SurfaceCard(
            gradient: AppGradients.primary,
            onTap: () => taps++,
            child: const Text('Open featured report'),
          ),
        ],
      ),
    );

    final BoxDecoration staticDecoration = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((DecoratedBox box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((BoxDecoration decoration) => decoration.gradient != null);
    expect(staticDecoration.gradient, AppGradients.primary);
    final Ink ink = tester.widget<Ink>(find.byType(Ink));
    expect((ink.decoration! as BoxDecoration).gradient, AppGradients.primary);
    await tester.tap(find.text('Open featured report'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('tappable surface cards provide spring press feedback',
      (tester) async {
    tester.useDevice(Device.compact);
    var taps = 0;
    await tester.pumpApp(
      home: SurfaceCard(
        onTap: () => taps++,
        child: const Text('Open inventory'),
      ),
    );

    await tester.tap(find.text('Open inventory'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(Transform), findsWidgets);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('surface card feedback remains static with reduced motion',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      disableAnimations: true,
      home: SurfaceCard(
        onTap: () {},
        child: const Text('Open inventory'),
      ),
    );

    expect(find.text('Open inventory'), findsOneWidget);
  });
}
