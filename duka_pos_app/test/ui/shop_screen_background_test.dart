import 'package:duka_pos/ui/components/shop_screen_background.dart';
import 'package:duka_pos/theme/app_colors.dart';
import 'package:duka_pos/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shop backdrop follows light and dark themes',
      (WidgetTester tester) async {
    for (final Brightness brightness in <Brightness>[
      Brightness.light,
      Brightness.dark,
    ]) {
      final ThemeData theme = brightness == Brightness.dark
          ? buildDukaDarkTheme()
          : buildDukaLightTheme();
      final AppColors colors = brightness == Brightness.dark
          ? const AppColors.dark()
          : const AppColors.light();

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: ShopScreenBackground(
            brightness: brightness,
            colors: colors,
            child: const Scaffold(body: Text('Shop screen')),
          ),
        ),
      );

      final ColoredBox backdrop = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(ShopScreenBackground),
          matching: find.byType(ColoredBox),
        ),
      );
      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));

      expect(backdrop.color, colors.canvas);
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(scaffold.backgroundColor, isNull);
      expect(find.text('Shop screen'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ShopScreenBackground),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    }
  });
}
