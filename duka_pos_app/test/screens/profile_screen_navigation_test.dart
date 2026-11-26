import 'dart:io';

import 'package:duka_pos/l10n/app_localizations_config.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/profile_screen.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../support/harness.dart';

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
  });

  testWidgets('back to settings pops the profile instead of pushing settings',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PathProviderPlatform.instance = _FakePathProvider();
    final AppState appState = AppState()
      ..owner = Owner(
        id: 1,
        name: 'Amina Njeri',
        pinHash: '',
        email: 'amina@example.com',
        shopName: 'Green Basket',
        createdAt: '2024-01-01',
      );
    addTearDown(appState.dispose);
    final GoRouter router = GoRouter(
      initialLocation: '/settings',
      routes: <RouteBase>[
        GoRoute(
          path: '/settings',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/settings/profile'),
                child: const Text('Open account'),
              ),
            ),
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AppState>.value(value: appState),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: buildDukaLightTheme(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open account'));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(ProfileScreen)),
    );
    expect(find.text(l10n.profileTitle), findsOneWidget);
    await tester.tap(find.text(l10n.profileBackToSettings));
    await tester.pumpAndSettle();

    expect(find.text('Open account'), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
